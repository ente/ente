import {
    authenticatedRequestHeaders,
    ensureOk,
    publicRequestHeaders,
    retryEnsuringHTTPOk,
} from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";
import {
    b64ToBytes,
    createStreamEncryptor,
    encryptBlob,
    encryptBox,
    encryptFileStreamWithKey,
    md5Base64,
    stringToB64,
} from "./crypto";
import {
    RemoteIDResponseSchema,
    RemoteUploadURLResponseSchema,
} from "./remote-types";

/**
 * The server requires every file to have a thumbnail. For Locker files we
 * don't need a real one, so we encrypt this tiny placeholder and set the
 * `noThumb` flag in pubMagicMetadata.
 *
 * Generated via PIL: `Image.new('RGB', (1,1), (0,0,0)).save(buf, 'JPEG')`.
 */
const BLACK_THUMBNAIL_B64 =
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////" +
    "2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB" +
    "/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAk" +
    "M2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKz" +
    "tLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgEC" +
    "BAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpj" +
    "ZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6" +
    "/9oADAMBAAIRAxEAPwCOiiigD//Z";

const STREAM_ENCRYPTION_CHUNK_SIZE = 4 * 1024 * 1024;
const MULTIPART_CHUNKS_PER_PART = 5;

const MultipartUploadURLs = z.object({
    objectKey: z.string(),
    partURLs: z.array(z.string()),
    completeURL: z.string(),
});

interface MultipartCompletedPart {
    partNumber: number;
    eTag: string;
}

export type LockerUploadProgress =
    | { phase: "preparing" }
    | { phase: "uploading"; loaded: number; total: number }
    | { phase: "finalizing" };

interface UploadDeps<TCollectionRecord> {
    getCollectionRecord: (
        collectionID: number,
    ) => TCollectionRecord | undefined;
    decryptCollectionKey: (
        collectionRecord: TCollectionRecord,
        masterKey: string,
    ) => Promise<string>;
    addFileToCollections: (
        fileID: number,
        fileKey: string,
        targetCollectionIDs: number[],
        masterKey: string,
    ) => Promise<void>;
}

/**
 * Request a presigned upload URL from the server.
 *
 * @param contentLength Size of the encrypted data in bytes.
 * @param contentMd5 MD5 hash of the encrypted data as base64.
 * @returns The S3 object key and presigned upload URL.
 */
const fetchUploadURL = async (
    contentLength: number,
    contentMd5: string,
): Promise<{ objectKey: string; url: string }> => {
    const headers = new Headers(await authenticatedRequestHeaders());
    headers.set("Content-Type", "application/json");
    const res = await fetch(
        await apiURL("/files/upload-url", { ts: Date.now() }),
        {
            method: "POST",
            headers,
            body: JSON.stringify({ contentLength, contentMD5: contentMd5 }),
        },
    );
    ensureOk(res);
    return RemoteUploadURLResponseSchema.parse(await res.json());
};

const fetchMultipartUploadURLs = async ({
    contentLength,
    partLength,
    partMd5s,
}: {
    contentLength: number;
    partLength: number;
    partMd5s: string[];
}): Promise<z.infer<typeof MultipartUploadURLs>> => {
    const headers = new Headers(await authenticatedRequestHeaders());
    headers.set("Content-Type", "application/json");
    const res = await fetch(
        await apiURL("/files/multipart-upload-url", { ts: Date.now() }),
        {
            method: "POST",
            headers,
            body: JSON.stringify({ contentLength, partLength, partMd5s }),
        },
    );
    ensureOk(res);
    return MultipartUploadURLs.parse(await res.json());
};

