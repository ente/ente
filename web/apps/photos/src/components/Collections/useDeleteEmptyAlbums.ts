import type { RemotePullOpts } from "@/components/gallery";
import { ensureLocalUser } from "ente-accounts/services/user";
import { useBaseContext } from "ente-base/context";
import {
    deleteCollection,
    isArchivedCollection,
    isDefaultHiddenCollection,
} from "ente-new/photos/services/collection";
import {
    isBulkDeletableEmptyAlbum,
    type CollectionSummary,
} from "ente-new/photos/services/collection-summary";
import {
    savedCollectionFiles,
    savedCollections,
} from "ente-new/photos/services/photos-fdb";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import { trashFilesDialogAttributes } from "../utils/dialog-attributes";

export const useDeleteEmptyAlbums = (
    collectionSummaries: CollectionSummary[],
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>,
) => {
    const { showMiniDialog } = useBaseContext();
    const { showNotification } = usePhotosAppContext();
    const emptyAlbumCandidates = collectionSummaries.filter(
        isBulkDeletableEmptyAlbum,
    );

    const deleteEmptyAlbums = async (candidateIDs: number[]) => {
        let failedCount = 0;
        let confirmedCandidateIDs: number[];

        try {
            await onRemotePull({ strict: true });

            const [collections, collectionFiles] = await Promise.all([
                savedCollections(),
                savedCollectionFiles(),
            ]);
            const candidateIDSet = new Set(candidateIDs);
            const nonEmptyCollectionIDs = new Set(
                collectionFiles.map((file) => file.collectionID),
            );
            const userID = ensureLocalUser().id;
            confirmedCandidateIDs = collections
                .filter(
                    (collection) =>
                        candidateIDSet.has(collection.id) &&
                        !nonEmptyCollectionIDs.has(collection.id) &&
                        (collection.type == "album" ||
                            collection.type == "folder") &&
                        collection.owner.id == userID &&
                        !collection.sharees.length &&
                        !collection.publicURLs.length &&
                        !isArchivedCollection(collection) &&
                        !isDefaultHiddenCollection(collection),
                )
                .map((collection) => collection.id);
        } catch {
            showNotification({
                color: "critical",
                title: t("delete_empty_albums_failed", {
                    count: candidateIDs.length,
                }),
            });
            return;
        }

        if (!confirmedCandidateIDs.length) return;

        for (const id of confirmedCandidateIDs) {
            try {
                await deleteCollection(id, { keepFiles: true });
            } catch {
                failedCount++;
            }
        }

        let refreshFailed = false;
        try {
            await onRemotePull({ strict: true });
        } catch {
            refreshFailed = true;
        }

        if (failedCount > 0) {
            showNotification({
                color: "critical",
                title: t("delete_empty_albums_failed", { count: failedCount }),
            });
        } else if (refreshFailed) {
            showNotification({
                color: "critical",
                title: t("delete_empty_albums_refresh_failed"),
            });
        }
    };

    const handleDeleteEmptyAlbums = () => {
        const candidateIDs = emptyAlbumCandidates.map((cs) => cs.id);
        const attributes = trashFilesDialogAttributes(candidateIDs.length, () =>
            deleteEmptyAlbums(candidateIDs),
        );
        showMiniDialog({
            ...attributes,
            title: t("delete_empty_albums_title"),
            kind: "info",
            message: t("delete_empty_albums_message", {
                count: candidateIDs.length,
            }),
            continue: { ...attributes.continue, text: t("delete") },
        });
    };

    return {
        handleDeleteEmptyAlbums,
        hasEnoughEmptyAlbums: emptyAlbumCandidates.length >= 3,
    };
};
