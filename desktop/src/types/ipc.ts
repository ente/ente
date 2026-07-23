/**
 * @file types that are shared across the IPC boundary with the renderer process
 *
 * This file is manually kept in sync with the renderer code.
 * See [Note: types.ts <-> preload.ts <-> ipc.ts]
 */

export type UtilityProcessType = "ml";

export interface AppUpdate {
    autoUpdatable: boolean;
    version: string;
}

/**
 * Native provider used for desktop app lock authentication.
 *
 * `touchid` means we can use the platform-native auth prompt.
 * `none` means no supported native provider is currently available.
 */
export type NativeDeviceLockProvider = "touchid" | "none";

/**
 * Why native device lock is unavailable on this machine/session.
 */
export type NativeDeviceLockUnavailableReason =
    | "unsupported-platform"
    | "touchid-not-enrolled"
    | "touchid-temporarily-unavailable"
    | "touchid-api-error";

/**
 * Capability metadata returned by main-process device-lock checks.
 */
export interface NativeDeviceLockCapability {
    /** True when native auth can be prompted right now. */
    available: boolean;
    /** Which native provider backs authentication (if available). */
    provider: NativeDeviceLockProvider;
    /** Present when unavailable, with a machine-readable reason. */
    reason?: NativeDeviceLockUnavailableReason;
}

/**
 * Persisted desktop app-lock configuration.
 *
 * This excludes the passphrase hash material, which continues to live in the
 * renderer KV DB.
 */
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
    /**
     * Whether the folder is currently accessible on disk.
     *
     * Folders on ejected external drives will have this set to false. This
     * property is not persisted and is computed each time the watch list is
     * fetched.
     */
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
