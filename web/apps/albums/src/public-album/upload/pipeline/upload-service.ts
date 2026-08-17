import type { BytesOrB64 } from "ente-base/crypto/types";
import { streamEncryptionChunkSize } from "ente-base/crypto/types";
import type { CryptoWorker } from "ente-base/crypto/worker";
import { nameAndExtension } from "ente-base/file-name";
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
import { tryParseEpochMicrosecondsFromFileName } from "ente-gallery/services/upload/date";
import { computeMd5Base64 } from "ente-gallery/services/upload/md5";
import {
    detectFileTypeInfoFromChunk,
    isFileTypeNotSupportedError,
} from "ente-gallery/utils/detect-type";
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
import { matchJSONMetadata, type ParsedMetadataJSON } from "./metadata-json";
import {
    completeMultipartUpload,
    completeMultipartUploadViaWorker,
    fetchPublicAlbumsMultipartUploadURLsWithMetadata,
    fetchPublicAlbumsUploadURLWithMetadata,
    postPublicAlbumsEnteFile,
    putFile,
    putFilePart,
    putFilePartViaWorker,
    putFileViaWorker,
    type MultipartCompletedPart,
    type PostEnteFileRequest,
} from "./remote";
import { fallbackThumbnail, generateThumbnailWeb } from "./thumbnail";

const bitFlipErrorPrefix = "BitFlipDetected";

interface FileStream {
    stream: ReadableStream<Uint8Array>;
    chunkCount: number;
    fileSize: number;
    lastModifiedMs: number;
    file?: File;
}

const multipartChunksPerPart = 5;

class UploadService {
    private publicAlbumsCredentials: PublicAlbumsCredentials | undefined;

    init(publicAlbumsCredentials: PublicAlbumsCredentials | undefined) {
        this.publicAlbumsCredentials = publicAlbumsCredentials;
    }

    logout() {
        this.publicAlbumsCredentials = undefined;
    }

    setFileCount(fileCount: number) {
        void fileCount;
    }

    reducePendingUploadCount() {
        return undefined;
    }

    async getUploadURL(metadata?: {
        contentLength: number;
        contentMd5: string;
    }) {
        const credentials = this.publicAlbumsCredentials;
        if (!credentials) {
            throw new Error("Missing public album credentials");
        }
        if (!metadata || metadata.contentLength < 0 || !metadata.contentMd5) {
            throw new Error("Public uploads require content metadata");
        }
        try {
            return await fetchPublicAlbumsUploadURLWithMetadata(
                metadata,
                credentials,
            );
        } catch (e) {
            throw translateURLFetchErrorIfNeeded(e);
        }
    }

    async fetchMultipartUploadURLs(
        _uploadPartCount: number,
        metadata?: {
            contentLength: number;
            partLength: number;
            partMd5s: string[];
        },
    ) {
        const credentials = this.publicAlbumsCredentials;
        if (!credentials) {
            throw new Error("Missing public album credentials");
        }
        if (
            !metadata ||
            metadata.contentLength <= 0 ||
            metadata.partLength <= 0 ||
            metadata.partMd5s.length == 0
        ) {
            throw new Error(
                "Public multipart uploads require content metadata",
            );
        }
        return fetchPublicAlbumsMultipartUploadURLsWithMetadata(
            metadata,
            credentials,
        ).catch((e: unknown) => {
            throw translateURLFetchErrorIfNeeded(e);
        });
    }
}

const uploadService = new UploadService();

export default uploadService;

