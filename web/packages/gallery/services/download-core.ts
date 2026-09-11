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

export type RenderableSourceURLs =
    | {
          type: "image";
          imageURL: string;
          originalImageBlob: Blob;
          mimeType?: string;
      }
    | { type: "video"; videoURL: string }
    | {
          type: "livePhoto";
          imageURL: () => Promise<string>;
          originalImageBlob: Blob;
          videoURL: () => Promise<string>;
      };

export interface FileDownloadOpts {
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

export class DownloadManagerCore {
    private thumbnailCache: BlobCache | null | undefined;
    private thumbnailURLPromises = new Map<
        number,
        Promise<string | undefined>
    >();
    private fileURLPromises = new Map<number, Promise<string>>();
    private renderableSourceURLPromises = new Map<
        number,
        Promise<RenderableSourceURLs>
    >();

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

    logout() {
        this.thumbnailURLPromises.clear();
        this.fileURLPromises.clear();
        this.renderableSourceURLPromises.clear();
        this.fileDownloadProgress.clear();
        this.fileDownloadProgressListeners = [];
    }

    fileDownloadProgressSubscribe(onChange: () => void) {
        this.fileDownloadProgressListeners.push(onChange);
        return () => {
            this.fileDownloadProgressListeners =
                this.fileDownloadProgressListeners.filter((l) => l != onChange);
        };
    }

    fileDownloadProgressSnapshot() {
        return this.fileDownloadProgress;
    }

    private setFileDownloadProgress(progress: Map<number, number>) {
        this.fileDownloadProgress = progress;
        this.fileDownloadProgressListeners.forEach((l) => l());
    }

    // Returned object URLs are cache-owned; callers must not revoke them.
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
            // Do not cache a failed promise; follow-up calls should retry.
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

    async fileBlob(file: EnteFile, opts?: FileDownloadOpts) {
        const _fileBlob = () =>
            this.fileStream(file, opts).then((stream) =>
                this.blobWithInferredType(file, stream),
            );

        const cachedURL = this.fileURLPromises.get(file.id);
        try {
            return await _fileBlob();
        } catch (e) {
            // Retry without the cached object URL before surfacing the failure.
            if (cachedURL) {
                this.fileURLPromises.delete(file.id);
                return _fileBlob();
            } else {
                throw e;
            }
        }
    }

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

        let leftoverBytes: Uint8Array = new Uint8Array();

        return new ReadableStream({
            pull: async (controller) => {
                // Each pull must enqueue or close before returning.
                let didEnqueue = false;
                do {
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

                    // A network read can contain several encrypted chunks.
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
                        // Only EOF proves that a short remainder is the final chunk.
                        if (data.length) {
                            const decryptedData = await decryptStreamChunk(
                                data,
                                pullState,
                            );
                            controller.enqueue(decryptedData);
                        }
                        didEnqueue = true;
                        controller.close();
                    } else {
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

export class NetworkDownloadError extends Error {
    error: unknown;

    constructor(e: unknown) {
        super(
            `NetworkDownloadError: ${e instanceof Error ? e.message : String(e)}`,
        );

        Error.captureStackTrace?.(this, NetworkDownloadError);

        this.error = e;
    }
}

export const isNetworkDownloadError = (e: unknown) =>
    e instanceof NetworkDownloadError;

const wrapErrors = <T>(op: () => Promise<T>) =>
    op().catch((e: unknown) => {
        throw new NetworkDownloadError(e);
    });

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
