// Keep this bridge in sync with desktop/src/types/ipc.ts and desktop/src/preload.ts.
export type NativeDeviceLockProvider = "touchid" | "none";

export type NativeDeviceLockUnavailableReason =
    | "unsupported-platform"
    | "touchid-not-enrolled"
    | "touchid-temporarily-unavailable"
    | "touchid-api-error";

export interface NativeDeviceLockCapability {
    available: boolean;
    provider: NativeDeviceLockProvider;
    reason?: NativeDeviceLockUnavailableReason;
}

export interface PersistedAppLockConfig {
    enabled: boolean;
    lockType: "pin" | "password" | "device" | "none";
    autoLockTimeMs: number;
}

export interface Electron {
    appVersion: () => Promise<string>;
    logToDisk: (message: string) => void;
    openDirectory: (dirPath: string) => Promise<void>;
    openLogDirectory: () => Promise<void>;
    selectDirectory: () => Promise<string | undefined>;
    pathForFile: (file: File) => string;
    logout: () => Promise<void>;
    masterKeyFromSafeStorage: () => Promise<string | undefined>;
    saveMasterKeyInSafeStorage: (masterKey: string) => Promise<void>;
    isSafeStorageAvailable: () => Promise<boolean>;
    appLockConfigFromSafeStorage: () => Promise<
        PersistedAppLockConfig | undefined
    >;
    saveAppLockConfigInSafeStorage: (
        config: PersistedAppLockConfig,
    ) => Promise<void>;
    clearAppLockConfigFromSafeStorage: () => Promise<void>;
    onMainWindowFocus: (cb: (() => void) | undefined) => void;
    onMainWindowBlur: (cb: (() => void) | undefined) => void;
    setTitleBarOverlay: (isDark: boolean) => void;
    onOpenEnteURL: (cb: ((url: string) => void) | undefined) => void;
    lastShownChangelogVersion: () => Promise<number | undefined>;
    setLastShownChangelogVersion: (version: number) => Promise<void>;
    isAutoLaunchEnabled: () => Promise<boolean>;
    toggleAutoLaunch: () => Promise<void>;
    getNativeDeviceLockCapability: () => Promise<NativeDeviceLockCapability>;
    promptDeviceLock: (reason: string) => Promise<boolean>;

    onAppUpdateAvailable: (
        cb: ((update: AppUpdate) => void) | undefined,
    ) => void;
    updateAndRestart: () => void;
    updateOnNextRestart: (version: string) => void;
    skipAppUpdate: (version: string) => void;

    fs: {
        exists: (path: string) => Promise<boolean>;
        mkdirIfNeeded: (dirPath: string) => Promise<void>;
        rename: (oldPath: string, newPath: string) => Promise<void>;
        rmdir: (path: string) => Promise<void>;
        rm: (path: string) => Promise<void>;
        readTextFile: (path: string) => Promise<string>;
        writeFile: (path: string, contents: string) => Promise<void>;
        writeFileViaBackup: (path: string, contents: string) => Promise<void>;
        isDir: (dirPath: string) => Promise<boolean>;
        statMtime: (path: string) => Promise<number>;
        findFiles: (folderPath: string) => Promise<string[]>;
    };

    convertToJPEG: (imageData: Uint8Array) => Promise<Uint8Array<ArrayBuffer>>;
    generateImageThumbnail: (
        pathOrZipItem: string | ZipItem,
        maxDimension: number,
        maxSize: number,
    ) => Promise<Uint8Array<ArrayBuffer>>;
    ffmpegExec: (
        command: FFmpegCommand,
        pathOrZipItem: string | ZipItem,
        outputFileExtension: string,
    ) => Promise<Uint8Array<ArrayBuffer>>;
    ffmpegDetermineVideoDuration: (
        pathOrZipItem: string | ZipItem,
    ) => Promise<number>;

    triggerCreateUtilityProcess: (type: UtilityProcessType) => void;

