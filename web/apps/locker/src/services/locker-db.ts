import { ensureLocalUser } from "ente-accounts/services/user";
import log from "ente-base/log";
import { deleteDB, openDB, type DBSchema, type IDBPDatabase } from "idb";
import type {
    EncryptedCollectionRecord,
    EncryptedFileRecord,
} from "./remote-cache";

const LOCKER_DB_NAME_PREFIX = "ente-locker";
const LOCKER_DB_VERSION = 2;
const COLLECTIONS_SINCE_TIME_KEY = "collections_since_time";
const TRASH_SINCE_TIME_KEY = "trash_since_time";

const collectionSinceTimeKey = (collectionID: number) =>
    `collection_since_time:${collectionID}`;

const collectionIDFromSinceTimeKey = (key: string) => {
    const prefix = "collection_since_time:";
    if (!key.startsWith(prefix)) {
        return undefined;
    }

    const collectionID = Number.parseInt(key.slice(prefix.length), 10);
    return Number.isFinite(collectionID) ? collectionID : undefined;
};

export interface StoredTrashFileRecord extends EncryptedFileRecord {
    updatedAt: number;
    deleteBy: number;
}

type StoredCollectionRecord = Omit<EncryptedCollectionRecord, "payload">;

interface LockerDBSchema extends DBSchema {
    collections: { key: number; value: StoredCollectionRecord };
    files: { key: [number, number]; value: EncryptedFileRecord };
    trashFiles: { key: number; value: StoredTrashFileRecord };
    meta: { key: string; value: number };
}

interface CachedLockerDB {
    userID: number;
    dbPromise: ReturnType<typeof openLockerDB>;
}

export interface LockerDBSnapshot {
    collections: Map<number, EncryptedCollectionRecord>;
    files: EncryptedFileRecord[];
    trashFiles: StoredTrashFileRecord[];
    collectionsSinceTime: number;
    collectionSinceTimeByID: Map<number, number>;
    trashSinceTime: number;
    hasPersistedState: boolean;
}

let _lockerDB: CachedLockerDB | undefined;

const lockerDBName = (userID: number) => `${LOCKER_DB_NAME_PREFIX}-${userID}`;

const toStoredCollectionRecord = (
    record: EncryptedCollectionRecord,
): StoredCollectionRecord => {
    const storedRecord = { ...record } as Partial<EncryptedCollectionRecord>;
    delete storedRecord.payload;
    return storedRecord as StoredCollectionRecord;
};

const recreateLockerObjectStores = (db: IDBPDatabase<LockerDBSchema>) => {
    for (const storeName of [
        "collections",
        "files",
        "trashFiles",
        "meta",
    ] as const) {
        if (db.objectStoreNames.contains(storeName)) {
            db.deleteObjectStore(storeName);
        }
    }

    db.createObjectStore("collections", { keyPath: "id" });
    db.createObjectStore("files", { keyPath: ["id", "collectionID"] });
    db.createObjectStore("trashFiles", { keyPath: "id" });
    db.createObjectStore("meta");
};

const openLockerDB = async (userID: number) => {
    const name = lockerDBName(userID);
    const db = await openDB<LockerDBSchema>(name, LOCKER_DB_VERSION, {
        upgrade(db, oldVersion, newVersion) {
            log.info(
                `Upgrading Locker DB (${name}) ${oldVersion} => ${newVersion}`,
            );
            if (oldVersion < 2) {
                recreateLockerObjectStores(db);
            }
        },
        blocking() {
            log.info(
                `Another client is attempting to open a new version of Locker DB (${name})`,
            );
            db.close();
            if (_lockerDB?.userID === userID) {
                _lockerDB = undefined;
            }
        },
        blocked() {
            log.warn(
                `Waiting for an existing client to close Locker DB (${name})`,
            );
        },
        terminated() {
            log.warn(`Our connection to Locker DB (${name}) was terminated`);
            if (_lockerDB?.userID === userID) {
                _lockerDB = undefined;
            }
        },
    });

    return db;
};

const resolveLockerDB = async (userID = ensureLocalUser().id) => {
    if (_lockerDB?.userID === userID) {
        return _lockerDB.dbPromise;
    }

    if (_lockerDB) {
        try {
            (await _lockerDB.dbPromise).close();
        } catch (error) {
            log.warn("Ignoring error while closing prior Locker DB", error);
        }
    }

    const dbPromise = openLockerDB(userID);
    _lockerDB = { userID, dbPromise };
    return dbPromise;
};

const resetCachedLockerDB = async (userID?: number) => {
    if (_lockerDB && (userID === undefined || _lockerDB.userID === userID)) {
        try {
            (await _lockerDB.dbPromise).close();
        } catch (error) {
            log.warn("Ignoring error while closing Locker DB", error);
        }
        _lockerDB = undefined;
    }
};

export const clearLockerDB = async (userID = ensureLocalUser().id) => {
    await resetCachedLockerDB(userID);
    return deleteDB(lockerDBName(userID), {
        blocked() {
            log.warn(
                `Waiting for an existing client to close Locker DB (${lockerDBName(
                    userID,
                )}) so that we can delete it`,
            );
        },
    });
};

