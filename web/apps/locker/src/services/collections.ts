import { ensureLocalUser } from "ente-accounts/services/user";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { encryptBox, encryptBoxBytes, generateKey } from "ente-locker-wasm";
import { findCollectionByType, getCollectionRecord } from "./locker-cache";
import { RemoteCollectionCreateResponseSchema } from "./remote-types";
import { decryptCollectionKey } from "./sync/decrypt";
import { fetchLockerData } from "./sync/sync";

const ensureCollectionWithType = async (
    name: string,
    type: string,
    masterKey: string,
) => {
    const currentUserID = ensureLocalUser().id;
    let collection = findCollectionByType(type, currentUserID);
    if (collection) {
        return collection;
    }

    await createCollection(name, masterKey, type);
    await fetchLockerData();

    collection = findCollectionByType(type, currentUserID);
    if (!collection) {
        throw new Error(`Failed to create ${name} collection`);
    }

    return collection;
};

export const createCollection = async (
    name: string,
    masterKey: string,
    type = "folder",
): Promise<number> => {
    const collectionKey = await generateKey();
    const encryptedKey = await encryptBox(collectionKey, masterKey);
    const encryptedName = await encryptBoxBytes(
        new TextEncoder().encode(name),
        collectionKey,
    );

    const res = await fetch(await apiURL("/collections"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            encryptedKey: encryptedKey.encryptedData,
            keyDecryptionNonce: encryptedKey.nonce,
            encryptedName: encryptedName.encryptedData,
            nameDecryptionNonce: encryptedName.nonce,
            type,
        }),
    });
    ensureOk(res);
    const data = RemoteCollectionCreateResponseSchema.parse(await res.json());
    return data.collection.id;
};

export const ensureUncategorizedCollection = (masterKey: string) =>
    ensureCollectionWithType("Uncategorized", "uncategorized", masterKey);

export const ensureFavoritesCollection = (masterKey: string) =>
    ensureCollectionWithType("Important", "favorites", masterKey);

export const renameCollection = async (
    collectionID: number,
    newName: string,
): Promise<void> => {
    const collectionRecord = getCollectionRecord(collectionID);
    if (!collectionRecord) {
        throw new Error(`Collection ${collectionID} not in cache`);
    }

    const collectionKey = await decryptCollectionKey(collectionRecord);
    const encryptedName = await encryptBoxBytes(
        new TextEncoder().encode(newName),
        collectionKey,
    );

    const res = await fetch(await apiURL("/collections/rename"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            collectionID,
            encryptedName: encryptedName.encryptedData,
            nameDecryptionNonce: encryptedName.nonce,
        }),
    });
    ensureOk(res);
};

export const deleteCollection = async (
    collectionID: number,
    opts?: { keepFiles?: boolean },
): Promise<void> => {
    const keepFiles = opts?.keepFiles ?? false;
    const res = await fetch(
        await apiURL(`/collections/v3/${collectionID}`, {
            collectionID,
            keepFiles,
        }),
        { method: "DELETE", headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
};

export const resolveCollectionIDsWithUncategorizedFallback = async (
    collectionIDs: number[],
    masterKey: string,
) =>
    collectionIDs.length > 0
        ? Array.from(new Set(collectionIDs))
        : [(await ensureUncategorizedCollection(masterKey)).id];
