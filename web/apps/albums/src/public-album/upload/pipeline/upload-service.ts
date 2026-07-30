// TODO: Audit this file
/* eslint-disable @typescript-eslint/ban-ts-comment */

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

/**
 * A readable stream for a file, and its associated size and last modified time.
 *
 * This is the in-memory representation of the {@link UploadItem} type that we
 * usually pass around. See: [Note: Reading a UploadItem]
 */
interface FileStream {
    /**
     * A stream of the file's contents
     *
     * This stream is guaranteed to emit data in
     * {@link streamEncryptionChunkSize} sized chunks (except the last chunk
     * which can be smaller since a file would rarely align exactly to a
     * {@link streamEncryptionChunkSize} multiple).
     *
     * Note: A stream can only be read once!
     */
    stream: ReadableStream<Uint8Array>;
    /**
     * Number of chunks {@link stream} will emit, each
     * {@link streamEncryptionChunkSize} sized (except the last one).
     */
    chunkCount: number;
    /**
     * The size in bytes of the underlying file.
     */
    fileSize: number;
    /**
     * The modification time of the file, in epoch milliseconds.
     */
    lastModifiedMs: number;
    /**
     * Set to the underlying {@link File} when we also have access to it.
     */
    file?: File;
}

/**
 * If the stream we have is more than 5 {@link streamEncryptionChunkSize}
 * chunks, then use multipart uploads for it, with each multipart-part
 * containing 5 chunks.
 *
 * {@link streamEncryptionChunkSize} is 4 MB, and the number of chunks in a
 * single upload part is 5, so each part is (up to) 20 MB.
 */
const multipartChunksPerPart = 5;

/** Upload files to cloud storage */
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

/** The singleton instance of {@link UploadService}. */
const uploadService = new UploadService();

export default uploadService;

/**
 * Return the file name for the given {@link uploadItem}.
 */
export const uploadItemFileName = (uploadItem: UploadItem) => uploadItem.name;

/* -- Various intermediate types used during upload -- */

export type ExternalParsedMetadata = ParsedMetadata & {
    creationTime?: number | undefined;
};

export interface UploadAsset {
    /**
     * `true` if this is a live photo.
     */
    isLivePhoto?: boolean;
    /**
     * The two parts of the live photo being uploaded.
     *
     * Valid for live photos.
     */
    livePhotoAssets?: LivePhotoAssets;
    /**
     * The item being uploaded.
     *
     * Valid for non-live photos.
     */
    uploadItem?: UploadItem;
    /**
     * The path prefix of the uploadItem (if not a live photo), or of the image
     * component of the live photo (otherwise).
     *
     * The only expected scenario where this will not be present is when we're
     * uploading an edited file (edited in the in-app image editor).
     */
    pathPrefix: UploadPathPrefix | undefined;
    /**
     * Metadata we know about a file externally. Valid for non-live photos.
     *
     * This is metadata that is not present within the file, but we have
     * available from external sources. There is also a parsed metadata we
     * obtain from JSON files. So together with the metadata present within the
     * file itself, there are three places where the file's initial metadata can
     * be filled in from.
     *
     * This will not be present for live photos.
     */
    externalParsedMetadata?: ExternalParsedMetadata;
}

interface ThumbnailedFile {
    fileStreamOrData: FileStream | Uint8Array<ArrayBuffer>;
    /** The JPEG data of the generated thumbnail */
    thumbnail: Uint8Array<ArrayBuffer>;
    /**
     * `true` if this is a fallback (all black) thumbnail we're returning since
     * thumbnail generation failed for some reason.
     */
    hasStaticThumbnail: boolean;
}

interface FileWithMetadata extends Omit<ThumbnailedFile, "hasStaticThumbnail"> {
    localID: number;
    metadata: FileMetadata;
    publicMagicMetadata: FilePublicMagicMetadataData;
}

interface EncryptedFileStream {
    /**
     * A stream of the file's encrypted contents
     *
     * This stream is guaranteed to emit data in
     * {@link streamEncryptionChunkSize} chunks (except the last chunk which can
     * be smaller since a file would rarely align exactly to a
     * {@link streamEncryptionChunkSize} multiple).
     */
    stream: ReadableStream<Uint8Array<ArrayBuffer>>;
    /**
     * Number of chunks {@link stream} will emit, each
     * {@link streamEncryptionChunkSize} sized (except the last one).
     */
    chunkCount: number;
}