    watch: {
        get: () => Promise<FolderWatch[]>;
        add: (
            folderPath: string,
            collectionMapping: CollectionMapping,
        ) => Promise<FolderWatch[]>;
        remove: (folderPath: string) => Promise<FolderWatch[]>;
        updateSyncedFiles: (
            syncedFiles: FolderWatch["syncedFiles"],
            folderPath: string,
        ) => Promise<void>;
        updateIgnoredFiles: (
            ignoredFiles: FolderWatch["ignoredFiles"],
            folderPath: string,
        ) => Promise<void>;
        onAddFile: (f: (path: string, watch: FolderWatch) => void) => void;
        onRemoveFile: (f: (path: string, watch: FolderWatch) => void) => void;
        onRemoveDir: (f: (path: string, watch: FolderWatch) => void) => void;
    };

    listZipItems: (
        zipPath: string,
    ) => Promise<{
        items: ZipItem[];
        preUploadSkippedFiles: PreUploadSkippedFile[];
    }>;
    pathOrZipItemSize: (pathOrZipItem: string | ZipItem) => Promise<number>;
    pendingUploads: () => Promise<PendingUploads | undefined>;
    setPendingUploads: (pendingUploads: PendingUploads) => Promise<void>;
    markUploadedFile: (
        path: string,
        associatedPath?: string,
    ) => Promise<number>;
    markUploadedZipItem: (
        item: ZipItem,
        associatedItem?: ZipItem,
    ) => Promise<number>;
    clearPendingUploads: () => Promise<void>;
}

export type UtilityProcessType = "ml";

export interface ElectronMLWorker {
    fsStatMtime: (path: string) => Promise<number>;
    analyzeImage: (
        request: MLWorkerAnalyzeImageRequest,
    ) => Promise<MLWorkerAnalyzeImageResponse>;
    releaseMLRuntime: () => Promise<void>;
    computeCLIPTextEmbeddingIfAvailable: (
        text: string,
    ) => Promise<Float32Array | undefined>;
}

export interface MLWorkerAnalyzeImageRequest {
    fileID: number;
    bytes: Uint8Array;
    runFaces: boolean;
    runClip: boolean;
    runPets: boolean;
    generateFaceCrops: boolean;
}

export type MLWorkerAnalyzeImageErrorKind = "init" | "ort" | "image" | "misc";

export interface MLWorkerAnalyzeImageError {
    kind: MLWorkerAnalyzeImageErrorKind;
    message: string;
}

export type MLWorkerAnalyzeImageResponse =
    | { ok: true; result: MLWorkerAnalyzeImageResult }
    | { ok: false; error: MLWorkerAnalyzeImageError };

export interface MLWorkerFaceResult {
    faceId: string;
    detection: { score: number; boxXyxy: number[]; keypoints: number[][] };
    blurValue: number;
    embedding: Float32Array<ArrayBuffer>;
}

export interface MLWorkerAnalyzeImageResult {
    fileId: number;
    decodedImageSize: { width: number; height: number };
    faces?: MLWorkerFaceResult[];
    faceCrops?: (Uint8Array<ArrayBuffer> | null)[];
    clip?: { embedding: Float32Array<ArrayBuffer> };
    petFaces?: unknown;
    petBodies?: unknown;
    usedCoreml: boolean;
    usedWebgpu: boolean;
}

export interface AppUpdate {
    autoUpdatable: boolean;
    version: string;
}

export interface FolderWatch {
    collectionMapping: CollectionMapping;
    folderPath: string;
    syncedFiles: FolderWatchSyncedFile[];
    ignoredFiles: string[];
    isAccessible?: boolean;
}

export type CollectionMapping = "root" | "parent";
export interface FolderWatchSyncedFile {
    path: string;
    uploadedFileID: number;
    collectionID: number;
}

export type ZipItem = [zipPath: string, entryName: string];

export interface PreUploadSkippedFile {
    name: string;
    type: "hiddenFile" | "failedZip";
}

export interface PendingUploads {
    collectionName?: string;
    filePaths: string[];
    zipItems: ZipItem[];
    preUploadSkippedFiles?: PreUploadSkippedFile[];
    importTakeoutFavorites?: boolean;
    includePartnerSharedFiles?: boolean;
}

export type FFmpegCommand = string[] | { default: string[]; hdr: string[] };
