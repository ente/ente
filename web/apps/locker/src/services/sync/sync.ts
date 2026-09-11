import type { LockerCollection, LockerItem } from "@/types";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import {
    type EncryptedCollectionRecord,
    type EncryptedFileRecord,
    type LockerEncryptedCache,
    replaceLockerCache,
    setEncryptedFileRecord,
} from "../locker-cache";
import {
    type StoredTrashFileRecord,
    deleteCollectionSinceTime,
    deleteFileRecords,
    deleteFileRecordsForCollection,
    deleteTrashFileRecords,
    loadLockerSnapshotFromDB,
    saveCollectionRecords,
    saveCollectionSinceTime,
    saveCollectionsSinceTime,
    saveFileRecords,
    saveTrashFileRecords,
    saveTrashSinceTime,
} from "../locker-db";
import {
    type LockerTrashData,
    buildEncryptedFileRecord,
    buildStoredTrashFileRecord,
    decryptAllData,
    decryptStoredTrash,
    toEncryptedCollectionRecord,
} from "./decrypt";
import {
    CollectionsResponse,
    FileDiffResponse,
    TrashDiffResponse,
} from "./schemas";

interface LockerHydratedState {
    collections: LockerCollection[];
    trashItems: LockerItem[];
    trashLastUpdatedAt: number;
    collectionsSinceTime: number;
    trashSinceTime: number;
}

interface LockerPersistedState extends LockerHydratedState {
    hasPersistedState: boolean;
}

const buildLockerCache = (
    collections: Map<number, EncryptedCollectionRecord>,
    files: EncryptedFileRecord[],
    trashFiles: StoredTrashFileRecord[],
): LockerEncryptedCache => {
    const nextFiles = new Map<number, Map<number, EncryptedFileRecord>>();
    for (const record of files) {
        setEncryptedFileRecord(nextFiles, record);
    }
    for (const record of trashFiles) {
        setEncryptedFileRecord(nextFiles, record);
    }

    return { collections, files: nextFiles };
};

const fetchEncryptedCollections = async (sinceTime: number) => {
    const response = await fetch(
        await apiURL("/collections/v2", { sinceTime }),
        { headers: await authenticatedRequestHeaders() },
    );
    ensureOk(response);
    const { collections } = CollectionsResponse.parse(await response.json());
    return collections;
};

interface CollectionFileDiff {
    recordsToSave: EncryptedFileRecord[];
    fileKeysToDelete: [number, number][];
    sinceTime: number;
}

const fetchEncryptedFilesForCollection = async (
    collectionID: number,
    initialSinceTime: number,
): Promise<CollectionFileDiff> => {
    let sinceTime = initialSinceTime;
    let hasMore = true;
    const recordsToSave: EncryptedFileRecord[] = [];
    const fileKeysToDelete: [number, number][] = [];

    while (hasMore) {
        const response = await fetch(
            await apiURL("/collections/v2/diff", { collectionID, sinceTime }),
            { headers: await authenticatedRequestHeaders() },
        );
        ensureOk(response);
        const parsed = FileDiffResponse.parse(await response.json());

        for (const file of parsed.diff) {
            sinceTime = Math.max(sinceTime, file.updationTime);
            if (file.isDeleted) {
                fileKeysToDelete.push([file.id, collectionID]);
            } else {
                recordsToSave.push(buildEncryptedFileRecord(file));
            }
        }

        hasMore = parsed.hasMore;
    }

    return { recordsToSave, fileKeysToDelete, sinceTime };
};

const withoutFailedCollections = (
    cache: LockerEncryptedCache,
    failedCollectionIDs: number[],
): LockerEncryptedCache => {
    if (failedCollectionIDs.length === 0) {
        return cache;
    }

    const failedCollectionIDSet = new Set(failedCollectionIDs);
    return {
        collections: new Map(
            [...cache.collections.entries()].filter(
                ([collectionID]) => !failedCollectionIDSet.has(collectionID),
            ),
        ),
        files: new Map(
            [...cache.files.entries()]
                .map(
                    ([fileID, records]): [
                        number,
                        Map<number, EncryptedFileRecord>,
                    ] => [
                        fileID,
                        new Map(
                            [...records.entries()].filter(
                                ([collectionID]) =>
                                    !failedCollectionIDSet.has(collectionID),
                            ),
                        ),
                    ],
                )
                .filter(([, records]) => records.size > 0),
        ),
    };
};

const hydrateLockerState = async (
    collections: Map<number, EncryptedCollectionRecord>,
    files: EncryptedFileRecord[],
    trashFiles: StoredTrashFileRecord[],
    trashLastUpdatedAt: number,
): Promise<LockerHydratedState> => {
    const activeCache = buildLockerCache(collections, files, []);

    const decrypted = await decryptAllData(activeCache);
    if (
        decrypted.totalCollectionCount > 0 &&
        decrypted.collections.length === 0
    ) {
        throw new Error(
            `Failed to decrypt all ${decrypted.totalCollectionCount} locker collections`,
        );
    }

    const hydratedCache = withoutFailedCollections(
        buildLockerCache(collections, files, trashFiles),
        decrypted.failedCollectionIDs,
    );
    replaceLockerCache(hydratedCache);

    if (decrypted.failedCollectionIDs.length > 0) {
        log.warn(
            `Decrypted ${decrypted.collections.length}/${decrypted.totalCollectionCount} locker collections`,
        );
    }

    const trash = await decryptStoredTrash(
        hydratedCache,
        trashFiles,
        trashLastUpdatedAt,
    );

    return {
        collections: decrypted.collections,
        trashItems: trash.items,
        trashLastUpdatedAt: trash.lastUpdatedAt,
        collectionsSinceTime: 0,
        trashSinceTime: 0,
    };
};

