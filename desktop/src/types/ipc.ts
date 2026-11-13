// Keep these definitions in sync with web/packages/base/types/ipc.ts.
export type UtilityProcessType = "ml";

export type ThemeMode = "light" | "dark" | "system";

export interface AppUpdate {
    autoUpdatable: boolean;
    version: string;
}

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

// Passphrase hashes remain in renderer KV storage.
export interface PersistedAppLockConfig {
    enabled: boolean;
    lockType: "pin" | "password" | "device" | "none";
    autoLockTimeMs: number;
}

export interface FolderWatch {
    collectionMapping: CollectionMapping;
    folderPath: string;
    syncedFiles: FolderWatchSyncedFile[];
    ignoredFiles: string[];
    // Computed on read; false for ejected external drives.
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
    collectionName: string | undefined;
    filePaths: string[];
    zipItems: ZipItem[];
    preUploadSkippedFiles?: PreUploadSkippedFile[];
    importTakeoutFavorites?: boolean;
    includePartnerSharedFiles?: boolean;
}

export type FFmpegCommand = string[] | { default: string[]; hdr: string[] };
