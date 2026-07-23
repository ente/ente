import type {
    LockerCollection,
    LockerCollectionParticipant,
    LockerItem,
} from "@/types";
import {
    ensureLocalUser,
    ensureUserKeyPair,
} from "ente-accounts-rs/services/user";
import {
    authenticatedRequestHeaders,
    ensureOk,
    publicRequestHeaders,
} from "ente-base/http";
import log from "ente-base/log";
import { apiURL, customAPIOrigin } from "ente-base/origins";
import { ensureAuthToken } from "ente-base/token";
import { z } from "zod";
import {
    boxSealOpen,
    createStreamDecryptor,
    decryptBox,
    decryptBoxBytes,
    decryptMetadataJSON,
    encryptBox,
    stringToB64,
} from "./crypto";
import { fromInfoTypeWireValue } from "./info-type-wire";
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
} from "./locker-db";
import {
    type EncryptedCollectionRecord,
    type EncryptedFileRecord,
    type LockerCollectionPayload,
    type LockerEncryptedCache,
    getEncryptedFileRecord,
    getLockerCacheSnapshot,
    replaceLockerCache,
    setEncryptedFileRecord,
} from "./remote-cache";
import {
    RemoteCollectionUserSchema,
    toLockerCollectionParticipant,
} from "./remote-types";

const RemoteMagicMetadata = z.object({
    version: z.number(),
    count: z.number().optional(),
    data: z.string(),
    header: z.string(),
});

const RemoteCollection = z.object({
    id: z.number(),
    owner: RemoteCollectionUserSchema,
    encryptedKey: z.string(),
    keyDecryptionNonce: z.string().nullish(),
    encryptedName: z.string().nullish(),
    nameDecryptionNonce: z.string().nullish(),
    name: z.string().nullish(),
    type: z.string(),
    sharees: z.array(RemoteCollectionUserSchema).nullish(),
    publicURLs: z.array(z.unknown()).nullish(),
    updationTime: z.number(),
    isDeleted: z.boolean().nullish(),
    magicMetadata: RemoteMagicMetadata.nullish(),
    pubMagicMetadata: RemoteMagicMetadata.nullish(),
    sharedMagicMetadata: RemoteMagicMetadata.nullish(),
});

type RemoteCollection = z.infer<typeof RemoteCollection>;

const CollectionsResponse = z.object({
    collections: z.array(RemoteCollection),
});

const RemoteEncryptedMetadata = z.object({
    encryptedData: z.string(),
    decryptionHeader: z.string(),
});

const RemoteFileObjectAttributes = z.object({ decryptionHeader: z.string() });

const RemoteFile = z.object({
    id: z.number(),
    collectionID: z.number(),
    ownerID: z.number().optional(),
    encryptedKey: z.string(),
    keyDecryptionNonce: z.string(),
    file: RemoteFileObjectAttributes,
    thumbnail: RemoteFileObjectAttributes.optional(),
    metadata: RemoteEncryptedMetadata,
    magicMetadata: z
        .object({
            version: z.number(),
            count: z.number().optional(),
            data: z.string(),
            header: z.string(),
        })
        .nullish(),
    pubMagicMetadata: z
        .object({
            version: z.number(),
            count: z.number().optional(),
            data: z.string(),
            header: z.string(),
        })
        .nullish(),
    updationTime: z.number(),
    isDeleted: z.boolean(),
    info: z.object({ fileSize: z.number().optional() }).nullish(),
});

type RemoteFile = z.infer<typeof RemoteFile>;

const FileDiffResponse = z.object({
    diff: z.array(RemoteFile),
    hasMore: z.boolean(),
});

const RemoteTrashItem = z.object({
    file: RemoteFile,
    isDeleted: z.boolean(),
    isRestored: z.boolean(),
    updatedAt: z.number(),
    deleteBy: z.number(),
});

const TrashDiffResponse = z.object({
    diff: z.array(RemoteTrashItem),
    hasMore: z.boolean(),
});

