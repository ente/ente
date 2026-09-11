import type { LockerCollectionParticipant } from "@/types";

export interface LockerCollectionPayload {
    owner: LockerCollectionParticipant;
    sharees: LockerCollectionParticipant[];
    name?: string;
}

export interface EncryptedCollectionRecord {
    id: number;
    ownerID: number;
    encryptedKey: string;
    keyDecryptionNonce: string | undefined;
    encryptedName: string | undefined;
    nameDecryptionNonce: string | undefined;
    payloadEncryptedData?: string;
    payloadDecryptionNonce?: string;
    payloadVersion?: number;
    type: string;
    isDeleted: boolean;
    updationTime: number;
    // Transient decrypted details. These must stay in-memory only and must
    // never be written to IndexedDB.
    payload?: LockerCollectionPayload;
}

export interface EncryptedFileRecord {
    id: number;
    collectionID: number;
    ownerID?: number;
    encryptedKey: string;
    keyDecryptionNonce: string;
    fileDecryptionHeader: string;
    hasObject: boolean;
    fileSize?: number;
    metadata: { encryptedData: string; decryptionHeader: string };
    magicMetadata?: { version: number; data: string; header: string };
    pubMagicMetadata?: { version: number; data: string; header: string };
    updationTime: number;
}

export interface LockerEncryptedCache {
    collections: Map<number, EncryptedCollectionRecord>;
    files: Map<number, Map<number, EncryptedFileRecord>>;
}

let encryptedCollections = new Map<number, EncryptedCollectionRecord>();

let encryptedFiles = new Map<number, Map<number, EncryptedFileRecord>>();

export const setEncryptedFileRecord = (
    target: Map<number, Map<number, EncryptedFileRecord>>,
    record: EncryptedFileRecord,
) => {
    const existing =
        target.get(record.id) ?? new Map<number, EncryptedFileRecord>();
    existing.set(record.collectionID, record);
    target.set(record.id, existing);
};

export const getLockerCacheSnapshot = (): LockerEncryptedCache => ({
    collections: encryptedCollections,
    files: encryptedFiles,
});

export const replaceLockerCache = (cache: LockerEncryptedCache) => {
    encryptedCollections = cache.collections;
    encryptedFiles = cache.files;
};

export const clearLockerCache = () => {
    encryptedCollections = new Map();
    encryptedFiles = new Map();
};

export const getCollectionRecord = (collectionID: number) =>
    encryptedCollections.get(collectionID);

export const findCollectionByType = (type: string, ownerID?: number) =>
    [...encryptedCollections.values()].find(
        (candidate) =>
            candidate.type === type &&
            (ownerID === undefined || candidate.ownerID === ownerID),
    );

export const updateCollectionShareesInCache = (
    collectionID: number,
    sharees: LockerCollectionParticipant[],
) => {
    const record = encryptedCollections.get(collectionID);
    if (!record) {
        return;
    }

    encryptedCollections.set(collectionID, {
        ...record,
        payload: {
            owner: record.payload?.owner ?? {
                id: record.ownerID,
                role: "OWNER",
            },
            sharees,
            name: record.payload?.name,
        },
    });
};

export const getEncryptedFileRecord = (
    fileID: number,
    collectionID?: number,
): EncryptedFileRecord | undefined => {
    const records = encryptedFiles.get(fileID);
    if (!records) {
        return undefined;
    }
    if (collectionID !== undefined) {
        return records.get(collectionID);
    }
    return records.values().next().value;
};

export const getCollectionIDsForFile = (fileID: number): number[] => {
    const records = encryptedFiles.get(fileID);
    return records ? [...records.keys()] : [];
};

export const updateCachedPubMagicMetadata = (
    fileID: number,
    pubMagicMetadata: { version: number; data: string; header: string },
) => {
    const records = encryptedFiles.get(fileID);
    if (!records) {
        return;
    }

    encryptedFiles = new Map(encryptedFiles);
    encryptedFiles.set(
        fileID,
        new Map(
            [...records.entries()].map(([recordCollectionID, record]) => [
                recordCollectionID,
                { ...record, pubMagicMetadata },
            ]),
        ),
    );
};
