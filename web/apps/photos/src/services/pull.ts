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
} from "ente-new/photos/services/collection";
import {
    isMLSupported,
    mlSync,
    pullMLStatus,
} from "ente-new/photos/services/ml";
import { searchDataSync } from "ente-new/photos/services/search";
import { pullSettings } from "ente-new/photos/services/settings";
import { pullTrash, type TrashItem } from "ente-new/photos/services/trash";
import { ensureAuthenticatedSession } from "./authenticated-session";

export const prePullFiles = async () => {
    await Promise.all([pullSettings(), isMLSupported && pullMLStatus()]);
};

interface PullFilesOpts {
    onSetCollections: (collections: Collection[]) => void;
    onSetCollectionFiles: (collectionFiles: EnteFile[]) => void;
    onSetTrashedItems: (trashItems: TrashItem[]) => void;
    onDidUpdateCollectionFiles: () => void;
}

// Do not run pullFiles concurrently.
export const pullFiles = async (opts?: PullFilesOpts) => {
    await ensureAuthenticatedSession();
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
    // Older self-hosted servers may not expose pending removal actions.
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

export const postPullFiles = async (source?: string) => {
    await Promise.all([searchDataSync(), videoProcessingSyncIfNeeded()]);
    // Initial indexing can be long; do not block the remote pull.
    void mlSync(source ? `remote-pull:${source}` : "remote-pull");
};
