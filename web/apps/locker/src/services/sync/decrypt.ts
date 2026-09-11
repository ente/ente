import type {
    LockerCollection,
    LockerCollectionParticipant,
    LockerItem,
} from "@/types";
import log from "ente-base/log";
import {
    decryptBox,
    decryptBoxBytes,
    decryptMetadataJSON,
    encryptBoxBytes,
    openCollectionKey,
} from "ente-locker-wasm";
import type { z } from "zod";
import { ensureAuthenticatedSession } from "../authenticated-session";
import { fromInfoTypeWireValue } from "../info-type-wire";
import {
    type EncryptedCollectionRecord,
    type EncryptedFileRecord,
    type LockerCollectionPayload,
    type LockerEncryptedCache,
    getLockerCacheSnapshot,
} from "../locker-cache";
import type { StoredTrashFileRecord } from "../locker-db";
import { toLockerCollectionParticipant } from "../remote-types";
import type { RemoteCollection, RemoteFile, RemoteTrashItem } from "./schemas";

interface DecryptAllDataResult {
    collections: LockerCollection[];
    failedCollectionIDs: number[];
    totalCollectionCount: number;
}

export interface LockerTrashData {
    items: LockerItem[];
    lastUpdatedAt: number;
}

const COLLECTION_PAYLOAD_VERSION = 1;

const collectionTextDecoder = new TextDecoder();

const describeCryptoError = (error: unknown) =>
    error instanceof Error ? error.message : String(error);

const toEpochMicroseconds = (timestamp: unknown) => {
    if (typeof timestamp !== "number") {
        return undefined;
    }

    // Locker mobile stores metadata timestamps in epoch milliseconds while
    // server structural timestamps use epoch microseconds.
    return timestamp < 100_000_000_000_000 ? timestamp * 1000 : timestamp;
};

export const buildEncryptedFileRecord = (
    file: RemoteFile,
): EncryptedFileRecord => ({
    id: file.id,
    collectionID: file.collectionID,
    ownerID: file.ownerID ?? undefined,
    encryptedKey: file.encryptedKey,
    keyDecryptionNonce: file.keyDecryptionNonce,
    fileDecryptionHeader: file.file.decryptionHeader,
    hasObject: file.file.decryptionHeader.length > 0,
    fileSize: file.info?.fileSize,
    metadata: {
        encryptedData: file.metadata.encryptedData,
        decryptionHeader: file.metadata.decryptionHeader,
    },
    magicMetadata: file.magicMetadata
        ? {
              version: file.magicMetadata.version,
              data: file.magicMetadata.data,
              header: file.magicMetadata.header,
          }
        : undefined,
    pubMagicMetadata: file.pubMagicMetadata
        ? {
              version: file.pubMagicMetadata.version,
              data: file.pubMagicMetadata.data,
              header: file.pubMagicMetadata.header,
          }
        : undefined,
    updationTime: file.updationTime,
});

const normalizeCollectionParticipant = (
    value: unknown,
    fallback?: Partial<LockerCollectionParticipant> & { id: number },
): LockerCollectionParticipant | undefined => {
    const participant =
        typeof value === "object" && value
            ? (value as Record<string, unknown>)
            : undefined;
    const id =
        typeof participant?.id === "number" ? participant.id : fallback?.id;
    if (id === undefined) {
        return undefined;
    }

    const email =
        typeof participant?.email === "string"
            ? participant.email
            : fallback?.email;
    const role =
        typeof participant?.role === "string"
            ? participant.role
            : fallback?.role;

    return {
        id,
        email: email || undefined,
        role: role
            ? (role.toUpperCase() as LockerCollectionParticipant["role"])
            : undefined,
    };
};

const fallbackCollectionPayload = (
    record: Pick<EncryptedCollectionRecord, "ownerID" | "payload">,
): LockerCollectionPayload => ({
    owner: record.payload?.owner ?? { id: record.ownerID, role: "OWNER" },
    sharees: record.payload?.sharees ?? [],
    name: record.payload?.name,
});

