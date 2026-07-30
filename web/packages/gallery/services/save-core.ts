import { assertionFailed } from "ente-base/assert";
import { nameAndExtension } from "ente-base/file-name";
import log from "ente-base/log";
import { saveAsFileAndRevokeObjectURL } from "ente-base/utils/web";
import type { EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { decodeLivePhoto } from "ente-media/live-photo";
import type JSZip from "jszip";
import type {
    AddSaveGroup,
    UpdateSaveGroup,
} from "../components/utils/save-groups";

export interface BrowserSaveDownloader {
    fileBlob(file: EnteFile): Promise<Blob>;
}

export interface DownloadAndSaveFilesWebOpts {
    downloader: BrowserSaveDownloader;
    files: EnteFile[];
    title: string;
    onAddSaveGroup: AddSaveGroup;
    collectionSummaryID?: number;
    isHiddenCollectionSummary?: boolean;
}

/**
 * Download limits optimized for different devices and browsers.
 */
interface DownloadLimits {
    /** Number of concurrent file downloads. */
    concurrency: number;
    /** Maximum size of a ZIP batch in bytes. */
    maxZipSize: number;
}

let cachedLimits: DownloadLimits | undefined;
type JSZipConstructor = new () => JSZip;

let jsZipConstructorPromise: Promise<JSZipConstructor> | undefined;

const createJSZip = async (): Promise<JSZip> => {
    const JSZipConstructor = await (jsZipConstructorPromise ??=
        import("jszip").then((module) => {
            const candidate = (
                module as unknown as { default?: JSZipConstructor }
            ).default;
            return candidate ?? (module as unknown as JSZipConstructor);
        }));
    return new JSZipConstructor();
};

/**
 * Get download limits for the current device.
 *
 * - Mobile devices: 4 concurrent, 100MB max
 * - Desktop: 8 concurrent, 250MB max
 */
const getDownloadLimits = (): DownloadLimits => {
    if (cachedLimits) return cachedLimits;

    const ua = navigator.userAgent.toLowerCase();
    const isMobile =
        ua.includes("iphone") ||
        ua.includes("ipad") ||
        ua.includes("ipod") ||
        ua.includes("android") ||
        ua.includes("mobile") ||
        ua.includes("tablet") ||
        (ua.includes("macintosh") && navigator.maxTouchPoints > 1);

    cachedLimits = isMobile
        ? { concurrency: 4, maxZipSize: 100 * 1024 * 1024 } // 100MB
        : { concurrency: 8, maxZipSize: 250 * 1024 * 1024 }; // 250MB

    return cachedLimits;
};

const shouldIncludeZipNumber = (
    files: EnteFile[],
    maxZipSize: number,
): boolean => {
    let totalSize = 0;
    for (const file of files) {
        const size = file.info?.fileSize;
        if (size == null) {
            return true;
        }
        totalSize += size;
        if (totalSize > maxZipSize) {
            return true;
        }
    }
    return false;
};

export const downloadAndSaveFilesWeb = async ({
    downloader,
    files,
    title,
    onAddSaveGroup,
    collectionSummaryID,
    isHiddenCollectionSummary,
}: DownloadAndSaveFilesWebOpts) => {
    const total = files.length;
    if (!files.length) {
        // Nothing to download.
        assertionFailed();
        return;
    }

    const shouldZipOnWeb =
        files.length > 1 ||
        (files.length === 1 &&
            files[0]?.metadata.fileType === FileType.livePhoto);
    const includeZipNumber =
        shouldZipOnWeb &&
        shouldIncludeZipNumber(files, getDownloadLimits().maxZipSize);

    const canceller = new AbortController();
    const failedFiles: EnteFile[] = [];
    let isDownloading = false;
    let updateSaveGroup: UpdateSaveGroup = () => undefined;
    // Track the next ZIP batch index across retries so part numbers continue
    // sequentially (e.g., if initial download creates Parts 1-5 and fails,
    // retry creates Part 6+ instead of starting over at Part 1).
    let nextZipBatchIndex = 1;

    const downloadFilesWeb = async (
        filesToDownload: EnteFile[],
        resetFailedCount = false,
    ) => {
        if (!filesToDownload.length || isDownloading) return;

        // Reset counts first if this is a retry, before any other logic
        if (resetFailedCount) {
            updateSaveGroup((g) => ({
                ...g,
                failed: 0,
                failureReason: undefined,
            }));
            failedFiles.length = 0;
        }

        // If already offline, mark all files as failed so retry is available
        if (!navigator.onLine) {
            log.info("Download skipped - network is offline");
            for (const file of filesToDownload) {
                failedFiles.push(file);
            }
            updateSaveGroup((g) => ({
                ...g,
                failed: filesToDownload.length,
                failureReason: "network_offline",
            }));
            return;
        }

        isDownloading = true;
        // Only clear on first download, not retry (already cleared above)
        if (!resetFailedCount) {
            failedFiles.length = 0;
        }

        try {
            // Single non-live-photo file: download directly without zipping
            const singleFile = filesToDownload[0];
            if (
                filesToDownload.length === 1 &&
                singleFile &&
                singleFile.metadata.fileType !== FileType.livePhoto
            ) {
                try {
                    const fileBlob = await downloader.fileBlob(singleFile);
                    const fileName = fileFileName(singleFile);
                    const url = URL.createObjectURL(fileBlob);
                    saveAsFileAndRevokeObjectURL(url, fileName);
                    updateSaveGroup((g) => ({ ...g, success: g.success + 1 }));
                } catch (e) {
                    log.error("File download failed", e);
                    failedFiles.push(singleFile);
                    updateSaveGroup((g) => ({ ...g, failed: g.failed + 1 }));
                }
            } else {
                // Multiple files or live photo: use ZIP
                nextZipBatchIndex = await saveAsZip(
                    downloader,
                    filesToDownload,
                    title,
                    () =>
                        updateSaveGroup((g) => ({
                            ...g,
                            success: g.success + 1,
                        })),
                    (file) => {
                        failedFiles.push(file);
                        updateSaveGroup((g) => ({
                            ...g,
                            failed: g.failed + 1,
                        }));
                    },
                    canceller,
                    updateSaveGroup,
                    nextZipBatchIndex,
                    includeZipNumber,
                );
            }

            if (!failedFiles.length) {
                updateSaveGroup((g) => ({ ...g, retry: undefined }));
            }
        } finally {
            isDownloading = false;
        }
    };

    const retry = () => {
        if (!failedFiles.length || isDownloading || canceller.signal.aborted)
            return;
        void downloadFilesWeb([...failedFiles], true);
    };

    updateSaveGroup = onAddSaveGroup({
        title,
        collectionSummaryID,
        isHiddenCollectionSummary,
        total,
        includeZipNumber,
        canceller,
        retry,
    });

    await downloadFilesWeb(files);
};

/**
 * A helper class to accumulate files into ZIP batches and download them when
 * the batch size limit is reached.
 */
class ZipBatcher {
    private zipPromise = createJSZip();
    private currentBatchSize = 0;
    private currentFileCount = 0;
    private batchIndex: number;
    private usedNames = new Set<string>();
    private baseName: string;
    private maxZipSize: number;
    private includePartNumber: boolean;
    private onStateChange?: (
        isDownloading: boolean,
        partNumber: number,
    ) => void;

    constructor(
        baseName: string,
        maxZipSize: number,
        startingBatchIndex = 1,
        onStateChange?: (isDownloading: boolean, partNumber: number) => void,
        includePartNumber = false,
    ) {
        this.baseName = baseName;
        this.maxZipSize = maxZipSize;
        this.batchIndex = startingBatchIndex;
        this.onStateChange = onStateChange;
        this.includePartNumber = includePartNumber || startingBatchIndex > 1;
    }

    /**
     * Get the next batch index that would be used for the next ZIP file.
     * This is useful for tracking progress across retries.
     */
    getNextBatchIndex(): number {
        return this.batchIndex;
    }

    /**
     * Add file data to the current ZIP batch. If adding this file would exceed
     * the batch size limit, the current batch is downloaded first.
     */
    async addFile(data: Uint8Array | Blob, fileName: string): Promise<void> {
        const size = data instanceof Blob ? data.size : data.byteLength;

        // If adding this file would exceed the limit and we have files in the
        // batch, download the current batch first.
        if (
            this.currentBatchSize > 0 &&
            this.currentBatchSize + size > this.maxZipSize
        ) {
            this.includePartNumber = true;
            await this.downloadCurrentBatch();
            // Notify that we're now preparing a new part
            this.onStateChange?.(false, this.batchIndex);
        }

        // Ensure unique file names within the ZIP
        const uniqueName = this.getUniqueName(fileName);
        this.usedNames.add(uniqueName);
        const zip = await this.zipPromise;
        zip.file(uniqueName, data);
        this.currentBatchSize += size;
        this.currentFileCount++;
    }

    /**
     * Download any remaining files in the current batch.
     */
    async flush(): Promise<void> {
        if (this.currentBatchSize > 0) {
            await this.downloadCurrentBatch();
        }
    }

    private async downloadCurrentBatch(): Promise<void> {
        this.onStateChange?.(true, this.batchIndex);
        try {
            const zip = await this.zipPromise;
            const zipBlob = await zip.generateAsync({ type: "blob" });
            const fileLabel =
                this.currentFileCount === 1
                    ? "1 file"
                    : `${this.currentFileCount} files`;
            const baseName = this.baseName.trim();
            const nameBase = this.includePartNumber
                ? `${baseName} Part ${this.batchIndex}`
                : baseName;
            const zipName =
                baseName.toLowerCase() === fileLabel.toLowerCase()
                    ? `${nameBase}.zip`
                    : `${nameBase} - ${fileLabel}.zip`;

            const url = URL.createObjectURL(zipBlob);
            saveAsFileAndRevokeObjectURL(url, zipName);
        } finally {
            this.onStateChange?.(false, this.batchIndex);
        }

        // Reset for next batch
        this.zipPromise = createJSZip();
        this.currentBatchSize = 0;
        this.currentFileCount = 0;
        this.usedNames.clear();
        this.batchIndex++;
    }

    /**
     * Generate a unique file name within the ZIP by appending a suffix if the
     * name already exists.
     */
    private getUniqueName(fileName: string): string {
        if (!this.usedNames.has(fileName)) {
            return fileName;
        }

        const [name, ext] = nameAndExtension(fileName);
        let counter = 1;
        let uniqueName: string;
        do {
            uniqueName = ext
                ? `${name}(${counter}).${ext}`
                : `${name}(${counter})`;
            counter++;
        } while (this.usedNames.has(uniqueName));

        return uniqueName;
    }
}

/** Result of downloading and processing a single file for ZIP inclusion. */
type DownloadedFileData =
    | { type: "regular"; fileName: string; data: Uint8Array }
    | {
          type: "livePhoto";
          imageFileName: string;
          imageData: Uint8Array;
          videoFileName: string;
          videoData: Uint8Array;
      };

/**
 * Download and process a single file, returning the data ready for ZIP.
 */
const downloadFileForZip = async (
    downloader: BrowserSaveDownloader,
    file: EnteFile,
): Promise<DownloadedFileData> => {
    const fileBlob = await downloader.fileBlob(file);
    const fileName = fileFileName(file);

    if (file.metadata.fileType == FileType.livePhoto) {
        const { imageFileName, imageData, videoFileName, videoData } =
            await decodeLivePhoto(fileName, fileBlob);
        return {
            type: "livePhoto",
            imageFileName,
            imageData,
            videoFileName,
            videoData,
        };
    } else {
        const data = new Uint8Array(await fileBlob.arrayBuffer());
        return { type: "regular", fileName, data };
    }
};

/**
 * Save multiple files as ZIP archives to the user's download folder.
 *
 * Files are batched into ZIPs using device-specific size limits. If the total
 * exceeds that limit, multiple ZIP files will be downloaded. Downloads are
 * performed concurrently for better performance.
 *
 * @param files The files to download and add to the ZIP.
 * @param baseName The base name for the ZIP file(s).
 * @param onSuccess Callback invoked after each file is successfully added.
 * @param onError Callback invoked when a file fails to download.
 * @param canceller An AbortController to check for cancellation.
 * @param startingBatchIndex The batch index to start from (for retries).
 * @returns The next batch index to use for subsequent ZIPs (useful for retries).
 */
const saveAsZip = async (
    downloader: BrowserSaveDownloader,
    files: EnteFile[],
    baseName: string,
    onSuccess: () => void,
    onError: (file: EnteFile, error: unknown) => void,
    canceller: AbortController,
    updateSaveGroup: UpdateSaveGroup,
    startingBatchIndex = 1,
    includePartNumber = false,
): Promise<number> => {
    const { concurrency, maxZipSize } = getDownloadLimits();
    const batcher = new ZipBatcher(
        baseName,
        maxZipSize,
        startingBatchIndex,
        (isDownloading, partNumber) =>
            updateSaveGroup((g) => ({
                ...g,
                isDownloadingZip: isDownloading,
                currentPart: partNumber,
            })),
        includePartNumber,
    );

    // Set initial part number
    updateSaveGroup((g) => ({ ...g, currentPart: startingBatchIndex }));

    // Queue of files to process
    let fileIndex = 0;

    // Track if we've gone offline to stop processing immediately.
    // Using an object so the value can be mutated by event handlers and
    // checked synchronously by the async workers.
    const networkState = { isOffline: !navigator.onLine };
    const handleOffline = () => {
        networkState.isOffline = true;
    };
    const handleOnline = () => {
        networkState.isOffline = false;
    };
    window.addEventListener("offline", handleOffline);
    window.addEventListener("online", handleOnline);

    // Mutex for serializing ZIP additions (download is concurrent, but adding
    // to the ZIP must be serialized to avoid race conditions with batching)
    let zipMutex: Promise<void> = Promise.resolve();
    const withZipLock = async <T>(fn: () => Promise<T>): Promise<T> => {
        const prev = zipMutex;
        let resolve: () => void;
        zipMutex = new Promise((r) => (resolve = r));
        await prev;
        try {
            return await fn();
        } finally {
            resolve!();
        }
    };

    // Process a single file: download, then add to ZIP
    const processFile = async (): Promise<boolean> => {
        // Stop immediately if offline or cancelled
        if (networkState.isOffline || canceller.signal.aborted) {
            return false;
        }

        // Get next file to process
        const currentIndex = fileIndex++;
        if (currentIndex >= files.length) {
            return false;
        }

        const file = files[currentIndex]!;
        try {
            // Check again before starting download (value can change via event handler)
            // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
            if (networkState.isOffline) {
                // Put this file back for retry
                onError(file, new Error("Network offline"));
                return false;
            }

            // Download happens concurrently
            const downloadedData = await downloadFileForZip(downloader, file);

            // Adding to ZIP is serialized via mutex
            await withZipLock(async () => {
                if (downloadedData.type === "livePhoto") {
                    await batcher.addFile(
                        downloadedData.imageData,
                        downloadedData.imageFileName,
                    );
                    await batcher.addFile(
                        downloadedData.videoData,
                        downloadedData.videoFileName,
                    );
                } else {
                    await batcher.addFile(
                        downloadedData.data,
                        downloadedData.fileName,
                    );
                }
            });
            onSuccess();
        } catch (e) {
            // Individual file failed - mark it for retry but continue with others
            // Only log non-network errors to avoid log spam when offline
            // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
            if (!networkState.isOffline) {
                log.error(`Failed to download file ${file.id}, skipping`, e);
            }
            onError(file, e);

            // Only stop all processing if we went offline (not for individual failures)
            // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
            if (networkState.isOffline) {
                updateSaveGroup((g) => ({
                    ...g,
                    failureReason: "network_offline",
                }));
                return false;
            }
            // Mark as file error for individual failures
            updateSaveGroup((g) => ({
                ...g,
                failureReason: g.failureReason ?? "file_error",
            }));
            // Continue processing remaining files even if this one failed
        }

        return true;
    };

    // Worker that continuously processes files until done
    const worker = async (): Promise<void> => {
        while (await processFile()) {
            // Continue processing
        }
    };

    try {
        // Start concurrent workers
        const workers = Array.from(
            { length: Math.min(concurrency, files.length) },
            () => worker(),
        );
        await Promise.all(workers);

        // If we went offline, mark remaining files as failed
        if (networkState.isOffline) {
            updateSaveGroup((g) => ({
                ...g,
                failureReason: "network_offline",
            }));
            while (fileIndex < files.length) {
                const file = files[fileIndex++];
                if (file) {
                    onError(file, new Error("Network offline"));
                }
            }
        }

        // Flush whatever we have (even partial) unless cancelled
        if (!canceller.signal.aborted) {
            await batcher.flush();
        }

        return batcher.getNextBatchIndex();
    } finally {
        // Clean up event listeners
        window.removeEventListener("offline", handleOffline);
        window.removeEventListener("online", handleOnline);
    }
};
