import type { BytesOrB64 } from "ente-base/crypto/types";
import {
    streamEncryptionChunkOverhead,
    streamEncryptionChunkSize,
} from "ente-base/crypto/types";
import type { CryptoWorker } from "ente-base/crypto/worker";
import { ensureElectron } from "ente-base/electron";
import { basename, nameAndExtension } from "ente-base/file-name";
import {
    ensureOk,
    HTTPError,
    retryAsyncOperation,
    type HTTPRequestRetrier,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import log from "ente-base/log";
import { extractExif } from "ente-gallery/services/exif";
import {
    determineVideoDuration,
    extractVideoMetadata,
} from "ente-gallery/services/ffmpeg";
import {
    detectFileTypeInfoFromChunk,
    isFileTypeNotSupportedError,
} from "ente-gallery/utils/detect-type";
import { readStream } from "ente-gallery/utils/native-stream";
import { decryptRemoteFile, type EnteFile } from "ente-media/file";
import {
    fileFileName,
    metadataHash,
    type FileMetadata,
    type FilePublicMagicMetadataData,
    type ParsedMetadata,
} from "ente-media/file-metadata";
import { FileType, type FileTypeInfo } from "ente-media/file-type";
import { encodeLivePhoto } from "ente-media/live-photo";
import {
    createMagicMetadata,
    encryptMagicMetadata,
    type RemoteMagicMetadata,
} from "ente-media/magic-metadata";
import { addToCollection } from "ente-new/photos/services/collection";
import { mergeUint8Arrays } from "ente-utils/array";
import { ensureInteger, ensureNumber } from "ente-utils/ensure";
import {
    areChecksumProtectedUploadsEnabled,
    type LivePhotoAssets,
    type UploadableUploadItem,
    type UploadItem,
    type UploadPathPrefix,
    type UploadResult,
} from ".";
import { tryParseEpochMicrosecondsFromFileName } from "./date";
import { computeMd5Base64 } from "./md5";
import { matchJSONMetadata, type ParsedMetadataJSON } from "./metadata-json";
import {
    completeMultipartUpload,
    completeMultipartUploadViaWorker,
    fetchMultipartUploadURLs,
    fetchMultipartUploadURLsWithMetadata,
    fetchPublicAlbumsMultipartUploadURLsWithMetadata,
    fetchPublicAlbumsUploadURLWithMetadata,
    fetchUploadURLs,
    fetchUploadURLWithMetadata,
    postEnteFile,
    postPublicAlbumsEnteFile,
    putFile,
    putFilePart,
    putFilePartViaWorker,
    putFileViaWorker,
    type MultipartCompletedPart,
    type ObjectUploadURL,
    type PostEnteFileRequest,
} from "./remote";
import {
    fallbackThumbnail,
    generateThumbnailNative,
    generateThumbnailWeb,
} from "./thumbnail";

const bitFlipErrorPrefix = "BitFlipDetected";

interface FileStream {
    // Streams are single-use and always emit encryption-sized chunks.
    stream: ReadableStream<Uint8Array>;
    chunkCount: number;
    fileSize: number;
    lastModifiedMs: number;
    file?: File;
}

const multipartChunksPerPart = 5;

class UploadService {
    private uploadURLs: ObjectUploadURL[] = [];
    private pendingUploadCount = 0;
    private publicAlbumsCredentials: PublicAlbumsCredentials | undefined;
    private activeUploadURLRefill: Promise<void> | undefined;

    init(publicAlbumsCredentials: PublicAlbumsCredentials | undefined) {
        this.publicAlbumsCredentials = publicAlbumsCredentials;
    }

    logout() {
        this.uploadURLs = [];
        this.pendingUploadCount = 0;
        this.publicAlbumsCredentials = undefined;
        this.activeUploadURLRefill = undefined;
    }

    async setFileCount(fileCount: number) {
        this.pendingUploadCount = fileCount;
        if (
            areChecksumProtectedUploadsEnabled() ||
            this.publicAlbumsCredentials
        ) {
            this.uploadURLs = [];
            return;
        }
        await this.refillUploadURLs();
    }

    reducePendingUploadCount() {
        this.pendingUploadCount--;
    }

    async getUploadURL(metadata?: {
        contentLength: number;
        contentMd5: string;
    }) {
        if (this.publicAlbumsCredentials) {
            if (
                metadata &&
                metadata.contentLength >= 0 &&
                metadata.contentMd5
            ) {
                return fetchPublicAlbumsUploadURLWithMetadata(
                    metadata,
                    this.publicAlbumsCredentials,
                );
            }
            throw new Error("Public uploads require content metadata");
        }
        if (
            areChecksumProtectedUploadsEnabled() &&
            metadata &&
            metadata.contentLength >= 0 &&
            metadata.contentMd5
        ) {
            return fetchUploadURLWithMetadata(metadata).catch((e: unknown) => {
                throw translateURLFetchErrorIfNeeded(e);
            });
        }
        if (this.uploadURLs.length == 0 && this.pendingUploadCount) {
            await this.refillUploadURLs();
        }
        const url = this.uploadURLs.pop();
        if (!url) throw new Error("Failed to obtain upload URL");
        return url;
    }

    private async refillUploadURLs() {
        try {
            if (!this.activeUploadURLRefill) {
                this.activeUploadURLRefill = this._refillUploadURLs();
            }
            await this.activeUploadURLRefill;
        } finally {
            this.activeUploadURLRefill = undefined;
        }

        if (
            this.uploadURLs.length !=
            new Set(this.uploadURLs.map((u) => u.url)).size
        ) {
            throw new Error("Duplicate upload URLs detected");
        }
    }

    private async _refillUploadURLs() {
        if (this.publicAlbumsCredentials) {
            throw new Error(
                "Public uploads should request metadata upload URLs",
            );
        }
        let urls: ObjectUploadURL[];
        try {
            urls = await fetchUploadURLs(this.pendingUploadCount);
        } catch (e) {
            throw translateURLFetchErrorIfNeeded(e);
        }
        urls.forEach((u) => this.uploadURLs.push(u));
    }

    async fetchMultipartUploadURLs(
        uploadPartCount: number,
        metadata?: {
            contentLength: number;
            partLength: number;
            partMd5s: string[];
        },
    ) {
        if (this.publicAlbumsCredentials) {
            if (
                metadata &&
                metadata.contentLength > 0 &&
                metadata.partLength > 0 &&
                metadata.partMd5s.length > 0
            ) {
                return fetchPublicAlbumsMultipartUploadURLsWithMetadata(
                    metadata,
                    this.publicAlbumsCredentials,
                );
            }
            throw new Error(
                "Public multipart uploads require content metadata",
            );
        }
        if (
            metadata &&
            areChecksumProtectedUploadsEnabled() &&
            metadata.contentLength > 0 &&
            metadata.partLength > 0 &&
            metadata.partMd5s.length > 0
        ) {
            return fetchMultipartUploadURLsWithMetadata(metadata).catch(
                (e: unknown) => {
                    throw translateURLFetchErrorIfNeeded(e);
                },
            );
        }
        return fetchMultipartUploadURLs(uploadPartCount).catch((e: unknown) => {
            throw translateURLFetchErrorIfNeeded(e);
        });
    }

    async fetchMultipartUploadURLsWithoutChecksums(
        contentLength: number,
        partLength: number,
    ) {
        if (this.publicAlbumsCredentials) {
            throw new Error("Public uploads require part checksums");
        }
        return fetchMultipartUploadURLsWithMetadata({
            contentLength,
            partLength,
        }).catch((e: unknown) => {
            throw translateURLFetchErrorIfNeeded(e);
        });
    }
}

const uploadService = new UploadService();

export default uploadService;

export const uploadItemFileName = (uploadItem: UploadItem) => {
    if (uploadItem instanceof File) return uploadItem.name;
    if (typeof uploadItem == "string") return basename(uploadItem);
    if (Array.isArray(uploadItem)) return basename(uploadItem[1]);
    return uploadItem.file.name;
};

export interface UploadAsset {
    isLivePhoto?: boolean;
    livePhotoAssets?: LivePhotoAssets;
    uploadItem?: UploadItem;
    pathPrefix: UploadPathPrefix | undefined;
    externalParsedMetadata?: ParsedMetadata;
}

interface ThumbnailedFile {
    fileStreamOrData: FileStream | Uint8Array<ArrayBuffer>;
    thumbnail: Uint8Array<ArrayBuffer>;
    hasStaticThumbnail: boolean;
}

interface FileWithMetadata extends Omit<ThumbnailedFile, "hasStaticThumbnail"> {
    localID: number;
    metadata: FileMetadata;
    publicMagicMetadata: FilePublicMagicMetadataData;
}

interface EncryptedFileStream {
    stream: ReadableStream<Uint8Array<ArrayBuffer>>;
    chunkCount: number;
    encryptedSize: number;
}

interface EncryptedFilePieces {
    file: {
        encryptedData: Uint8Array<ArrayBuffer> | EncryptedFileStream;
        decryptionHeader: string;
    };
    thumbnail: {
        encryptedData: Uint8Array<ArrayBuffer>;
        decryptionHeader: string;
    };
    metadata: { encryptedData: string; decryptionHeader: string };
    pubMagicMetadata: RemoteMagicMetadata | undefined;
    localID: number;
}

export interface PotentialLivePhotoAsset {
    fileName: string;
    fileType: number;
    collectionID: number;
    uploadItem: UploadItem;
    pathPrefix: UploadPathPrefix | undefined;
}

export const areLivePhotoAssets = async (
    f: PotentialLivePhotoAsset,
    g: PotentialLivePhotoAsset,
    parsedMetadataJSONMap: Map<string, ParsedMetadataJSON>,
) => {
    if (f.collectionID != g.collectionID) return false;
    if (f.pathPrefix != g.pathPrefix) return false;

    const [fName, fExt] = nameAndExtension(f.fileName);
    const [gName, gExt] = nameAndExtension(g.fileName);

    let fPrunedName: string;
    let gPrunedName: string;
    if (f.fileType == FileType.image && g.fileType == FileType.video) {
        fPrunedName = removePotentialLivePhotoSuffix(
            fName,
            // Google can name the image half IMG_0001.mp4.jpg.
            gExt ? `.${gExt}` : undefined,
        );
        gPrunedName = removePotentialLivePhotoSuffix(gName);
    } else if (f.fileType == FileType.video && g.fileType == FileType.image) {
        fPrunedName = removePotentialLivePhotoSuffix(fName);
        gPrunedName = removePotentialLivePhotoSuffix(
            gName,
            fExt ? `.${fExt}` : undefined,
        );
    } else {
        return false;
    }

    if (fPrunedName != gPrunedName) return false;

    // The live-photo ZIP encoder cannot stream, so bound each component.
    const maxAssetSize = 20 * 1024 * 1024;
    const fSize = await uploadItemSize(f.uploadItem);
    const gSize = await uploadItemSize(g.uploadItem);
    if (fSize > maxAssetSize || gSize > maxAssetSize) {
        log.info(
            `Not classifying files with too large sizes (${fSize} and ${gSize} bytes) as a live photo`,
        );
        return false;
    }

    const fParsedMetadataJSON = matchJSONMetadata(
        f.pathPrefix,
        f.collectionID,
        f.fileName,
        parsedMetadataJSONMap,
    );
    const gParsedMetadataJSON = matchJSONMetadata(
        g.pathPrefix,
        g.collectionID,
        g.fileName,
        parsedMetadataJSONMap,
    );

    const fDate = await uploadItemCreationDate(
        f.uploadItem,
        f.fileType,
        fParsedMetadataJSON,
    );
    const gDate = await uploadItemCreationDate(
        g.uploadItem,
        g.fileType,
        gParsedMetadataJSON,
    );

    // One component can lack timezone data, producing up to a one-day skew.
    const thresholdSeconds = 24 * 60 * 60;
    const haveSameishDate =
        fDate && gDate && Math.abs(fDate - gDate) / 1e6 < thresholdSeconds;

    if (!haveSameishDate) {
        // Google Takeout omits JSON for the video half of a live photo.
        if (
            (!fParsedMetadataJSON && !gParsedMetadataJSON) ||
            (fParsedMetadataJSON && gParsedMetadataJSON)
        ) {
            return false;
        }
    }

    return true;
};

const removePotentialLivePhotoSuffix = (name: string, suffix?: string) => {
    const suffix_3 = "_3";

    // icloud-photos-downloader appends this to live-photo filenames.
    const suffix_hvec = "_HVEC";

    let foundSuffix: string | undefined;
    if (name.endsWith(suffix_3)) {
        foundSuffix = suffix_3;
    } else if (
        name.endsWith(suffix_hvec) ||
        name.endsWith(suffix_hvec.toLowerCase())
    ) {
        foundSuffix = suffix_hvec;
    } else if (suffix) {
        if (name.endsWith(suffix) || name.endsWith(suffix.toLowerCase())) {
            foundSuffix = suffix;
        }
    }

    return foundSuffix ? name.slice(0, foundSuffix.length * -1) : name;
};

const uploadItemSize = async (uploadItem: UploadItem): Promise<number> => {
    if (uploadItem instanceof File) return uploadItem.size;
    if (typeof uploadItem == "string")
        return ensureElectron().pathOrZipItemSize(uploadItem);
    if (Array.isArray(uploadItem))
        return ensureElectron().pathOrZipItemSize(uploadItem);
    return uploadItem.file.size;
};

const uploadItemCreationDate = async (
    uploadItem: UploadItem,
    fileType: number,
    parsedMetadataJSON: ParsedMetadataJSON | undefined,
) => {
    if (parsedMetadataJSON?.creationTime)
        return parsedMetadataJSON.creationTime;

    let parsedMetadata: ParsedMetadata | undefined;
    if (fileType == FileType.image) {
        parsedMetadata = await tryExtractImageMetadata(uploadItem, undefined);
    } else if (fileType == FileType.video) {
        parsedMetadata = await tryExtractVideoMetadata(uploadItem);
    } else {
        throw new Error(
            `Unexpected file type ${fileType} for ${uploadItemFileName(uploadItem)}`,
        );
    }

    return (
        parsedMetadata?.creationDate?.timestamp ?? parsedMetadata?.creationTime
    );
};

export const uploadCancelledErrorMessage = "Upload cancelled";

export const isUploadCancelledError = (e: unknown) =>
    e instanceof Error && e.message == uploadCancelledErrorMessage;

export const sessionExpiredErrorMessage = "Session expired";

export const subscriptionExpiredErrorMessage = "Subscription expired";

export const storageLimitExceededErrorMessage = "Storage limit exceeded";

const eTagMissingErrorMessage = "ETag header not present in response";

const fileTooLargeErrorMessage = "File too large";

interface UploadContext {
    isCFUploadProxyDisabled: boolean;
    deferMultipartChecksums: boolean;
    isInternalUser: boolean;
    skipDuplicateAddToUploadCollection?: boolean;
    includePartnerSharedFiles?: boolean;
    publicAlbumsCredentials?: PublicAlbumsCredentials;
    abortIfCancelled: () => void;
    updateUploadProgress: (fileLocalID: number, percentage: number) => void;
}

export const upload = async (
    { collection, localID, fileName, ...uploadAsset }: UploadableUploadItem,
    uploaderName: string | undefined,
    existingFiles: EnteFile[],
    parsedMetadataJSONMap: Map<string, ParsedMetadataJSON>,
    worker: CryptoWorker,
    uploadContext: UploadContext,
): Promise<UploadResult> => {
    const {
        abortIfCancelled,
        includePartnerSharedFiles = true,
        skipDuplicateAddToUploadCollection,
    } = uploadContext;

    log.info(`Upload ${fileName} | start`);
    try {
        if (!includePartnerSharedFiles) {
            const parsedMetadataJSON = matchJSONMetadata(
                uploadAsset.pathPrefix,
                collection.id,
                fileName,
                parsedMetadataJSONMap,
            );
            if (parsedMetadataJSON?.fromPartnerSharing) {
                log.info(`Not uploading ${fileName} (from partner sharing)`);
                return { type: "partnerShared" };
            }
        }

        let assetDetails: ReadAssetDetailsResult;

        try {
            assetDetails = await readAssetDetails(uploadAsset);
        } catch (e) {
            if (isFileTypeNotSupportedError(e)) {
                log.error(`Not uploading ${fileName}`, e);
                return { type: "unsupported" };
            }
            throw e;
        }

        const { fileTypeInfo, fileSize, lastModifiedMs } = assetDetails;

        if (fileSize === 0) return { type: "zeroSize" };

        const maxFileSize =
            (uploadContext.isInternalUser ? 20 : 10) * 1024 * 1024 * 1024;
        if (fileSize >= maxFileSize) return { type: "tooLarge" };

        abortIfCancelled();

        const { metadata, publicMagicMetadata } = await extractAssetMetadata(
            uploadAsset,
            fileTypeInfo.fileType,
            lastModifiedMs,
            collection.id,
            parsedMetadataJSONMap,
            worker,
        );

        const matches = existingFiles.filter((file) =>
            areFilesSame(file, metadata),
        );

        const anyMatch = matches.length > 0 ? matches[0] : undefined;

        if (anyMatch) {
            const matchInSameCollection = matches.find(
                (f) => f.collectionID == collection.id,
            );
            if (matchInSameCollection && !skipDuplicateAddToUploadCollection) {
                return { type: "alreadyUploaded", file: matchInSameCollection };
            }

            if (skipDuplicateAddToUploadCollection) {
                return {
                    type: "addedSymlink",
                    file: matchInSameCollection ?? anyMatch,
                };
            }

            const symlink = Object.assign({}, anyMatch);
            symlink.collectionID = collection.id;
            await addToCollection(collection, [symlink]);
            return { type: "addedSymlink", file: symlink };
        }

        abortIfCancelled();

        const { fileStreamOrData, thumbnail, hasStaticThumbnail } =
            await readAsset(fileTypeInfo, uploadAsset);

        if (hasStaticThumbnail) metadata.hasStaticThumbnail = true;

        abortIfCancelled();

        const fileWithMetadata: FileWithMetadata = {
            localID,
            fileStreamOrData,
            thumbnail,
            metadata,
            publicMagicMetadata: {
                ...publicMagicMetadata,
                ...(uploaderName && { uploaderName }),
            },
        };

        const { encryptedFilePieces, encryptedFileKey } = await encryptFile(
            fileWithMetadata,
            collection.key,
            worker,
        );

        abortIfCancelled();

        const backupedFile = await uploadToBucket(
            encryptedFilePieces,
            uploadContext,
        );

        abortIfCancelled();

        const newFileRequest = {
            collectionID: collection.id,
            encryptedKey: encryptedFileKey.encryptedData,
            keyDecryptionNonce: encryptedFileKey.nonce,
            ...backupedFile,
        };

        const uploadedFile = await createRemoteFile(
            newFileRequest,
            uploadContext,
        );

        return {
            type: metadata.hasStaticThumbnail
                ? "uploadedWithStaticThumbnail"
                : "uploaded",
            file: await decryptRemoteFile(uploadedFile, collection.key),
        };
    } catch (e) {
        if (isUploadCancelledError(e)) {
            throw e;
        }

        log.error(`Upload failed for ${fileName}`, e);
        switch (e instanceof Error && e.message) {
            case sessionExpiredErrorMessage:
            case subscriptionExpiredErrorMessage:
            case storageLimitExceededErrorMessage:
                throw e;

            case eTagMissingErrorMessage:
                return { type: "blocked" };
            case fileTooLargeErrorMessage:
                return { type: "largerThanAvailableStorage" };
            default:
                return { type: "failed" };
        }
    }
};

const translateURLFetchErrorIfNeeded = (e: unknown) => {
    if (e instanceof HTTPError) {
        switch (e.res.status) {
            case 401:
                return new Error(sessionExpiredErrorMessage);
            case 402:
                return new Error(subscriptionExpiredErrorMessage);
            case 426:
                return new Error(storageLimitExceededErrorMessage);
        }
    }
    return e;
};

const readUploadItem = async (uploadItem: UploadItem): Promise<FileStream> => {
    let underlyingStream: ReadableStream;
    let file: File | undefined;
    let fileSize: number;
    let lastModifiedMs: number;

    if (typeof uploadItem == "string" || Array.isArray(uploadItem)) {
        const {
            response,
            size,
            lastModifiedMs: lm,
        } = await readStream(ensureElectron(), uploadItem);
        underlyingStream = response.body!;
        fileSize = size;
        lastModifiedMs = lm;
    } else {
        if (uploadItem instanceof File) {
            file = uploadItem;
        } else {
            file = uploadItem.file;
        }
        underlyingStream = file.stream();
        fileSize = file.size;
        lastModifiedMs = file.lastModified;
    }

    const N = streamEncryptionChunkSize;
    const chunkCount = Math.ceil(fileSize / streamEncryptionChunkSize);

    let pending: Uint8Array | undefined;
    const transformer = new TransformStream<Uint8Array, Uint8Array>({
        transform(
            chunk: Uint8Array,
            controller: TransformStreamDefaultController,
        ) {
            let next: Uint8Array;
            if (pending) {
                next = new Uint8Array(pending.length + chunk.length);
                next.set(pending);
                next.set(chunk, pending.length);
                pending = undefined;
            } else {
                next = chunk;
            }
            while (next.length >= N) {
                controller.enqueue(next.slice(0, N));
                next = next.slice(N);
            }
            if (next.length) pending = next;
        },
        flush(controller: TransformStreamDefaultController) {
            if (pending) controller.enqueue(pending);
        },
    });

    const stream = underlyingStream.pipeThrough(transformer);

    return { stream, chunkCount, fileSize, lastModifiedMs, file };
};

interface ReadAssetDetailsResult {
    fileTypeInfo: FileTypeInfo;
    fileSize: number;
    lastModifiedMs: number;
}

const readAssetDetails = async ({
    isLivePhoto,
    livePhotoAssets,
    uploadItem,
}: UploadAsset): Promise<ReadAssetDetailsResult> =>
    isLivePhoto
        ? readLivePhotoDetails(livePhotoAssets!)
        : readImageOrVideoDetails(uploadItem!);

const readLivePhotoDetails = async ({ image, video }: LivePhotoAssets) => {
    const img = await readImageOrVideoDetails(image);
    const vid = await readImageOrVideoDetails(video);

    return {
        fileTypeInfo: {
            fileType: FileType.livePhoto,
            extension: img.fileTypeInfo.extension,
        },
        fileSize: img.fileSize + vid.fileSize,
        lastModifiedMs: img.lastModifiedMs,
    };
};

const readImageOrVideoDetails = async (uploadItem: UploadItem) => {
    const { stream, fileSize, lastModifiedMs } =
        await readUploadItem(uploadItem);

    const fileTypeInfo = await detectFileTypeInfoFromChunk(async () => {
        const reader = stream.getReader();
        const chunk = (await reader.read()).value;
        await reader.cancel();
        return chunk;
    }, uploadItemFileName(uploadItem));

    return { fileTypeInfo, fileSize, lastModifiedMs };
};

const readEntireStream = async (
    stream: ReadableStream,
): Promise<Uint8Array<ArrayBuffer>> =>
    new Uint8Array(await new Response(stream).arrayBuffer());

interface ExtractAssetMetadataResult {
    metadata: FileMetadata;
    publicMagicMetadata: FilePublicMagicMetadataData;
}

const extractAssetMetadata = async (
    {
        isLivePhoto,
        uploadItem,
        livePhotoAssets,
        pathPrefix,
        externalParsedMetadata,
    }: UploadAsset,
    fileType: FileType,
    lastModifiedMs: number,
    collectionID: number,
    parsedMetadataJSONMap: Map<string, ParsedMetadataJSON>,
    worker: CryptoWorker,
): Promise<ExtractAssetMetadataResult> =>
    isLivePhoto
        ? await extractLivePhotoMetadata(
              livePhotoAssets!,
              pathPrefix,
              lastModifiedMs,
              collectionID,
              parsedMetadataJSONMap,
              worker,
          )
        : await extractImageOrVideoMetadata(
              uploadItem!,
              pathPrefix,
              externalParsedMetadata,
              fileType,
              lastModifiedMs,
              collectionID,
              parsedMetadataJSONMap,
              worker,
          );

const extractLivePhotoMetadata = async (
    livePhotoAssets: LivePhotoAssets,
    pathPrefix: UploadPathPrefix | undefined,
    lastModifiedMs: number,
    collectionID: number,
    parsedMetadataJSONMap: Map<string, ParsedMetadataJSON>,
    worker: CryptoWorker,
) => {
    const { metadata: imageMetadata, publicMagicMetadata } =
        await extractImageOrVideoMetadata(
            livePhotoAssets.image,
            pathPrefix,
            undefined,
            FileType.image,
            lastModifiedMs,
            collectionID,
            parsedMetadataJSONMap,
            worker,
        );

    const imageHash = imageMetadata.hash;
    const videoHash = await computeHash(livePhotoAssets.video, worker);

    const hash = `${imageHash}:${videoHash}`;

    return {
        metadata: {
            ...imageMetadata,
            title: uploadItemFileName(livePhotoAssets.image),
            fileType: FileType.livePhoto,
            hash,
        },
        publicMagicMetadata,
    };
};

const extractImageOrVideoMetadata = async (
    uploadItem: UploadItem,
    pathPrefix: UploadPathPrefix | undefined,
    externalParsedMetadata: ParsedMetadata | undefined,
    fileType: FileType,
    lastModifiedMs: number,
    collectionID: number,
    parsedMetadataJSONMap: Map<string, ParsedMetadataJSON>,
    worker: CryptoWorker,
) => {
    const fileName = uploadItemFileName(uploadItem);

    let parsedMetadata: ParsedMetadata | undefined;
    if (fileType == FileType.image) {
        parsedMetadata = await tryExtractImageMetadata(
            uploadItem,
            lastModifiedMs,
        );
    } else if (fileType == FileType.video) {
        parsedMetadata = await tryExtractVideoMetadata(uploadItem);
    } else {
        throw new Error(
            `Unexpected file type ${fileType} for ${uploadItemFileName(uploadItem)}`,
        );
    }

    if (externalParsedMetadata) {
        parsedMetadata = { ...externalParsedMetadata, ...parsedMetadata };
    }

    const hash = await computeHash(uploadItem, worker);

    const parsedMetadataJSON = matchJSONMetadata(
        pathPrefix,
        collectionID,
        fileName,
        parsedMetadataJSONMap,
    );

    const publicMagicMetadata: FilePublicMagicMetadataData = {};

    const modificationTime =
        parsedMetadataJSON?.modificationTime ?? lastModifiedMs * 1000;

    let creationTime: number;
    if (parsedMetadataJSON?.creationTime) {
        creationTime = parsedMetadataJSON.creationTime;
    } else if (parsedMetadata?.creationDate) {
        const { dateTime, offset, timestamp } = parsedMetadata.creationDate;
        creationTime = timestamp;
        publicMagicMetadata.dateTime = dateTime;
        if (offset) publicMagicMetadata.offsetTime = offset;
    } else if (parsedMetadata?.creationTime) {
        creationTime = parsedMetadata.creationTime;
    } else {
        creationTime =
            tryParseEpochMicrosecondsFromFileName(fileName) ?? modificationTime;
    }

    let duration: number | undefined;
    if (fileType == FileType.video) {
        duration = await tryDetermineVideoDuration(uploadItem);
    }

    // Malformed Exif has produced non-numeric dimensions in real uploads.
    const metadata: FileMetadata = {
        fileType,
        title: fileName,
        creationTime: ensureInteger(creationTime),
        modificationTime: ensureInteger(modificationTime),
        hash,
    };

    if (duration) {
        metadata.duration = ensureInteger(Math.ceil(duration));
    }

    const location = parsedMetadataJSON?.location ?? parsedMetadata?.location;
    if (location) {
        metadata.latitude = ensureNumber(location.latitude);
        metadata.longitude = ensureNumber(location.longitude);
    }

    if (parsedMetadata) {
        const { width: w, height: h } = parsedMetadata;
        if (w) publicMagicMetadata.w = ensureInteger(w);
        if (h) publicMagicMetadata.h = ensureInteger(h);
    }

    const caption =
        parsedMetadataJSON?.description ?? parsedMetadata?.description;
    if (
        caption != null &&
        (typeof caption == "string" || typeof caption == "number")
    ) {
        publicMagicMetadata.caption =
            typeof caption == "number" ? String(caption) : caption;
    }

    if (parsedMetadata?.cameraMake) {
        publicMagicMetadata.cameraMake = parsedMetadata.cameraMake;
    }
    if (parsedMetadata?.cameraModel) {
        publicMagicMetadata.cameraModel = parsedMetadata.cameraModel;
    }

    return { metadata, publicMagicMetadata };
};

const tryExtractImageMetadata = async (
    uploadItem: UploadItem,
    lastModifiedMs: number | undefined,
): Promise<ParsedMetadata | undefined> => {
    let file: File;
    if (typeof uploadItem == "string" || Array.isArray(uploadItem)) {
        const { response } = await readStream(ensureElectron(), uploadItem);
        const path = typeof uploadItem == "string" ? uploadItem : uploadItem[1];
        const opts = lastModifiedMs ? { lastModified: lastModifiedMs } : {};
        file = new File([await response.arrayBuffer()], basename(path), opts);
    } else if (uploadItem instanceof File) {
        file = uploadItem;
    } else {
        file = uploadItem.file;
    }

    try {
        return await extractExif(file);
    } catch (e) {
        const fileName = uploadItemFileName(uploadItem);
        log.error(`Failed to extract image metadata for ${fileName}`, e);
        return undefined;
    }
};

const tryExtractVideoMetadata = async (uploadItem: UploadItem) => {
    try {
        return await extractVideoMetadata(uploadItem);
    } catch (e) {
        const fileName = uploadItemFileName(uploadItem);
        log.error(`Failed to extract video metadata for ${fileName}`, e);
        return undefined;
    }
};

const tryDetermineVideoDuration = async (uploadItem: UploadItem) => {
    try {
        return await determineVideoDuration(uploadItem);
    } catch (e) {
        const fileName = uploadItemFileName(uploadItem);
        log.error(`Failed to extract video duration for ${fileName}`, e);
        return undefined;
    }
};

const computeHash = async (uploadItem: UploadItem, worker: CryptoWorker) => {
    const { stream, chunkCount } = await readUploadItem(uploadItem);
    const hashState = await worker.chunkHashInit();

    const streamReader = stream.getReader();
    for (let i = 0; i < chunkCount; i++) {
        const { done, value: chunk } = await streamReader.read();
        if (done) throw new Error("Less chunks than expected");
        await worker.chunkHashUpdate(hashState, Uint8Array.from(chunk));
    }

    const { done } = await streamReader.read();
    if (!done) throw new Error("More chunks than expected");
    return await worker.chunkHashFinal(hashState);
};

const areFilesSame = (fFile: EnteFile, gm: FileMetadata) => {
    const fm = fFile.metadata;

    if (fileFileName(fFile) != gm.title) return false;

    if (fm.fileType != gm.fileType) return false;

    const fh = metadataHash(fm);
    const gh = metadataHash(gm);
    return fh && gh && fh == gh;
};

const readAsset = async (
    fileTypeInfo: FileTypeInfo,
    { isLivePhoto, uploadItem, livePhotoAssets }: UploadAsset,
): Promise<ThumbnailedFile> =>
    isLivePhoto
        ? await readLivePhoto(livePhotoAssets!, fileTypeInfo)
        : await readImageOrVideo(uploadItem!, fileTypeInfo);

const readLivePhoto = async (
    livePhotoAssets: LivePhotoAssets,
    fileTypeInfo: FileTypeInfo,
) => {
    const {
        fileStreamOrData: imageFileStreamOrData,
        thumbnail,
        hasStaticThumbnail,
    } = await augmentWithThumbnail(
        livePhotoAssets.image,
        { fileType: FileType.image, extension: fileTypeInfo.extension },
        await readUploadItem(livePhotoAssets.image),
    );
    const videoFileStreamOrData = await readUploadItem(livePhotoAssets.video);

    // The ZIP encoder accepts blobs or bytes, not streams. The size was bounded above.
    const fileOrData = async (sd: FileStream | Uint8Array<ArrayBuffer>) => {
        const fos = async ({ file, stream }: FileStream) =>
            file ? file : await readEntireStream(stream);
        return sd instanceof Uint8Array ? sd : fos(sd);
    };

    return {
        fileStreamOrData: await encodeLivePhoto({
            imageFileName: uploadItemFileName(livePhotoAssets.image),
            imageFileOrData: await fileOrData(imageFileStreamOrData),
            videoFileName: uploadItemFileName(livePhotoAssets.video),
            videoFileOrData: await fileOrData(videoFileStreamOrData),
        }),
        thumbnail,
        hasStaticThumbnail,
    };
};

const readImageOrVideo = async (
    uploadItem: UploadItem,
    fileTypeInfo: FileTypeInfo,
) => {
    const fileStream = await readUploadItem(uploadItem);
    return augmentWithThumbnail(uploadItem, fileTypeInfo, fileStream);
};

const augmentWithThumbnail = async (
    uploadItem: UploadItem,
    fileTypeInfo: FileTypeInfo,
    fileStream: FileStream,
): Promise<ThumbnailedFile> => {
    let fileData: Uint8Array<ArrayBuffer> | undefined;
    let thumbnail: Uint8Array<ArrayBuffer> | undefined;
    let hasStaticThumbnail = false;

    const electron = globalThis.electron;

    if (electron && !(uploadItem instanceof File)) {
        try {
            thumbnail = await generateThumbnailNative(
                electron,
                uploadItem,
                fileTypeInfo,
            );
        } catch (e) {
            log.error("Native thumbnail generation failed", e);
        }
    }

    if (!thumbnail) {
        let blob: Blob | undefined;
        if (uploadItem instanceof File) {
            blob = uploadItem;
        } else {
            // Never buffer an unbounded video after native thumbnailing fails.
            if (fileTypeInfo.fileType == FileType.image) {
                const data = await readEntireStream(fileStream.stream);
                blob = new Blob([data]);

                fileData = data;
            } else {
                const fileName = uploadItemFileName(uploadItem);
                log.warn(
                    `Not using browser based thumbnail generation fallback for video at path ${fileName}`,
                );
            }
        }

        try {
            if (blob)
                thumbnail = await generateThumbnailWeb(blob, fileTypeInfo);
        } catch (e) {
            log.error("Web thumbnail creation failed", e);
        }
    }

    if (!thumbnail) {
        thumbnail = fallbackThumbnail();
        hasStaticThumbnail = true;
    }

    return {
        fileStreamOrData: fileData ?? fileStream,
        thumbnail,
        hasStaticThumbnail,
    };
};

const encryptFile = async (
    file: FileWithMetadata,
    collectionKey: string,
    worker: CryptoWorker,
) => {
    const fileKey = await worker.generateBlobOrStreamKey();

    const {
        fileStreamOrData,
        thumbnail,
        metadata,
        publicMagicMetadata,
        localID,
    } = file;

    const shouldVerify = areChecksumProtectedUploadsEnabled();
    const encryptedFiledata =
        fileStreamOrData instanceof Uint8Array
            ? await encryptBytesWithOptionalVerification(
                  fileStreamOrData,
                  fileKey,
                  worker,
                  shouldVerify,
              )
            : await encryptFileStream(
                  fileStreamOrData,
                  fileKey,
                  worker,
                  shouldVerify,
              );

    const {
        encryptedData: encryptedThumbnailData,
        decryptionHeader: thumbnailDecryptionHeaderBytes,
    } = await worker.encryptBlobBytes(thumbnail, fileKey);

    const encryptedThumbnail = {
        encryptedData: encryptedThumbnailData,
        decryptionHeader: await worker.toB64(thumbnailDecryptionHeaderBytes),
    };

    const encryptedMetadata = await worker.encryptMetadataJSON(
        metadata,
        fileKey,
    );

    let encryptedPubMagicMetadata: RemoteMagicMetadata | undefined;
    const pubMagicMetadata = createMagicMetadata(publicMagicMetadata);
    if (pubMagicMetadata.count) {
        encryptedPubMagicMetadata = await encryptMagicMetadata(
            pubMagicMetadata,
            fileKey,
        );
    }

    const encryptedFileKey = await worker.encryptBox(fileKey, collectionKey);

    return {
        encryptedFilePieces: {
            file: encryptedFiledata,
            thumbnail: encryptedThumbnail,
            metadata: encryptedMetadata,
            pubMagicMetadata: encryptedPubMagicMetadata,
            localID: localID,
        },
        encryptedFileKey,
    };
};

const encryptBytesWithOptionalVerification = async (
    data: Uint8Array,
    fileKey: BytesOrB64,
    worker: CryptoWorker,
    shouldVerify: boolean,
) => {
    const encrypted = await worker.encryptStreamBytes(data, fileKey);
    if (!shouldVerify) return encrypted;
    try {
        const decrypted = await worker.decryptStreamBytes(encrypted, fileKey);
        if (!areUint8ArraysEqual(decrypted, data)) {
            throw new Error(
                `${bitFlipErrorPrefix}: mismatch while verifying encrypted bytes`,
            );
        }
    } catch (error) {
        log.error("Encrypted bytes verification failed", error);
        throw error instanceof Error
            ? error
            : new Error(
                  `${bitFlipErrorPrefix}: verification failed while encrypting bytes`,
              );
    }
    return encrypted;
};

const encryptFileStream = async (
    { stream, chunkCount, fileSize }: FileStream,
    fileKey: BytesOrB64,
    worker: CryptoWorker,
    shouldVerify: boolean,
) => {
    const fileStreamReader = stream.getReader();
    const { decryptionHeader, pushState } =
        await worker.initChunkEncryption(fileKey);
    const verificationPullState = shouldVerify
        ? (await worker.initChunkDecryption(decryptionHeader, fileKey))
              .pullState
        : undefined;
    const ref = { pullCount: 1 };
    const encryptedFileStream = new ReadableStream<Uint8Array<ArrayBuffer>>({
        async pull(controller) {
            const { value, done } = await fileStreamReader.read();
            if (done) {
                // readUploadItem promised exactly chunkCount chunks.
                controller.close();
                throw new Error("Unexpected stream state");
            }
            const isFinalChunk = ref.pullCount === chunkCount;
            const encryptedFileChunk = await worker.encryptStreamChunk(
                value,
                pushState,
                isFinalChunk,
            );
            if (verificationPullState) {
                try {
                    const decryptedChunk = await worker.decryptStreamChunk(
                        encryptedFileChunk,
                        verificationPullState,
                    );
                    if (!areUint8ArraysEqual(decryptedChunk, value)) {
                        throw new Error(
                            `${bitFlipErrorPrefix}: mismatch while verifying chunk ${ref.pullCount}`,
                        );
                    }
                } catch (error) {
                    log.error(
                        `Encrypted chunk verification failed (chunk ${ref.pullCount})`,
                        error,
                    );
                    throw error instanceof Error
                        ? error
                        : new Error(
                              `${bitFlipErrorPrefix}: verification failed for chunk ${ref.pullCount}`,
                          );
                }
            }
            controller.enqueue(encryptedFileChunk);
            if (isFinalChunk) {
                controller.close();
            }
            ref.pullCount++;
        },
    });
    return {
        decryptionHeader,
        encryptedData: {
            stream: encryptedFileStream,
            chunkCount,
            encryptedSize:
                fileSize + chunkCount * streamEncryptionChunkOverhead,
        },
    };
};

const areUint8ArraysEqual = (a: Uint8Array, b: Uint8Array) => {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
        if (a[i] !== b[i]) return false;
    }
    return true;
};

