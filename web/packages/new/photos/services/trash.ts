import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import type { Collection } from "ente-media/collection";
import {
    decryptRemoteFile,
    RemoteEnteFile,
    type EnteFile,
} from "ente-media/file";
import { fileCreationTime } from "ente-media/file-metadata";
import { z } from "zod";
import { getCollectionByID } from "./collection";
import {
    savedTrashItemCollectionKeys,
    savedTrashItems,
    savedTrashLastUpdatedAt,
    saveTrashItemCollectionKeys,
    saveTrashItems,
    saveTrashLastUpdatedAt,
} from "./photos-fdb";

export interface TrashItem {
    file: EnteFile;
    // Both timestamps use epoch microseconds.
    updatedAt: number;
    deleteBy: number;
}

const RemoteTrashItem = z.looseObject({
    file: RemoteEnteFile,
    isDeleted: z.boolean(),
    isRestored: z.boolean(),
    updatedAt: z.number(),
    deleteBy: z.number(),
});

type RemoteTrashItem = z.infer<typeof RemoteTrashItem>;

export const pullTrash = async (
    collections: Collection[],
    onSetTrashedItems: ((trashItems: TrashItem[]) => void) | undefined,
    onPruneDeletedFileIDs: (deletedFileIDs: Set<number>) => Promise<void>,
): Promise<void> => {
    // Trash can outlive its collection, so persist every key still in use here.
    const collectionKeyByID = new Map(collections.map((c) => [c.id, c.key]));
    const trashItemCollectionKeys = await savedTrashItemCollectionKeys();
    for (const { id, key } of trashItemCollectionKeys) {
        collectionKeyByID.set(id, key);
    }

    const trashItemsByID = new Map(
        (await savedTrashItems()).map((t) => [t.file.id, t]),
    );
    let sinceTime = (await savedTrashLastUpdatedAt()) ?? 0;

    while (true) {
        const { diff, hasMore } = await getTrashDiff(sinceTime);
        if (!diff.length) break;

        const deletedFileIDs = new Set<number>();
        for (const change of diff) {
            sinceTime = Math.max(sinceTime, change.updatedAt);
            const fileID = change.file.id;
            if (change.isDeleted) deletedFileIDs.add(fileID);
            if (change.isDeleted || change.isRestored) {
                trashItemsByID.delete(fileID);
            } else {
                const collectionID = change.file.collectionID;
                let collectionKey = collectionKeyByID.get(collectionID);
                if (!collectionKey) {
                    const collection = await getCollectionByID(collectionID);
                    collectionKey = collection.key;
                    collectionKeyByID.set(collectionID, collectionKey);
                    trashItemCollectionKeys.push({
                        id: collectionID,
                        key: collectionKey,
                    });
                    await saveTrashItemCollectionKeys(trashItemCollectionKeys);
                }
                trashItemsByID.set(fileID, {
                    ...change,
                    file: await decryptRemoteFile(change.file, collectionKey),
                });
            }
        }

        const trashItems = [...trashItemsByID.values()];
        onSetTrashedItems?.(trashItems);
        await saveTrashItems(trashItems);
        await saveTrashLastUpdatedAt(sinceTime);
        if (deletedFileIDs.size) await onPruneDeletedFileIDs(deletedFileIDs);
        if (!hasMore) break;
    }

    const trashCollectionIDs = new Set(
        [...trashItemsByID.values()].map((item) => item.file.collectionID),
    );
    await saveTrashItemCollectionKeys(
        [...collectionKeyByID.entries()]
            .filter(([id]) => trashCollectionIDs.has(id))
            .map(([id, key]) => ({ id, key })),
    );
};

const TrashDiffResponse = z.object({
    diff: RemoteTrashItem.array(),
    hasMore: z.boolean(),
});

const getTrashDiff = async (sinceTime: number) => {
    const res = await fetch(await apiURL("/trash/v2/diff", { sinceTime }), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return TrashDiffResponse.parse(await res.json());
};

export const sortTrashItems = (trashItems: TrashItem[]) =>
    trashItems.sort((a, b) => {
        if (a.deleteBy == b.deleteBy) {
            const af = a.file;
            const bf = b.file;
            const at = fileCreationTime(af);
            const bt = fileCreationTime(bf);
            return at == bt
                ? bf.metadata.modificationTime - af.metadata.modificationTime
                : bt - at;
        }
        return b.deleteBy - a.deleteBy;
    });

export const savedTrashItemFileIDs = () =>
    savedTrashItems().then((items) => new Set(items.map((f) => f.file.id)));

export const emptyTrash = async () => {
    await postTrashEmpty((await savedTrashLastUpdatedAt()) ?? 0);
    await saveTrashItems([]);
};

// The cutoff protects files trashed after this client's last pull.
const postTrashEmpty = async (lastUpdatedAt: number) =>
    ensureOk(
        await fetch(await apiURL("/trash/empty"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({ lastUpdatedAt }),
        }),
    );
