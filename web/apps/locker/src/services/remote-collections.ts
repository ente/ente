import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { encryptBox, generateKey, stringToB64 } from "ente-core-wasm";
import { RemoteCollectionCreateResponseSchema } from "./remote-types";

interface CollectionRecordLike {
    id: number;
    type: string;
}

interface RenameCollectionDeps<TCollectionRecord> {
    getCollectionRecord: (
        collectionID: number,
    ) => TCollectionRecord | undefined;
    decryptCollectionKey: (
        collectionRecord: TCollectionRecord,
        masterKey: string,
    ) => Promise<string>;
}

interface EnsureUncategorizedDeps<TCollectionRecord> {
    findCollectionByType: (type: string) => TCollectionRecord | undefined;
    refetchCollections: (masterKey: string) => Promise<void>;
}

const ensureCollectionWithTypeWithDeps = async <
    TCollectionRecord extends CollectionRecordLike,
>(
    name: string,
    type: string,
    masterKey: string,
    deps: EnsureUncategorizedDeps<TCollectionRecord>,
): Promise<TCollectionRecord> => {
    let collection = deps.findCollectionByType(type);
    if (collection) {
        return collection;
    }

    await createCollectionWithDeps(name, masterKey, type);
    await deps.refetchCollections(masterKey);

    collection = deps.findCollectionByType(type);
    if (!collection) {
        throw new Error(`Failed to create ${name} collection`);
    }

    return collection;
};

export const createCollectionWithDeps = async (
    name: string,
    masterKey: string,
    type = "folder",
): Promise<number> => {
    const collectionKey = await generateKey();
    const encryptedKey = await encryptBox(collectionKey, masterKey);
    const nameB64 = stringToB64(name);
    const encryptedName = await encryptBox(nameB64, collectionKey);

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

export const ensureUncategorizedCollectionWithDeps = async <
    TCollectionRecord extends CollectionRecordLike,
>(
    masterKey: string,
    deps: EnsureUncategorizedDeps<TCollectionRecord>,
): Promise<TCollectionRecord> =>
    ensureCollectionWithTypeWithDeps(
        "Uncategorized",
        "uncategorized",
        masterKey,
        deps,
    );

export const ensureFavoritesCollectionWithDeps = async <
    TCollectionRecord extends CollectionRecordLike,
>(
    masterKey: string,
    deps: EnsureUncategorizedDeps<TCollectionRecord>,
): Promise<TCollectionRecord> =>
    ensureCollectionWithTypeWithDeps("Important", "favorites", masterKey, deps);

export const renameCollectionWithDeps = async <TCollectionRecord>(
    collectionID: number,
    newName: string,
    masterKey: string,
    deps: RenameCollectionDeps<TCollectionRecord>,
): Promise<void> => {
    const collectionRecord = deps.getCollectionRecord(collectionID);
    if (!collectionRecord) {
        throw new Error(`Collection ${collectionID} not in cache`);
    }

    const collectionKey = await deps.decryptCollectionKey(
        collectionRecord,
        masterKey,
    );
    const nameB64 = stringToB64(newName);
    const encryptedName = await encryptBox(nameB64, collectionKey);

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

export const deleteCollectionWithDeps = async (
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