const uploadToBucket = async (
    encryptedFilePieces: EncryptedFilePieces,
    uploadContext: UploadContext,
): Promise<
    Pick<
        PostEnteFileRequest,
        "file" | "thumbnail" | "metadata" | "pubMagicMetadata"
    >
> => {
    const { isCFUploadProxyDisabled, abortIfCancelled, updateUploadProgress } =
        uploadContext;
    const checksumEnabled = areChecksumProtectedUploadsEnabled();
    const shouldSendContentChecksum =
        checksumEnabled || !!uploadContext.publicAlbumsCredentials;

    const { localID, file, thumbnail, metadata, pubMagicMetadata } =
        encryptedFilePieces;

    const requestRetrier = createAbortableRetryEnsuringHTTPOk(abortIfCancelled);

    const maxPercent = Math.floor(95 + 5 * Math.random());

    let fileObjectKey: string;
    let fileSize: number;

    const encryptedData = file.encryptedData;
    if (
        !(encryptedData instanceof Uint8Array) &&
        encryptedData.chunkCount >= multipartChunksPerPart
    ) {
        ({ objectKey: fileObjectKey, fileSize } =
            await uploadStreamUsingMultipart(
                localID,
                encryptedData,
                uploadContext,
                requestRetrier,
                maxPercent,
                checksumEnabled,
            ));
    } else {
        const data =
            encryptedData instanceof Uint8Array
                ? encryptedData
                : await readEntireStream(encryptedData.stream);
        fileSize = data.length;

        const fileMd5 = shouldSendContentChecksum
            ? computeMd5Base64(data)
            : undefined;
        const fileUploadURL = await uploadService.getUploadURL(
            shouldSendContentChecksum
                ? { contentLength: data.length, contentMd5: fileMd5! }
                : undefined,
        );
        fileObjectKey = fileUploadURL.objectKey;
        const shouldUseWorker = !isCFUploadProxyDisabled;
        if (shouldUseWorker) {
            await putFileViaWorker(fileUploadURL.url, data, requestRetrier, {
                contentMd5: fileMd5,
            });
        } else {
            await putFile(fileUploadURL.url, data, requestRetrier, {
                contentMd5: fileMd5,
            });
        }
        updateUploadProgress(localID, maxPercent);
    }

    const thumbnailMd5 = shouldSendContentChecksum
        ? computeMd5Base64(thumbnail.encryptedData)
        : undefined;
    const thumbnailUploadURL = await uploadService.getUploadURL(
        shouldSendContentChecksum
            ? {
                  contentLength: thumbnail.encryptedData.length,
                  contentMd5: thumbnailMd5!,
              }
            : undefined,
    );
    const shouldUseWorkerForThumbnail = !isCFUploadProxyDisabled;
    if (shouldUseWorkerForThumbnail) {
        await putFileViaWorker(
            thumbnailUploadURL.url,
            thumbnail.encryptedData,
            requestRetrier,
            { contentMd5: thumbnailMd5 },
        );
    } else {
        await putFile(
            thumbnailUploadURL.url,
            thumbnail.encryptedData,
            requestRetrier,
            { contentMd5: thumbnailMd5 },
        );
    }

    return {
        file: {
            decryptionHeader: file.decryptionHeader,
            objectKey: fileObjectKey,
            size: fileSize,
        },
        thumbnail: {
            decryptionHeader: thumbnail.decryptionHeader,
            objectKey: thumbnailUploadURL.objectKey,
            size: thumbnail.encryptedData.length,
        },
        metadata,
        pubMagicMetadata,
    };
};

