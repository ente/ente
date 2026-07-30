/**
 * @file Interface with the Node.js layer of our desktop app to provide the
 * watch folders functionality.
 */

import debounce from "debounce";
import { ensureElectron } from "ente-base/electron";
import { basename, dirname, lowercaseExtension } from "ente-base/file-name";
import log from "ente-base/log";
import type {
    CollectionMapping,
    FolderWatch,
    FolderWatchSyncedFile,
} from "ente-base/types/ipc";
import type { UploadResult } from "ente-gallery/services/upload";
import type { UploadAsset } from "ente-gallery/services/upload/upload-service";
import { groupFilesByCollectionID } from "ente-gallery/utils/file";
import type { EnteFile } from "ente-media/file";
import { removeFromOwnCollection } from "ente-new/photos/services/collection";
import { computeAllCollectionFilesFromSaved } from "ente-new/photos/services/file";
import { ensureString } from "ente-utils/ensure";
import { type UploadItemWithCollection, uploadManager } from "./upload-manager";

/**
 * Watch for file system folders and automatically update the corresponding Ente
 * collections.
 *
 * This class relies on APIs exposed over the Electron IPC layer, and thus only
 * works when we're running inside our desktop app.
 */
class FolderWatcher {
    /** Pending file system events that we need to process. */
    private eventQueue: WatchEvent[] = [];
    /** The folder watch whose event we're currently processing */
    private activeWatch: FolderWatch | undefined;
    /**
     * If the file system directory corresponding to the (root) folder path of a
     * folder watch is deleted on disk, we note down that in this queue so that
     * we can ignore any file system events that come for it next.
     */
    private deletedFolderPaths: string[] = [];
    /**
     * A set of folder paths that were inaccessible in the last accessibility
     * check. Used to detect when a folder transitions from inaccessible to
     * accessible (e.g., when an external drive is reconnected).
     */
    private previouslyInaccessiblePaths = new Set<string>();
    /** `true` if we are using the uploader. */
    private uploadRunning = false;
    /** `true` if we are temporarily paused to let a user upload go through. */
    private isPaused = false;
    /**
     * A map from file paths to the (fileID, collectionID) of the file that was
     * uploaded (or symlinked) as part of the most recent upload attempt.
     */
    private uploadedFileForPath = new Map<string, EnteFile>();
    /**
     * A set of file paths that could not be uploaded in the most recent upload
     * attempt. These are the uploads that failed due to a permanent error that
     * a retry will not fix.
     */
    private unUploadableFilePaths = new Set<string>();

    /**
     * A function to call when we want to enqueue a new upload of the given list
     * of file paths to the given Ente collection.
     *
     * This is passed as a param to {@link init}.
     */
    private upload:
        | ((collectionName: string, filePaths: string[]) => void)
        | undefined;
    /**
     * A function to call when we want to trigger a full remote pull. It will
     * initiate the pull but will not await its completion.
     *
     * This is passed as a param to {@link init}.
     */
    private onTriggerRemotePull: (() => void) | undefined;

    /** A helper function that debounces invocations of {@link runNextEvent}. */
    private debouncedRunNextEvent: () => void;

    constructor() {
        // TODO:
        // eslint-disable-next-line @typescript-eslint/no-misused-promises
        this.debouncedRunNextEvent = debounce(() => this.runNextEvent(), 1000);
    }

    /**
     * Initialize the watcher and start processing file system events.
     *
     * This is only called when we're running in the context of our desktop app.
     *
     * The caller provides us with the hooks we can use to actually upload the
     * files, and to pull the latest changes from remote (say after deletion).
     */
    init(
        upload: (collectionName: string, filePaths: string[]) => void,
        onTriggerRemotePull: () => void,
    ) {
        this.upload = upload;
        this.onTriggerRemotePull = onTriggerRemotePull;
        this.registerListeners();
        this.initializeAccessibilityState();
        this.triggerSyncWithDisk();
    }

