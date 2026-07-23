/**
 * @file code that really belongs to pages/gallery.tsx itself, but it written
 * here in a separate file so that we can write in this package that has
 * TypeScript strict mode enabled.
 *
 * Once the original gallery.tsx is strict mode, this code can be inlined back
 * there.
 *
 * Separate from index.tsx so that it can export non-(React-)components, which
 * is a needed for fast refresh to work.
 */

import { getUserRecoveryKey } from "ente-accounts/services/recovery-key";
import log from "ente-base/log";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import type { CollectionOp } from "ente-new/photos/components/SelectedFileOptions";
import {
    addOrCopyToCollection,
    moveFromCollection,
    moveToCollection,
    restoreToCollection,
} from "ente-new/photos/services/collection";
import { createUncategorizedCollection } from "../../services/collection";
import { PseudoCollectionID } from "../../services/collection-summary";

/**
 * Ensure that the keys in local storage are not malformed by verifying that the
 * recoveryKey can be decrypted with the masterKey.
 *
 * This is not meant to be bullet proof, but more like an extra sanity check.
 *
 * @returns `true` if the sanity check passed, otherwise `false`. Since failure
 * is not expected, the caller should {@link logout} on `false` to avoid
 * continuing with an unexpected local state.
 */
export const validateKey = async () => {
    try {
        await getUserRecoveryKey();
        return true;
    } catch (e) {
        log.warn("Failed to validate key" /*, caller will logout */, e);
        return false;
    }
};

/**
 * Return the {@link Collection} (from amongst {@link collections}) with the
 * given {@link collectionSummaryID}.
 *
 * As a special case, if the given {@link collectionSummaryID} is the ID of the
 * placeholder uncategorized collection, create a new uncategorized collection
 * and then return it.
 *
 * This is used in the context of the collection summary, so one of the two
 * cases must be true.
 */
export const findCollectionCreatingUncategorizedIfNeeded = async (
    collections: Collection[],
    collectionSummaryID: number,
): Promise<Collection> =>
    collectionSummaryID == PseudoCollectionID.uncategorizedPlaceholder
        ? createUncategorizedCollection()
        : // Null assert since the collection selector should only
          // show "selectable" normalCollectionSummaries.
          //
          // See: [Note: Picking from selectable collection summaries].
          collections.find(({ id }) => id == collectionSummaryID)!;

/**
 * Perform a "collection operation" on the selected file(s).
 *
 * @param op The {@link CollectionOp} to perform, e.g. "add", "restore".
 *
 * @param selectedCollection The existing or new collection selected by the
 * user. This serves as the target of the operation.
 *
 * @param selectedFiles The files selected by the user, on which the operation
 * should be performed.
 *
 * @param sourceCollectionID In the case of a "move", the operation is always
 * expected to happen in the context of an existing collection, which serves as
 * the source collection for the move. In such a case, the caller should provide
 * this argument, using the collection ID of the collection in which the
 * selection occurred.
 *
 * [Note: Add and move of non-user files]
 *
 * Adds can now operate on both owned and non-owned files using the same parity
 * semantics as mobile:
 *
 * - current-user-owned files are added directly,
 * - other-owned files reuse a same-hash owned file when available,
 * - otherwise they are copied directly or via uncategorized depending on the
 *   destination ownership.
 *
 * Move semantics remain owner-only. Remote does not support cross-ownership
 * moves, and mobile also models shared-album contributor flows as adds, not
 * moves.
 */
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
            await moveFromCollection(
                sourceCollectionID!,
                selectedCollection,
                selectedFiles,
            );
            break;
        case "restore":
            await restoreToCollection(selectedCollection, selectedFiles);
            break;
        case "unhide":
            await moveToCollection(selectedCollection, selectedFiles);
            break;
    }
};
