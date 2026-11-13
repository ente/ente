import { deleteDB, openDB, type DBSchema } from "idb";
import log from "./log";

// Keep this as one store without indexes.
// Indexed variants had rare cross-context data loss.
interface KVDBSchema extends DBSchema {
    kv: { key: string; value: unknown };
}

let _kvDB: ReturnType<typeof openKVDB> | undefined;

const openKVDB = async () => {
    const db = await openDB<KVDBSchema>("kv", 1, {
        upgrade(db) {
            db.createObjectStore("kv");
        },
        blocking() {
            log.info(
                "Another client is attempting to open a new version of KV DB",
            );
            db.close();
            _kvDB = undefined;
        },
        blocked() {
            log.warn(
                "Waiting for an existing client to close their connection so that we can update the KV DB version",
            );
        },
        terminated() {
            log.warn("Our connection to KV DB was unexpectedly terminated");
            _kvDB = undefined;
        },
    });

    return db;
};

const kvDB = () => (_kvDB ??= openKVDB());

// Terminate workers first; each execution context caches its own connection.
export const clearKVDB = async () => {
    try {
        if (_kvDB) (await _kvDB).close();
    } catch (e) {
        log.warn("Ignoring error when trying to close KV DB", e);
    }
    _kvDB = undefined;

    return deleteDB("kv", {
        blocked() {
            log.warn(
                "Waiting for an existing client to close their connection so that we can delete the KV DB",
            );
        },
    });
};

export const getKV = async (key: string) => {
    const db = await kvDB();
    return db.get("kv", key);
};

const _getKV = async <T extends string | number | boolean>(
    key: string,
    type: string,
): Promise<T | undefined> => {
    const db = await kvDB();
    const v = await db.get("kv", key);
    if (v === undefined) return undefined;
    if (typeof v != type)
        throw new Error(
            // Best-effort diagnostic only.
            // eslint-disable-next-line @typescript-eslint/no-base-to-string
            `Expected the value corresponding to key ${key} to be a ${type}, but instead got ${String(v)}`,
        );
    return v as T;
};

export const getKVS = async (key: string) => _getKV<string>(key, "string");

export const getKVN = async (key: string) => _getKV<number>(key, "number");

export const getKVB = async (key: string) => _getKV<boolean>(key, "boolean");

export const setKV = async (key: string, value: unknown) => {
    const db = await kvDB();
    await db.put("kv", value, key);
};

export const removeKV = async (key: string) => {
    const db = await kvDB();
    await db.delete("kv", key);
};
