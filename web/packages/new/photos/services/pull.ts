import log from "ente-base/log";
import { resetFileViewerDataSourceOnClose } from "ente-gallery/components/viewer/data-source";
import {
    videoProcessingSyncIfNeeded,
    videoPrunePermanentlyDeletedFileIDsIfNeeded,
} from "ente-gallery/services/video";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    movePendingRemovalActionsToUncategorized,
    pullCollectionFiles,
    pullCollections,
} from "./collection";
import { isMLSupported, mlSync, pullMLStatus } from "./ml";
import { searchDataSync } from "./search";
import { pullSettings } from "./settings";
import { pullTrash, type TrashItem } from "./trash";

/**
 * Called during a full remote pull, before doing the files pull.
 *
 * [Note: Remote pull]
 *
 * There are two types of remote pulls we perform:
 *
 * - A "files" pull: Updating our local state with the latest collections,
 *   collection files, and trash from remote.
 *
 * - A "full" pull, which includes the files pull, and more.
 *
 * The full pull is performed by the gallery page, in the following sequence:
 *
 * 1. {@link prePullFiles}
 * 2. {@link pullFiles}
 * 3. {@link postPullFiles}.
 *
 * The full pull is performed in the following cases:
 *
 * - On the gallery page load (for both web and desktop).
 * - Every 5 minutes thereafter (while the user is on the gallery page).
 * - Each time the desktop app gains focus.
 * - When the file viewer is closed after performing some operation.
 *
 * In some other cases, where we know that only specific collection or file
 * state needs to be pulled, step 2 ({@link pullFiles}) is performed
 * independently. For example, after deduping files, or updating the metadata of
 * a file. See also: [Note: Full remote pull vs files pull]
 */
export const prePullFiles = async () => {
    await Promise.all([pullSettings(), isMLSupported && pullMLStatus()]);
};

interface PullFilesOpts {
    /**
     * Called when the saved collections were replaced by the given
     * {@link collections}.
     *
     * Can be called multiple times during a pull, as each batch of changes is
     * received and processed.
     */
    onSetCollections: (collections: Collection[]) => void;
    /**
     * Called when saved collection files were replaced by the given
     * {@link collectionFiles}.
     *
     * Can be called multiple times during a pull, as each batch of changes is
     * received and processed.
     */
    onSetCollectionFiles: (collectionFiles: EnteFile[]) => void;
    /**
     * Called when saved trashed items were replaced by the given
     * {@link trashItems}.
     *
     * Can be called multiple times during a pull, as each batch of changes is
     * received and processed.
     */
    onSetTrashedItems: (trashItems: TrashItem[]) => void;
    /**
     * Called if one or more files were updated during the pull.
     *
     * Will be called at most once per pull.
     */
    onDidUpdateCollectionFiles: () => void;
}

/**
 * Pull the latest collections, collections files and trash items from remote,
 * updating our local database and also calling the provided callbacks.
 *
 * This is a subset of a full remote pull, independently exposed for use at
 * times when we only want to pull the file related information (e.g. we just
 * made some API request that modified collections or files, and so now want to
 * update our local changes to match remote).
 *
 * See also: [Note: Remote pull]
 *
 * It is not robust to have multiple of these executing in parallel, and caller
 * should have some mechanism to serialize invocations.
 *
 * @param opts various callbacks that are used by gallery to update its local
 * state in tandem with the pull. The callbacks are optional since we might not
 * have local state to update, as is the case when this is invoked post dedup.
 */
export const pullFiles = async (opts?: PullFilesOpts) => {
    const collections = await pullCollections();
    opts?.onSetCollections(collections);
    const didUpdateFiles = await pullCollectionFiles(
        collections,
        opts?.onSetCollectionFiles,
    );
    await pullTrash(
        collections,
        opts?.onSetTrashedItems,
        videoPrunePermanentlyDeletedFileIDsIfNeeded,
    );
    // After trash sync, fetch pending removal actions and move affected files
    // to the uncategorized collection.
    // Wrapped in try-catch since self-hosted servers may not have this endpoint.
    try {
        await movePendingRemovalActionsToUncategorized(collections);
    } catch (e) {
        log.warn("Failed to process pending removal actions", e);
    }
    if (didUpdateFiles) {
        // TODO: Ok for now since its is only commented for the deduper (gallery
        // does this by providing onDidUpdateCollectionFiles), but still needs
        // fixing instead of a hidden gotcha. Fix is simple, just uncomment, but
        // that can be done once the exportService can be imported here in the
        // ente-new package.
        //
        // exportService.onLocalFilesUpdated();
        opts?.onDidUpdateCollectionFiles();
        resetFileViewerDataSourceOnClose();
    }
};

/**
 * Called during a full remote pull, after doing the files pull.
 *
 * See: [Note: Remote pull]
 */
export const postPullFiles = async (source?: string) => {
    await Promise.all([searchDataSync(), videoProcessingSyncIfNeeded()]);
    // ML sync might take a very long time for initial indexing, so don't wait
    // for it to finish.
    void mlSync(source ? `remote-pull:${source}` : "remote-pull");
};