interface EncryptedFilePieces {
    /**
     * The encrypted contents of the file (as bytes or a stream of bytes), and
     * the decryption header that was used during encryption (base64 string).
     */
    file: {
        encryptedData: Uint8Array<ArrayBuffer> | EncryptedFileStream;
        decryptionHeader: string;
    };
    /**
     * The encrypted contents of the file's thumbnail (as bytes), and the
     * decryption header that was used during encryption (base64 string).
     */
    thumbnail: {
        encryptedData: Uint8Array<ArrayBuffer>;
        decryptionHeader: string;
    };
    /**
     * The encrypted contents of the file's metadata (as a base64 string), and
     * the decryption header that was used during encryption (base64 string).
     */
    metadata: { encryptedData: string; decryptionHeader: string };
    pubMagicMetadata: RemoteMagicMetadata | undefined;
    localID: number;
}

export interface PotentialLivePhotoAsset {
    fileName: string;
    fileType: number /* FileType | -1 */;
    collectionID: number;
    uploadItem: UploadItem;
    pathPrefix: UploadPathPrefix | undefined;
}

/**
 * Check if the two given assets should be clubbed together as a live photo.
 */
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
            // A Google Live Photo image file can have video extension appended
            // as suffix, so we pass that to removePotentialLivePhotoSuffix to
            // remove it.
            //
            // Example: IMG_20210630_0001.mp4.jpg (Google Live Photo image file)
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

    // Also check that the size of an individual Live Photo asset is less than
    // an (arbitrary) limit. This should be true in practice as the videos for a
    // live photo are a few seconds long. Further on, the zipping library that
    // we use doesn't support stream as a input.

    const maxAssetSize = 20 * 1024 * 1024; /* 20MB */
    const fSize = uploadItemSize(f.uploadItem);
    const gSize = uploadItemSize(g.uploadItem);
    if (fSize > maxAssetSize || gSize > maxAssetSize) {
        log.info(
            `Not classifying files with too large sizes (${fSize} and ${gSize} bytes) as a live photo`,
        );
        return false;
    }

    // Finally, ensure that the creation times of the image and video are within
    // some epsilon of each other. This is to avoid clubbing together unrelated
    // items that coincidentally have the same name (this is not uncommon since,
    // e.g. many cameras use a deterministic numbering scheme).

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

    // The exact threshold to use is hard to decide. The times should be usually
    // exact to minute, but it is possible that one of the items is missing the
    // timezone while the other has it. Their dates (as shown by the app) would
    // both be correct, just the UTC epochs will vary.
    //
    // Using a threshold of 1 day makes the app more robust to such timezone
    // discrepancies while only marginally increasing the risk of false
    // positives. But this is a heuristic that might not always be correct.
    const thresholdSeconds = 24 * 60 * 60; /* 1 day */
    const haveSameishDate =
        fDate && gDate && Math.abs(fDate - gDate) / 1e6 < thresholdSeconds;

    if (!haveSameishDate) {
        // Google does not include the metadata JSON for the video part of the
        // live photo in the Takeout, causing this date check to fail.
        //
        // So only incorporate this check if either neither file has a metadata
        // JSON, or both have it.
        if (
            (!fParsedMetadataJSON && !gParsedMetadataJSON) ||
            (fParsedMetadataJSON && gParsedMetadataJSON)
        ) {
            return false;
        }
    }

    // All checks pass. Club these two as a live photo.
    return true;
};