const decryptCollectionPayload = async (
    record: EncryptedCollectionRecord,
    collectionKey: string,
): Promise<LockerCollectionPayload | undefined> => {
    if (record.payload) {
        return record.payload;
    }

    if (!record.payloadEncryptedData || !record.payloadDecryptionNonce) {
        return undefined;
    }

    try {
        const payloadBytes = await decryptBoxBytes(
            {
                encryptedData: record.payloadEncryptedData,
                nonce: record.payloadDecryptionNonce,
            },
            collectionKey,
        );
        const payload = JSON.parse(
            collectionTextDecoder.decode(payloadBytes),
        ) as unknown;
        const payloadObject =
            typeof payload === "object" && payload
                ? (payload as Record<string, unknown>)
                : undefined;
        const owner = normalizeCollectionParticipant(payloadObject?.owner, {
            id: record.ownerID,
            role: "OWNER",
        }) ?? { id: record.ownerID, role: "OWNER" };
        const sharees = Array.isArray(payloadObject?.sharees)
            ? payloadObject.sharees
                  .map((sharee) => normalizeCollectionParticipant(sharee))
                  .filter(
                      (
                          participant,
                      ): participant is LockerCollectionParticipant =>
                          participant !== undefined,
                  )
            : [];
        const name =
            typeof payloadObject?.name === "string" && payloadObject.name
                ? payloadObject.name
                : undefined;

        return { owner, sharees, name };
    } catch (error) {
        log.error(
            `Failed to decrypt collection payload for ${record.id}`,
            error,
        );
        return undefined;
    }
};

const decryptCollectionNameFromRemote = async (
    collectionID: number,
    encryptedName: string | undefined,
    nameDecryptionNonce: string | undefined,
    collectionKey: string,
): Promise<string | undefined> => {
    if (!encryptedName || !nameDecryptionNonce) {
        return undefined;
    }

    try {
        const nameBytes = await decryptBoxBytes(
            { encryptedData: encryptedName, nonce: nameDecryptionNonce },
            collectionKey,
        );
        return collectionTextDecoder.decode(nameBytes);
    } catch (error) {
        log.error(
            `Failed to decrypt collection name for ${collectionID}`,
            error,
        );
        return undefined;
    }
};

const encryptCollectionPayload = async (
    payload: LockerCollectionPayload,
    collectionKey: string,
) => {
    const encryptedPayload = await encryptBoxBytes(
        new TextEncoder().encode(JSON.stringify(payload)),
        collectionKey,
    );

    return {
        payloadEncryptedData: encryptedPayload.encryptedData,
        payloadDecryptionNonce: encryptedPayload.nonce,
        payloadVersion: COLLECTION_PAYLOAD_VERSION,
    };
};

export const toEncryptedCollectionRecord = (
    collection: RemoteCollection,
): Promise<EncryptedCollectionRecord> => {
    const record: EncryptedCollectionRecord = {
        id: collection.id,
        ownerID: collection.owner.id,
        encryptedKey: collection.encryptedKey,
        keyDecryptionNonce: collection.keyDecryptionNonce ?? undefined,
        encryptedName: collection.encryptedName ?? undefined,
        nameDecryptionNonce: collection.nameDecryptionNonce ?? undefined,
        type: collection.type,
        isDeleted: !!collection.isDeleted,
        updationTime: collection.updationTime,
    };

    const buildEncryptedRecord = async () => {
        const collectionKey = await decryptCollectionKey(record);
        const payload: LockerCollectionPayload = {
            owner: {
                ...toLockerCollectionParticipant(collection.owner),
                role: "OWNER",
            },
            sharees: (collection.sharees ?? []).map(
                toLockerCollectionParticipant,
            ),
            name:
                collection.name ??
                (await decryptCollectionNameFromRemote(
                    collection.id,
                    record.encryptedName,
                    record.nameDecryptionNonce,
                    collectionKey,
                )),
        };

        return {
            ...record,
            ...(await encryptCollectionPayload(payload, collectionKey)),
        };
    };

    return buildEncryptedRecord().catch((error: unknown) => {
        log.error(
            `Failed to locally encrypt collection payload for ${collection.id}`,
            error,
        );
        return record;
    });
};