interface DecryptAllDataResult {
    collections: LockerCollection[];
    failedCollectionIDs: number[];
    totalCollectionCount: number;
}

export interface LockerTrashData {
    items: LockerItem[];
    lastUpdatedAt: number;
}

export interface LockerHydratedState {
    collections: LockerCollection[];
    trashItems: LockerItem[];
    trashLastUpdatedAt: number;
    collectionsSinceTime: number;
    trashSinceTime: number;
}

export interface LockerPersistedState extends LockerHydratedState {
    hasPersistedState: boolean;
}

const COLLECTION_PAYLOAD_VERSION = 1;
const collectionTextDecoder = new TextDecoder();
const DOWNLOAD_URL_REVOKE_DELAY_MS = 30_000;

const describeCryptoError = (error: unknown): string => {
    if (typeof error === "object" && error && "code" in error) {
        const code = typeof error.code === "string" ? error.code : "unknown";
        const message =
            "message" in error && typeof error.message === "string"
                ? error.message
                : "unknown";
        return `code=${code}, msg=${message}`;
    }
    if (error instanceof Error) {
        return error.message;
    }
    return String(error);
};

const toEpochMicroseconds = (timestamp: unknown) => {
    if (typeof timestamp !== "number") {
        return undefined;
    }

    // Locker mobile stores metadata timestamps in epoch milliseconds while
    // server structural timestamps use epoch microseconds.
    return timestamp < 100_000_000_000_000 ? timestamp * 1000 : timestamp;
};

