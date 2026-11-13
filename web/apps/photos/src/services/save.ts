import { safeDirectoryName, safeFileName } from "@/utils/native-fs";
import { assertionFailed } from "ente-base/assert";
import { suppressMainWindowBlurForTrustedPrompt } from "ente-base/electron";
import { joinPath } from "ente-base/file-name";
import log from "ente-base/log";
import type { Electron } from "ente-base/types/ipc";
import type {
    AddSaveGroup,
    UpdateSaveGroup,
} from "ente-gallery/components/utils/save-groups";
import { downloadManager } from "ente-gallery/services/download";
import type { FileDownloadProgress } from "ente-gallery/services/download-core";
import { downloadAndSaveFilesWeb } from "ente-gallery/services/save-core";
import { createSaveProgress } from "ente-gallery/services/save-progress";
import { writeStream } from "ente-gallery/utils/native-stream";
import type { EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { decodeLivePhoto } from "ente-media/live-photo";

export const downloadAndSaveFiles = (
    files: EnteFile[],
    title: string,
    onAddSaveGroup: AddSaveGroup,
) => downloadAndSave(files, title, onAddSaveGroup);

export const downloadAndSaveCollectionFiles = async (
    collectionSummaryName: string,
    collectionSummaryID: number,
    files: EnteFile[],
    isHiddenCollectionSummary: boolean | undefined,
    onAddSaveGroup: AddSaveGroup,
) =>
    downloadAndSave(
        files,
        collectionSummaryName,
        onAddSaveGroup,
        collectionSummaryName,
        collectionSummaryID,
        isHiddenCollectionSummary,
    );

const downloadAndSave = async (
    files: EnteFile[],
    title: string,
    onAddSaveGroup: AddSaveGroup,
    collectionSummaryName?: string,
    collectionSummaryID?: number,
    isHiddenCollectionSummary?: boolean,
) => {
    const electron = globalThis.electron;
    if (!electron) {
        return downloadAndSaveFilesWeb({
            downloader: downloadManager,
            files,
            title,
            onAddSaveGroup,
            collectionSummaryID,
            isHiddenCollectionSummary,
        });
    }

    const total = files.length;
    if (!files.length) {
        assertionFailed();
        return;
    }

    suppressMainWindowBlurForTrustedPrompt();
    const selectedDirPath = await electron.selectDirectory();
    if (!selectedDirPath) {
        return;
    }
    const downloadDirPath = collectionSummaryName
        ? await mkdirCollectionDownloadFolder(
              electron,
              selectedDirPath,
              collectionSummaryName,
          )
        : selectedDirPath;

    const canceller = new AbortController();
    const failedFiles: EnteFile[] = [];
    let isDownloading = false;
    let updateSaveGroup: UpdateSaveGroup = () => undefined;
    const progress = createSaveProgress(files, (tx) => updateSaveGroup(tx));

    const downloadFilesDesktop = async (
        filesToDownload: EnteFile[],
        resetFailedCount = false,
    ) => {
        if (!filesToDownload.length || isDownloading) return;

        isDownloading = true;
        if (resetFailedCount) {
            updateSaveGroup((g) => ({ ...g, failed: 0 }));
        }
        failedFiles.length = 0;

        try {
            for (const file of filesToDownload) {
                if (canceller.signal.aborted) break;
                try {
                    progress.start(file);
                    await saveFileDesktop(
                        electron,
                        file,
                        downloadDirPath,
                        (next) => progress.update(file, next),
                    );
                    updateSaveGroup((g) => ({ ...g, success: g.success + 1 }));
                } catch (e) {
                    log.error("File download failed", e);
                    failedFiles.push(file);
                    updateSaveGroup((g) => ({ ...g, failed: g.failed + 1 }));
                }
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
        void downloadFilesDesktop([...failedFiles], true);
    };

    updateSaveGroup = onAddSaveGroup({
        title,
        collectionSummaryID,
        isHiddenCollectionSummary,
        downloadDirPath,
        total,
        includeZipNumber: false,
        canceller,
        retry,
    });

    await downloadFilesDesktop(files);
};

const mkdirCollectionDownloadFolder = async (
    { fs }: Electron,
    downloadDirPath: string,
    collectionName: string,
) => {
    const collectionDownloadName = await safeDirectoryName(
        downloadDirPath,
        collectionName,
        fs.exists,
    );
    const collectionDownloadPath = joinPath(
        downloadDirPath,
        collectionDownloadName,
    );
    await fs.mkdirIfNeeded(collectionDownloadPath);
    return collectionDownloadPath;
};

const saveFileDesktop = async (
    electron: Electron,
    file: EnteFile,
    directoryPath: string,
    onProgress: (progress: FileDownloadProgress) => void,
) => {
    const fs = electron.fs;

    const createExportName = (fileName: string) =>
        safeFileName(directoryPath, fileName, fs.exists);

    const writeStreamToFile = (
        exportName: string,
        stream: ReadableStream<Uint8Array> | null,
    ) => writeStream(electron, joinPath(directoryPath, exportName), stream);

    const stream = await downloadManager.fileStream(file, { onProgress });
    const fileName = fileFileName(file);

    if (file.metadata.fileType == FileType.livePhoto) {
        const { imageFileName, imageData, videoFileName, videoData } =
            await decodeLivePhoto(fileName, await new Response(stream).blob());
        const imageExportName = await createExportName(imageFileName);
        await writeStreamToFile(imageExportName, new Response(imageData).body);
        try {
            await writeStreamToFile(
                await createExportName(videoFileName),
                new Response(videoData).body,
            );
        } catch (e) {
            await fs.rm(joinPath(directoryPath, imageExportName));
            throw e;
        }
    } else {
        await writeStreamToFile(await createExportName(fileName), stream);
    }
};