const decryptCollectionDetails = async (
    record: EncryptedCollectionRecord,
    collectionKey: string,
): Promise<LockerCollectionPayload & { name: string }> => {
    const payload =
        (await decryptCollectionPayload(record, collectionKey)) ??
        fallbackCollectionPayload(record);
    const name =
        payload.name ??
        (await decryptCollectionNameFromRemote(
            record.id,
            record.encryptedName,
            record.nameDecryptionNonce,
            collectionKey,
        )) ??
        "Untitled";

    return { owner: payload.owner, sharees: payload.sharees, name };
};

export const decryptStoredTrash = async (
    cache: LockerEncryptedCache,
    trashFiles: StoredTrashFileRecord[],
    lastUpdatedAt: number,
): Promise<LockerTrashData> => {
    const trashItems: LockerItem[] = [];
    for (const record of trashFiles) {
        const collectionRecord = cache.collections.get(record.collectionID);
        if (!collectionRecord) {
            log.warn(
                `Skipping trash file ${record.id}: collection ${record.collectionID} not in cache`,
            );
            continue;
        }

        try {
            const collectionKey = await decryptCollectionKey(collectionRecord);
            const item = await decryptFileToLockerItem(
                record,
                collectionKey,
                collectionRecord.ownerID,
            );
            if (item) {
                trashItems.push({
                    ...item,
                    updatedAt: record.updatedAt,
                    deleteBy: record.deleteBy,
                });
            }
        } catch (error) {
            log.error(`Failed to decrypt trash file ${record.id}`, error);
        }
    }

    trashItems.sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0));
    return { items: trashItems, lastUpdatedAt };
};

export const buildStoredTrashFileRecord = (
    entry: z.infer<typeof RemoteTrashItem>,
): StoredTrashFileRecord => ({
    ...buildEncryptedFileRecord(entry.file),
    updatedAt: entry.updatedAt,
    deleteBy: entry.deleteBy,
});

export const decryptCollectionKey = async (
    record: EncryptedCollectionRecord,
): Promise<string> =>
    openCollectionKey(
        await ensureAuthenticatedSession(),
        record.ownerID,
        record.encryptedKey,
        record.keyDecryptionNonce,
    );

const decryptFileKeyForRecordFromCollections = async (
    record: EncryptedFileRecord,
    collections: Map<number, EncryptedCollectionRecord>,
): Promise<string> => {
    const collectionRecord = collections.get(record.collectionID);
    if (!collectionRecord) {
        throw new Error(`Collection ${record.collectionID} not found in cache`);
    }

    const collectionKey = await decryptCollectionKey(collectionRecord);
    return decryptBox(
        {
            encryptedData: record.encryptedKey,
            nonce: record.keyDecryptionNonce,
        },
        collectionKey,
    );
};

export const decryptFileKeyForRecord = async (
    record: EncryptedFileRecord,
): Promise<string> => {
    const cacheSnapshot = getLockerCacheSnapshot();
    return decryptFileKeyForRecordFromCollections(
        record,
        cacheSnapshot.collections,
    );
};

