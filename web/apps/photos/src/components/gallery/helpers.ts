// TODO: Move this code back into gallery.tsx.
// Kept outside index.tsx so Fast Refresh allows non-component exports.

import type { CollectionOp } from "@/components/SelectedFileOptions";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    addOrCopyToCollection,
    createUncategorizedCollection,
    getOrCreateDefaultHiddenCollection,
    moveFromCollection,
    moveToCollection,
    restoreToCollection,
} from "ente-new/photos/services/collection";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";

export const findCollectionCreatingIfNeeded = async (
    collections: Collection[],
    collectionSummaryID: number,
): Promise<Collection> =>
    collectionSummaryID == PseudoCollectionID.uncategorizedPlaceholder
        ? createUncategorizedCollection()
        : collectionSummaryID == PseudoCollectionID.hiddenItems
          ? getOrCreateDefaultHiddenCollection()
          : // The selector only exposes summaries backed by collections.
            collections.find(({ id }) => id == collectionSummaryID)!;

// Adds may copy non-owned files or reuse an owned file with the same hash.
// Moves remain owner-only; shared contributor flows are adds.
export const performCollectionOp = async (
    op: CollectionOp,
    selectedCollection: Collection,
    selectedFiles: EnteFile[],
    sourceCollectionID: number | undefined,
): Promise<void> => {
    switch (op) {
        case "add":
            await addOrCopyToCollection(selectedCollection, selectedFiles);
            break;
        case "move":
            if (sourceCollectionID == PseudoCollectionID.hiddenItems) {
                await moveToCollection(selectedCollection, selectedFiles);
            } else {
                await moveFromCollection(
                    sourceCollectionID!,
                    selectedCollection,
                    selectedFiles,
                );
            }
            break;
        case "restore":
            await restoreToCollection(selectedCollection, selectedFiles);
            break;
        case "unhide":
            await moveToCollection(selectedCollection, selectedFiles);
            break;
    }
};