const putFileToS3 = async (
    url: string,
    data: Uint8Array<ArrayBuffer>,
    contentMd5: string,
    onProgress?: (progress: { loaded: number; total?: number }) => void,
): Promise<void> => {
    const res = await new Promise<{
        ok: boolean;
        status: number;
        statusText: string;
    }>((resolve, reject) => {
        const request = new XMLHttpRequest();
        request.open("PUT", url);
        request.setRequestHeader("Content-Type", "application/octet-stream");
        request.setRequestHeader("Content-MD5", contentMd5);
        request.upload.onprogress = (event) => {
            onProgress?.({
                loaded: event.loaded,
                total: event.lengthComputable ? event.total : data.length,
            });
        };
        request.onload = () =>
            resolve({
                ok: request.status >= 200 && request.status < 300,
                status: request.status,
                statusText: request.statusText,
            });
        request.onerror = () => reject(new Error("S3 upload failed"));
        request.send(data);
    });
    if (!res.ok) {
        throw new Error(`S3 upload failed: ${res.status} ${res.statusText}`);
    }
};

const uploadSingleObject = async (
    data: Uint8Array<ArrayBuffer>,
    contentMd5: string,
    onProgress?: (progress: { loaded: number; total?: number }) => void,
): Promise<string> => {
    const maxAttempts = 3;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
            const uploadURL = await fetchUploadURL(data.length, contentMd5);
            await putFileToS3(uploadURL.url, data, contentMd5, onProgress);
            return uploadURL.objectKey;
        } catch (error) {
            if (attempt === maxAttempts) {
                throw error;
            }
        }
    }

    throw new Error("Unreachable upload retry state");
};

const putFilePartToS3 = async (
    url: string,
    data: Uint8Array<ArrayBuffer>,
    contentMd5: string,
    onProgress?: (progress: { loaded: number; total?: number }) => void,
): Promise<string> => {
    const maxAttempts = 3;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
            const eTag = await new Promise<string | null>((resolve, reject) => {
                const request = new XMLHttpRequest();
                request.open("PUT", url);
                for (const [headerName, headerValue] of Object.entries({
                    ...publicRequestHeaders(),
                    "Content-MD5": contentMd5,
                })) {
                    request.setRequestHeader(headerName, headerValue);
                }
                request.upload.onprogress = (event) => {
                    onProgress?.({
                        loaded: event.loaded,
                        total: event.lengthComputable
                            ? event.total
                            : data.length,
                    });
                };
                request.onload = () => {
                    if (request.status < 200 || request.status >= 300) {
                        reject(
                            new Error(
                                `S3 multipart upload failed: ${request.status} ${request.statusText}`,
                            ),
                        );
                        return;
                    }
                    resolve(request.getResponseHeader("etag"));
                };
                request.onerror = () =>
                    reject(new Error("S3 multipart upload failed"));
                request.send(data);
            });
            if (!eTag) {
                throw new Error("Missing ETag from multipart upload response");
            }
            return eTag;
        } catch (error) {
            if (attempt === maxAttempts) {
                throw error;
            }
        }
    }

    throw new Error("Unreachable multipart upload retry state");
};

const completeMultipartUpload = async (
    completionURL: string,
    completedParts: MultipartCompletedPart[],
) => {
    const body = [
        "<CompleteMultipartUpload>",
        ...completedParts.map(
            (part) =>
                `<Part><PartNumber>${part.partNumber}</PartNumber><ETag>${part.eTag}</ETag></Part>`,
        ),
        "</CompleteMultipartUpload>",
    ].join("\n");

    await retryEnsuringHTTPOk(() =>
        fetch(completionURL, {
            method: "POST",
            headers: { ...publicRequestHeaders(), "Content-Type": "text/xml" },
            body,
        }),
    );
};

const mergeUint8Arrays = (chunks: Uint8Array[]): Uint8Array<ArrayBuffer> => {
    const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
    const merged = new Uint8Array(totalLength);
    let offset = 0;
    for (const chunk of chunks) {
        merged.set(chunk, offset);
        offset += chunk.length;
    }
    return merged;
};

const createAggregateUploadProgressReporter = (
    total: number,
    onProgress?: (progress: LockerUploadProgress) => void,
) => {
    let uploadedBytes = 0;

    return {
        reportPartProgress: (loaded: number) => {
            onProgress?.({
                phase: "uploading",
                loaded: Math.min(total, uploadedBytes + loaded),
                total,
            });
        },
        completePart: (partLength: number) => {
            uploadedBytes += partLength;
            onProgress?.({
                phase: "uploading",
                loaded: Math.min(total, uploadedBytes),
                total,
            });
        },
    };
};