const createAbortableRetryEnsuringHTTPOk =
    (abortIfCancelled: () => void): HTTPRequestRetrier =>
    (request, opts) =>
        retryAsyncOperation(
            async () => {
                abortIfCancelled();
                const r = await request();
                ensureOk(r);
                return r;
            },
            {
                ...opts,
                abortIfNeeded(e) {
                    if (isUploadCancelledError(e)) throw e;
                },
            },
        );

const uploadStreamUsingMultipart = async (
    fileLocalID: number,
    dataStream: EncryptedFileStream,
    uploadContext: UploadContext,
    requestRetrier: HTTPRequestRetrier,
    maxPercent: number,
    checksumEnabled: boolean,
) => {
    const { isCFUploadProxyDisabled, abortIfCancelled, updateUploadProgress } =
        uploadContext;
    const shouldSendPartChecksums =
        checksumEnabled || !!uploadContext.publicAlbumsCredentials;
    const deferPartChecksums =
        uploadContext.deferMultipartChecksums &&
        !uploadContext.publicAlbumsCredentials;

    const { stream } = dataStream;
    const streamReader = stream.getReader();

    let uploadPartCount = Math.ceil(
        dataStream.chunkCount / multipartChunksPerPart,
    );

    if (shouldSendPartChecksums && !deferPartChecksums) {
        const parts: Uint8Array<ArrayBuffer>[] = [];
        const partMd5s: string[] = [];
        let fileSize = 0;
        while (true) {
            abortIfCancelled();
            const partData = await nextMultipartUploadPart(streamReader);
            if (partData.length === 0) break;
            parts.push(partData);
            fileSize += partData.length;
            partMd5s.push(computeMd5Base64(partData));
        }
        const { done } = await streamReader.read();
        if (!done) throw new Error("More chunks than expected");

        uploadPartCount = parts.length;
        if (uploadPartCount == 0) {
            throw new Error("Multipart upload produced no parts");
        }
        const firstPartLength = parts[0]?.length ?? 0;
        if (firstPartLength == 0) {
            throw new Error("Multipart part length missing");
        }
        const partLength = firstPartLength;

        const multipartUploadURLs =
            await uploadService.fetchMultipartUploadURLs(uploadPartCount, {
                contentLength: fileSize,
                partLength,
                partMd5s,
            });

        const percentPerPart = maxPercent / uploadPartCount;
        const completedParts: MultipartCompletedPart[] = [];
        for (const [
            index,
            partUploadURL,
        ] of multipartUploadURLs.partURLs.entries()) {
            abortIfCancelled();

            const partNumber = index + 1;
            const partData = parts[index];
            const checksum = partMd5s[index];
            if (!partData || !checksum) {
                throw new Error("Multipart checksum part mismatch");
            }

            const eTag = !isCFUploadProxyDisabled
                ? await putFilePartViaWorker(
                      partUploadURL,
                      partData,
                      requestRetrier,
                      { contentMd5: checksum },
                  )
                : await putFilePart(partUploadURL, partData, requestRetrier, {
                      contentMd5: checksum,
                  });
            if (!eTag) throw new Error(eTagMissingErrorMessage);

            updateUploadProgress(fileLocalID, percentPerPart * partNumber);
            completedParts.push({ partNumber, eTag });
            parts[index] = new Uint8Array(0);
        }

        const completionURL = multipartUploadURLs.completeURL;
        if (!isCFUploadProxyDisabled) {
            await completeMultipartUploadViaWorker(
                completionURL,
                completedParts,
                requestRetrier,
            );
        } else {
            await completeMultipartUpload(
                completionURL,
                completedParts,
                requestRetrier,
            );
        }

        return { objectKey: multipartUploadURLs.objectKey, fileSize };
    }

    const partLength = Math.min(
        dataStream.encryptedSize,
        multipartChunksPerPart *
            (streamEncryptionChunkSize + streamEncryptionChunkOverhead),
    );
    const multipartUploadURLs = deferPartChecksums
        ? await uploadService.fetchMultipartUploadURLsWithoutChecksums(
              dataStream.encryptedSize,
              partLength,
          )
        : await uploadService.fetchMultipartUploadURLs(uploadPartCount);
    if (multipartUploadURLs.partURLs.length != uploadPartCount) {
        throw new Error("Unexpected multipart upload URL count");
    }

    const percentPerPart = maxPercent / uploadPartCount;
    let fileSize = 0;
    const completedParts: MultipartCompletedPart[] = [];
    for (const [
        index,
        partUploadURL,
    ] of multipartUploadURLs.partURLs.entries()) {
        abortIfCancelled();

        const partNumber = index + 1;
        const partData = await nextMultipartUploadPart(streamReader);
        fileSize += partData.length;
        const checksum = deferPartChecksums
            ? computeMd5Base64(partData)
            : undefined;

        const eTag = !isCFUploadProxyDisabled
            ? await putFilePartViaWorker(
                  partUploadURL,
                  partData,
                  requestRetrier,
                  { contentMd5: checksum },
              )
            : await putFilePart(partUploadURL, partData, requestRetrier, {
                  contentMd5: checksum,
              });
        if (!eTag) throw new Error(eTagMissingErrorMessage);

        updateUploadProgress(fileLocalID, percentPerPart * partNumber);
        completedParts.push({ partNumber, eTag });
    }
    const { done } = await streamReader.read();
    if (!done) throw new Error("More chunks than expected");

    const completionURL = multipartUploadURLs.completeURL;
    if (!isCFUploadProxyDisabled) {
        await completeMultipartUploadViaWorker(
            completionURL,
            completedParts,
            requestRetrier,
        );
    } else {
        await completeMultipartUpload(
            completionURL,
            completedParts,
            requestRetrier,
        );
    }

    return { objectKey: multipartUploadURLs.objectKey, fileSize };
};

