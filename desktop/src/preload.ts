// Sandboxed preload scripts cannot import runtime code from src, so this file
// must remain self-contained. DOM types expose window here but conflict with
// Node's ReadableStream types; see main/utils/stream.ts.
/// <reference lib="dom" />

// Keep the exposed bridge in sync with web/packages/base/types/ipc.ts.

import { contextBridge, ipcRenderer, webUtils } from "electron/renderer";

import type { IpcRendererEvent } from "electron";
import type {
    AppUpdate,
    CollectionMapping,
    FFmpegCommand,
    FolderWatch,
    NativeDeviceLockCapability,
    PendingUploads,
    PersistedAppLockConfig,
    UtilityProcessType,
    ZipItem,
} from "./types/ipc";

const windowLoaded = new Promise((resolve) => {
    window.onload = resolve;
});

const appVersion = () => ipcRenderer.invoke("appVersion");

const logToDisk = (message: string): void =>
    ipcRenderer.send("logToDisk", message);

const openDirectory = (dirPath: string) =>
    ipcRenderer.invoke("openDirectory", dirPath);

const openLogDirectory = () => ipcRenderer.invoke("openLogDirectory");

const selectDirectory = () => ipcRenderer.invoke("selectDirectory");

const pathForFile =
    process.platform == "win32"
        ? (file: File) => webUtils.getPathForFile(file).replace(/\\/g, "/")
        : (file: File) => webUtils.getPathForFile(file);

const logout = () => {
    watchRemoveListeners();
    return ipcRenderer.invoke("logout");
};

const masterKeyFromSafeStorage = () =>
    ipcRenderer.invoke("masterKeyFromSafeStorage");

const saveMasterKeyInSafeStorage = (masterKey: string) =>
    ipcRenderer.invoke("saveMasterKeyInSafeStorage", masterKey);

const isSafeStorageAvailable = (): Promise<boolean> =>
    ipcRenderer.invoke("isSafeStorageAvailable");

const appLockConfigFromSafeStorage = (): Promise<
    PersistedAppLockConfig | undefined
> => ipcRenderer.invoke("appLockConfigFromSafeStorage");

const saveAppLockConfigInSafeStorage = (config: PersistedAppLockConfig) =>
    ipcRenderer.invoke("saveAppLockConfigInSafeStorage", config);

const clearAppLockConfigFromSafeStorage = () =>
    ipcRenderer.invoke("clearAppLockConfigFromSafeStorage");

const lastShownChangelogVersion = () =>
    ipcRenderer.invoke("lastShownChangelogVersion");

const setLastShownChangelogVersion = (version: number) =>
    ipcRenderer.invoke("setLastShownChangelogVersion", version);

const isAutoLaunchEnabled = () => ipcRenderer.invoke("isAutoLaunchEnabled");

const toggleAutoLaunch = () => ipcRenderer.invoke("toggleAutoLaunch");

const getNativeDeviceLockCapability = (): Promise<NativeDeviceLockCapability> =>
    ipcRenderer.invoke("getNativeDeviceLockCapability");

const minDeviceLockPromptIntervalMs = 1_500;
let lastDeviceLockPromptTimeMs = 0;

const promptDeviceLock = async (reason: string) => {
    const now = Date.now();
    if (now - lastDeviceLockPromptTimeMs < minDeviceLockPromptIntervalMs) {
        return false;
    }

    lastDeviceLockPromptTimeMs = now;
    const result: unknown = await ipcRenderer.invoke(
        "promptDeviceLock",
        reason,
    );
    return result === true;
};

const onMainWindowFocus = (cb: (() => void) | undefined) => {
    ipcRenderer.removeAllListeners("mainWindowFocus");
    if (cb) ipcRenderer.on("mainWindowFocus", cb);
};

const onMainWindowBlur = (cb: (() => void) | undefined) => {
    ipcRenderer.removeAllListeners("mainWindowBlur");
    if (cb) ipcRenderer.on("mainWindowBlur", cb);
};

const setTitleBarOverlay = (isDark: boolean) =>
    ipcRenderer.send("setTitleBarOverlay", isDark);

const onOpenEnteURL = (cb: ((url: string) => void) | undefined) => {
    ipcRenderer.removeAllListeners("openEnteURL");
    if (cb) ipcRenderer.on("openEnteURL", (_, url: string) => cb(url));
};

