/**
 * @file Photos app specific files DB. See: [Note: Files DB].
 */

import {
    LocalCollections,
    LocalEnteFile,
    localForage,
    LocalTimestamp,
    transformFilesIfNeeded,
} from "ente-gallery/services/files-db";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { z } from "zod";
import type { TrashItem } from "./trash";

/**
 * Return all collections present in our local database.
 *
 * This includes both normal (non-hidden) and hidden collections.
 *
 * Use {@link saveCollections} to update the database.
 */
export const savedCollections = async (): Promise<Collection[]> =>
    LocalCollections.parse((await localForage.getItem("collections")) ?? []);

/**
 * Replace the list of collections stored in our local database.
 *
 * This is the setter corresponding to {@link savedCollections}.
 *
 * This updates the underlying storage of both normal (non-hidden) and hidden
 * collections (the split between normal and hidden is not at the database level
 * but is a filter when they are accessed).
 */
export const saveCollections = async (collections: Collection[]) => {
    await localForage.setItem("collections", collections);
};

/**
 * Return the locally persisted {@link updationTime} of the latest collection we
 * have pulled from remote.
 *
 * Use {@link saveCollectionsUpdationTime} to update the saved value.
 */
export const savedCollectionsUpdationTime = async () =>
    LocalTimestamp.parse(await localForage.getItem("collection-updation-time"));

/**
 * Update the locally persisted timestamp that will be returned by subsequent
 * calls to {@link savedCollectionsUpdationTime}.
 */
export const saveCollectionsUpdationTime = async (time: number) => {
    await localForage.setItem("collection-updation-time", time);
};

const TrashItemCollectionKey = z.object({
    /**
     * Collection ID.
     */
    id: z.number(),
    /**
     * Decrypted collection key.
     */
    key: z.string(),
});

const TrashItemCollectionKeys = TrashItemCollectionKey.array();

export type TrashItemCollectionKey = z.infer<typeof TrashItemCollectionKey>;

/**
 * Return keys of collections (including potentially deleted ones) referred to
 * by trash items present in our local database.
 *
 * Use {@link saveTrashItemCollectionKeys} to update the database.
 *
 * [Note: Trash item collection keys]
 *
 * Trash items are erstwhile files, and like collection files, they need a
 * collection key to decrypt them.
 *
 * However, it is possible that the collection which contained the file was also
 * deleted. Such deleted collections will not be present in the list returned by
 * {@link savedCollections}.
 *
 * So to still be able to access the collection keys in order to process the
 * trash item, we separately save a list of {collectionID, collectionKey} pairs.
 *
 * - This list contains only collectionsIDs for which there is a corresponding
 *   local trash item.
 *
 * - During each trash sync, this list is seeded using {@link savedCollections}.
 *   Then, whenever we encounter a collection which is not present locally
 *   (since it might've been deleted), we fetch it from remote and add an entry
 *   for it in {@link savedTrashItemCollectionKeys}.
 *
 * - Once the sync completes, we updated this list to retain only entries that
 *   are still referred to by items remaining in the trash.
 */
export const savedTrashItemCollectionKeys = async (): Promise<
    TrashItemCollectionKey[]
> =>
    TrashItemCollectionKeys.parse(
        // This key name is not accurate, these are not deleted collections but
        // collections referred to by deleted items (so they can include deleted
        // collections, but not exclusively).
        //
        // But since the use of this key name is localized to this file so we
        // let the original name be.
        (await localForage.getItem("deleted-collection")) ?? [],
    );

/**
 * Replace the list of trash item collection keys stored in our local database.
 *
 * This is the setter corresponding to {@link saveTrashItemCollectionKeys}.
 */
export const saveTrashItemCollectionKeys = async (
    cks: TrashItemCollectionKey[],
) => {
    await localForage.setItem("deleted-collection", cks);
};

/**
 * Return all files present in our local database.
 *
 * These are "collection files", meaning that there might be multiple entries
 * for the same file, one for each collection that the file belongs to. For more
 * details, See: [Note: Collection File].
 *
 * Use {@link saveCollectionFiles} to update the database.
 */
