/**
 * @file Listen for IPC events sent/invoked by the renderer process, and route
 * them to their correct handlers.
 *
 * This file is meant as a sibling to `preload.ts`, but this one runs in the
 * context of the main process, and can import other files from `src/`.
 *
 * See [Note: types.ts <-> preload.ts <-> ipc.ts]
 */

import type { FSWatcher } from "chokidar";
import type { BrowserWindow, IpcMainEvent, IpcMainInvokeEvent } from "electron";
import { ipcMain, safeStorage } from "electron/main";
import type {
    CollectionMapping,
    FFmpegCommand,
    FolderWatch,
    PendingUploads,
    PersistedAppLockConfig,
    UtilityProcessType,
    ZipItem,
} from "../types/ipc";
import log, { logToDisk } from "./log";
import {
    appVersion,
    skipAppUpdate,
    updateAndRestart,
    updateOnNextRestart,
} from "./services/app-update";
import autoLauncher from "./services/auto-launcher";
import {
    getNativeDeviceLockCapability,
    promptDeviceLock,
} from "./services/device-lock";
import {
    openDirectory,
    openLogDirectory,
    selectDirectory,
} from "./services/dir";
import { ffmpegDetermineVideoDuration, ffmpegExec } from "./services/ffmpeg";
import {
    fsExists,
    fsFindFiles,
    fsIsDir,
    fsMkdirIfNeeded,
    fsReadTextFile,
    fsRename,
    fsRm,
    fsRmdir,
    fsStatMtime,
    fsWriteFile,
    fsWriteFileViaBackup,
} from "./services/fs";
import { convertToJPEG, generateImageThumbnail } from "./services/image";
import { logout } from "./services/logout";
import {
    appLockConfigFromSafeStorage,
    clearAppLockConfigFromSafeStorage,
    lastShownChangelogVersion,
    masterKeyFromSafeStorage,
    saveAppLockConfigInSafeStorage,
    saveMasterKeyInSafeStorage,
    setLastShownChangelogVersion,
} from "./services/store";
import {
    clearPendingUploads,
    listZipItems,
    markUploadedFile,
    markUploadedZipItem,
    pathOrZipItemSize,
    pendingUploads,
    setPendingUploads,
} from "./services/upload";
import {
    watchAdd,
    watchGet,
    watchRemove,
    watchUpdateIgnoredFiles,
    watchUpdateSyncedFiles,
} from "./services/watch";
import { triggerCreateUtilityProcess } from "./services/workers";

const parsePersistedAppLockConfig = (
    config: unknown,
): PersistedAppLockConfig => {
    if (!config || typeof config !== "object") {
        throw new Error("Invalid persisted app lock config");
    }

    const { enabled, lockType, autoLockTimeMs } = config as Record<
        string,
        unknown
    >;
    if (
        typeof enabled !== "boolean" ||
        (lockType !== "pin" &&
            lockType !== "password" &&
            lockType !== "device" &&
            lockType !== "none") ||
        typeof autoLockTimeMs !== "number" ||
        !Number.isFinite(autoLockTimeMs)
    ) {
        throw new Error("Invalid persisted app lock config");
    }

    return { enabled, lockType, autoLockTimeMs };
};

const rendererOrigin = "ente://app";

/**
 * Guard against IPC from anything other than our own renderer.
 *
 * The preload script exposes the {@link Electron} object to whatever document
 * is loaded in the main window, including any external page (e.g. the Stripe
 * checkout) the window navigates to. Ensure that the frame invoking us is
 * actually our renderer before running the privileged handler.
 */
const ensureTrustedIPCSender = (
    channel: string,
    event: IpcMainEvent | IpcMainInvokeEvent,
) => {
    const origin = event.senderFrame?.origin;
    if (origin == rendererOrigin) return true;
    log.warn(
        `Ignoring IPC "${channel}" from unexpected origin ${origin ?? "?"}`,
    );
    return false;
};

/**
 * A variant of {@link ipcMain.handle} that ignores requests from untrusted
 * senders. See {@link ensureTrustedIPCSender}.
 */
