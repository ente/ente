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

export const savedCollections = async (): Promise<Collection[]> =>
    LocalCollections.parse((await localForage.getItem("collections")) ?? []);

export const saveCollections = async (collections: Collection[]) => {
    await localForage.setItem("collections", collections);
};

export const savedCollectionsUpdationTime = async () =>
    LocalTimestamp.parse(await localForage.getItem("collection-updation-time"));

export const saveCollectionsUpdationTime = async (time: number) => {
    await localForage.setItem("collection-updation-time", time);
};

const TrashItemCollectionKey = z.object({ id: z.number(), key: z.string() });

const TrashItemCollectionKeys = TrashItemCollectionKey.array();

export type TrashItemCollectionKey = z.infer<typeof TrashItemCollectionKey>;

export const savedTrashItemCollectionKeys = async (): Promise<
    TrashItemCollectionKey[]
> =>
    TrashItemCollectionKeys.parse(
        // Historical name; this stores every collection key still used by trash.
        (await localForage.getItem("deleted-collection")) ?? [],
    );

export const saveTrashItemCollectionKeys = async (
    cks: TrashItemCollectionKey[],
) => {
    await localForage.setItem("deleted-collection", cks);
};

export const savedCollectionFiles = async (): Promise<EnteFile[]> => {
    // Zod parsing 200k self-written records costs about a second.
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
        await localForage.removeItem("hidden-collection-ids");
    }

    return transformFilesIfNeeded(files);
};

export const saveCollectionFiles = async (files: EnteFile[]) => {
    await localForage.setItem("files", transformFilesIfNeeded(files));
};

export const savedCollectionLastSyncTime = async (collection: Collection) =>
    LocalTimestamp.parse(await localForage.getItem(`${collection.id}-time`));

export const saveCollectionLastSyncTime = async (
    collection: Collection,
    time: number,
) => {
    await localForage.setItem(`${collection.id}-time`, time);
};

export const removeCollectionIDLastSyncTime = async (collectionID: number) => {
    await localForage.removeItem(`${collectionID}-time`);
};

const LocalTrashItem = z.looseObject({
    file: LocalEnteFile,
    updatedAt: z.number(),
    deleteBy: z.number(),
});

export const savedTrashItems = async (): Promise<TrashItem[]> =>
    LocalTrashItem.array().parse(
        (await localForage.getItem("file-trash")) ?? [],
    );

export const saveTrashItems = async (trashItems: TrashItem[]) => {
    await localForage.setItem("file-trash", trashItems);
};

export const savedTrashLastUpdatedAt = async (): Promise<number | undefined> =>
    LocalTimestamp.parse(await localForage.getItem("trash-time"));

export const saveTrashLastUpdatedAt = async (updatedAt: number) => {
    await localForage.setItem("trash-time", updatedAt);
};
