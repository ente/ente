// Following are types shared with the Electron process. This list is manually
// kept in sync with `desktop/src/types/ipc.ts`.
//
// See [Note: types.ts <-> preload.ts <-> ipc.ts]

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
 * Capability metadata used by the renderer to decide whether to show and use
 * "Device lock" as an app-lock mode.
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

/**
 * Extra APIs provided by our Node.js layer when our code is running inside our
 * desktop (Electron) app.
 *
 * This list is manually kept in sync with `desktop/src/preload.ts`. In case of
 * a mismatch, the types may lie. See also: [Note: types.ts <-> preload.ts <->
 * ipc.ts]
 *
 * These extra objects and functions will only be available when our code is
 * running as the renderer process in Electron. These can be accessed by using
 * the `electron` property of the window (See @{link globalElectron} for a
 * systematic way of getting at that).
 */
export interface Electron {
    // - General

    /**
     * Return the version of the desktop app.
     *
     * The return value is of the form `v1.2.3`.
     */
    appVersion: () => Promise<string>;

    /**
     * Log the given {@link message} to the on-disk log file maintained by the
     * desktop app.
     *
     * Note: Unlike the other functions exposed over the Electron bridge,
     * logToDisk is fire-and-forget and does not return a promise.
     */
    logToDisk: (message: string) => void;

    /**
     * Open the given {@link dirPath} in the system's folder viewer.
     *
     * For example, on macOS this'll open {@link dirPath} in Finder.
     */
    openDirectory: (dirPath: string) => Promise<void>;

    /**
     * Open the app's log directory in the system's folder viewer.
     *
     * @see {@link openDirectory}
     */
    openLogDirectory: () => Promise<void>;

    /**
     * Ask the user to select a directory on their local file system, and return
     * it path.
     *
     * The returned path is guaranteed to use POSIX separators ('/').
     *
     * We don't strictly need IPC for this, we can use a hidden <input> element
     * and trigger its click for the same behaviour (as we do for the
     * `useFileInput` hook that we use for uploads). However, it's a bit
     * cumbersome, and we anyways will need to IPC to get back its full path, so
     * it is just convenient to expose this direct method.
     */
    selectDirectory: () => Promise<string | undefined>;

    /**
     * Return the file system path that this File object points to.
     *
     * The returned path will use POSIX separators (even on Windows).
     *
     * This method is a bit different from the other methods on the Electron
     * object in the sense that there is no actual IPC happening - the
     * implementation of this method is completely in the preload script. Thus
     * we can pass it an otherwise unserializable File object.
     *
     * Consequently, it is also _not_ async.
     */
    pathForFile: (file: File) => string;

    /**
     * Perform any logout related cleanup of native side state.
     */
    logout: () => Promise<void>;

    /**
     * Return the previously saved user's master key from the persistent safe
     * storage accessible to the desktop app.
     *
     * The key is returned as a base64 encoded string.
     *
     * If the key is not found, return `undefined`.
     *
     * See also: {@link saveMasterKeyInSafeStorage}.
     */
    masterKeyFromSafeStorage: () => Promise<string | undefined>;

    /**
     * Save the given {@link masterKey} (encoded as a base64 string) to the
     * persistent safe storage accessible to the desktop app.
     */
    saveMasterKeyInSafeStorage: (masterKey: string) => Promise<void>;

    /**
     * Return true when the desktop app can currently use OS safe storage.
     */
    isSafeStorageAvailable: () => Promise<boolean>;

    /**
     * Return the persisted desktop app-lock configuration from safe storage, if
     * any.
     */
    appLockConfigFromSafeStorage: () => Promise<
        PersistedAppLockConfig | undefined
    >;

    /**
     * Save the given desktop app-lock configuration to safe storage.
     */
    saveAppLockConfigInSafeStorage: (
        config: PersistedAppLockConfig,
    ) => Promise<void>;

    /**
     * Remove any persisted desktop app-lock configuration from safe storage.
     */
    clearAppLockConfigFromSafeStorage: () => Promise<void>;