// The type parameters preserve each handler's specific argument types.
// eslint-disable-next-line @typescript-eslint/no-unnecessary-type-parameters
const handle = <A extends unknown[], R>(
    channel: string,
    handler: (event: IpcMainInvokeEvent, ...args: A) => R,
) =>
    ipcMain.handle(channel, (event: IpcMainInvokeEvent, ...args: A) => {
        if (!ensureTrustedIPCSender(channel, event))
            throw new Error(`Refusing IPC "${channel}" from untrusted sender`);
        return handler(event, ...args);
    });

/**
 * A variant of {@link ipcMain.on} that ignores requests from untrusted senders.
 * See {@link ensureTrustedIPCSender}.
 */
// eslint-disable-next-line @typescript-eslint/no-unnecessary-type-parameters
const on = <A extends unknown[]>(
    channel: string,
    handler: (event: IpcMainEvent, ...args: A) => void,
) =>
    ipcMain.on(channel, (event: IpcMainEvent, ...args: A) => {
        if (ensureTrustedIPCSender(channel, event)) handler(event, ...args);
    });

/**
 * Listen for IPC events sent/invoked by the renderer process, and route them to
 * their correct handlers.
 */
export const attachIPCHandlers = () => {
    // Notes:
    //
    // The first parameter of the handler passed to `ipcMain.handle` is the
    // `event`, and is usually ignored. The rest of the parameters are the
    // arguments passed to `ipcRenderer.invoke`.
    //
    // [Note: Catching exception during .send/.on]
    //
    // While we can use ipcRenderer.send/ipcMain.on for one-way communication,
    // that has the disadvantage that any exceptions thrown in the processing of
    // the handler are not sent back to the renderer. So we use the
    // ipcRenderer.invoke/ipcMain.handle 2-way pattern even for things that are
    // conceptually one way. An exception (pun intended) to this is logToDisk,
    // which is a primitive, frequently used, operation and shouldn't throw, so
    // having its signature by synchronous is a bit convenient.

    // - General

    handle("appVersion", () => appVersion());

    handle("openDirectory", (_, dirPath: string) => openDirectory(dirPath));

    handle("openLogDirectory", () => openLogDirectory());

    // See [Note: Catching exception during .send/.on]
    on("logToDisk", (_, message: string) => logToDisk(message));

    handle("selectDirectory", () => selectDirectory());

    handle("masterKeyFromSafeStorage", () => masterKeyFromSafeStorage());

    handle("saveMasterKeyInSafeStorage", (_, masterKey: string) =>
        saveMasterKeyInSafeStorage(masterKey),
    );

    handle("isSafeStorageAvailable", (): boolean =>
        safeStorage.isEncryptionAvailable(),
    );

    handle("appLockConfigFromSafeStorage", () =>
        appLockConfigFromSafeStorage(),
    );

    handle("saveAppLockConfigInSafeStorage", (_, config: unknown) =>
        saveAppLockConfigInSafeStorage(parsePersistedAppLockConfig(config)),
    );

    handle("clearAppLockConfigFromSafeStorage", () =>
        clearAppLockConfigFromSafeStorage(),
    );

    handle("lastShownChangelogVersion", () => lastShownChangelogVersion());

    handle("setLastShownChangelogVersion", (_, version: number) =>
        setLastShownChangelogVersion(version),
    );

    handle("isAutoLaunchEnabled", () => autoLauncher.isEnabled());

    handle("toggleAutoLaunch", () => autoLauncher.toggleAutoLaunch());

    // - Desktop app lock (native device authentication)
    //
    // These handlers are the main-process bridge for the desktop app lock flow:
    // the renderer asks about native auth capability/support, then requests a
    // native unlock prompt when the user needs to unlock the app.

    // Returns richer capability details (for example, available prompt type)
    // so the UI can decide which app-lock option to show.
    handle("getNativeDeviceLockCapability", () =>
        getNativeDeviceLockCapability(),
    );

    // Triggers the macOS-native Touch ID prompt and returns the auth result
    // back to the renderer. Other platforms currently return false.
    handle("promptDeviceLock", (_, reason: string) => promptDeviceLock(reason));

    // - App update

    on("updateAndRestart", () => updateAndRestart());

    on("updateOnNextRestart", (_, version: string) =>
        updateOnNextRestart(version),
    );

    on("skipAppUpdate", (_, version: string) => skipAppUpdate(version));

    // - FS

    handle("fsExists", (_, path: string) => fsExists(path));

    handle("fsRename", (_, oldPath: string, newPath: string) =>
        fsRename(oldPath, newPath),
    );

    handle("fsMkdirIfNeeded", (_, dirPath: string) => fsMkdirIfNeeded(dirPath));

    handle("fsRmdir", (_, path: string) => fsRmdir(path));

    handle("fsRm", (_, path: string) => fsRm(path));

    handle("fsReadTextFile", (_, path: string) => fsReadTextFile(path));

    handle("fsWriteFile", (_, path: string, contents: string) =>
        fsWriteFile(path, contents),
    );

    handle("fsWriteFileViaBackup", (_, path: string, contents: string) =>
        fsWriteFileViaBackup(path, contents),
    );

    handle("fsIsDir", (_, dirPath: string) => fsIsDir(dirPath));

    handle("fsStatMtime", (_, path: string) => fsStatMtime(path));

    handle("fsFindFiles", (_, folderPath: string) => fsFindFiles(folderPath));

    // - Conversion

    handle("convertToJPEG", (_, imageData: Uint8Array) =>
        convertToJPEG(imageData),
    );

    handle(
        "generateImageThumbnail",
        (
            _,
            pathOrZipItem: string | ZipItem,
            maxDimension: number,
            maxSize: number,
        ) => generateImageThumbnail(pathOrZipItem, maxDimension, maxSize),
    );

    handle(
        "ffmpegExec",
        (
            _,
            command: FFmpegCommand,
            pathOrZipItem: string | ZipItem,
            outputFileExtension: string,
        ) => ffmpegExec(command, pathOrZipItem, outputFileExtension),
    );

    handle(
        "ffmpegDetermineVideoDuration",
        (_, pathOrZipItem: string | ZipItem) =>
            ffmpegDetermineVideoDuration(pathOrZipItem),
    );

    // - Upload

    handle("listZipItems", (_, zipPath: string) => listZipItems(zipPath));

    handle("pathOrZipItemSize", (_, pathOrZipItem: string | ZipItem) =>
        pathOrZipItemSize(pathOrZipItem),
    );

    handle("pendingUploads", () => pendingUploads());

    handle("setPendingUploads", (_, pendingUploads: PendingUploads) =>
        setPendingUploads(pendingUploads),
    );

    handle(
        "markUploadedFile",
        (_, path: string, associatedPath: string | undefined) =>
            markUploadedFile(path, associatedPath),
    );

    handle(
        "markUploadedZipItem",
        (_, item: ZipItem, associatedItem: ZipItem | undefined) =>
            markUploadedZipItem(item, associatedItem),
    );

    handle("clearPendingUploads", () => clearPendingUploads());
};