export const uploadItemFileName = (uploadItem: UploadItem) => uploadItem.name;

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
    // -1 means unknown.
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
            // Google Live Photo images can be named like IMG_0001.mp4.jpg.
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

    // Live photos are read into memory before zipping.
    const maxAssetSize = 20 * 1024 * 1024;
    const fSize = uploadItemSize(f.uploadItem);
    const gSize = uploadItemSize(g.uploadItem);
    if (fSize > maxAssetSize || gSize > maxAssetSize) {
        log.info(
            `Not classifying files with too large sizes (${fSize} and ${gSize} bytes) as a live photo`,
        );
        return false;
    }

    // Camera filenames repeat, so matching names are not enough.
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

    // Allow one day because either asset may be missing timezone metadata.
    const thresholdSeconds = 24 * 60 * 60;
    const haveSameishDate =
        fDate && gDate && Math.abs(fDate - gDate) / 1e6 < thresholdSeconds;

    if (!haveSameishDate) {
        // Takeout omits some video sidecars.
        // Enforce dates only when both assets have sidecars or neither does.
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

    // icloud-photos-downloader appends "_HVEC" to Live Photo names.
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

const uploadItemSize = (uploadItem: UploadItem): number => {
    return uploadItem.size;
};

// Live-photo matching happens before full metadata extraction.
// Do not fall back to modification time here.
const uploadItemCreationDate = async (
    uploadItem: UploadItem,
    fileType: number,
    parsedMetadataJSON: ParsedMetadataJSON | undefined,
) => {
    if (parsedMetadataJSON?.creationTime)
        return parsedMetadataJSON.creationTime;

    let parsedMetadata: ParsedMetadata | undefined;
    if (fileType == FileType.image) {
        parsedMetadata = await tryExtractImageMetadata(uploadItem);
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
    publicAlbumsCredentials: PublicAlbumsCredentials | undefined;
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
    const { abortIfCancelled } = uploadContext;

    log.info(`Upload ${fileName} | start`);
    try {
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

        const maxFileSize = 10 * 1024 * 1024 * 1024;
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
            return {
                type: "alreadyUploaded",
                file: matchInSameCollection ?? anyMatch,
            };
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

const readUploadItem = (uploadItem: UploadItem): FileStream => {
    const file = uploadItem;
    const underlyingStream = file.stream();
    const fileSize = file.size;
    const lastModifiedMs = file.lastModified;

    const N = streamEncryptionChunkSize;
    const chunkCount = Math.ceil(fileSize / streamEncryptionChunkSize);

    // Encryption requires fixed-size chunks.
    // Only the final chunk may be smaller.
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
            // A live photo uses its image extension.
            extension: img.fileTypeInfo.extension,
        },
        fileSize: img.fileSize + vid.fileSize,
        lastModifiedMs: img.lastModifiedMs,
    };
};

const readImageOrVideoDetails = async (uploadItem: UploadItem) => {
    const { stream, fileSize, lastModifiedMs } = readUploadItem(uploadItem);

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
        parsedMetadata = await tryExtractImageMetadata(uploadItem);
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

    // Malformed Exif has put arrays in numeric fields.
    // Keep these runtime checks even though TypeScript considers them redundant.
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
): Promise<ParsedMetadata | undefined> => {
    try {
        return await extractExif(uploadItem);
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
    const { stream, chunkCount } = readUploadItem(uploadItem);
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
        readUploadItem(livePhotoAssets.image),
    );
    const videoFileStreamOrData = readUploadItem(livePhotoAssets.video);

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
    const fileStream = readUploadItem(uploadItem);
    return augmentWithThumbnail(uploadItem, fileTypeInfo, fileStream);
};

const augmentWithThumbnail = async (
    uploadItem: UploadItem,
    fileTypeInfo: FileTypeInfo,
    fileStream: FileStream,
): Promise<ThumbnailedFile> => {
    let thumbnail: Uint8Array<ArrayBuffer> | undefined;
    let hasStaticThumbnail = false;

    try {
        thumbnail = await generateThumbnailWeb(uploadItem, fileTypeInfo);
    } catch (e) {
        log.error("Web thumbnail creation failed", e);
    }

    if (!thumbnail) {
        thumbnail = fallbackThumbnail();
        hasStaticThumbnail = true;
    }

    return { fileStreamOrData: fileStream, thumbnail, hasStaticThumbnail };
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
    { stream, chunkCount }: FileStream,
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
        encryptedData: { stream: encryptedFileStream, chunkCount },
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

    // Leave room for the final API request.
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
) => {
    const { isCFUploadProxyDisabled, abortIfCancelled, updateUploadProgress } =
        uploadContext;

    const { stream } = dataStream;
    const streamReader = stream.getReader();

    // The API needs every part checksum before it returns upload URLs.
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

    const uploadPartCount = parts.length;
    if (uploadPartCount == 0) {
        throw new Error("Multipart upload produced no parts");
    }
    const partLength = parts[0]?.length ?? 0;
    if (partLength == 0) {
        throw new Error("Multipart part length missing");
    }

    const multipartUploadURLs = await uploadService.fetchMultipartUploadURLs(
        uploadPartCount,
        { contentLength: fileSize, partLength, partMd5s },
    );

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
        parts[index] = new Uint8Array(0); // release memory
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
    if (!publicAlbumsCredentials) {
        throw new Error("Missing public album credentials");
    }
    return retriedPostPublicAlbumsEnteFile(
        newFileRequest,
        publicAlbumsCredentials,
        uploadContext,
    );
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