    /**
     * Set or clear the callback {@link cb} to invoke whenever the app comes
     * into the foreground. More precisely, the callback gets invoked when the
     * main window gets focus.
     *
     * Setting a callback clears any previous callbacks.
     *
     * @param cb The function to call when the main window gets focus. Pass
     * `undefined` to clear the callback.
     */
    onMainWindowFocus: (cb: (() => void) | undefined) => void;

    /**
     * Set or clear the callback {@link cb} to invoke whenever the app goes to
     * the background. More precisely, the callback gets invoked when the main
     * window blurs and the app is no longer focused.
     *
     * Setting a callback clears any previous callbacks.
     *
     * @param cb The function to call when the app is backgrounded. Pass
     * `undefined` to clear the callback.
     */
    onMainWindowBlur: (cb: (() => void) | undefined) => void;

    /**
     * Set or clear the callback {@link cb} to invoke whenever the app gets
     * asked to open a deeplink that begins with "ente://". This allows the
     * Node.js layer to ask the renderer to handle deeplinks and redirect itself
     * to a new location if needed.
     *
     * In particular, this is necessary for handling passkey authentication.
     * See: [Note: Passkey verification in the desktop app]
     *
     * Setting a callback clears any previous callbacks.
     *
     * @param cb The function to call when the app gets asked to open a
     * "ente://" URL. The URL string (a.k.a. "deeplink") we were asked to open
     * is passed to the function verbatim.
     */
    onOpenEnteURL: (cb: ((url: string) => void) | undefined) => void;

    /**
     * Get the persisted version for the last shown changelog.
     *
     * See: [Note: Conditions for showing "What's new"]
     */
    lastShownChangelogVersion: () => Promise<number | undefined>;

    /**
     * Save the given {@link version} to disk as the version of the last shown
     * changelog.
     *
     * The value is saved to a store which is not cleared during logout.
     *
     * @see {@link lastShownChangelogVersion}
     */
    setLastShownChangelogVersion: (version: number) => Promise<void>;

    /**
     * Return true if the auto launch on system startup is enabled.
     */
    isAutoLaunchEnabled: () => Promise<boolean>;

    /**
     * Toggle the auto launch on system startup behaviour.
     *
     * @see {@link isAutoLaunchEnabled}
     */
    toggleAutoLaunch: () => Promise<void>;

    /**
     * Return native device lock capability details for the current machine.
     *
     * Includes whether native auth is available, provider metadata, and a
     * reason when unavailable.
     */
    getNativeDeviceLockCapability: () => Promise<NativeDeviceLockCapability>;

    /**
     * Prompt native device lock authentication.
     *
     * The {@link reason} can be shown by the OS in the native auth prompt.
     * Returns true on successful authentication.
     */
    promptDeviceLock: (reason: string) => Promise<boolean>;

    // - App update

    /**
     * Set or clear the callback {@link cb} to invoke whenever a new
     * (actionable) app update is available. This allows the Node.js layer to
     * ask the renderer to show an "Update available" dialog to the user.
     *
     * Setting a callback clears any previous callbacks.
     */
    onAppUpdateAvailable: (
        cb: ((update: AppUpdate) => void) | undefined,
    ) => void;

    /**
     * Restart the app to apply the latest available update.
     *
     * This is expected to be called in response to {@link onAppUpdateAvailable}
     * if the user so wishes.
     */
    updateAndRestart: () => void;

    /**
     * Mute update notifications for the given {@link version}. This allows us
     * to implement the "Install on next launch" functionality in response to
     * the {@link onAppUpdateAvailable} event.
     */
    updateOnNextRestart: (version: string) => void;

    /**
     * Skip the app update with the given {@link version}.
     *
     * This is expected to be called in response to {@link onAppUpdateAvailable}
     * if the user so wishes. It will remember this {@link version} as having
     * been marked as skipped so that we don't prompt the user again.
     */
    skipAppUpdate: (version: string) => void;

    // - FS

