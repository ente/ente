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
import { userPreferences } from "./stores/user-preferences";

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

// The preload bridge remains exposed while the window visits Stripe, so every
// privileged handler must verify that its caller is our renderer.
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

// eslint-disable-next-line @typescript-eslint/no-unnecessary-type-parameters
const on = <A extends unknown[]>(
    channel: string,
    handler: (event: IpcMainEvent, ...args: A) => void,
) =>
    ipcMain.on(channel, (event: IpcMainEvent, ...args: A) => {
        if (ensureTrustedIPCSender(channel, event)) handler(event, ...args);
    });

export const attachIPCHandlers = () => {
    handle("appVersion", () => appVersion());

    handle("openDirectory", (_, dirPath: string) => openDirectory(dirPath));

    handle("openLogDirectory", () => openLogDirectory());

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

    handle("getNativeDeviceLockCapability", () =>
        getNativeDeviceLockCapability(),
    );

    handle("promptDeviceLock", (_, reason: string) => promptDeviceLock(reason));

    on("updateAndRestart", () => updateAndRestart());

    on("updateOnNextRestart", (_, version: string) =>
        updateOnNextRestart(version),
    );

    on("skipAppUpdate", (_, version: string) => skipAppUpdate(version));

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

export const attachMainWindowIPCHandlers = (mainWindow: BrowserWindow) => {
    on("setTitleBarOverlay", (_, isDark: boolean) => {
        if (typeof isDark != "boolean") return;

        userPreferences.set("isDarkMode", isDark);

        if (process.platform != "win32") return;

        mainWindow.setTitleBarOverlay({
            color: isDark ? "black" : "white",
            symbolColor: isDark ? "#cdcdcd" : "black",
        });
    });

    on("triggerCreateUtilityProcess", (_, type: UtilityProcessType) =>
        triggerCreateUtilityProcess(type, mainWindow),
    );
};

export const attachFSWatchIPCHandlers = (watcher: FSWatcher) => {
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

export const attachLogoutIPCHandler = (watcher: FSWatcher) => {
    handle("logout", () => logout(watcher));
};