    /**
     * Initialize the accessibility tracking state by capturing which watches
     * are currently inaccessible. This allows subsequent checkAccessibility
     * calls to detect when a folder transitions from inaccessible to accessible.
     */
    private initializeAccessibilityState() {
        void this.getWatches().then((watches) => {
            for (const watch of watches) {
                if (watch.isAccessible === false) {
                    this.previouslyInaccessiblePaths.add(watch.folderPath);
                }
            }
            if (this.previouslyInaccessiblePaths.size > 0) {
                log.info(
                    `Folder watch: ${this.previouslyInaccessiblePaths.size} folder(s) currently inaccessible`,
                );
            }
        });
    }

    /** Return `true` if we are currently using the uploader. */
    isUploadRunning() {
        return this.uploadRunning;
    }

    /** Return `true` if syncing has been temporarily paused. */
    isSyncPaused() {
        return this.isPaused;
    }

    /**
     * Temporarily pause syncing and cancel any running uploads.
     *
     * This frees up the uploader for handling user initiated uploads.
     */
    pauseRunningSync() {
        this.isPaused = true;
        uploadManager.cancelRunningUpload();
    }

    /**
     * Resume from a temporary pause, resyncing from disk.
     *
     * Sibling of {@link pauseRunningSync}.
     */
    resumePausedSync() {
        this.isPaused = false;
        this.triggerSyncWithDisk();
    }

    /** Return the list of folders we are watching for changes. */
    async getWatches(): Promise<FolderWatch[]> {
        return await ensureElectron().watch.get();
    }

    /**
     * Check accessibility of all watch folders and trigger sync if any
     * previously inaccessible folder has become accessible.
     *
     * This is meant to be called when the app gains focus, allowing us to
     * detect when an external drive has been reconnected.
     */
    async checkAccessibility(): Promise<void> {
        try {
            const watches = await this.getWatches();

            // Determine which folders are currently inaccessible.
            const currentlyInaccessiblePaths = new Set<string>();
            for (const watch of watches) {
                if (watch.isAccessible === false) {
                    currentlyInaccessiblePaths.add(watch.folderPath);
                }
            }

            // Check if any previously inaccessible folder is now accessible.
            const newlyAccessiblePaths: string[] = [];
            for (const path of this.previouslyInaccessiblePaths) {
                if (!currentlyInaccessiblePaths.has(path)) {
                    // This folder was inaccessible before but is no longer in
                    // the inaccessible set. Check if the watch still exists.
                    const watchStillExists = watches.some(
                        (w) => w.folderPath === path,
                    );
                    if (watchStillExists) {
                        newlyAccessiblePaths.push(path);
                    }
                }
            }

            // Update our tracking of inaccessible paths for the next check.
            this.previouslyInaccessiblePaths = currentlyInaccessiblePaths;

            // Only trigger sync if at least one folder became accessible.
            if (newlyAccessiblePaths.length > 0 && !this.isPaused) {
                log.info(
                    `Folder watch: ${newlyAccessiblePaths.length} folder(s) became accessible (${newlyAccessiblePaths.join(", ")}), triggering sync`,
                );
                this.triggerSyncWithDisk();
            }
        } catch (e) {
            log.error("Error checking watch folder accessibility", e);
        }
    }

    /**
     * Return true if we are currently syncing files that belong to the given
     * {@link folderPath}.
     */
    isSyncingFolder(folderPath: string) {
        return this.activeWatch?.folderPath == folderPath;
    }

    /**
     * Add a new folder watch for the given root {@link folderPath}
     *
     * @param mapping The {@link CollectionMapping} to use to decide which
     * collection do files belonging to nested directories go to.
     *
     * @returns The updated list of watches.
     */
    async addWatch(folderPath: string, mapping: CollectionMapping) {
        const watches = await ensureElectron().watch.add(folderPath, mapping);
        this.triggerSyncWithDisk();
        return watches;
    }

