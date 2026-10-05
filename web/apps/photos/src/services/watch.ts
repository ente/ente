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

class FolderWatcher {
    private eventQueue: WatchEvent[] = [];
    private activeWatch: FolderWatch | undefined;
    // A root deletion can be followed by stale child events.
    private deletedFolderPaths: string[] = [];
    private previouslyInaccessiblePaths = new Set<string>();
    private uploadRunning = false;
    private isPaused = false;
    private uploadedFileForPath = new Map<string, EnteFile>();
    private unUploadableFilePaths = new Set<string>();

    private upload:
        | ((collectionName: string, filePaths: string[]) => void)
        | undefined;
    private onTriggerRemotePull: (() => void) | undefined;
    private isUploadInProgress: (() => boolean) | undefined;

    private debouncedRunNextEvent: () => void;

    constructor() {
        // eslint-disable-next-line @typescript-eslint/no-misused-promises
        this.debouncedRunNextEvent = debounce(() => this.runNextEvent(), 1000);
    }

    init(
        upload: (collectionName: string, filePaths: string[]) => void,
        onTriggerRemotePull: () => void,
        isUploadInProgress: () => boolean,
    ) {
        this.upload = upload;
        this.onTriggerRemotePull = onTriggerRemotePull;
        this.isUploadInProgress = isUploadInProgress;
        this.registerListeners();
        this.initializeAccessibilityState();
        this.triggerSyncWithDisk();
    }

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

    isUploadRunning() {
        return this.uploadRunning;
    }

    isSyncPaused() {
        return this.isPaused;
    }

    pauseRunningSync() {
        // User uploads share this uploader with folder watch.
        this.isPaused = true;
        uploadManager.cancelRunningUpload();
    }

    resumePausedSync() {
        this.isPaused = false;
        this.triggerSyncWithDisk();
    }

    async getWatches(): Promise<FolderWatch[]> {
        return await ensureElectron().watch.get();
    }

    async checkAccessibility(): Promise<void> {
        try {
            const watches = await this.getWatches();

            const currentlyInaccessiblePaths = new Set<string>();
            for (const watch of watches) {
                if (watch.isAccessible === false) {
                    currentlyInaccessiblePaths.add(watch.folderPath);
                }
            }

            const newlyAccessiblePaths: string[] = [];
            for (const path of this.previouslyInaccessiblePaths) {
                if (!currentlyInaccessiblePaths.has(path)) {
                    const watchStillExists = watches.some(
                        (w) => w.folderPath === path,
                    );
                    if (watchStillExists) {
                        newlyAccessiblePaths.push(path);
                    }
                }
            }

            this.previouslyInaccessiblePaths = currentlyInaccessiblePaths;

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

    isSyncingFolder(folderPath: string) {
        return this.activeWatch?.folderPath == folderPath;
    }

    async addWatch(folderPath: string, mapping: CollectionMapping) {
        const watches = await ensureElectron().watch.add(folderPath, mapping);
        this.triggerSyncWithDisk();
        return watches;
    }

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

        // Renames arrive as add and remove events in either order.
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

        // Uploads share one uploader, so wait for the current one to finish.
        if (
            this.eventQueue[0]?.action == "upload" &&
            this.isUploadInProgress!()
        ) {
            this.debouncedRunNextEvent();
            return;
        }

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

    onFileUpload(item: UploadItemWithCollection, uploadResult: UploadResult) {
        // Watch uploads use absolute path strings despite UploadItem's wider type.
        switch (uploadResult.type) {
            case "alreadyUploaded":
            case "addedSymlink":
            case "uploaded":
            case "uploadedWithStaticThumbnail":
                {
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

        // Include hidden copies when removing files deleted from disk.
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

const watcher = new FolderWatcher();

export default watcher;

interface WatchEvent {
    action: "upload" | "trash";
    folderPath: string;
    collectionName: string;
    filePath: string;
}

type ClubbedWatchEvent = Omit<WatchEvent, "filePath"> & { filePaths: string[] };

const deduceEvents = async (watches: FolderWatch[]): Promise<WatchEvent[]> => {
    const electron = ensureElectron();
    const events: WatchEvent[] = [];

    for (const watch of watches) {
        // An ejected drive must not look like an empty folder.
        if (watch.isAccessible === false) {
            log.info(
                `Skipping sync for inaccessible folder ${watch.folderPath}`,
            );
            continue;
        }

        const folderPath = watch.folderPath;

        const filePaths = await electron.fs.findFiles(folderPath);

        for (const filePath of pathsToUpload(filePaths, watch))
            events.push({
                action: "upload",
                folderPath,
                collectionName: collectionNameForPath(filePath, watch),
                filePath,
            });

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

const pathsToUpload = (paths: string[], watch: FolderWatch) =>
    paths
        .filter((path) => !basename(path).startsWith("."))
        .filter((path) => !shouldIgnoreForUpload(path))
        .filter((path) => !isSyncedOrIgnoredPath(path, watch));

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
    "clpi",
    "mpls",
    "bdmv",
    "cmap",
]);

const shouldIgnoreForUpload = (path: string): boolean => {
    const extension = lowercaseExtension(path);
    return extension !== undefined && ignoredExtensions.has(extension);
};