const buildEncryptedFileRecord = (file: RemoteFile): EncryptedFileRecord => ({
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
    const encryptedPayload = await encryptBox(
        stringToB64(JSON.stringify(payload)),
        collectionKey,
    );

    return {
        payloadEncryptedData: encryptedPayload.encryptedData,
        payloadDecryptionNonce: encryptedPayload.nonce,
        payloadVersion: COLLECTION_PAYLOAD_VERSION,
    };
};

const toEncryptedCollectionRecord = (
    collection: RemoteCollection,
    masterKey: string,
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
        const collectionKey = await decryptCollectionKey(record, masterKey);
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

const decryptStoredTrash = async (
    masterKey: string,
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
            const collectionKey = await decryptCollectionKey(
                collectionRecord,
                masterKey,
            );
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

const buildStoredTrashFileRecord = (
    entry: z.infer<typeof RemoteTrashItem>,
): StoredTrashFileRecord => ({
    ...buildEncryptedFileRecord(entry.file),
    updatedAt: entry.updatedAt,
    deleteBy: entry.deleteBy,
});

export const decryptCollectionKey = async (
    record: EncryptedCollectionRecord,
    masterKey: string,
): Promise<string> => {
    const currentUserID = ensureLocalUser().id;
    if (record.ownerID === currentUserID) {
        return decryptBox(
            {
                encryptedData: record.encryptedKey,
                nonce: record.keyDecryptionNonce!,
            },
            masterKey,
        );
    }

    return boxSealOpen(record.encryptedKey, await ensureUserKeyPair());
};

const decryptFileKeyForRecordFromCollections = async (
    record: EncryptedFileRecord,
    masterKey: string,
    collections: Map<number, EncryptedCollectionRecord>,
): Promise<string> => {
    const collectionRecord = collections.get(record.collectionID);
    if (!collectionRecord) {
        throw new Error(`Collection ${record.collectionID} not found in cache`);
    }

    const collectionKey = await decryptCollectionKey(
        collectionRecord,
        masterKey,
    );
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
    masterKey: string,
): Promise<string> => {
    const cacheSnapshot = getLockerCacheSnapshot();
    return decryptFileKeyForRecordFromCollections(
        record,
        masterKey,
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
                // Public metadata can be missing or unreadable for some older
                // files. We still want to surface the file row if basic
                // metadata decrypts successfully.
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

const decryptAllData = async (
    masterKey: string,
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
            const collectionKey = await decryptCollectionKey(
                collectionRecord,
                masterKey,
            );
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
    masterKey: string,
    collections: Map<number, EncryptedCollectionRecord>,
    files: EncryptedFileRecord[],
    trashFiles: StoredTrashFileRecord[],
    trashLastUpdatedAt: number,
): Promise<LockerHydratedState> => {
    const activeCache = buildLockerCache(collections, files, []);

    const decrypted = await decryptAllData(masterKey, activeCache);
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
        masterKey,
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

export const loadPersistedLockerState = async (
    masterKey: string,
): Promise<LockerPersistedState> => {
    const snapshot = await loadLockerSnapshotFromDB();
    const hydrated = await hydrateLockerState(
        masterKey,
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

export const syncLockerState = async (
    masterKey: string,
): Promise<LockerHydratedState> => {
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
        const record = await toEncryptedCollectionRecord(change, masterKey);
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
        masterKey,
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

export const fetchLockerData = async (
    masterKey: string,
): Promise<LockerCollection[]> =>
    (await syncLockerState(masterKey)).collections;

export const fetchLockerTrash = async (
    masterKey: string,
): Promise<LockerTrashData> => {
    const state = await syncLockerState(masterKey);
    return { items: state.trashItems, lastUpdatedAt: state.trashLastUpdatedAt };
};

export const downloadLockerFile = async (
    fileID: number,
    fileName: string,
    masterKey: string,
    onProgress?: (progress: { loaded: number; total?: number }) => void,
): Promise<void> => {
    const fileRecord = getEncryptedFileRecord(fileID);
    if (!fileRecord) {
        log.error(`Locker download missing file record ${fileID}`);
        throw new Error(`File ${fileID} not found in cache`);
    }

    log.info(
        `Locker download start ${fileID}: hasObject=${fileRecord.hasObject} size=${fileRecord.fileSize ?? "unknown"}`,
    );

    const cacheSnapshot = getLockerCacheSnapshot();
    const collectionRecord = cacheSnapshot.collections.get(
        fileRecord.collectionID,
    );
    if (!collectionRecord) {
        log.error(
            `Locker download missing collection record ${fileID}: collectionID=${fileRecord.collectionID}`,
        );
        throw new Error(
            `Collection ${fileRecord.collectionID} not found in cache`,
        );
    }

    let fileKey: string;
    try {
        const collectionKey = await decryptCollectionKey(
            collectionRecord,
            masterKey,
        );
        fileKey = await decryptBox(
            {
                encryptedData: fileRecord.encryptedKey,
                nonce: fileRecord.keyDecryptionNonce,
            },
            collectionKey,
        );
    } catch (error) {
        log.error(
            `Locker download key preparation failed ${fileID}: collectionID=${fileRecord.collectionID}`,
            error,
        );
        throw error;
    }

    const customOrigin = await customAPIOrigin();
    const downloadSource = customOrigin ? "api" : "proxy";
    let response: Response;
    try {
        if (customOrigin) {
            const token = await ensureAuthToken();
            const url = await apiURL(`/files/download/${fileID}`, { token });
            response = await fetch(url, { headers: publicRequestHeaders() });
        } else {
            response = await fetch(`https://files.ente.com/?fileID=${fileID}`, {
                headers: await authenticatedRequestHeaders(),
            });
        }
    } catch (error) {
        log.error(
            `Locker download request failed ${fileID}: source=${downloadSource}`,
            error,
        );
        throw error;
    }
    ensureOk(response);
    log.info(
        `Locker download response ${fileID}: source=${downloadSource} status=${response.status} redirected=${response.redirected} contentType=${response.headers.get("Content-Type") ?? "unknown"} contentLength=${response.headers.get("Content-Length") ?? "unknown"}`,
    );

    const body = response.body;
    if (!body) {
        log.error(
            `Locker download empty response body ${fileID}: source=${downloadSource} status=${response.status}`,
        );
        throw new Error("Download response body is empty");
    }

    const reader = body.getReader();
    const contentLength =
        parseInt(response.headers.get("Content-Length") ?? "", 10) || 0;
    let downloadedBytes = 0;

    onProgress?.({
        loaded: 0,
        total: contentLength > 0 ? contentLength : undefined,
    });

    const streamDecryptor = await createStreamDecryptor(
        fileRecord.fileDecryptionHeader,
        fileKey,
    );
    let leftoverBytes = new Uint8Array();

    const decryptedStream = new ReadableStream<Uint8Array>({
        pull: async (controller) => {
            let didEnqueue = false;
            try {
                do {
                    const { done, value } = await reader.read();
                    let data: Uint8Array;
                    if (done) {
                        data = leftoverBytes;
                    } else {
                        downloadedBytes += value.length;
                        onProgress?.({
                            loaded: downloadedBytes,
                            total:
                                contentLength > 0 ? contentLength : undefined,
                        });
                        data = new Uint8Array(
                            leftoverBytes.length + value.length,
                        );
                        data.set(leftoverBytes, 0);
                        data.set(value, leftoverBytes.length);
                    }

                    while (data.length >= streamDecryptor.decryptionChunkSize) {
                        const decryptedChunk =
                            await streamDecryptor.decryptChunk(
                                data.slice(
                                    0,
                                    streamDecryptor.decryptionChunkSize,
                                ),
                            );
                        controller.enqueue(decryptedChunk);
                        didEnqueue = true;
                        data = data.slice(streamDecryptor.decryptionChunkSize);
                    }

                    if (done) {
                        if (data.length > 0) {
                            const decryptedChunk =
                                await streamDecryptor.decryptChunk(data);
                            controller.enqueue(decryptedChunk);
                        }
                        if (!streamDecryptor.isFinalized()) {
                            throw new Error(
                                "Download stream truncated before final chunk",
                            );
                        }
                        onProgress?.({
                            loaded:
                                contentLength > 0
                                    ? contentLength
                                    : downloadedBytes,
                            total:
                                contentLength > 0 ? contentLength : undefined,
                        });
                        streamDecryptor.free();
                        controller.close();
                        didEnqueue = true;
                    } else {
                        leftoverBytes = new Uint8Array(data);
                    }
                } while (!didEnqueue);
            } catch (error) {
                log.error(
                    `Locker download stream failed ${fileID}: source=${downloadSource} downloaded=${downloadedBytes} total=${contentLength > 0 ? contentLength : "unknown"} leftover=${leftoverBytes.length}`,
                    error,
                );
                streamDecryptor.free();
                controller.error(error);
            }
        },
        cancel: () => {
            log.warn(
                `Locker download stream cancelled ${fileID}: source=${downloadSource} downloaded=${downloadedBytes} total=${contentLength > 0 ? contentLength : "unknown"}`,
            );
            streamDecryptor.free();
            void reader.cancel();
        },
    });

    let decryptedData: Blob;
    try {
        decryptedData = await new Response(decryptedStream).blob();
    } catch (error) {
        log.error(
            `Locker download blob assembly failed ${fileID}: source=${downloadSource} downloaded=${downloadedBytes} total=${contentLength > 0 ? contentLength : "unknown"}`,
            error,
        );
        throw error;
    }
    log.info(
        `Locker download decrypted ${fileID}: source=${downloadSource} downloaded=${downloadedBytes} blobSize=${decryptedData.size}`,
    );
    const url = URL.createObjectURL(decryptedData);
    const anchor = document.createElement("a");
    anchor.style.display = "none";
    anchor.href = url;
    anchor.download = fileName;
    document.body.appendChild(anchor);
    anchor.click();
    log.info(
        `Locker download triggered save ${fileID}: source=${downloadSource}`,
    );
    setTimeout(() => URL.revokeObjectURL(url), DOWNLOAD_URL_REVOKE_DELAY_MS);
    anchor.remove();
};