    /**
     * A subset of file system access APIs.
     *
     * The renderer process, being a web process, does not have full access to
     * the local file system apart from files explicitly dragged and dropped (or
     * selected by the user in a native file open dialog).
     *
     * The main process, however, has full fil system access (limited only be an
     * OS level sandbox on the entire process).
     *
     * When we're running in the desktop app, we want to better utilize the
     * local file system access to provide more integrated features to the user;
     * things that are not currently possible using web technologies. For
     * example, continuous exports to an arbitrary user chosen location on disk,
     * or watching some folders for changes and syncing them automatically.
     *
     * Towards this end, this fs object provides some generic file system access
     * functions that are needed for such features (in some cases, there are
     * other feature specific methods too in the top level electron object).
     */
    fs: {
        /** Return true if there is an item at the given {@link path}. */
        exists: (path: string) => Promise<boolean>;

        /**
         * Equivalent of `mkdir -p`.
         *
         * Create a directory at the given path if it does not already exist.
         * Any parent directories in the path that don't already exist will also
         * be created recursively, i.e. this command is analogous to an running
         * `mkdir -p`.
         */
        mkdirIfNeeded: (dirPath: string) => Promise<void>;

        /** Rename {@link oldPath} to {@link newPath} */
        rename: (oldPath: string, newPath: string) => Promise<void>;

        /**
         * Equivalent of `rmdir`.
         *
         * Delete the directory at the {@link path} if it is empty.
         */
        rmdir: (path: string) => Promise<void>;

        /**
         * Equivalent of `rm`.
         *
         * Delete the file at {@link path}.
         */
        rm: (path: string) => Promise<void>;

        /** Read the string contents of a file at {@link path}. */
        readTextFile: (path: string) => Promise<string>;

        /**
         * Write a string to a file, replacing the file if it already exists.
         *
         * @param path The path of the file.
         * @param contents The string contents to write.
         */
        writeFile: (path: string, contents: string) => Promise<void>;

        /**
         * A variant of {@link writeFile} that first writes the file to a backup
         * file, and then renames the backup file to the actual path. This both
         * makes the write atomic (as far as the node's fs.rename guarantees
         * atomicity), and also keeps the backup file around for recovery if
         * something goes wrong during the rename.
         *
         * This behaviour of this function is tailored around for writes to the
         * "export_status.json" during exports.
         */
        writeFileViaBackup: (path: string, contents: string) => Promise<void>;

        /**
         * Return true if there is an item at {@link dirPath}, and it is as
         * directory.
         */
        isDir: (dirPath: string) => Promise<boolean>;

        /**
         * Return the last modified time (integral epoch milliseconds) of the
         * file system entry at {@link path}.
         */
        statMtime: (path: string) => Promise<number>;

        /**
         * Return the paths of all the files under the given folder.
         *
         * This function walks the directory tree starting at {@link folderPath}
         * and returns a list of the absolute paths of all the files that exist
         * therein. It will recursively traverse into nested directories, and
         * return the absolute paths of the files there too.
         *
         * The returned paths are guaranteed to use POSIX separators ('/').
         */
        findFiles: (folderPath: string) => Promise<string[]>;
    };

    // - Conversion

    /**
     * Try to convert an arbitrary image into JPEG using native layer tools.
     *
     * The behaviour is OS dependent. On macOS we use the `sips` utility, while
     * on Linux and Windows we use a `vips` bundled with our desktop app.
     *
     * @param imageData The raw image data (the contents of the image file).
     *
     * @returns JPEG data of the converted image.
     */
    convertToJPEG: (imageData: Uint8Array) => Promise<Uint8Array<ArrayBuffer>>;

    /**
     * Generate a JPEG thumbnail for the given image.
     *
     * The behaviour is OS dependent. On macOS we use the `sips` utility, while
     * on Linux and Windows we use a `vips` bundled with our desktop app.
     *
     * @param pathOrZipItem The file whose thumbnail we want to generate. It can
     * be provided as raw image data (the contents of the image file), or the
     * path to the image file, or a tuple containing the path of the zip file
     * along with the name of an entry in it.
     *
     * @param maxDimension The maximum width or height of the generated
     * thumbnail.
     *
     * @param maxSize Maximum size (in bytes) of the generated thumbnail.
     *
     * @returns JPEG data of the generated thumbnail.
     */
    generateImageThumbnail: (
        pathOrZipItem: string | ZipItem,
        maxDimension: number,
        maxSize: number,
    ) => Promise<Uint8Array<ArrayBuffer>>;