    /**
     * Remove the folder watch for the given root {@link folderPath}.
     *
     * @returns The updated list of watches.
     */
    async removeWatch(folderPath: string) {
        return await ensureElectron().watch.remove(folderPath);
    }

    private triggerSyncWithDisk() {
        void this.syncWithDisk();
    }

    private async syncWithDisk() {
        try {
            const watches = await this.getWatches();

            this.eventQueue = [];
            const events = await deduceEvents(watches);
            log.info(`Folder watch deduced ${events.length} events`);
            this.eventQueue = this.eventQueue.concat(events);

            this.debouncedRunNextEvent();
        } catch (e) {
            log.error("Ignoring error while syncing watched folders", e);
        }
    }

    pushEvent(event: WatchEvent) {
        this.eventQueue.push(event);
        log.info("Folder watch event", event);
        this.debouncedRunNextEvent();
    }

    private registerListeners() {
        const watch = ensureElectron().watch;

        // [Note: File renames during folder watch]
        //
        // Renames come as two file system events - an `onAddFile` + an
        // `onRemoveFile` - in an arbitrary order.

        watch.onAddFile((path: string, watch: FolderWatch) => {
            this.pushEvent({
                action: "upload",
                collectionName: collectionNameForPath(path, watch),
                folderPath: watch.folderPath,
                filePath: path,
            });
        });

        watch.onRemoveFile((path: string, watch: FolderWatch) => {
            this.pushEvent({
                action: "trash",
                collectionName: collectionNameForPath(path, watch),
                folderPath: watch.folderPath,
                filePath: path,
            });
        });

        watch.onRemoveDir((path: string, watch: FolderWatch) => {
            if (path == watch.folderPath) {
                log.info(
                    `Received file system delete event for a watched folder at ${path}`,
                );
                this.deletedFolderPaths.push(path);
            }
        });
    }

    private async runNextEvent() {
        if (this.eventQueue.length == 0 || this.activeWatch || this.isPaused)
            return;

        const event = this.dequeueClubbedEvent();
        if (!event) return;
        log.info(
            `Processing ${event.action} event for folder watch ${event.folderPath} (collectionName ${event.collectionName}, ${event.filePaths.length} files)`,
        );

        const skip = (reason: string) => {
            log.info(`Ignoring event since ${reason}`);
            this.debouncedRunNextEvent();
        };

        const watch = (await this.getWatches()).find(
            (watch) => watch.folderPath == event.folderPath,
        );
        if (!watch) {
            // Possibly stale
            skip(`no folder watch for found for ${event.folderPath}`);
            return;
        }

        if (watch.isAccessible === false) {
            skip(`folder ${event.folderPath} is inaccessible`);
            return;
        }

        if (event.action == "upload") {
            const paths = pathsToUpload(event.filePaths, watch);
            if (paths.length == 0) {
                skip("none of the files need uploading");
                return;
            }

            // Here we pass control to the uploader. When the upload is done,
            // the uploader will notify us by calling allFileUploadsDone.

            this.activeWatch = watch;
            this.uploadRunning = true;

            const collectionName = event.collectionName;
            log.info(
                `Folder watch requested upload of ${paths.length} files to collection ${collectionName}`,
            );

            this.upload!(collectionName, paths);
        } else {
            if (this.pruneFileEventsFromDeletedFolderPaths()) {
                skip("event was from a deleted folder path");
                return;
            }

            const [removed, rest] = watch.syncedFiles.reduce(
                ([removed, rest], syncedFile) => {
                    (event.filePaths.includes(syncedFile.path)
                        ? removed
                        : rest
                    ).push(syncedFile);
                    return [removed, rest];
                },
                [new Array<FolderWatchSyncedFile>(), []],
            );

            this.activeWatch = watch;

            try {
                await this.moveToTrash(removed);
            } catch (e) {
                log.error(
                    "Failed to trash files from watch folder, clearing stale sync entries",
                    e,
                );
            }

            // Always update syncedFiles to remove stale entries, even if
            // trashing failed. Otherwise we'll keep retrying forever.
            await ensureElectron().watch.updateSyncedFiles(
                rest,
                watch.folderPath,
            );

            this.activeWatch = undefined;

            this.debouncedRunNextEvent();
        }
    }