const onAppUpdateAvailable = (
    cb: ((update: AppUpdate) => void) | undefined,
) => {
    ipcRenderer.removeAllListeners("appUpdateAvailable");
    if (cb) {
        ipcRenderer.on("appUpdateAvailable", (_, update: AppUpdate) =>
            cb(update),
        );
    }
};

const updateAndRestart = () => ipcRenderer.send("updateAndRestart");

const updateOnNextRestart = (version: string) =>
    ipcRenderer.send("updateOnNextRestart", version);

const skipAppUpdate = (version: string) => {
    ipcRenderer.send("skipAppUpdate", version);
};

const fsExists = (path: string) => ipcRenderer.invoke("fsExists", path);

const fsMkdirIfNeeded = (dirPath: string) =>
    ipcRenderer.invoke("fsMkdirIfNeeded", dirPath);

const fsRename = (oldPath: string, newPath: string) =>
    ipcRenderer.invoke("fsRename", oldPath, newPath);

const fsRmdir = (path: string) => ipcRenderer.invoke("fsRmdir", path);

const fsRm = (path: string) => ipcRenderer.invoke("fsRm", path);

const fsReadTextFile = (path: string) =>
    ipcRenderer.invoke("fsReadTextFile", path);

const fsWriteFile = (path: string, contents: string) =>
    ipcRenderer.invoke("fsWriteFile", path, contents);

const fsWriteFileViaBackup = (path: string, contents: string) =>
    ipcRenderer.invoke("fsWriteFileViaBackup", path, contents);

const fsIsDir = (dirPath: string) => ipcRenderer.invoke("fsIsDir", dirPath);

const fsStatMtime = (path: string) => ipcRenderer.invoke("fsStatMtime", path);

const convertToJPEG = (
    imageData: Uint8Array,
): Promise<Uint8Array<ArrayBuffer>> =>
    ipcRenderer.invoke("convertToJPEG", imageData);

const generateImageThumbnail = (
    pathOrZipItem: string | ZipItem,
    maxDimension: number,
    maxSize: number,
): Promise<Uint8Array<ArrayBuffer>> =>
    ipcRenderer.invoke(
        "generateImageThumbnail",
        pathOrZipItem,
        maxDimension,
        maxSize,
    );

const ffmpegExec = (
    command: FFmpegCommand,
    pathOrZipItem: string | ZipItem,
    outputFileExtension: string,
): Promise<Uint8Array<ArrayBuffer>> =>
    ipcRenderer.invoke(
        "ffmpegExec",
        command,
        pathOrZipItem,
        outputFileExtension,
    );

const ffmpegDetermineVideoDuration = (pathOrZipItem: string | ZipItem) =>
    ipcRenderer.invoke("ffmpegDetermineVideoDuration", pathOrZipItem);

const triggerCreateUtilityProcess = (type: UtilityProcessType) => {
    const portEvent = `utilityProcessPort/${type}`;
    const l = (event: IpcRendererEvent) => {
        void windowLoaded.then(() => {
            window.postMessage(portEvent, "*", event.ports);
            ipcRenderer.off(portEvent, l);
        });
    };
    ipcRenderer.on(portEvent, l);
    ipcRenderer.send("triggerCreateUtilityProcess", type);
};

const watchGet = () => ipcRenderer.invoke("watchGet");

const watchAdd = (folderPath: string, collectionMapping: CollectionMapping) =>
    ipcRenderer.invoke("watchAdd", folderPath, collectionMapping);

const watchRemove = (folderPath: string) =>
    ipcRenderer.invoke("watchRemove", folderPath);

const watchUpdateSyncedFiles = (
    syncedFiles: FolderWatch["syncedFiles"],
    folderPath: string,
) => ipcRenderer.invoke("watchUpdateSyncedFiles", syncedFiles, folderPath);

const watchUpdateIgnoredFiles = (
    ignoredFiles: FolderWatch["ignoredFiles"],
    folderPath: string,
) => ipcRenderer.invoke("watchUpdateIgnoredFiles", ignoredFiles, folderPath);