    /**
     * Execute a FFmpeg {@link command} on the given {@link pathOrZipItem}.
     *
     * This executes the command using a FFmpeg executable we bundle with our
     * desktop app. We also have a Wasm FFmpeg implementation that we use when
     * running on the web, which has a sibling function with the same
     * parameters. See [Note:FFmpeg in Electron].
     *
     * @param command An array of strings, each representing one positional
     * parameter in the command to execute. Placeholders for the input, output
     * and ffmpeg's own path are replaced before executing the command
     * (respectively {@link inputPathPlaceholder},
     * {@link outputPathPlaceholder}, {@link ffmpegPathPlaceholder}).
     *
     * @param pathOrZipItem The path to the input file on the user's local disk,
     * or the path to a zip file on the user's disk and the name of an entry in
     * it. In the second case, the data gets serialized to a temporary file, and
     * then that path (or if it was already a path) gets substituted in the
     * FFmpeg {@link command} in lieu of {@link inputPathPlaceholder}.
     *
     * @param outputFileExtension The extension (without the dot, e.g. "jpeg")
     * to use for the output file that we ask FFmpeg to create in
     * {@param command}. While this file will eventually get deleted, and we'll
     * just return its contents, for some FFmpeg command the extension matters
     * (e.g. conversion to a JPEG fails if the extension is arbitrary).
     *
     * @returns The contents of the output file produced by the ffmpeg command
     * (specified as {@link outputPathPlaceholder} in {@link command}).
     */
    ffmpegExec: (
        command: FFmpegCommand,
        pathOrZipItem: string | ZipItem,
        outputFileExtension: string,
    ) => Promise<Uint8Array<ArrayBuffer>>;

    /**
     * Determine the duration (in seconds) of the video  present at
     * {@link pathOrZipItem} using ffmpeg.
     *
     * This is a bespoke variant of {@link ffmpegExec} for the sole purpose of
     * retrieving the video duration.
     *
     * @param pathOrZipItem The input file whose duration we want to determine.
     * For more details, see the documentation of the {@link ffmpegExec}
     * parameter with the same name.
     *
     * @returns The duration (in seconds) of the video referred to by
     * {@link pathOrZipItem}.
     */
    ffmpegDetermineVideoDuration: (
        pathOrZipItem: string | ZipItem,
    ) => Promise<number>;

    // - Utility process

    /**
     * Trigger the creation of a new utility process of the given {@link type},
     * terminating the older ones (if any).
     *
     * This creates a new Node.js utility process, and sets things up so that we
     * can communicate directly with that utility process using a
     * {@link MessagePort} that gets posted on the "utilityProcessPort/<type>"
     * channel.
     *
     * The code running in the utility process is determined by the specific
     * value of {@link type}. Thus, att the other end of that port will be an
     * object that conforms to:
     *
     * - {@link ElectronMLWorker} interface, when type is "ml".
     *
     * For more details about the IPC flow, see: [Note: ML IPC].
     *
     * Note: For simplicity of implementation, we assume that there is at most
     * one outstanding call to {@link triggerCreateUtilityProcess} for a given
     * {@link type}.
     */
    triggerCreateUtilityProcess: (type: UtilityProcessType) => void;

    // - Watch