/**
 * A subset of {@link attachIPCHandlers} for functions that need a reference to
 * the main window to do their thing.
 */
export const attachMainWindowIPCHandlers = (mainWindow: BrowserWindow) => {
    // - Utility processes

    on("triggerCreateUtilityProcess", (_, type: UtilityProcessType) =>
        triggerCreateUtilityProcess(type, mainWindow),
    );
};

/**
 * Sibling of {@link attachIPCHandlers} that attaches handlers specific to the
 * watch folder functionality.
 *
 * It gets passed a {@link FSWatcher} instance which it can then forward to the
 * actual handlers if they need access to it to do their thing.
 */
export const attachFSWatchIPCHandlers = (watcher: FSWatcher) => {
    // - Watch

    handle("watchGet", () => watchGet(watcher));

    handle(
        "watchAdd",
        (_, folderPath: string, collectionMapping: CollectionMapping) =>
            watchAdd(watcher, folderPath, collectionMapping),
    );

    handle("watchRemove", (_, folderPath: string) =>
        watchRemove(watcher, folderPath),
    );

    handle(
        "watchUpdateSyncedFiles",
        (_, syncedFiles: FolderWatch["syncedFiles"], folderPath: string) =>
            watchUpdateSyncedFiles(syncedFiles, folderPath),
    );

    handle(
        "watchUpdateIgnoredFiles",
        (_, ignoredFiles: FolderWatch["ignoredFiles"], folderPath: string) =>
            watchUpdateIgnoredFiles(ignoredFiles, folderPath),
    );
};

/**
 * Sibling of {@link attachIPCHandlers} specifically for use with the logout
 * event with needs access to the {@link FSWatcher} instance.
 */
export const attachLogoutIPCHandler = (watcher: FSWatcher) => {
    handle("logout", () => logout(watcher));
};
