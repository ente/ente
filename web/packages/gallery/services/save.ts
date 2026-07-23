import { assertionFailed } from "ente-base/assert";
import { suppressMainWindowBlurForTrustedPrompt } from "ente-base/electron";
import { joinPath } from "ente-base/file-name";
import log from "ente-base/log";
import type { Electron } from "ente-base/types/ipc";
import { downloadManager } from "ente-gallery/services/download";
import { writeStream } from "ente-gallery/utils/native-stream";
import type { EnteFile } from "ente-media/file";
import { fileFileName } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { decodeLivePhoto } from "ente-media/live-photo";
import {
    safeDirectoryName,
    safeFileName,
} from "ente-new/photos/utils/native-fs";
import type {
    AddSaveGroup,
    UpdateSaveGroup,
} from "../components/utils/save-groups";
import { downloadAndSaveFilesWeb } from "./save-core";

/**
 * Save the given {@link files} to the user's device.
 *
 * If we're running in the context of the web app, the files will be saved to
 * the user's download folder. If we're running in the context of our desktop
 * app, the user will be prompted to select a directory on their file system and
 * the files will be saved therein.
 *
 * @param files The files to save.
 *
 * @param title A title to show in the UI notification that indicates the
 * progress of the save.
 *
 * @param onAddSaveGroup A function that can be used to create a save group
 * associated with the save. The newly added save group will correspond to a
 * notification shown in the UI, and the progress and status of the save can be
 * communicated by updating the save group's state using the updater function
 * obtained when adding the save group.
 */
export const downloadAndSaveFiles = (
    files: EnteFile[],
    title: string,
    onAddSaveGroup: AddSaveGroup,
) => downloadAndSave(files, title, onAddSaveGroup);

/**
 * Save all the files of a collection to the user's device.
 *
 * This is a variant of {@link downloadAndSaveFiles}, except instead of taking a
 * list of files to save, this variant is tailored for saving saves all the
 * files that belong to a collection. Otherwise, it broadly behaves similarly;
 * see that method's documentation for more details.
 *
 * When running in the context of the desktop app, instead of saving the files
 * in the directory selected by the user, files are saved in a directory with
 * the same name as the collection.
 *
 * @param isHiddenCollectionSummary `true` if the collection is associated with
 * a "hidden" collection or pseudo-collection in the app. Only relevant when
 * running in the context of the photos app, can be `undefined` otherwise.
 */
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

/**
 * The lower level primitive that the public API of this module delegates to.
 */
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
        // Nothing to download.
        assertionFailed();
        return;
    }

    suppressMainWindowBlurForTrustedPrompt();
    const selectedDirPath = await electron.selectDirectory();
    if (!selectedDirPath) {
        // The user cancelled on the directory selection dialog.
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
                    await saveFileDesktop(electron, file, downloadDirPath);
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

/**
 * Create a new directory on the user's file system with the same name as the
 * provided {@link collectionName} under the provided {@link downloadDirPath},
 * and return the full path to the created directory.
 *
 * This function can be used only when running in the context of our desktop
 * app, and so such requires an {@link Electron} instance as the witness.
 */
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

/**
 * Save a file to the given {@link directoryPath} using native filesystem APIs.
 *
 * This is a sibling of {@link saveAsFile} for use when we are running in the
 * context of our desktop app. Unlike the browser, the desktop app can use
 * native file system APIs to efficiently write the files on disk without
 * needing to prompt the user for each write.
 *
 * @param electron An {@link Electron} instance, a witness to the fact that
 * we're running in the desktop app.
 *
 * @param file The {@link EnteFile} whose contents we want to save to the user's
 * file system.
 *
 * @param directoryPath The file system directory in which to save the file.
 */
const saveFileDesktop = async (
    electron: Electron,
    file: EnteFile,
    directoryPath: string,
) => {
    const fs = electron.fs;

    const createExportName = (fileName: string) =>
        safeFileName(directoryPath, fileName, fs.exists);

    const writeStreamToFile = (
        exportName: string,
        stream: ReadableStream<Uint8Array> | null,
    ) => writeStream(electron, joinPath(directoryPath, exportName), stream);

    const stream = await downloadManager.fileStream(file);
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