    /**
     * Interface with the file system watcher running in our Node.js layer.
     *
     * [Note: Folder vs Directory in the context of FolderWatch-es]
     *
     * A note on terminology: The word "folder" is used to the top level root
     * folder for which a {@link FolderWatch} has been added. This folder is
     * also in 1-1 correspondence to be a directory on the user's disk. It can
     * have other, nested directories too (which may or may not be getting
     * mapped to separate Ente collections), but we'll not refer to these nested
     * directories as folders - only the root of the tree, which the user
     * dragged/dropped or selected to set up the folder watch, will be referred
     * to as a folder when naming things.
     */
    watch: {
        /**
         * Return the list of folder watches, pruning non-existing directories.
         *
         * The list of folder paths (and auxiliary details) is persisted in the
         * Node.js layer. The implementation of this function goes through the
         * list, permanently removes any watches whose on-disk directory is no
         * longer present, and returns this pruned list of watches.
         */
        get: () => Promise<FolderWatch[]>;

        /**
         * Add a new folder watch for the given {@link folderPath}.
         *
         * This adds a new entry in the list of watches (persisting them on
         * disk), and also starts immediately observing for file system events
         * that happen within {@link folderPath}.
         *
         * @param collectionMapping Determines how nested directories (if any)
         * get mapped to Ente collections.
         *
         * @returns The updated list of watches.
         */
        add: (
            folderPath: string,
            collectionMapping: CollectionMapping,
        ) => Promise<FolderWatch[]>;

        /**
         * Remove the pre-existing watch for the given {@link folderPath}.
         *
         * Persist this removal, and also stop listening for file system events
         * that happen within the {@link folderPath}.
         *
         * @returns The updated list of watches.
         */
        remove: (folderPath: string) => Promise<FolderWatch[]>;

        /**
         * Update the list of synced files for the folder watch associated
         * with the given {@link folderPath}.
         */
        updateSyncedFiles: (
            syncedFiles: FolderWatch["syncedFiles"],
            folderPath: string,
        ) => Promise<void>;

        /**
         * Update the list of ignored file paths for the folder watch
         * associated with the given {@link folderPath}.
         */
        updateIgnoredFiles: (
            ignoredFiles: FolderWatch["ignoredFiles"],
            folderPath: string,
        ) => Promise<void>;

        /**
         * Register the function to invoke when a file is added in one of the
         * folders we are watching.
         *
         * The callback function is passed the path to the file that was added,
         * and the folder watch it was associated with.
         *
         * The path is guaranteed to use POSIX separators ('/').
         */
        onAddFile: (f: (path: string, watch: FolderWatch) => void) => void;

        /**
         * Register the function to invoke when a file is removed in one of the
         * folders we are watching.
         *
         * The callback function is passed the path to the file that was
         * removed, and the folder watch it was associated with.
         *
         * The path is guaranteed to use POSIX separators ('/').
         */
        onRemoveFile: (f: (path: string, watch: FolderWatch) => void) => void;

        /**
         * Register the function to invoke when a directory is removed in one of
         * the folders we are watching.
         *
         * The callback function is passed the path to the directory that was
         * removed, and the folder watch it was associated with.
         *
         * The path is guaranteed to use POSIX separators ('/').
         */
        onRemoveDir: (f: (path: string, watch: FolderWatch) => void) => void;
    };

    // - Upload

    /**
     * Get the list of files that are present in the given zip file.
     *
     * @param zipPath The path of the zip file on the user's local file system.
     *
     * @returns A list of (zipPath, entryName) tuples, one for each file in the
     * given zip. Directories are traversed recursively, but the directory
     * entries themselves will be excluded from the returned list. File entries
     * whose file name begins with a dot (i.e. "hidden" files) will also be
     * excluded.
     *
     * Alongside `items`, the result includes `preUploadSkippedFiles`: the
     * hidden entries excluded above, plus a single entry for the zip itself if
     * it could not be opened.
     *
     * To read the contents of the files themselves, see [Note: IPC streams].
     */
    listZipItems: (
        zipPath: string,
    ) => Promise<{
        items: ZipItem[];
        preUploadSkippedFiles: PreUploadSkippedFile[];
    }>;

    /**
     * Return the size in bytes of the file at the given path or of a particular
     * entry within a zip file.
     */
    pathOrZipItemSize: (pathOrZipItem: string | ZipItem) => Promise<number>;

    /**
     * Return any pending uploads that were previously enqueued but haven't yet
     * been completed.
     *
     * Return undefined if there are no such pending uploads.
     *
     * The state of pending uploads is persisted in the Node.js layer. Or app
     * start, we read in this data from the Node.js layer via this IPC method.
     * The Node.js code returns the persisted data after filtering out any files
     * that no longer exist on disk.
     */
    pendingUploads: () => Promise<PendingUploads | undefined>;

    /**
     * Set the state of pending uploads.
     *
     * - Typically, this would be called at the start of an upload.
     *
     * - Thereafter, as each item gets uploaded one by one, we'd call
     *   {@link markUploadedFile} or {@link markUploadedZipItem}.
     *
     * - Finally, once the upload completes (or gets cancelled), we'd call
     *   {@link clearPendingUploads} to complete the circle.
     */
    setPendingUploads: (pendingUploads: PendingUploads) => Promise<void>;