const watchOnAddFile = (f: (path: string, watch: FolderWatch) => void) => {
    ipcRenderer.removeAllListeners("watchAddFile");
    ipcRenderer.on("watchAddFile", (_, path: string, watch: FolderWatch) =>
        f(path, watch),
    );
};

const watchOnRemoveFile = (f: (path: string, watch: FolderWatch) => void) => {
    ipcRenderer.removeAllListeners("watchRemoveFile");
    ipcRenderer.on("watchRemoveFile", (_, path: string, watch: FolderWatch) =>
        f(path, watch),
    );
};

const watchOnRemoveDir = (f: (path: string, watch: FolderWatch) => void) => {
    ipcRenderer.removeAllListeners("watchRemoveDir");
    ipcRenderer.on("watchRemoveDir", (_, path: string, watch: FolderWatch) =>
        f(path, watch),
    );
};

const fsFindFiles = (folderPath: string) =>
    ipcRenderer.invoke("fsFindFiles", folderPath);

const watchRemoveListeners = () => {
    ipcRenderer.removeAllListeners("watchAddFile");
    ipcRenderer.removeAllListeners("watchRemoveFile");
    ipcRenderer.removeAllListeners("watchRemoveDir");
};

const listZipItems = (zipPath: string) =>
    ipcRenderer.invoke("listZipItems", zipPath);

const pathOrZipItemSize = (pathOrZipItem: string | ZipItem) =>
    ipcRenderer.invoke("pathOrZipItemSize", pathOrZipItem);

const pendingUploads = () => ipcRenderer.invoke("pendingUploads");

const setPendingUploads = (pendingUploads: PendingUploads) =>
    ipcRenderer.invoke("setPendingUploads", pendingUploads);

const markUploadedFile = (path: string, associatedPath?: string) =>
    ipcRenderer.invoke("markUploadedFile", path, associatedPath);

const markUploadedZipItem = (item: ZipItem, associatedItem?: ZipItem) =>
    ipcRenderer.invoke("markUploadedZipItem", item, associatedItem);

const clearPendingUploads = () => ipcRenderer.invoke("clearPendingUploads");

// contextBridge copies ArrayBuffers between processes; use stream:// for large data.
contextBridge.exposeInMainWorld("electron", {
    appVersion,
    logToDisk,
    openDirectory,
    openLogDirectory,
    selectDirectory,
    pathForFile,
    logout,
    masterKeyFromSafeStorage,
    saveMasterKeyInSafeStorage,
    isSafeStorageAvailable,
    appLockConfigFromSafeStorage,
    saveAppLockConfigInSafeStorage,
    clearAppLockConfigFromSafeStorage,
    lastShownChangelogVersion,
    setLastShownChangelogVersion,
    isAutoLaunchEnabled,
    toggleAutoLaunch,
    getNativeDeviceLockCapability,
    promptDeviceLock,
    onMainWindowFocus,
    onMainWindowBlur,
    setTitleBarOverlay,
    onOpenEnteURL,

    onAppUpdateAvailable,
    updateAndRestart,
    updateOnNextRestart,
    skipAppUpdate,

    fs: {
        exists: fsExists,
        rename: fsRename,
        mkdirIfNeeded: fsMkdirIfNeeded,
        rmdir: fsRmdir,
        rm: fsRm,
        readTextFile: fsReadTextFile,
        writeFile: fsWriteFile,
        writeFileViaBackup: fsWriteFileViaBackup,
        isDir: fsIsDir,
        statMtime: fsStatMtime,
        findFiles: fsFindFiles,
    },

    convertToJPEG,
    generateImageThumbnail,
    ffmpegExec,
    ffmpegDetermineVideoDuration,

    triggerCreateUtilityProcess,

    watch: {
        get: watchGet,
        add: watchAdd,
        remove: watchRemove,
        updateSyncedFiles: watchUpdateSyncedFiles,
        updateIgnoredFiles: watchUpdateIgnoredFiles,
        onAddFile: watchOnAddFile,
        onRemoveFile: watchOnRemoveFile,
        onRemoveDir: watchOnRemoveDir,
    },

    listZipItems,
    pathOrZipItemSize,
    pendingUploads,
    setPendingUploads,
    markUploadedFile,
    markUploadedZipItem,
    clearPendingUploads,
});