/**
 * Upload a file to Locker with E2E encryption.
 */
export const uploadLockerFileWithDeps = async <TCollectionRecord>(
    file: File,
    collectionIDs: number[],
    masterKey: string,
    deps: UploadDeps<TCollectionRecord>,
    onProgress?: (progress: LockerUploadProgress) => void,
): Promise<number> => {
    const [collectionID, ...additionalCollectionIDs] = collectionIDs;
    if (collectionID === undefined) {
        throw new Error("No collection selected");
    }
    onProgress?.({ phase: "preparing" });

    const plaintextChunkCount = Math.max(
        1,
        Math.ceil(file.size / STREAM_ENCRYPTION_CHUNK_SIZE),
    );

    const streamEncryptor = await createStreamEncryptor();
    const fileKey = streamEncryptor.key;
    const encryptedFileHeader = streamEncryptor.decryptionHeader;

    let encryptedFileObjectKey: string;
    let encryptedFileSize = 0;

    try {
        if (plaintextChunkCount >= MULTIPART_CHUNKS_PER_PART) {
            const parts: Uint8Array<ArrayBuffer>[] = [];
            const partMd5s: string[] = [];
            let pendingEncryptedChunks: Uint8Array<ArrayBuffer>[] = [];

            for (
                let chunkIndex = 0;
                chunkIndex < plaintextChunkCount;
                chunkIndex++
            ) {
                const chunkStart = chunkIndex * STREAM_ENCRYPTION_CHUNK_SIZE;
                const chunkEnd = Math.min(
                    file.size,
                    chunkStart + STREAM_ENCRYPTION_CHUNK_SIZE,
                );
                const plaintextChunk = new Uint8Array(
                    await file.slice(chunkStart, chunkEnd).arrayBuffer(),
                );
                const isFinalChunk = chunkIndex === plaintextChunkCount - 1;
                const encryptedChunk = await streamEncryptor.encryptChunk(
                    plaintextChunk,
                    isFinalChunk,
                );
                pendingEncryptedChunks.push(encryptedChunk);

                if (
                    pendingEncryptedChunks.length ===
                        MULTIPART_CHUNKS_PER_PART ||
                    isFinalChunk
                ) {
                    const partData = mergeUint8Arrays(pendingEncryptedChunks);
                    parts.push(partData);
                    partMd5s.push(await md5Base64(partData));
                    encryptedFileSize += partData.length;
                    pendingEncryptedChunks = [];
                }
            }

            const firstPartLength = parts[0]?.length ?? 0;
            if (!firstPartLength) {
                throw new Error("Multipart upload produced no parts");
            }

            const multipartUpload = await fetchMultipartUploadURLs({
                contentLength: encryptedFileSize,
                partLength: firstPartLength,
                partMd5s,
            });
            const completedParts: MultipartCompletedPart[] = [];
            const progressReporter = createAggregateUploadProgressReporter(
                encryptedFileSize,
                onProgress,
            );

            for (const [index, partData] of parts.entries()) {
                const partUploadURL = multipartUpload.partURLs[index];
                const partMd5 = partMd5s[index];
                if (!partUploadURL || !partMd5) {
                    throw new Error("Missing multipart upload URL");
                }
                const eTag = await putFilePartToS3(
                    partUploadURL,
                    partData,
                    partMd5,
                    ({ loaded }) => progressReporter.reportPartProgress(loaded),
                );
                completedParts.push({ partNumber: index + 1, eTag });
                progressReporter.completePart(partData.length);
                parts[index] = new Uint8Array(0);
            }

            await completeMultipartUpload(
                multipartUpload.completeURL,
                completedParts,
            );
            encryptedFileObjectKey = multipartUpload.objectKey;
        } else {
            const encryptedChunks: Uint8Array<ArrayBuffer>[] = [];

            for (
                let chunkIndex = 0;
                chunkIndex < plaintextChunkCount;
                chunkIndex++
            ) {
                const chunkStart = chunkIndex * STREAM_ENCRYPTION_CHUNK_SIZE;
                const chunkEnd = Math.min(
                    file.size,
                    chunkStart + STREAM_ENCRYPTION_CHUNK_SIZE,
                );
                const plaintextChunk = new Uint8Array(
                    await file.slice(chunkStart, chunkEnd).arrayBuffer(),
                );
                const isFinalChunk = chunkIndex === plaintextChunkCount - 1;
                encryptedChunks.push(
                    await streamEncryptor.encryptChunk(
                        plaintextChunk,
                        isFinalChunk,
                    ),
                );
            }

            const encryptedFileBytes = mergeUint8Arrays(encryptedChunks);
            encryptedFileSize = encryptedFileBytes.length;
            const encryptedFileMd5 = await md5Base64(encryptedFileBytes);
            encryptedFileObjectKey = await uploadSingleObject(
                encryptedFileBytes,
                encryptedFileMd5,
                ({ loaded, total }) =>
                    onProgress?.({
                        phase: "uploading",
                        loaded,
                        total: total ?? encryptedFileBytes.length,
                    }),
            );
        }
    } finally {
        streamEncryptor.free();
    }

    onProgress?.({
        phase: "uploading",
        loaded: encryptedFileSize,
        total: encryptedFileSize,
    });
    onProgress?.({ phase: "finalizing" });

    const encryptedThumb = await encryptFileStreamWithKey(
        BLACK_THUMBNAIL_B64,
        fileKey,
    );
    const encryptedThumbBytes = b64ToBytes(encryptedThumb.encryptedData);
    const thumbObjectKey = await uploadSingleObject(
        encryptedThumbBytes,
        encryptedThumb.md5Hash,
    );

    const collectionRecord = deps.getCollectionRecord(collectionID);
    if (!collectionRecord) {
        throw new Error(`Collection ${collectionID} not in cache`);
    }
    const collectionKey = await deps.decryptCollectionKey(
        collectionRecord,
        masterKey,
    );
    const encryptedKey = await encryptBox(fileKey, collectionKey);

    const now = Date.now();
    const sourceModificationTime =
        file.lastModified > 0 ? file.lastModified : now;
    const metadata = {
        title: file.name,
        creationTime: sourceModificationTime,
        modificationTime: sourceModificationTime,
        fileType: 3,
    };
    const metadataJSON = JSON.stringify(metadata);
    const encryptedMetadata = await encryptBlob(
        stringToB64(metadataJSON),
        fileKey,
    );

    const pubMagicMetadata = { noThumb: true };
    const pubMagicJSON = JSON.stringify(pubMagicMetadata);
    const encryptedPubMagic = await encryptBlob(
        stringToB64(pubMagicJSON),
        fileKey,
    );

    const postHeaders = new Headers(await authenticatedRequestHeaders());
    postHeaders.set("Content-Type", "application/json");
    const res = await fetch(await apiURL("/files"), {
        method: "POST",
        headers: postHeaders,
        body: JSON.stringify({
            collectionID,
            encryptedKey: encryptedKey.encryptedData,
            keyDecryptionNonce: encryptedKey.nonce,
            file: {
                objectKey: encryptedFileObjectKey,
                decryptionHeader: encryptedFileHeader,
                size: encryptedFileSize,
            },
            thumbnail: {
                objectKey: thumbObjectKey,
                decryptionHeader: encryptedThumb.decryptionHeader,
                size: encryptedThumbBytes.length,
            },
            metadata: {
                encryptedData: encryptedMetadata.encryptedData,
                decryptionHeader: encryptedMetadata.decryptionHeader,
            },
            pubMagicMetadata: {
                version: 1,
                count: 1,
                data: encryptedPubMagic.encryptedData,
                header: encryptedPubMagic.decryptionHeader,
            },
        }),
    });
    ensureOk(res);
    const created = RemoteIDResponseSchema.parse(await res.json());
    if (additionalCollectionIDs.length > 0) {
        await deps.addFileToCollections(
            created.id,
            fileKey,
            additionalCollectionIDs,
            masterKey,
        );
    }
    return created.id;
};
