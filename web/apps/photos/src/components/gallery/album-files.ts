import { uniqueFilesByID } from "ente-gallery/utils/file";
import type { Collection } from "ente-media/collection";
import { sortCollectionFiles } from "ente-media/collection-sort";
import type { EnteFile } from "ente-media/file";
import { isArchivedFile } from "ente-media/file-metadata";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { suppressSharedFilesSavedByUser } from "./media-files";
import type { GalleryState } from "./reducer";
import type { GalleryView } from "./view-types";
export const deriveAlbumsOrHiddenAlbumsFilteredFiles = (
    trashItems: GalleryState["trashItems"],
    collectionFiles: GalleryState["collectionFiles"],
    defaultHiddenCollectionIDs: GalleryState["defaultHiddenCollectionIDs"],
    hiddenFileIDs: GalleryState["hiddenFileIDs"],
    archivedCollectionIDs: GalleryState["archivedCollectionIDs"],
    archivedFileIDs: GalleryState["archivedFileIDs"],
    tempDeletedFileIDs: GalleryState["tempDeletedFileIDs"],
    tempHiddenFileIDs: GalleryState["tempHiddenFileIDs"],
    view: Extract<
        GalleryView,
        { type: "albums" | "hidden-albums" | "archive-albums" }
    >,
    currentUserID: number | undefined,
) => {
    const activeCollectionSummaryID = view.activeCollectionSummaryID;

    if (activeCollectionSummaryID == PseudoCollectionID.trash) {
        return uniqueFilesByID([
            ...trashItems.map(({ file, deleteBy }) => ({ ...file, deleteBy })),
            ...collectionFiles.filter((file) =>
                tempDeletedFileIDs.has(file.id),
            ),
        ]);
    }

    const filteredFiles = collectionFiles.filter((file) => {
        if (tempDeletedFileIDs.has(file.id)) return false;

        if (
            activeCollectionSummaryID == PseudoCollectionID.hiddenItems &&
            defaultHiddenCollectionIDs.has(file.collectionID)
        ) {
            return true;
        }

        // A file can be individually archived and belong to an archived album.
        if (isArchivedFile(file)) {
            return (
                (activeCollectionSummaryID == PseudoCollectionID.archiveItems &&
                    !hiddenFileIDs.has(file.id) &&
                    !tempHiddenFileIDs.has(file.id)) ||
                activeCollectionSummaryID == file.collectionID
            );
        }

        if (archivedCollectionIDs.has(file.collectionID)) {
            return activeCollectionSummaryID === file.collectionID;
        }

        if (activeCollectionSummaryID === PseudoCollectionID.all) {
            if (hiddenFileIDs.has(file.id)) return false;
            if (tempHiddenFileIDs.has(file.id)) return false;

            if (archivedFileIDs.has(file.id)) {
                return false;
            }

            return true;
        }

        return activeCollectionSummaryID == file.collectionID;
    });

    return sortAndUniqueFilteredFiles(
        filteredFiles,
        view.activeCollection,
        currentUserID,
    );
};
export const sortAndUniqueFilteredFiles = (
    files: EnteFile[],
    activeCollection: Collection | undefined,
    currentUserID: number | undefined,
) => {
    const uniqueFiles = uniqueFilesByID(
        suppressSharedFilesSavedByUser(files, currentUserID, activeCollection),
    );
    const metadata = activeCollection?.pubMagicMetadata?.data;
    // The synced library is already in newest-first order.
    return metadata?.asc || metadata?.sortBy === "fileName"
        ? sortCollectionFiles(uniqueFiles, metadata)
        : uniqueFiles;
};
