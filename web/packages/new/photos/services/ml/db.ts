import log from "ente-base/log";
import { deleteDB, openDB, type DBSchema } from "idb";
import type { LocalCLIPIndex } from "./clip";
import type { FaceCluster } from "./cluster";
import type { LocalFaceIndex } from "./face";

interface MLDBSchema extends DBSchema {
    "file-status": {
        key: number;
        value: FileStatus;
        indexes: { status: FileStatus["status"] };
    };
    "face-index": { key: number; value: LocalFaceIndex };
    "clip-index": { key: number; value: LocalCLIPIndex };
    "face-cluster": { key: string; value: FaceCluster };
    "cluster-group": { key: string; value: unknown };
}

interface FileStatus {
    fileID: number;
    status: "indexable" | "indexed" | "failed";
    failureCount: number;
}

// Workers cache separate connections; terminate them before deleting this DB.
let _mlDB: ReturnType<typeof openMLDB> | undefined;

const openMLDB = async () => {
    const db = await openDB<MLDBSchema>("ml", 1, {
        upgrade(db, oldVersion, newVersion) {
            log.info(`Upgrading ML DB ${oldVersion} => ${newVersion}`);
            if (oldVersion < 1) {
                db.createObjectStore("file-status", {
                    keyPath: "fileID",
                }).createIndex("status", "status");
                db.createObjectStore("face-index", { keyPath: "fileID" });
                db.createObjectStore("clip-index", { keyPath: "fileID" });
                db.createObjectStore("face-cluster", { keyPath: "id" });
                db.createObjectStore("cluster-group", { keyPath: "id" });
            }
        },
        blocking() {
            log.info(
                "Another client is attempting to open a new version of ML DB",
            );
            db.close();
            _mlDB = undefined;
        },
        blocked() {
            log.warn(
                "Waiting for an existing client to close their connection so that we can update the ML DB version",
            );
        },
        terminated() {
            log.warn("Our connection to ML DB was unexpectedly terminated");
            _mlDB = undefined;
        },
    });
    return db;
};

const mlDB = () => (_mlDB ??= openMLDB());

export const clearMLDB = async () => {
    try {
        if (_mlDB) (await _mlDB).close();
    } catch (e) {
        log.warn("Ignoring error when trying to close ML DB", e);
    }
    _mlDB = undefined;

    return deleteDB("ml", {
        blocked() {
            log.warn(
                "Waiting for an existing client to close their connection so that we can delete the ML DB",
            );
        },
    });
};

export const saveIndexes = async (
    faceIndex: LocalFaceIndex,
    clipIndex: LocalCLIPIndex,
) => {
    const { fileID } = faceIndex;

    const db = await mlDB();
    // Status must not say indexed unless both indexes commit.
    const tx = db.transaction(
        ["file-status", "face-index", "clip-index"],
        "readwrite",
    );

    await Promise.all([
        tx
            .objectStore("file-status")
            .put({ fileID, status: "indexed", failureCount: 0 }),
        tx.objectStore("face-index").put(faceIndex),
        tx.objectStore("clip-index").put(clipIndex),
        tx.done,
    ]);
};

const newFileStatus = (fileID: number): FileStatus => ({
    fileID,
    status: "indexable",
    failureCount: 0,
});

export const savedFaceIndex = async (fileID: number) => {
    const db = await mlDB();
    return db.get("face-index", fileID);
};

export const savedFaceIndexes = async () => {
    const db = await mlDB();
    return await db.getAll("face-index");
};

export const savedCLIPIndexes = async () => {
    const db = await mlDB();
    return await db.getAll("clip-index");
};

export const updateAssumingLocalFiles = async (
    localFileIDs: number[],
    localTrashFilesIDs: Set<number>,
) => {
    const db = await mlDB();
    const tx = db.transaction(
        ["file-status", "face-index", "clip-index"],
        "readwrite",
    );
    const fdbFileIDs = await tx.objectStore("file-status").getAllKeys();
    const fdbIndexedFileIDs = await tx
        .objectStore("file-status")
        .getAllKeys(IDBKeyRange.only("indexed"));

    const local = new Set(localFileIDs);
    const fdb = new Set(fdbFileIDs);
    const fdbIndexed = new Set(fdbIndexedFileIDs);

    const newFileIDs = localFileIDs.filter((id) => !fdb.has(id));
    const removedFileIDs = fdbFileIDs.filter((id) => {
        if (local.has(id)) return false;
        if (localTrashFilesIDs.has(id)) {
            // Retain finished indexes to avoid reindexing a restored file.
            if (fdbIndexed.has(id)) {
                return false;
            }
        }
        return true;
    });

    await Promise.all(
        [
            newFileIDs.map((id) =>
                tx.objectStore("file-status").put(newFileStatus(id)),
            ),
            removedFileIDs.map((id) =>
                tx.objectStore("file-status").delete(id),
            ),
            removedFileIDs.map((id) => tx.objectStore("face-index").delete(id)),
            removedFileIDs.map((id) => tx.objectStore("clip-index").delete(id)),
            tx.done,
        ].flat(),
    );
};

export const savedIndexCounts = async () => {
    const db = await mlDB();
    const tx = db.transaction("file-status", "readonly");
    const indexableCount = await tx.store
        .index("status")
        .count(IDBKeyRange.only("indexable"));
    const indexedCount = await tx.store
        .index("status")
        .count(IDBKeyRange.only("indexed"));
    const failedCount = await tx.store
        .index("status")
        .count(IDBKeyRange.only("failed"));
    return { indexableCount, indexedCount, failedCount };
};

export const readNextIndexableFileIDs = async (count: number) => {
    const db = await mlDB();
    const tx = db.transaction("file-status", "readonly");
    // Higher file IDs approximate newer files; index them first.
    let cursor = await tx.store
        .index("status")
        .openKeyCursor(IDBKeyRange.only("indexable"), "prev");
    const result: number[] = [];
    while (cursor && count > 0) {
        result.push(cursor.primaryKey);
        cursor = await cursor.continue();
        count -= 1;
    }
    return result;
};

export const markIndexingFailed = async (fileID: number) => {
    const db = await mlDB();
    const tx = db.transaction("file-status", "readwrite");
    const fileStatus = (await tx.store.get(fileID)) ?? newFileStatus(fileID);
    fileStatus.status = "failed";
    fileStatus.failureCount = fileStatus.failureCount + 1;
    await Promise.all([tx.store.put(fileStatus), tx.done]);
};

export const savedFaceClusters = async () => {
    const db = await mlDB();
    return db.getAll("face-cluster");
};

export const saveFaceClusters = async (clusters: FaceCluster[]) => {
    const db = await mlDB();
    const tx = db.transaction("face-cluster", "readwrite");
    await tx.store.clear();
    await Promise.all(clusters.map((cluster) => tx.store.put(cluster)));
    return tx.done;
};