    /**
     * Batch the next run of events with the same action, collection and folder
     * path into a single clubbed event that contains the list of all effected
     * file paths from the individual events.
     */
    private dequeueClubbedEvent(): ClubbedWatchEvent | undefined {
        const event = this.eventQueue.shift();
        if (!event) return undefined;

        const filePaths = [event.filePath];
        while (
            this.eventQueue.length > 0 &&
            event.action === this.eventQueue[0]?.action &&
            event.folderPath === this.eventQueue[0].folderPath &&
            event.collectionName === this.eventQueue[0].collectionName
        ) {
            filePaths.push(this.eventQueue[0].filePath);
            this.eventQueue.shift();
        }
        return { ...event, filePaths };
    }

    /**
     * Callback invoked by the uploader whenever a item we requested to
     * {@link upload} gets uploaded.
     */
    onFileUpload(item: UploadItemWithCollection, uploadResult: UploadResult) {
        // Re the usage of ensureString: For desktop watch, the only possibility
        // for a UploadItem is for it to be a string (the absolute path to a
        // file on disk).
        switch (uploadResult.type) {
            case "alreadyUploaded":
            case "addedSymlink":
            case "uploaded":
            case "uploadedWithStaticThumbnail":
                {
                    // Done.
                    if (item.isLivePhoto) {
                        this.uploadedFileForPath.set(
                            ensureString(item.livePhotoAssets?.image),
                            uploadResult.file,
                        );
                        this.uploadedFileForPath.set(
                            ensureString(item.livePhotoAssets?.video),
                            uploadResult.file,
                        );
                    } else {
                        this.uploadedFileForPath.set(
                            ensureString(item.uploadItem),
                            uploadResult.file,
                        );
                    }
                }
                break;
            case "partnerShared":
            case "unsupported":
            case "tooLarge":
                {
                    // Non-retriable error.
                    if (item.isLivePhoto) {
                        this.unUploadableFilePaths.add(
                            ensureString(item.livePhotoAssets?.image),
                        );
                        this.unUploadableFilePaths.add(
                            ensureString(item.livePhotoAssets?.video),
                        );
                    } else {
                        this.unUploadableFilePaths.add(
                            ensureString(item.uploadItem),
                        );
                    }
                }
                break;
        }
    }

    /**
     * Callback invoked by the uploader whenever all the files we requested to
     * {@link upload} get uploaded.
     */
    async allFileUploadsDone(uploadedItems: UploadAsset[]) {
        const electron = ensureElectron();
        const watch = this.activeWatch!;

        log.debug(() => [
            "watch/allFileUploadsDone",
            JSON.stringify({ uploadedItems, watch }),
        ]);

        const { syncedFiles, ignoredFiles } =
            this.deduceSyncedAndIgnored(uploadedItems);

        if (syncedFiles.length > 0)
            await electron.watch.updateSyncedFiles(
                watch.syncedFiles.concat(syncedFiles),
                watch.folderPath,
            );

        if (ignoredFiles.length > 0)
            await electron.watch.updateIgnoredFiles(
                watch.ignoredFiles.concat(ignoredFiles),
                watch.folderPath,
            );

        this.activeWatch = undefined;
        this.uploadRunning = false;

        this.debouncedRunNextEvent();
    }

