import type { LockerCollectionParticipant } from "@/types";

export interface LockerCollectionPayload {
    owner: LockerCollectionParticipant;
    sharees: LockerCollectionParticipant[];
    name?: string;
}

/**
 * A collection record stored in the Locker cache. The persisted form keeps only
 * structural metadata plus encrypted fields. Decrypted collection details can
 * be attached transiently in-memory via `payload`, but must never be written to
 * IndexedDB.
 */
export interface EncryptedCollectionRecord {
    /** Collection ID. */
    id: number;
    /** Owner user ID (plaintext — structural metadata only). */
    ownerID: number;
    /** Encrypted collection key (base64). */
    encryptedKey: string;
    /** Nonce for key decryption (base64), null for shared collections. */
    keyDecryptionNonce: string | undefined;
    /** Encrypted collection name (base64). */
    encryptedName: string | undefined;
    /** Nonce for name decryption (base64). */
    nameDecryptionNonce: string | undefined;
    /**
     * Locally encrypted collection payload that mirrors mobile's encrypted
     * collection payload storage for name and participant metadata.
     */
    payloadEncryptedData?: string;
    /** Nonce for local collection payload decryption. */
    payloadDecryptionNonce?: string;
    /** Version of the local encrypted collection payload. */
    payloadVersion?: number;
    /** Collection type (structural metadata). */
    type: string;
    /** Whether this collection is deleted on remote (key still needed for trash restore). */
    isDeleted: boolean;
    /** Updation time (structural metadata). */
    updationTime: number;
    /** Transient decrypted collection details kept only in memory. */
    payload?: LockerCollectionPayload;
}

/**
 * An encrypted file record stored in-memory. All sensitive payloads remain
 * encrypted until explicitly decrypted for display.
 */
export interface EncryptedFileRecord {
    /** File ID (structural metadata). */
    id: number;
    /** Collection this file belongs to (structural metadata). */
    collectionID: number;
    /** Owner of the file, when provided by remote. */
    ownerID?: number;
    /** Encrypted file key (base64). */
    encryptedKey: string;
    /** Nonce for file key decryption (base64). */
    keyDecryptionNonce: string;
    /** Decryption header for the actual file content blob on S3. */
    fileDecryptionHeader: string;
    /** Whether the file has a downloadable backing object. */
    hasObject: boolean;
    /** File size in bytes, when provided by the API. */
    fileSize?: number;
    /** Encrypted file metadata. */
    metadata: { encryptedData: string; decryptionHeader: string };
    /** Encrypted private magic metadata, if present. */
    magicMetadata?: { version: number; data: string; header: string };
    /** Encrypted public magic metadata, if present. */
    pubMagicMetadata?: { version: number; data: string; header: string };
    /** Updation time (structural metadata). */
    updationTime: number;
}

export interface LockerEncryptedCache {
    collections: Map<number, EncryptedCollectionRecord>;
    files: Map<number, Map<number, EncryptedFileRecord>>;
}

/** In-memory cache: collectionID → EncryptedCollectionRecord */
let encryptedCollections = new Map<number, EncryptedCollectionRecord>();

/** In-memory cache: fileID → (collectionID → EncryptedFileRecord) */
let encryptedFiles = new Map<number, Map<number, EncryptedFileRecord>>();

export const createEmptyLockerCache = (): LockerEncryptedCache => ({
    collections: new Map<number, EncryptedCollectionRecord>(),
    files: new Map<number, Map<number, EncryptedFileRecord>>(),
});

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

export const getCollectionRecords = () => [...encryptedCollections.values()];

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

export const getAllEncryptedFileRecords = (): EncryptedFileRecord[] =>
    [...encryptedFiles.values()].flatMap((records) => [...records.values()]);

export const getCollectionIDsForFile = (fileID: number): number[] => {
    const records = encryptedFiles.get(fileID);
    return records ? [...records.keys()] : [];
};

export const mergeEncryptedFileRecordsIntoCache = (
    records: EncryptedFileRecord[],
) => {
    if (records.length === 0) {
        return;
    }

    const nextFiles = new Map(encryptedFiles);
    for (const record of records) {
        const existingRecords =
            nextFiles.get(record.id) ?? new Map<number, EncryptedFileRecord>();
        const nextRecords = new Map(existingRecords);
        nextRecords.set(record.collectionID, record);
        nextFiles.set(record.id, nextRecords);
    }
    encryptedFiles = nextFiles;
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
