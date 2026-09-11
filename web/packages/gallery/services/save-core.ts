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

interface DownloadLimits {
    concurrency: number;
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
        ? { concurrency: 4, maxZipSize: 100 * 1024 * 1024 }
        : { concurrency: 8, maxZipSize: 250 * 1024 * 1024 };

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
    // Retries continue part numbering instead of overwriting earlier ZIPs.
    let nextZipBatchIndex = 1;

    const downloadFilesWeb = async (
        filesToDownload: EnteFile[],
        resetFailedCount = false,
    ) => {
        if (!filesToDownload.length || isDownloading) return;

        if (resetFailedCount) {
            updateSaveGroup((g) => ({
                ...g,
                failed: 0,
                failureReason: undefined,
            }));
            failedFiles.length = 0;
        }

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
        if (!resetFailedCount) {
            failedFiles.length = 0;
        }

        try {
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

    getNextBatchIndex(): number {
        return this.batchIndex;
    }

    async addFile(data: Uint8Array | Blob, fileName: string): Promise<void> {
        const size = data instanceof Blob ? data.size : data.byteLength;

        if (
            this.currentBatchSize > 0 &&
            this.currentBatchSize + size > this.maxZipSize
        ) {
            this.includePartNumber = true;
            await this.downloadCurrentBatch();
            this.onStateChange?.(false, this.batchIndex);
        }

        const uniqueName = this.getUniqueName(fileName);
        this.usedNames.add(uniqueName);
        const zip = await this.zipPromise;
        zip.file(uniqueName, data);
        this.currentBatchSize += size;
        this.currentFileCount++;
    }

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

        this.zipPromise = createJSZip();
        this.currentBatchSize = 0;
        this.currentFileCount = 0;
        this.usedNames.clear();
        this.batchIndex++;
    }

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

type DownloadedFileData =
    | { type: "regular"; fileName: string; data: Uint8Array }
    | {
          type: "livePhoto";
          imageFileName: string;
          imageData: Uint8Array;
          videoFileName: string;
          videoData: Uint8Array;
      };

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

    updateSaveGroup((g) => ({ ...g, currentPart: startingBatchIndex }));

    let fileIndex = 0;

    const networkState = { isOffline: !navigator.onLine };
    const handleOffline = () => {
        networkState.isOffline = true;
    };
    const handleOnline = () => {
        networkState.isOffline = false;
    };
    window.addEventListener("offline", handleOffline);
    window.addEventListener("online", handleOnline);

    // Downloads run concurrently; ZIP mutation must stay serial.
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

    const processFile = async (): Promise<boolean> => {
        if (networkState.isOffline || canceller.signal.aborted) {
            return false;
        }

        const currentIndex = fileIndex++;
        if (currentIndex >= files.length) {
            return false;
        }

        const file = files[currentIndex]!;
        try {
            const downloadedData = await downloadFileForZip(downloader, file);

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
            // Event handlers can change this during the download.
            // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
            if (!networkState.isOffline) {
                log.error(`Failed to download file ${file.id}, skipping`, e);
            }
            onError(file, e);

            // Event handlers can change this during the download.
            // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
            if (networkState.isOffline) {
                updateSaveGroup((g) => ({
                    ...g,
                    failureReason: "network_offline",
                }));
                return false;
            }
            updateSaveGroup((g) => ({
                ...g,
                failureReason: g.failureReason ?? "file_error",
            }));
        }

        return true;
    };

    const worker = async (): Promise<void> => {
        while (await processFile()) {
            // Continue processing.
        }
    };

    try {
        const workers = Array.from(
            { length: Math.min(concurrency, files.length) },
            () => worker(),
        );
        await Promise.all(workers);

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

        if (!canceller.signal.aborted) {
            await batcher.flush();
        }

        return batcher.getNextBatchIndex();
    } finally {
        window.removeEventListener("offline", handleOffline);
        window.removeEventListener("online", handleOnline);
    }
};