const removePotentialLivePhotoSuffix = (name: string, suffix?: string) => {
    const suffix_3 = "_3";

    // The icloud-photos-downloader library appends _HVEC to the end of the
    // filename in case of live photos.
    //
    // https://github.com/icloud-photos-downloader/icloud_photos_downloader
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

/**
 * Return the size of the given {@link uploadItem}.
 */
const uploadItemSize = (uploadItem: UploadItem): number => {
    return uploadItem.size;
};

/**
 * Return the creation date for the given {@link uploadItem}.
 *
 * [Note: Duplicate retrieval of creation date for live photo clubbing]
 *
 * This function duplicates some logic of {@link extractImageOrVideoMetadata}.
 * This duplication, while not good, is currently unavoidable with the way the
 * code is structured since the live photo clubbing happens at an earlier time
 * in the pipeline when we don't have the Exif data, but the Exif data is needed
 * to determine the file's creation time (to ensure that we only club photos and
 * videos with close by creation times, instead of just relying on file names).
 *
 * Note that unlike {@link extractImageOrVideoMetadata}, we don't try to
 * fallback to the file's modification time. This is because for the purpose of
 * live photo clubbing, we wish to use the creation date only in cases where we
 * have it.
 */
const uploadItemCreationDate = async (
    uploadItem: UploadItem,
    fileType: number /* FileType */,
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

    return parsedMetadata?.creationDate?.timestamp;
};

/**
 * The message of the {@link Error} that is thrown when the user cancels an
 * upload.
 *
 * As a convenience, the {@link isUploadCancelledError} matcher can be used to
 * match such errors.
 *
 * [Note: Upload cancellation]
 *
 * 1. User cancels the upload by pressing the cancel button on the upload
 *    progress indicator in the UI.
 *
 * 2. This sets the {@link shouldUploadBeCancelled} flag on
 *    {@link UploadManager}.
 *
 * 3. Periodically the code that is performing the upload calls the
 *    {@link abortIfCancelled} flag. This function is a no-op normally, but if
 *    the {@link shouldUploadBeCancelled} is set then it throws an {@link Error}
 *    with the message set to {@link uploadCancelledErrorMessage}.
 *
 * 4. The intermediate per-file try catch handlers do not intercept this error,
 *    and it bubbles all the way to the top of the call stack, ending the upload.
 */
export const uploadCancelledErrorMessage = "Upload cancelled";

/**
 * A convenience function to check if the provided value is an {@link Error}
 * with message {@link uploadCancelledErrorMessage}.
 */
export const isUploadCancelledError = (e: unknown) =>
    e instanceof Error && e.message == uploadCancelledErrorMessage;

/**
 * The message of the {@link Error} that is thrown when the upload fails because
 * the user's current session has expired (e.g. maybe they logged this client
 * out from another session), and that they need to login again.
 */
export const sessionExpiredErrorMessage = "Session expired";

/**
 * The message of the {@link Error} that is thrown when the upload fails because
 * the user's subscription has expired.
 */
export const subscriptionExpiredErrorMessage = "Subscription expired";

/**
 * The message of the {@link Error} that is thrown when the upload fails because
 * the user's storage space has been exhausted.
 */
export const storageLimitExceededErrorMessage = "Storage limit exceeded";

/**
 * The message of the {@link Error} that is thrown when the PUT request for the
 * upload of a part of file (as part of an overall multipart upload) fails
 * because the response did not have the etag error.
 *
 * This usually happens because some browser extension is blocking access to the
 * ETag header (even when it is present in the remote S3 response). In self
 * hosted scenarios, this can also happen if the remote S3 bucket does not have
 * the appropriate CORS rules to allow access to the etag header.
 */
const eTagMissingErrorMessage = "ETag header not present in response";

/**
 * The message of the {@link Error} that is thrown when the size of the file
 * being uploaded exceeds the maximum allowed file size.
 *
 * The client already checks for the size of the file being uploaded, and aborts
 * the request if the client side limit is exceeded. An error with this message
 * is thrown if we remote side validation fails.
 *
 * The UI outcome is the same in both cases.
 */
const fileTooLargeErrorMessage = "File too large";

/**
 * Some state and callbacks used during upload that are not tied to a specific
 * file being uploaded.
 */
interface UploadContext {
    /**
     * If `true`, then the upload does not go via the worker.
     *
     * See {@link shouldDisableCFUploadProxy} for more details.
     */
    isCFUploadProxyDisabled: boolean;
    /**
     * If present, then the upload is happening in the context of the public
     * albums app and these are the credentials that should be used for
     * performing API requests (instead of trying to obtain and use the
     * credentials for the logged in user, as happens when we're running in the
     * context of the photos app).
     */
    publicAlbumsCredentials: PublicAlbumsCredentials | undefined;
    /**
     * A function that the upload sequence should use to periodically check in
     * and see if the upload has been cancelled by the user.
     *
     * If the upload has been cancelled, it will throw an exception with the
     * message set to {@link uploadCancelledErrorMessage}.
     *
     * See: [Note: Upload cancellation]
     */
    abortIfCancelled: () => void;
    /**
     * A function that gets called update the progress shown in the UI for a
     * particular file as the parts of that file get uploaded.
     *
     * @param {fileLocalID} The local ID of the file whose progress we want to
     * update.
     *
     * @param {percentage} The upload completion percentage, as a value between
     * 0 and 100 (inclusive).
     */
    updateUploadProgress: (fileLocalID: number, percentage: number) => void;
}

/**
 * Upload the given {@link UploadableUploadItem}
 *
 * This is lower layer implementation of the upload. It is invoked by
 * {@link UploadManager} after it has assembled all the relevant bits we need to
 * go forth and upload.
 *
 * @param uploadContext Some general state and callbacks for the entire set of
 * files being uploaded.
 */
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
        /*
         * We read the file four times:
         * 1. To determine its MIME type (only needs first few KBs).
         * 2. To extract its metadata.
         * 3. To calculate its hash.
         * 4. To encrypt it.
         *
         * When we already have a File object the multiple reads are fine.
         *
         * There might be room to optimize further by using
         * `ReadableStream.tee` to perform these steps simultaneously.
         * However, that'll require restructuring the code so that these steps
         * run in a parallel manner (tee will not work for strictly sequential
         * reads of large streams).
         */

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

        const maxFileSize = 10 * 1024 * 1024 * 1024; /* 10 GB */
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
            // The public albums uploader only writes into the current public
            // collection, and its dedup state is scoped to that collection.
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
            /* stop the upload */
            throw e;
        }

        log.error(`Upload failed for ${fileName}`, e);
        switch (e instanceof Error && e.message) {
            /* stop the upload */
            case sessionExpiredErrorMessage:
            case subscriptionExpiredErrorMessage:
            case storageLimitExceededErrorMessage:
                throw e;

            /* file specific */
            case eTagMissingErrorMessage:
                return { type: "blocked" };
            case fileTooLargeErrorMessage:
                return { type: "largerThanAvailableStorage" };
            default:
                return { type: "failed" };
        }
    }
};