const nextMultipartUploadPart = async (
    streamReader: ReadableStreamDefaultReader<Uint8Array>,
) => {
    const chunks = [];
    for (let i = 0; i < multipartChunksPerPart; i++) {
        const { done, value: chunk } = await streamReader.read();
        if (done) break;
        chunks.push(chunk);
    }
    return mergeUint8Arrays(chunks);
};

const createRemoteFile = async (
    newFileRequest: PostEnteFileRequest,
    uploadContext: UploadContext,
) => {
    const { publicAlbumsCredentials } = uploadContext;

    return publicAlbumsCredentials
        ? retriedPostPublicAlbumsEnteFile(
              newFileRequest,
              publicAlbumsCredentials,
              uploadContext,
          )
        : retriedPostEnteFile(newFileRequest, uploadContext);
};

const retriedPostPublicAlbumsEnteFile = async (
    newFileRequest: PostEnteFileRequest,
    credentials: PublicAlbumsCredentials,
    { abortIfCancelled }: UploadContext,
) =>
    retryAsyncOperation(
        () => {
            abortIfCancelled();
            return postPublicAlbumsEnteFile(newFileRequest, credentials);
        },
        {
            abortIfNeeded: (e) => {
                if (isUploadCancelledError(e)) throw e;
                if (e instanceof HTTPError) {
                    switch (e.res.status) {
                        case 413:
                            throw new Error(fileTooLargeErrorMessage);
                    }
                }
            },
        },
    );

const retriedPostEnteFile = async (
    newFileRequest: PostEnteFileRequest,
    { abortIfCancelled }: UploadContext,
) =>
    retryAsyncOperation(
        () => {
            abortIfCancelled();
            return postEnteFile(newFileRequest);
        },
        {
            abortIfNeeded: (e) => {
                if (isUploadCancelledError(e)) throw e;
                if (e instanceof HTTPError) {
                    switch (e.res.status) {
                        case 401:
                            throw new Error(sessionExpiredErrorMessage);
                        case 402:
                            throw new Error(subscriptionExpiredErrorMessage);
                        case 413:
                            throw new Error(fileTooLargeErrorMessage);
                        case 426:
                            throw new Error(storageLimitExceededErrorMessage);
                    }
                }
            },
        },
    );