    private deduceSyncedAndIgnored(uploadedItems: UploadAsset[]) {
        const syncedFiles: FolderWatch["syncedFiles"] = [];
        const ignoredFiles: FolderWatch["ignoredFiles"] = [];

        const markSynced = (file: EnteFile, path: string) => {
            syncedFiles.push({
                path,
                uploadedFileID: file.id,
                collectionID: file.collectionID,
            });
            this.uploadedFileForPath.delete(path);
        };

        const markIgnored = (path: string) => {
            log.debug(() => `Permanently ignoring file at ${path}`);
            ignoredFiles.push(path);
            this.unUploadableFilePaths.delete(path);
        };

        for (const item of uploadedItems) {
            // Re the usage of ensureString: For desktop watch, the only
            // possibility for a UploadItem is for it to be a string (the
            // absolute path to a file on disk).
            if (item.isLivePhoto) {
                const imagePath = ensureString(item.livePhotoAssets?.image);
                const videoPath = ensureString(item.livePhotoAssets?.video);

                const imageFile = this.uploadedFileForPath.get(imagePath);
                const videoFile = this.uploadedFileForPath.get(videoPath);

                if (imageFile && videoFile) {
                    markSynced(imageFile, imagePath);
                    markSynced(videoFile, videoPath);
                } else if (
                    this.unUploadableFilePaths.has(imagePath) &&
                    this.unUploadableFilePaths.has(videoPath)
                ) {
                    markIgnored(imagePath);
                    markIgnored(videoPath);
                }
            } else {
                const path = ensureString(item.uploadItem);
                const file = this.uploadedFileForPath.get(path);
                if (file) {
                    markSynced(file, path);
                } else if (this.unUploadableFilePaths.has(path)) {
                    markIgnored(path);
                }
            }
        }

        return { syncedFiles, ignoredFiles };
    }

    private pruneFileEventsFromDeletedFolderPaths() {
        const deletedFolderPath = this.deletedFolderPaths.shift();
        if (!deletedFolderPath) return false;

        this.eventQueue = this.eventQueue.filter(
            (event) => !event.filePath.startsWith(deletedFolderPath),
        );

        return true;
    }

    private async moveToTrash(syncedFiles: FolderWatch["syncedFiles"]) {
        const syncedFileForID = new Map<number, FolderWatchSyncedFile>();
        for (const file of syncedFiles)
            syncedFileForID.set(file.uploadedFileID, file);

        // Use all collection files (including hidden) so that files removed
        // from the watch folder are also removed from hidden albums.
        const files = await computeAllCollectionFilesFromSaved();
        const filesToTrash = files.filter((file) => {
            const correspondingSyncedFile = syncedFileForID.get(file.id);
            if (correspondingSyncedFile?.collectionID == file.collectionID) {
                return true;
            }
            return false;
        });

        const filesByCollectionID = groupFilesByCollectionID(filesToTrash);
        for (const [id, files] of filesByCollectionID.entries()) {
            await removeFromOwnCollection(id, files);
        }

        this.onTriggerRemotePull!();
    }
}

/** The singleton instance of {@link FolderWatcher}. */
const watcher = new FolderWatcher();

export default watcher;

/**
 * A file system watch event encapsulates a change that has occurred on disk
 * that needs us to take some action within Ente to synchronize with the user's
 * Ente collections.
 *
 * Events get added in two ways:
 *
 * - When the app starts, it reads the current state of files on disk and
 *   compares that with its last known state to determine what all events it
 *   missed. This is easier than it sounds as we have only two events: add and
 *   remove.
 *
 * - When the app is running, it gets live notifications from our file system
 *   watcher (from the Node.js layer) about changes that have happened on disk,
 *   which the app then enqueues onto the event queue if they pertain to the
 *   files we're interested in.
 */
interface WatchEvent {
    /** The action to take */
    action: "upload" | "trash";
    /** The path of the root folder corresponding to the {@link FolderWatch}. */
    folderPath: string;
    /** The name of the Ente collection the file belongs to. */
    collectionName: string;
    /** The absolute path to the file under consideration. */
    filePath: string;
}