/**
 * Convert specific HTTP errors during an API call to remote endpoints for
 * fetching new upload URLs into error with known messages (if applicable).
 *
 */
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

/**
 * Read the given file into an in-memory representation.
 *
 * [Note: Reading a UploadItem]
 *
 * The public albums uploader only deals with browser-provided
 * [File](https://developer.mozilla.org/en-US/docs/Web/API/File) objects.
 */
const readUploadItem = (uploadItem: UploadItem): FileStream => {
    const file = uploadItem;
    const underlyingStream = file.stream();
    const fileSize = file.size;
    const lastModifiedMs = file.lastModified;

    const N = streamEncryptionChunkSize;
    const chunkCount = Math.ceil(fileSize / streamEncryptionChunkSize);

    // Pipe the underlying stream through a transformer that emits
    // streamEncryptionChunkSize-ed chunks (except the last one, which can be
    // smaller).
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

/**
 * Read the associated file(s) to determine the type, size and last modified
 * time of the given {@link asset}.
 */
const readAssetDetails = async ({
    isLivePhoto,
    livePhotoAssets,
    uploadItem,
}: UploadAsset): Promise<ReadAssetDetailsResult> =>
    isLivePhoto
        ? // @ts-ignore
          readLivePhotoDetails(livePhotoAssets)
        : // @ts-ignore
          readImageOrVideoDetails(uploadItem);

const readLivePhotoDetails = async ({ image, video }: LivePhotoAssets) => {
    const img = await readImageOrVideoDetails(image);
    const vid = await readImageOrVideoDetails(video);

    return {
        fileTypeInfo: {
            fileType: FileType.livePhoto,
            // Use the extension of the image component as the extension of the
            // live photo.
            extension: img.fileTypeInfo.extension,
        },
        fileSize: img.fileSize + vid.fileSize,
        lastModifiedMs: img.lastModifiedMs,
    };
};

/**
 * Read the beginning of the given file to determine its MIME type. From that,
 * construct and return a {@link FileTypeInfo}.
 *
 * While we're at it, also return the size of the file, and its last modified
 * time (expressed as epoch milliseconds).
 *
 * @param uploadItem See: [Note: Reading a UploadItem]
 */
const readImageOrVideoDetails = async (uploadItem: UploadItem) => {
    const { stream, fileSize, lastModifiedMs } = readUploadItem(uploadItem);

    // @ts-ignore
    const fileTypeInfo = await detectFileTypeInfoFromChunk(async () => {
        const reader = stream.getReader();
        const chunk = (await reader.read()).value;
        await reader.cancel();
        return chunk;
    }, uploadItemFileName(uploadItem));

    return { fileTypeInfo, fileSize, lastModifiedMs };
};

/**
 * Read the entirety of a readable stream.
 *
 * It is not recommended to use this for large (say, multi-hundred MB) files. It
 * is provided as a syntactic shortcut for cases where we already know that the
 * size of the stream will be reasonable enough to be read in its entirety
 * without us running out of memory.
 */
const readEntireStream = async (
    stream: ReadableStream,
): Promise<Uint8Array<ArrayBuffer>> =>
    new Uint8Array(await new Response(stream).arrayBuffer());

interface ExtractAssetMetadataResult {
    metadata: FileMetadata;
    publicMagicMetadata: FilePublicMagicMetadataData;
}

/**
 * Compute the hash, extract Exif or other metadata, and merge in data from the
 * {@link parsedMetadataJSONMap} for the assets. Return the resultant metadatum.
 */
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
              // @ts-ignore
              livePhotoAssets,
              pathPrefix,
              lastModifiedMs,
              collectionID,
              parsedMetadataJSONMap,
              worker,
          )
        : await extractImageOrVideoMetadata(
              // @ts-ignore
              uploadItem,
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
    externalParsedMetadata: ExternalParsedMetadata | undefined,
    fileType: FileType,
    lastModifiedMs: number,
    collectionID: number,
    parsedMetadataJSONMap: Map<string, ParsedMetadataJSON>,
    worker: CryptoWorker,
) => {
    const fileName = uploadItemFileName(uploadItem);

    let parsedMetadata: (ParsedMetadata & ExternalParsedMetadata) | undefined;
    if (fileType == FileType.image) {
        parsedMetadata = await tryExtractImageMetadata(uploadItem);
    } else if (fileType == FileType.video) {
        parsedMetadata = await tryExtractVideoMetadata(uploadItem);
    } else {
        throw new Error(
            `Unexpected file type ${fileType} for ${uploadItemFileName(uploadItem)}`,
        );
    }

    // The `UploadAsset` itself might have metadata associated with a-priori, if
    // so, merge the data we read from the file's contents into it.
    if (externalParsedMetadata) {
        parsedMetadata = { ...externalParsedMetadata, ...parsedMetadata };
    }

    const hash = await computeHash(uploadItem, worker);

    // Some of this logic is duplicated in `uploadItemCreationDate`.
    //
    // See: [Note: Duplicate retrieval of creation date for live photo clubbing]

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

    // Video duration
    let duration: number | undefined;
    if (fileType == FileType.video) {
        duration = await tryDetermineVideoDuration(uploadItem);
    }

    // To avoid introducing malformed data into the metadata fields (which the
    // other clients might not expect and handle), we have extra "ensure" checks
    // here that act as a safety valve if somehow the TypeScript type is lying.
    //
    // There is no deterministic sample we found that necessitated adding these
    // extra checks, but we did get one user with a list in the width field of
    // the metadata (it should've been an integer). The most probable theory is
    // that somehow it made its way in through malformed Exif.

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

/**
 * Compute the hash of an item we're attempting to upload.
 *
 * The hash is retained in the file metadata, and is also used to detect
 * duplicates during upload.
 *
 * This process can take a noticable amount of time. As an extreme case, for a
 * 10 GB upload item, this can take a 2-3 minutes.
 *
 * @param uploadItem The {@link UploadItem} we're attempting to upload.
 *
 * @param worker A {@link CryptoWorker} to use for computing the hash.
 */
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

/**
 * Return true if the given file is the same as provided metadata.
 *
 * Note that the metadata includes the hash of the file's contents (when
 * available), so this also in effect compares the contents of the files, not
 * just the "meta" information about them.
 */
const areFilesSame = (fFile: EnteFile, gm: FileMetadata) => {
    const fm = fFile.metadata;

    // File name is different.
    if (fileFileName(fFile) != gm.title) return false;

    // File type is different.
    if (fm.fileType != gm.fileType) return false;

    // Name and type is same, compare hash.
    const fh = metadataHash(fm);
    const gh = metadataHash(gm);
    return fh && gh && fh == gh;
};

const readAsset = async (
    fileTypeInfo: FileTypeInfo,
    { isLivePhoto, uploadItem, livePhotoAssets }: UploadAsset,
): Promise<ThumbnailedFile> =>
    isLivePhoto
        ? // @ts-ignore
          await readLivePhoto(livePhotoAssets, fileTypeInfo)
        : // @ts-ignore
          await readImageOrVideo(uploadItem, fileTypeInfo);

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
        // For live photos, the extension field in the file type info is the
        // extension of the image component of the live photo.
        { fileType: FileType.image, extension: fileTypeInfo.extension },
        readUploadItem(livePhotoAssets.image),
    );
    const videoFileStreamOrData = readUploadItem(livePhotoAssets.video);

    // The JS zip library that encodeLivePhoto uses does not support
    // ReadableStreams, so pass the file (blob) if we have one, otherwise read
    // the entire stream into memory and pass the resultant data.
    //
    // This is a reasonable behaviour since the videos corresponding to live
    // photos are only a couple of seconds long (we've already done a pre-flight
    // check during areLivePhotoAssets to ensure their size is small).
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