const decryptFileToLockerItem = async (
    record: EncryptedFileRecord,
    collectionKey: string,
    collectionOwnerID: number,
): Promise<LockerItem | undefined> => {
    try {
        const fileKey = await decryptBox(
            {
                encryptedData: record.encryptedKey,
                nonce: record.keyDecryptionNonce,
            },
            collectionKey,
        );

        const metadata = (await decryptMetadataJSON(
            record.metadata,
            fileKey,
        )) as Record<string, unknown> | undefined;

        let pubMagicMetadata: Record<string, unknown> | undefined;
        if (record.pubMagicMetadata) {
            try {
                pubMagicMetadata = (await decryptMetadataJSON(
                    {
                        encryptedData: record.pubMagicMetadata.data,
                        decryptionHeader: record.pubMagicMetadata.header,
                    },
                    fileKey,
                )) as Record<string, unknown> | undefined;
            } catch {
                // Older files may have unreadable public metadata.
                // Basic metadata is enough to keep the row.
            }
        }

        const info = pubMagicMetadata?.info as
            | { type?: string; data?: Record<string, unknown> }
            | undefined;

        const infoType =
            typeof info?.type === "string"
                ? fromInfoTypeWireValue(info.type)
                : undefined;
        const infoData = info?.data;

        if (infoType && infoData) {
            return {
                id: record.id,
                type: infoType,
                data: infoData as unknown as LockerItem["data"],
                collectionID: record.collectionID,
                collectionIDs: [record.collectionID],
                ownerID: record.ownerID ?? collectionOwnerID,
                createdAt: toEpochMicroseconds(metadata?.creationTime),
                updatedAt: record.updationTime,
            };
        }

        const editedName =
            typeof pubMagicMetadata?.editedName === "string"
                ? pubMagicMetadata.editedName
                : undefined;
        const metadataTitle =
            typeof metadata?.title === "string" ? metadata.title : undefined;
        const displayName = editedName ?? metadataTitle ?? "File";

        return {
            id: record.id,
            type: "file",
            data: {
                name: displayName,
                fileSize: record.fileSize,
                hasObject: record.hasObject,
            },
            collectionID: record.collectionID,
            collectionIDs: [record.collectionID],
            ownerID: record.ownerID ?? collectionOwnerID,
            createdAt: toEpochMicroseconds(metadata?.creationTime),
            updatedAt: record.updationTime,
        };
    } catch (error) {
        log.error(
            `Failed to decrypt file ${record.id}: ${describeCryptoError(error)}`,
        );
        return undefined;
    }
};

export const decryptAllData = async (
    cache: LockerEncryptedCache,
): Promise<DecryptAllDataResult> => {
    const activeCollectionRecords = [...cache.collections.values()].filter(
        (collection) => !collection.isDeleted,
    );
    const result: LockerCollection[] = [];
    const failedCollectionIDs: number[] = [];
    const totalCollectionCount = activeCollectionRecords.length;

    const filesByCollection = new Map<number, EncryptedFileRecord[]>();
    const collectionIDsByFileID = new Map<number, number[]>();
    for (const records of cache.files.values()) {
        const sharedCollectionIDs = [...records.keys()];
        for (const file of records.values()) {
            const existing = filesByCollection.get(file.collectionID) ?? [];
            existing.push(file);
            filesByCollection.set(file.collectionID, existing);
            collectionIDsByFileID.set(file.id, sharedCollectionIDs);
        }
    }

    for (const collectionRecord of activeCollectionRecords) {
        try {
            const collectionKey = await decryptCollectionKey(collectionRecord);
            const collectionDetails = await decryptCollectionDetails(
                collectionRecord,
                collectionKey,
            );
            const files = filesByCollection.get(collectionRecord.id) ?? [];
            const decryptedItems = await Promise.all(
                files.map((file) =>
                    decryptFileToLockerItem(
                        file,
                        collectionKey,
                        collectionRecord.ownerID,
                    ),
                ),
            );
            const items = decryptedItems
                .filter((item): item is LockerItem => item !== undefined)
                .map((item) => ({
                    ...item,
                    collectionIDs:
                        collectionIDsByFileID.get(item.id) ??
                        item.collectionIDs,
                }));

            result.push({
                id: collectionRecord.id,
                name: collectionDetails.name,
                owner: collectionDetails.owner,
                sharees: collectionDetails.sharees,
                items,
                type: collectionRecord.type,
                isShared: collectionDetails.sharees.length > 0,
            });
        } catch (error) {
            failedCollectionIDs.push(collectionRecord.id);
            log.error(
                `Failed to decrypt collection ${collectionRecord.id}: ${describeCryptoError(
                    error,
                )}`,
            );
        }
    }

    result.sort((a, b) => a.name.localeCompare(b.name));
    return { collections: result, failedCollectionIDs, totalCollectionCount };
};