export const loadPersistedLockerState =
    async (): Promise<LockerPersistedState> => {
        const snapshot = await loadLockerSnapshotFromDB();
        const hydrated = await hydrateLockerState(
            snapshot.collections,
            snapshot.files,
            snapshot.trashFiles,
            snapshot.trashSinceTime,
        );

        return {
            ...hydrated,
            collectionsSinceTime: snapshot.collectionsSinceTime,
            trashSinceTime: snapshot.trashSinceTime,
            hasPersistedState: snapshot.hasPersistedState,
        };
    };

export const syncLockerState = async (): Promise<LockerHydratedState> => {
    const snapshot = await loadLockerSnapshotFromDB();
    const collectionChanges = await fetchEncryptedCollections(
        snapshot.collectionsSinceTime,
    );

    let latestCollectionsSinceTime = snapshot.collectionsSinceTime;
    const changedCollections: EncryptedCollectionRecord[] = [];
    const deletedCollectionIDs: number[] = [];

    for (const change of collectionChanges) {
        latestCollectionsSinceTime = Math.max(
            latestCollectionsSinceTime,
            change.updationTime,
        );
        const record = await toEncryptedCollectionRecord(change);
        changedCollections.push(record);
        if (record.isDeleted) {
            deletedCollectionIDs.push(record.id);
        }
    }

    if (changedCollections.length > 0) {
        await saveCollectionRecords(changedCollections);
    }
    for (const collectionID of deletedCollectionIDs) {
        await deleteFileRecordsForCollection(collectionID);
        await deleteCollectionSinceTime(collectionID);
    }
    await saveCollectionsSinceTime(latestCollectionsSinceTime);

    const postCollectionSnapshot = await loadLockerSnapshotFromDB();
    for (const collection of postCollectionSnapshot.collections.values()) {
        if (collection.isDeleted) {
            continue;
        }

        const savedSinceTime =
            postCollectionSnapshot.collectionSinceTimeByID.get(collection.id) ??
            0;
        if (savedSinceTime >= collection.updationTime) {
            continue;
        }

        const diff = await fetchEncryptedFilesForCollection(
            collection.id,
            savedSinceTime,
        );
        if (diff.recordsToSave.length > 0) {
            await saveFileRecords(diff.recordsToSave);
        }
        if (diff.fileKeysToDelete.length > 0) {
            await deleteFileRecords(diff.fileKeysToDelete);
        }

        await saveCollectionSinceTime(
            collection.id,
            Math.max(diff.sinceTime, collection.updationTime),
        );
    }

    let trashSinceTime = postCollectionSnapshot.trashSinceTime;
    let hasMore = true;
    while (hasMore) {
        const response = await fetch(
            await apiURL("/trash/v2/diff", { sinceTime: trashSinceTime }),
            { headers: await authenticatedRequestHeaders() },
        );
        ensureOk(response);
        const parsed = TrashDiffResponse.parse(await response.json());

        const recordsToSave: StoredTrashFileRecord[] = [];
        const fileIDsToDelete: number[] = [];
        for (const entry of parsed.diff) {
            trashSinceTime = Math.max(trashSinceTime, entry.updatedAt);
            if (entry.isDeleted || entry.isRestored) {
                fileIDsToDelete.push(entry.file.id);
            } else {
                recordsToSave.push(buildStoredTrashFileRecord(entry));
            }
        }

        if (recordsToSave.length > 0) {
            await saveTrashFileRecords(recordsToSave);
        }
        if (fileIDsToDelete.length > 0) {
            await deleteTrashFileRecords(fileIDsToDelete);
        }

        hasMore = parsed.hasMore;
    }

    await saveTrashSinceTime(trashSinceTime);

    const nextSnapshot = await loadLockerSnapshotFromDB();
    const hydrated = await hydrateLockerState(
        nextSnapshot.collections,
        nextSnapshot.files,
        nextSnapshot.trashFiles,
        nextSnapshot.trashSinceTime,
    );

    return {
        ...hydrated,
        collectionsSinceTime: nextSnapshot.collectionsSinceTime,
        trashSinceTime: nextSnapshot.trashSinceTime,
    };
};

export const fetchLockerData = async (): Promise<LockerCollection[]> =>
    (await syncLockerState()).collections;

export const fetchLockerTrash = async (): Promise<LockerTrashData> => {
    const state = await syncLockerState();
    return { items: state.trashItems, lastUpdatedAt: state.trashLastUpdatedAt };
};