/**
 * A composite of multiple {@link WatchEvent}s that only differ in their
 * {@link filePath}.
 *
 * When processing events, we combine a run of events with the same
 * {@link action}, {@link folderPath} and {@link collectionName}. This allows us
 * to process all the affected {@link filePaths} in one shot.
 */
type ClubbedWatchEvent = Omit<WatchEvent, "filePath"> & { filePaths: string[] };

/**
 * Determine which events we need to process to synchronize the watched on-disk
 * folders to their corresponding collections.
 */
const deduceEvents = async (watches: FolderWatch[]): Promise<WatchEvent[]> => {
    const electron = ensureElectron();
    const events: WatchEvent[] = [];

    for (const watch of watches) {
        // Skip inaccessible folders (e.g., ejected external drives).
        if (watch.isAccessible === false) {
            log.info(
                `Skipping sync for inaccessible folder ${watch.folderPath}`,
            );
            continue;
        }

        const folderPath = watch.folderPath;

        const filePaths = await electron.fs.findFiles(folderPath);

        // Files that are on disk but not yet synced.
        for (const filePath of pathsToUpload(filePaths, watch))
            events.push({
                action: "upload",
                folderPath,
                collectionName: collectionNameForPath(filePath, watch),
                filePath,
            });

        // Previously synced files that are no longer on disk.
        for (const filePath of pathsToRemove(filePaths, watch))
            events.push({
                action: "trash",
                folderPath,
                collectionName: collectionNameForPath(filePath, watch),
                filePath,
            });
    }

    return events;
};

/**
 * Filter out hidden files, non-media files, and previously synced or ignored
 * paths from {@link paths} to get the list of paths that need to be uploaded
 * to the Ente collection.
 */
const pathsToUpload = (paths: string[], watch: FolderWatch) =>
    paths
        // Filter out files whose names begins with a dot.
        .filter((path) => !basename(path).startsWith("."))
        // Filter out known non-media files.
        .filter((path) => !shouldIgnoreForUpload(path))
        // Files that are on disk but not yet synced or ignored.
        .filter((path) => !isSyncedOrIgnoredPath(path, watch));

/**
 * Return the paths to previously synced files that are no longer on disk and so
 * must be removed from the Ente collection.
 */
const pathsToRemove = (paths: string[], watch: FolderWatch) =>
    watch.syncedFiles
        .map((f) => f.path)
        .filter((path) => !paths.includes(path));

const isSyncedOrIgnoredPath = (path: string, watch: FolderWatch) =>
    watch.ignoredFiles.includes(path) ||
    watch.syncedFiles.find((f) => f.path === path);

const collectionNameForPath = (path: string, watch: FolderWatch) =>
    watch.collectionMapping == "root"
        ? basename(watch.folderPath)
        : parentDirectoryName(path);

const parentDirectoryName = (path: string) => basename(dirname(path));

/**
 * Extensions of files that should not be uploaded from watch folders.
 *
 * These are common non-media file types that might be present in directories
 * containing photos and videos, but are not themselves media files.
 */
const ignoredExtensions = new Set([
    "zip",
    "rar",
    "7z",
    "tar",
    "gz",
    "bz2",
    "txt",
    "ini",
    "sfv",
    "md5",
    "sha1",
    "sha256",
    "sha512",
    "sha",
    "html",
    "htm",
    "xmp",
    "db",
]);

/**
 * Return `true` if the file at the given path should be ignored for uploads.
 *
 * This is used to filter out known non-media files from watch folders before
 * attempting to upload them. This prevents spurious "Skipped" messages and
 * error logs for files that we know beforehand are not photos or videos.
 */
const shouldIgnoreForUpload = (path: string): boolean => {
    const extension = lowercaseExtension(path);
    return extension !== undefined && ignoredExtensions.has(extension);
};