    /**
     * Mark the given files (specified by their disk paths) as having been
     * uploaded.
     *
     * @param {@link path} The path to the file system file which was uploaded.
     *
     * @param {@link associatedPath} The path file (if any) of the file
     * associated with the file which was uploaded. This will be present only in
     * the case of live photos, where this will be set to the path of the video
     * component of the live photo on disk.
     *
     * @returns The last modified time (epoch milliseconds) of the file at
     * {@link path}.
     */
    markUploadedFile: (
        path: string,
        associatedPath?: string,
    ) => Promise<number>;

    /**
     * Mark the given {@link ZipItem}s as having been uploaded.
     *
     * @param {@link item} The {@link ZipItem} which was uploaded.
     *
     * @param {@link associatedItem} An optional extra {@link ZipItem}
     * associated with the {@link item} which was uploaded. This will be present
     * only in case of live photos, where this'll be set to the {@link ZipItem}
     * representing the video component of the live photo on disk.
     *
     * @returns The last modified time (epoch milliseconds) of the zip file
     * containing {@link item}.
     */
    markUploadedZipItem: (
        item: ZipItem,
        associatedItem?: ZipItem,
    ) => Promise<number>;

    /**
     * Clear any pending uploads.
     *
     * This is also taken by the Node.js layer as a signal to clear any cached
     * state it has kept around to speed up the upload.
     */
    clearPendingUploads: () => Promise<void>;
}

export type UtilityProcessType = "ml";

/**
 * The shape of the object exposed by the Node.js utility process listening on
 * the other side message port that the web layer obtains by doing
 * {@link triggerCreateUtilityProcess} with type "ml".
 */
export interface ElectronMLWorker {
    /**
     * Return the last modified time (epoch milliseconds) for the file at the
     * given {@link path} on the user's file system.
     */
    fsStatMtime: (path: string) => Promise<number>;

    /**
     * Return a CLIP embedding of the given image.
     *
     * See: [Note: Natural language search using CLIP]
     *
     * The input is a opaque float32 array representing the image. The layout
     * and exact encoding of the input is specific to the runtime (ONNX) and the
     * ML model (a MobileCLIP variant) we use. In particular, the image
     * pre-processing happens within our model itself.
     *
     * @returns A CLIP embedding (an array of 512 floating point values).
     */
    computeCLIPImageEmbedding: (
        input: Uint8ClampedArray,
        inputShape: number[],
    ) => Promise<Float32Array>;

    /**
     * Return a CLIP embedding of the given image if we already have the model
     * downloaded and prepped. If the model is not available return `undefined`.
     *
     * This differs from the other sibling ML functions in that it doesn't wait
     * for the model download to finish. It does trigger a model download, but
     * then immediately returns `undefined`. At some future point, when the
     * model downloaded finishes, calls to this function will start returning
     * the result we seek.
     *
     * The reason for doing it in this asymmetric way is because CLIP text
     * embeddings are used as part of deducing user initiated search results,
     * and we don't want to block that interaction on a large network request.
     *
     * See: [Note: Natural language search using CLIP]
     *
     * @param text The string whose embedding we want to compute.
     *
     * @returns A CLIP embedding.
     */
    computeCLIPTextEmbeddingIfAvailable: (
        text: string,
    ) => Promise<Float32Array | undefined>;

    /**
     * Detect faces in the given image using YOLO.
     *
     * Both the input and output are opaque binary data whose internal structure
     * is specific to our implementation and the model (YOLO) we use.
     */
    detectFaces: (
        input: Uint8ClampedArray,
        inputShape: number[],
    ) => Promise<Float32Array>;

    /**
     * Return a MobileFaceNet embeddings for the given faces.
     *
     * Both the input and output are opaque binary data whose internal structure
     * is specific to our implementation and the model (MobileFaceNet) we use.
     */
    computeFaceEmbeddings: (input: Float32Array) => Promise<Float32Array>;
}

/**
 * Data passed across the IPC bridge when an app update is available.
 */
export interface AppUpdate {
    /** `true` if the user automatically update to this (new) version */
    autoUpdatable: boolean;
    /** The new version that is available */
    version: string;
}

