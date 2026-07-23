import { blobCache, type BlobCache } from "ente-base/blob-cache";
import {
    decryptBlobBytes,
    decryptStreamBytes,
    decryptStreamChunk,
    initChunkDecryption,
} from "ente-base/crypto";
import log from "ente-base/log";
import type { EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { decodeLivePhoto } from "ente-media/live-photo";
import { detectFileTypeInfoFromChunk } from "../utils/detect-type";

/**
 * URL(s) for the original image or video, alongwith with potential conversions
 * applied to make it more likely that the browser will be able to render (or
 * play) it.
 *
 * The word "renderable" or "playable" is not a guarantee, but rather a best
 * effort indicator as we might not always be able to convert all formats to
 * something that the browser can show.
 */
export type RenderableSourceURLs =
    | {
          type: "image";
          /**
           * An object URL that can be directly provided to the browser to get
           * it to render the image.
           *
           * This is a best effort basis. Not all images will be renderable in
           * all browsers, so the file might still not be previewable.
           *
           * In cases where we detect that the browser can natively render this
           * image, this can be just the an object URL created from
           * {@link originalImageBlob}. In other cases, this will point to a
           * separate, converted blob.
           */
          imageURL: string;
          /**
           * A {@link Blob} from the original image.
           *
           * This is useful for extracting the Exif.
           */
          originalImageBlob: Blob;
          /**
           * Best effort attempt at obtaining the MIME type.
           *
           * It should usually be present, but it is not guaranteed that we'll
           * be able to detect the MIME type for all images. However, the only
           * scenario where it is needed currently is by the image editor, where
           * if we can't detect the MIME type, then the image can't be shown (or
           * edited) in the current browser anyway.
           */
          mimeType?: string;
      }
    | {
          type: "video";
          /**
           * An object URL that can be directly provided to the browser to get
           * it to render the image.
           *
           * This is a best effort basis. Not all videos will be playable in all
           * browsers, so the file might still not be previewable.
           */
          videoURL: string;
      }
    | {
          type: "livePhoto";
          /**
           * Similar to the {@link imageURL} for type "image", except
           * as a promise since we might want to operate on the different
           * components of a live image in a staggered order.
           */
          imageURL: () => Promise<string>;
          /**
           * Similar to the {@link originalImageBlob} for type "image".
           */
          originalImageBlob: Blob;
          /**
           * Similar to the {@link videoURL} for type "video", except as
           * a promise since we might want to operate on the different
           * components of a live image in a staggered order.
           */
          videoURL: () => Promise<string>;
      };

/**
 * Options for file downloads.
 */
export interface FileDownloadOpts {
    /**
     * `true` if the request is for a background task. These are considered less
     * latency sensitive than user initiated interactive requests.
     *
     * See: [Note: User initiated vs background downloads of files].
     */
    background?: boolean;
}

export interface DownloadManagerTransport {
    downloadThumbnail: (file: EnteFile) => Promise<Uint8Array<ArrayBuffer>>;
    downloadFile: (
        file: EnteFile,
        opts?: FileDownloadOpts,
    ) => Promise<Response>;
    renderableImageBlob: (imageBlob: Blob, fileName: string) => Promise<Blob>;
    playableVideoURL: (
        file: EnteFile,
        videoFileName: string,
        videoBlob: Blob,
    ) => Promise<string>;
}

/**
 * A class that tracks the state of in-progress downloads and conversions,
 * including caching them for subsequent retrieval if appropriate.
 */
export class DownloadManagerCore {
    /**
     * Local cache for thumbnail blobs.
     *
     * `undefined` indicates that the cache has not yet been initialized. It is
     * also possible that the cache might not be available, in which case it'd
     * be set to `null`.
     */
    private thumbnailCache: BlobCache | null | undefined;
    /**
     * An in-memory cache for an object URL to a file's thumbnail.
     *
     * This object URL can be directly used to render the thumbnail (e.g. in an
     * img tag). The entries are keyed by the file ID.
     */
    private thumbnailURLPromises = new Map<
        number,
        Promise<string | undefined>
    >();
    /**
     * An in-memory cache for an object URL to a file's original data.
     *
     * Unlike {@link thumbnailURLPromises}, there is no guarantee that the
     * browser will be able to render the original file (e.g. it might be in an
     * unsupported format). If a renderable URL is needed for the file,
     * {@link renderableSourceURLs} should be used instead.
     *
     * The entries are keyed by file ID.
     */
    private fileURLPromises = new Map<number, Promise<string>>();
    /**
     * An in-memory cache for {@link RenderableSourceURLs} for a file.
     *
     * These are saved as a result of invocation of
     * {@link renderableSourceURLs}, which goes one step beyond
     * {@link fileURLPromises}, and also attempts to convert the downloaded file
     * into a URL that the browser is likely to be able to render or play.
     *
     * The entries are keyed by file ID.
     */
    private renderableSourceURLPromises = new Map<
        number,
        Promise<RenderableSourceURLs>
    >();

    /**
     * A map from file ID to the progress (0-100%) of its active download (if
     * any).
     *
     * [Note: Tracking active file download progress in the UI]
     *
     * The download manager maintains a map of download progress for all files
     * which are being downloaded in a streaming manner (which is currently only
     * videos). The UI can observe this by using {@link useSyncExternalStore} in
     * combination with the {@link fileDownloadProgressSubscribe} and
     * {@link fileDownloadProgressSnapshot} methods of the download manager.
     */
    private fileDownloadProgress = new Map<number, number>();
    private fileDownloadProgressListeners: (() => void)[] = [];

    constructor(private transport: DownloadManagerTransport) {}

    private async initThumbnailCacheIfNeeded() {
        if (this.thumbnailCache === undefined) {
            try {
                this.thumbnailCache = await blobCache("thumbs");
            } catch (e) {
                this.thumbnailCache = null;
                log.error(
                    "Failed to open thumbnail cache, will continue without it",
                    e,
                );
            }
        }
    }

    /**
     * Reset the internal state of the download manager.
     */
    logout() {
        this.thumbnailURLPromises.clear();
        this.fileURLPromises.clear();
        this.renderableSourceURLPromises.clear();
        this.fileDownloadProgress.clear();
        this.fileDownloadProgressListeners = [];
    }

    /**
     * See: [Note: Tracking active file download progress in the UI]
     */
    fileDownloadProgressSubscribe(onChange: () => void) {
        this.fileDownloadProgressListeners.push(onChange);
        return () => {
            this.fileDownloadProgressListeners =
                this.fileDownloadProgressListeners.filter((l) => l != onChange);
        };
    }

    /**
     * See: [Note: Tracking active file download progress in the UI]
     */
    fileDownloadProgressSnapshot() {
        return this.fileDownloadProgress;
    }

    private setFileDownloadProgress(progress: Map<number, number>) {
        this.fileDownloadProgress = progress;
        this.fileDownloadProgressListeners.forEach((l) => l());
    }

    /**
     * Resolves with an URL that points to the file's thumbnail.
     *
     * The thumbnail will be downloaded if needed (unless {@link cachedOnly} is
     * true). It will also be cached for subsequent fetches.
     *
     * The optional {@link cachedOnly} parameter can be set to indicate that
     * this is being called as part of a scroll, so the downloader should not
     * attempt to download the file but should instead fulfill the request from
     * the disk cache. This avoids an unbounded flurry of requests on scroll,
     * only downloading when the position has quiescized.
     *
     * The returned URL is actually an object URL, but it should not be revoked
     * since the download manager caches it for future use.
     *
     * If {@link cachedOnly} is false (the default), then this method will
     * indicate errors by throwing but will never return `undefined`.
     */
    async renderableThumbnailURL(
        file: EnteFile,
        cachedOnly = false,
    ): Promise<string | undefined> {
        if (!this.thumbnailURLPromises.has(file.id)) {
            const url = this.thumbnailData(file, cachedOnly).then((data) =>
                data ? URL.createObjectURL(new Blob([data])) : undefined,
            );
            this.thumbnailURLPromises.set(file.id, url);
        }

        let thumb: string | undefined;
        try {
            thumb = await this.thumbnailURLPromises.get(file.id);
        } catch (e) {
            // Do not cache a failed promise; allow follow-up calls to retry.
            this.thumbnailURLPromises.delete(file.id);
            throw e;
        }

        if (cachedOnly) return thumb;

        if (!thumb) {
            this.thumbnailURLPromises.delete(file.id);
            thumb = await this.renderableThumbnailURL(file);
        }
        return thumb;
    }

    /**
     * Returns the thumbnail data for a file, downloading it if needed.
     *
     * The data is cached on disk for subsequent fetches.
     *
     * @param file The {@link EnteFile} whose thumbnail we want.
     *
     * @param cachedOnly If true, then the thumbnail is not downloaded if it is
     * not already present in the disk cache.
     *
     * @returns The bytes of the thumbnail, as a {@link Uint8Array}. This method
     * can return `undefined` iff the thumbnail is not already cached, and
     * {@link cachedOnly} is set to `true`.
     */
    async thumbnailData(
        file: EnteFile,
        cachedOnly = false,
    ): Promise<Uint8Array<ArrayBuffer> | undefined> {
        await this.initThumbnailCacheIfNeeded();

        const key = file.id.toString();
        const cached = await this.thumbnailCache?.get(key);
        if (cached) return new Uint8Array(await cached.arrayBuffer());
        if (cachedOnly) return undefined;

        const thumb = await this.downloadThumbnail(file);
        await this.thumbnailCache?.put(key, new Blob([thumb]));
        return thumb;
    }

    private downloadThumbnail = async (file: EnteFile) => {
        const encryptedData = await wrapErrors(() =>
            this.transport.downloadThumbnail(file),
        );
        const decryptionHeader = file.thumbnail.decryptionHeader;
        return decryptBlobBytes({ encryptedData, decryptionHeader }, file.key);
    };

    /**
     * Return a URL (and associated metadata) that can be used to show the given
     * {@link file} within the app, converting its format (on the fly) if needed
     * (if possible).
     *
     * See the documentation of {@link RenderableSourceURLs} for more details.
     */
    renderableSourceURLs = async (
        file: EnteFile,
    ): Promise<RenderableSourceURLs> => {
        let promise = this.renderableSourceURLPromises.get(file.id);
        if (!promise) {
            promise = createRenderableSourceURLs(
                file,
                this.fileURLDownloadAndCacheIfNeeded(file),
                this.transport,
            );
            this.renderableSourceURLPromises.set(file.id, promise);
        }

        try {
            return await promise;
        } catch (e) {
            log.error("Failed to obtain renderableSourceURLs", e);
            this.renderableSourceURLPromises.delete(file.id);
            throw e;
        }
    };

    /**
     * Return a blob to the file's contents, downloading it needed.
     *
     * This is a convenience abstraction over {@link fileStream} that converts
     * it into a {@link Blob}.
     */
    async fileBlob(file: EnteFile, opts?: FileDownloadOpts) {
        const _fileBlob = () =>
            this.fileStream(file, opts).then((stream) =>
                this.blobWithInferredType(file, stream),
            );

        const cachedURL = this.fileURLPromises.get(file.id);
        try {
            return await _fileBlob();
        } catch (e) {
            // If the stream came from a cached object URL then retry once
            // to rule out issues with the cache.
            if (cachedURL) {
                this.fileURLPromises.delete(file.id);
                return _fileBlob();
            } else {
                throw e;
            }
        }
    }

    /**
     * Return an stream to the file's contents, downloading it needed.
     *
     * Note that the results are not cached in-memory. That is, while the
     * request may be served from the existing item in the in-memory cache, if
     * it is not found and a download is required, that result will not be
     * cached for subsequent use.
     *
     * @param file The {@link EnteFile} whose data we want.
     *
     * @param opts Optional options to modify the download.
     */
    async fileStream(
        file: EnteFile,
        opts?: FileDownloadOpts,
    ): Promise<ReadableStream<Uint8Array> | null> {
        const cachedURL = this.fileURLPromises.get(file.id);
        if (cachedURL) {
            try {
                const url = await cachedURL;
                const res = await fetch(url);
                return res.body;
            } catch (e) {
                log.warn("Failed to use cached object URL", e);
                this.fileURLPromises.delete(file.id);
            }
        }

        return this.downloadFile(file, opts);
    }

    /**
     * A private variant of {@link fileStream} that also caches the results.
     */
    private async fileURLDownloadAndCacheIfNeeded(file: EnteFile) {
        const cachedURL = this.fileURLPromises.get(file.id);
        if (cachedURL) return cachedURL;

        const url = this.downloadFile(file)
            .then((stream) => this.blobWithInferredType(file, stream))
            .then((blob) => URL.createObjectURL(blob));
        this.fileURLPromises.set(file.id, url);

        try {
            return await url;
        } catch (e) {
            this.fileURLPromises.delete(file.id);
            throw e;
        }
    }

    private async downloadFile(
        file: EnteFile,
        opts?: FileDownloadOpts,
    ): Promise<ReadableStream<Uint8Array> | null> {
        log.info(`download attempted for file id ${file.id}`);

        const res = await wrapErrors(() =>
            this.transport.downloadFile(file, opts),
        );

        if (
            file.metadata.fileType == FileType.image ||
            file.metadata.fileType == FileType.livePhoto
        ) {
            const encryptedData = new Uint8Array(
                await wrapErrors(() => res.arrayBuffer()),
            );

            const decrypted = await decryptStreamBytes(
                { encryptedData, decryptionHeader: file.file.decryptionHeader },
                file.key,
            );
            return new Response(decrypted).body;
        }

        const body = res.body;
        if (!body) return null;
        const reader = body.getReader();

        const onDownloadProgress = this.trackDownloadProgress(
            file.id,
            file.info?.fileSize,
        );

        const contentLength =
            parseInt(res.headers.get("Content-Length") ?? "") || 0;
        let downloadedBytes = 0;

        const { pullState, decryptionChunkSize } = await initChunkDecryption(
            file.file.decryptionHeader,
            file.key,
        );

        let leftoverBytes = new Uint8Array();

        return new ReadableStream({
            pull: async (controller) => {
                // Each time pull is called, we want to enqueue at least once.
                let didEnqueue = false;
                do {
                    // done is a boolean and value is an Uint8Array. When done
                    // is true value will be empty.
                    const { done, value } = await wrapErrors(() =>
                        reader.read(),
                    );

                    let data: Uint8Array;
                    if (done) {
                        data = leftoverBytes;
                    } else {
                        downloadedBytes += value.length;
                        onDownloadProgress({
                            loaded: downloadedBytes,
                            total: contentLength,
                        });

                        data = new Uint8Array(
                            leftoverBytes.length + value.length,
                        );
                        data.set(new Uint8Array(leftoverBytes), 0);
                        data.set(new Uint8Array(value), leftoverBytes.length);
                    }

                    // data.length might be a multiple of decryptionChunkSize,
                    // and we might need multiple iterations to drain it all.
                    while (data.length >= decryptionChunkSize) {
                        const decryptedData = await decryptStreamChunk(
                            data.slice(0, decryptionChunkSize),
                            pullState,
                        );
                        controller.enqueue(decryptedData);
                        didEnqueue = true;
                        data = data.slice(decryptionChunkSize);
                    }

                    if (done) {
                        // Send off the remaining bytes without waiting for a
                        // full chunk, no more bytes are going to come.
                        if (data.length) {
                            const decryptedData = await decryptStreamChunk(
                                data,
                                pullState,
                            );
                            controller.enqueue(decryptedData);
                        }
                        // Don't loop again even if we didn't enqueue.
                        didEnqueue = true;
                        controller.close();
                    } else {
                        // Save it for the next pull.

                        // See: [Note: Revisit some Node.js types errors post 22
                        // upgrade]
                        //
                        // eslint-disable-next-line @typescript-eslint/ban-ts-comment
                        // @ts-ignore
                        leftoverBytes = data;
                    }
                } while (!didEnqueue);
            },
        });
    }

    private async blobWithInferredType(
        file: EnteFile,
        stream: ReadableStream<Uint8Array> | null,
    ) {
        const blob = await new Response(stream).blob();
        if (blob.type) return blob;

        try {
            const { mimeType } = await detectFileTypeInfoFromChunk(
                async () =>
                    new Uint8Array(await blob.slice(0, 4100).arrayBuffer()),
                fileFileName(file),
            );
            return mimeType ? blob.slice(0, blob.size, mimeType) : blob;
        } catch {
            return blob;
        }
    }

    private trackDownloadProgress(
        fileID: number,
        fileSize: number | undefined,
    ) {
        return (event: { loaded: number; total: number }) => {
            if (isNaN(event.total) || event.total === 0) {
                if (!fileSize) {
                    return;
                }
                event.total = fileSize;
            }
            const progress = new Map(this.fileDownloadProgress);
            if (event.loaded === event.total) {
                progress.delete(fileID);
            } else {
                progress.set(
                    fileID,
                    Math.round((event.loaded * 100) / event.total),
                );
            }
            this.setFileDownloadProgress(progress);
        };
    }
}

export const createDownloadManager = (transport: DownloadManagerTransport) =>
    new DownloadManagerCore(transport);

/**
 * A custom Error that is thrown if a download fails during network I/O.
 *
 * [Note: Identifying network related errors during download]
 *
 * We dealing with code that touches the network, we often don't specifically
 * care about the specific error - there is a lot that can go wrong when a
 * network is involved - but need to identify if an error was in the network
 * related phase of an action, since these are usually transient and can be
 * dealt with more softly than other errors.
 *
 * To that end, network related phases of download operations are wrapped in
 * catches that intercept the error and wrap it in our custom
 * {@link NetworkDownloadError} whose presence can be checked using the
 * {@link isNetworkDownloadError} predicate.
 */
export class NetworkDownloadError extends Error {
    error: unknown;

    constructor(e: unknown) {
        super(
            `NetworkDownloadError: ${e instanceof Error ? e.message : String(e)}`,
        );

        // Cargo culted from
        // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Error#custom_error_types
        Error.captureStackTrace?.(this, NetworkDownloadError);

        this.error = e;
    }
}

export const isNetworkDownloadError = (e: unknown) =>
    e instanceof NetworkDownloadError;

/**
 * A helper function to convert all rejections of the given promise {@link op}
 * into {@link NetworkDownloadError}s.
 */
const wrapErrors = <T>(op: () => Promise<T>) =>
    op().catch((e: unknown) => {
        throw new NetworkDownloadError(e);
    });

/**
 * Create and return a {@link RenderableSourceURLs} for the given {@link file},
 * where {@link originalFileURLPromise} is a promise that resolves with an
 * (object) URL to the contents of the original file.
 */
const createRenderableSourceURLs = async (
    file: EnteFile,
    originalFileURLPromise: Promise<string>,
    {
        playableVideoURL,
        renderableImageBlob,
    }: Pick<
        DownloadManagerTransport,
        "playableVideoURL" | "renderableImageBlob"
    >,
): Promise<RenderableSourceURLs> => {
    const originalFileURL = await originalFileURLPromise;
    const fileBlob = await fetch(originalFileURL).then((res) => res.blob());
    const fileName = fileFileName(file);
    const fileType = file.metadata.fileType;

    switch (fileType) {
        case FileType.image: {
            const convertedBlob = await renderableImageBlob(fileBlob, fileName);
            const imageURL =
                convertedBlob === fileBlob
                    ? originalFileURL
                    : URL.createObjectURL(convertedBlob);
            const originalImageBlob = fileBlob;
            const mimeType = convertedBlob.type;
            return { type: "image", imageURL, originalImageBlob, mimeType };
        }

        case FileType.livePhoto: {
            const livePhoto = await decodeLivePhoto(fileName, fileBlob);
            const originalImageBlob = new Blob([livePhoto.imageData]);

            const imageURL = async () =>
                URL.createObjectURL(
                    await renderableImageBlob(
                        originalImageBlob,
                        livePhoto.imageFileName,
                    ),
                );

            const videoURL = () =>
                playableVideoURL(
                    file,
                    livePhoto.videoFileName,
                    new Blob([livePhoto.videoData]),
                );

            return { type: "livePhoto", imageURL, originalImageBlob, videoURL };
        }

        case FileType.video: {
            const videoURL = await playableVideoURL(file, fileName, fileBlob);
            return { type: "video", videoURL };
        }

        default: {
            throw new Error(`Unsupported file type ${fileType}`);
        }
    }
};