export const loadLockerSnapshotFromDB = async (
    userID = ensureLocalUser().id,
): Promise<LockerDBSnapshot> => {
    const db = await resolveLockerDB(userID);
    const tx = db.transaction(
        ["collections", "files", "trashFiles", "meta"],
        "readonly",
    );

    const [collectionsList, files, trashFiles, metaEntries] = await Promise.all(
        [
            tx.objectStore("collections").getAll(),
            tx.objectStore("files").getAll(),
            tx.objectStore("trashFiles").getAll(),
            tx
                .objectStore("meta")
                .getAllKeys()
                .then(async (keys) =>
                    Promise.all(
                        keys.map(
                            async (key) =>
                                [
                                    key,
                                    await tx.objectStore("meta").get(key),
                                ] as const,
                        ),
                    ),
                ),
        ],
    );
    await tx.done;

    let collectionsSinceTime = 0;
    let trashSinceTime = 0;
    let hasCollectionsSinceTime = false;
    let hasTrashSinceTime = false;
    const collectionSinceTimeByID = new Map<number, number>();
    for (const [key, value] of metaEntries) {
        if (typeof key !== "string" || typeof value !== "number") {
            continue;
        }

        if (key === COLLECTIONS_SINCE_TIME_KEY) {
            collectionsSinceTime = value;
            hasCollectionsSinceTime = true;
            continue;
        }

        if (key === TRASH_SINCE_TIME_KEY) {
            trashSinceTime = value;
            hasTrashSinceTime = true;
            continue;
        }

        const collectionID = collectionIDFromSinceTimeKey(key);
        if (collectionID !== undefined) {
            collectionSinceTimeByID.set(collectionID, value);
        }
    }

    return {
        collections: new Map(
            collectionsList.map((record) => [record.id, { ...record }]),
        ),
        files,
        trashFiles,
        collectionsSinceTime,
        collectionSinceTimeByID,
        trashSinceTime,
        hasPersistedState:
            collectionsList.length > 0 ||
            files.length > 0 ||
            trashFiles.length > 0 ||
            hasCollectionsSinceTime ||
            hasTrashSinceTime ||
            collectionSinceTimeByID.size > 0,
    };
};

export const saveCollectionRecords = async (
    records: EncryptedCollectionRecord[],
    userID = ensureLocalUser().id,
) => {
    if (records.length === 0) {
        return;
    }

    const db = await resolveLockerDB(userID);
    const tx = db.transaction("collections", "readwrite");
    await Promise.all(
        records.map((record) => tx.store.put(toStoredCollectionRecord(record))),
    );
    await tx.done;
};

export const saveCollectionsSinceTime = async (
    sinceTime: number,
    userID = ensureLocalUser().id,
) => {
    const db = await resolveLockerDB(userID);
    await db.put("meta", sinceTime, COLLECTIONS_SINCE_TIME_KEY);
};

export const saveCollectionSinceTime = async (
    collectionID: number,
    sinceTime: number,
    userID = ensureLocalUser().id,
) => {
    const db = await resolveLockerDB(userID);
    await db.put("meta", sinceTime, collectionSinceTimeKey(collectionID));
};

export const deleteCollectionSinceTime = async (
    collectionID: number,
    userID = ensureLocalUser().id,
) => {
    const db = await resolveLockerDB(userID);
    await db.delete("meta", collectionSinceTimeKey(collectionID));
};

export const saveFileRecords = async (
    records: EncryptedFileRecord[],
    userID = ensureLocalUser().id,
) => {
    if (records.length === 0) {
        return;
    }

    const db = await resolveLockerDB(userID);
    const tx = db.transaction("files", "readwrite");
    await Promise.all(records.map((record) => tx.store.put(record)));
    await tx.done;
};

export const deleteFileRecords = async (
    keys: readonly (readonly [number, number])[],
    userID = ensureLocalUser().id,
) => {
    if (keys.length === 0) {
        return;
    }

    const db = await resolveLockerDB(userID);
    const tx = db.transaction("files", "readwrite");
    await Promise.all(keys.map((key) => tx.store.delete([...key])));
    await tx.done;
};

export const deleteFileRecordsForCollection = async (
    collectionID: number,
    userID = ensureLocalUser().id,
) => {
    const db = await resolveLockerDB(userID);
    const tx = db.transaction("files", "readwrite");
    let cursor = await tx.store.openCursor();
    while (cursor) {
        if (cursor.value.collectionID === collectionID) {
            await cursor.delete();
        }
        cursor = await cursor.continue();
    }
    await tx.done;
};

export const saveTrashFileRecords = async (
    records: StoredTrashFileRecord[],
    userID = ensureLocalUser().id,
) => {
    if (records.length === 0) {
        return;
    }

    const db = await resolveLockerDB(userID);
    const tx = db.transaction("trashFiles", "readwrite");
    await Promise.all(records.map((record) => tx.store.put(record)));
    await tx.done;
};

export const deleteTrashFileRecords = async (
    fileIDs: number[],
    userID = ensureLocalUser().id,
) => {
    if (fileIDs.length === 0) {
        return;
    }

    const db = await resolveLockerDB(userID);
    const tx = db.transaction("trashFiles", "readwrite");
    await Promise.all(fileIDs.map((fileID) => tx.store.delete(fileID)));
    await tx.done;
};

export const saveTrashSinceTime = async (
    sinceTime: number,
    userID = ensureLocalUser().id,
) => {
    const db = await resolveLockerDB(userID);
    await db.put("meta", sinceTime, TRASH_SINCE_TIME_KEY);
};