export const savedCollectionFiles = async (): Promise<EnteFile[]> => {
    // [Note: Avoiding Zod parsing for large DB arrays]
    //
    // Zod can be used to validate that the value we read from the DB is indeed
    // the same as the type we expect, but for potentially very large arrays,
    // this has an overhead that is perhaps not justified when dealing with DB
    // entries we ourselves wrote.
    //
    // For example (as a non-rigorous benchmark) parsing 200k files took one
    // second. Zod is fast, just that these arrays are big and might be accessed
    // frequently, and the schemas are, while not too complicated, non-trivial.
    //
    // As an optimization, we skip the runtime check here and cast. This might
    // not be the most optimal choice in the future, so (a) use it sparingly,
    // and (b) mark all such cases with the title of this note.
    //
    // Note that the cast is happening inside the local forage code since we're
    // passing a type parameter.
    let files = (await localForage.getItem<EnteFile[]>("files")) ?? [];

    // Previously hidden files were stored separately. If that key is present,
    // also read those files, and migrate them (save the concatenation to disk
    // and delete the corresponding DB key).
    //
    // This migration was added Jun 2025, v1.7.14-beta (tag: Migration).
    const previousHiddenFiles =
        await localForage.getItem<EnteFile[]>("hidden-files");
    if (previousHiddenFiles) {
        files = files.concat(previousHiddenFiles);
        await saveCollectionFiles(files);
        await localForage.removeItem("hidden-files");
        // While we're cleaning up, also remove this unused field related to
        // hidden collections also being separately stored earlier.
        await localForage.removeItem("hidden-collection-ids");
    }

    return transformFilesIfNeeded(files);
};

/**
 * Replace the list of collection files stored in our local database.
 *
 * This is the setter corresponding to {@link savedCollectionFiles}.
 */
export const saveCollectionFiles = async (files: EnteFile[]) => {
    await localForage.setItem("files", transformFilesIfNeeded(files));
};

/**
 * Return the locally persisted "last sync time" for a collection that we have
 * pulled from remote. This can be used to perform a paginated delta pull from
 * the saved time onwards.
 *
 * > Specifically, this is the {@link updationTime} of the latest file from the
 * > {@link collection}, or the the collection itself if it is fully synced.
 *
 * Use {@link saveCollectionLastSyncTime} to update the value saved in the
 * database, and {@link removeCollectionIDLastSyncTime} to remove the saved
 * value from the database.
 */
export const savedCollectionLastSyncTime = async (collection: Collection) =>
    LocalTimestamp.parse(await localForage.getItem(`${collection.id}-time`));

/**
 * Update the locally persisted timestamp that will be returned by subsequent
 * calls to {@link savedCollectionLastSyncTime}.
 */
export const saveCollectionLastSyncTime = async (
    collection: Collection,
    time: number,
) => {
    await localForage.setItem(`${collection.id}-time`, time);
};

/**
 * Remove the locally persisted timestamp, if any, previously saved for a
 * collection with the given ID using {@link saveCollectionLastSyncTime}.
 */
export const removeCollectionIDLastSyncTime = async (collectionID: number) => {
    await localForage.removeItem(`${collectionID}-time`);
};

/**
 * Zod schema for a trash entry saved in our local database.
 */
const LocalTrashItem = z.looseObject({
    file: LocalEnteFile,
    updatedAt: z.number(),
    deleteBy: z.number(),
});

/**
 * Return all trash entries present in our local database.
 *
 * Use {@link saveTrashItems} to update the database
 */
export const savedTrashItems = async (): Promise<TrashItem[]> =>
    LocalTrashItem.array().parse(
        (await localForage.getItem("file-trash")) ?? [],
    );

/**
 * Replace the list of trash items stored in our local database.
 *
 * This is the setter corresponding to {@link savedTrashItems}.
 */
export const saveTrashItems = async (trashItems: TrashItem[]) => {
    await localForage.setItem("file-trash", trashItems);
};

/**
 * Return the updatedAt of the latest trash items we have obtained from remote.
 *
 * Use {@link saveTrashLastUpdatedAt} to update the database.
 */
export const savedTrashLastUpdatedAt = async (): Promise<number | undefined> =>
    LocalTimestamp.parse(await localForage.getItem("trash-time"));

/**
 * Update the updatedAt of the latest trash items we have obtained from remote.
 *
 * This is the setter corresponding to {@link savedTrashLastUpdatedAt}.
 */
export const saveTrashLastUpdatedAt = async (updatedAt: number) => {
    await localForage.setItem("trash-time", updatedAt);
};