/**
 * Augment the given {@link dataOrStream} with thumbnail information.
 *
 * This is a companion method for {@link readUploadItem}, and can be used to
 * convert the result of {@link readUploadItem} into an {@link ThumbnailedFile}.
 *
 * @param uploadItem The {@link UploadItem} where the given {@link fileStream}
 * came from.
 *
 * Note: The `fileStream` in the returned {@link ThumbnailedFile} may be
 * different from the one passed to the function.
 */
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
                // TransformStream in readUploadItem guarantees that we'll get
                // encryption sized `chunkCount` chunks. Below we close the
                // controller on the last chunk. So we shouldn't be getting a
                // `done` here.
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

    // The bulk of the network time during upload is taken in uploading the
    // actual encrypted objects to remote S3, but after that there is another
    // API request we need to make to "finalize" the file (on museum). This
    // should be quick usually, but it's a different network route altogether
    // and we can't know for sure how long it'll take. So keep aside a small
    // approximate percentage for this last step.
    const maxPercent = Math.floor(95 + 5 * Math.random());

    let fileObjectKey: string;
    let fileSize: number;

    const encryptedData = file.encryptedData;
    if (
        !(encryptedData instanceof Uint8Array) &&
        encryptedData.chunkCount >= multipartChunksPerPart
    ) {
        // We have a stream, and it is more than multipartChunksPerPart
        // chunks long, so use a multipart upload to upload it.
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

/**
 * A factory method that returns a function which will act like variant of
 * {@link retryEnsuringHTTPOk} and also understands the cancellation mechanism
 * used by the upload subsystem.
 *
 * @param abortIfCancelled A function that aborts the operation by throwing a
 * error with the message set to {@link uploadCancelledErrorMessage} if the user
 * has cancelled the upload.
 *
 * @return A function of type {@link HTTPRequestRetrier} that can be used to
 * retry requests. This function will retry requests (obtained afresh each time
 * by calling the provided {@link request} function) in the same manner as
 * {@link retryEnsuringHTTPOk}. Additionally, it will call
 * {@link abortIfCancelled} before each attempt, and also bypass the retries
 * when the abort happens on such cancellations.
 */
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

    // Public album uploads always request metadata-aware multipart URLs, so we
    // first materialize each part to compute its checksum.
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

/**
 * Construct byte arrays, up to 20 MB each, containing the contents of (up to)
 * the next 5 {@link streamEncryptionChunkSize} chunks read from the given
 * {@link streamReader}.
 */
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

/**
 * Finalize an upload by creating an {@link EnteFile} on remote.
 */
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