/**
 * A top level folder that was selected by the user for watching.
 *
 * The user can set up multiple such watches. Each of these can in turn be
 * syncing multiple on disk folders to one or more Ente collections (depending
 * on the value of {@link collectionMapping}).
 *
 * This type is passed across the IPC boundary. It is persisted on the Node.js
 * side.
 */
export interface FolderWatch {
    /**
     * Specify if nested files should all be mapped to the same single root
     * collection, or if there should be a collection per directory that has
     * files. @see {@link CollectionMapping}.
     */
    collectionMapping: CollectionMapping;
    /**
     * The path to the (root) folder we are watching.
     */
    folderPath: string;
    /**
     * Files that have already been uploaded.
     */
    syncedFiles: FolderWatchSyncedFile[];
    /**
     * Files (paths) that should be ignored when uploading.
     */
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

/**
 * The ways in which directories are mapped to collection.
 *
 * This comes into play when we have nested directories that we are trying to
 * upload or watch on the user's local file system.
 */
export type CollectionMapping =
    /** All files go into a single collection named after the root directory. */
    | "root"
    /** Each file goes to a collection named after its parent directory. */
    | "parent";

/**
 * An on-disk file that was synced as part of a folder watch.
 */
export interface FolderWatchSyncedFile {
    path: string;
    uploadedFileID: number;
    collectionID: number;
}

/**
 * A particular file within a zip file.
 *
 * When the user uploads a zip file, we create a "zip item" for each entry
 * within the zip file. Each such entry is a tuple containing the (path to a zip
 * file itself, and the name of an entry within it).
 *
 * The name of the entry is not just the file name, but rather is the full path
 * of the file within the zip. That is, each entry name uniquely identifies a
 * particular file within the given zip.
 *
 * When `entryName` is a path within a nested directory, it is guaranteed to use
 * the POSIX path separator ("/") since that is the path separator required by
 * the ZIP format itself
 *
 * > 4.4.17.1 The name of the file, with optional relative path.
 * >
 * >  The path stored MUST NOT contain a drive or  device letter, or a leading
 * >  slash. All slashes MUST be forward slashes '/' as opposed to  backwards
 * >  slashes '\' for compatibility with Amiga and UNIX file systems etc. If
 * >  input came from standard input, there is no file name field.
 * >
 * > https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
 */
export type ZipItem = [zipPath: string, entryName: string];

export interface PreUploadSkippedFile {
    name: string;
    type: "hiddenFile" | "failedZip";
}

/**
 * State about pending and in-progress uploads.
 *
 * When the user starts an upload, we remember the files they'd selected (or
 * drag-dropped) so that we can resume if they restart the app in before the
 * uploads have been completed. This state is kept on the Electron side, and
 * this object is the IPC intermediary.
 */
export interface PendingUploads {
    /**
     * The collection to which we're uploading, or the root collection.
     *
     * This is name of the collection (when uploading to a singular collection)
     * or the root collection (when uploading to separate * albums) to which we
     * these uploads are meant to go to. See {@link CollectionMapping}.
     *
     * It will not be set if we're just uploading standalone files.
     */
    collectionName?: string;
    /**
     * Paths of regular files that need to be uploaded.
     */
    filePaths: string[];
    /**
     * {@link ZipItem} (zip path and entry name) that need to be uploaded.
     */
    zipItems: ZipItem[];
    /**
     * Files that were skipped because either we could not open them (zip files)
     * or they are hidden dot files.
     */
    preUploadSkippedFiles?: PreUploadSkippedFile[];
    /** Whether Takeout-favorited uploads should be added to Favorites. */
    importTakeoutFavorites?: boolean;
    /** Whether media originating from Google Photos partner sharing is uploaded. */
    includePartnerSharedFiles?: boolean;
}

/**
 * A command that we can ask FFmpeg to run for us.
 *
 * [Note: Alternative FFmpeg command for HDR videos]
 *
 * Usually, this is a single command (specified as an array of strings
 * containing the "words" of the command). However, we can also provide two
 * alternative commands - one to run when the input is (heuristically) detected
 * as a HDR video, and one otherwise.
 */
export type FFmpegCommand = string[] | { default: string[]; hdr: string[] };
