/**
 * @file Service layer for fetching, decrypting, and caching Locker data.
 *
 * Follows the mobile app's encryption-at-rest pattern: all Locker metadata
 * stored locally in the browser (IndexedDB plus the in-memory cache) remains
 * encrypted. Decryption happens only in-memory at read time and decrypted
 * values are never persisted.
 *
 * Key hierarchy (mirrors mobile):
 *   masterKey → collectionKey → fileKey → file metadata (pubMagicMetadata)
 */

import type {
    LockerCollection,
    LockerCollectionParticipant,
    LockerItem,
    LockerItemType,
} from "@/types";
import { deriveInteractiveKey } from "ente-accounts-rs/services/crypto";
import {
    ensureLocalUser,
    ensureUserKeyPair,
} from "ente-accounts-rs/services/user";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import { z } from "zod";
import {
    b64ToBytes,
    boxSeal,
    boxSealOpen,
    decryptBox,
    decryptMetadataJSON,
    encryptBlob,
    encryptBox,
    generateKey,
    stringToB64,
} from "./crypto";
import {
    clearLockerCache,
    findCollectionByType,
    getCollectionIDsForFile,
    getCollectionRecord,
    getEncryptedFileRecord,
    updateCachedPubMagicMetadata,
    updateCollectionShareesInCache,
} from "./remote-cache";
import {
    deleteCollectionKeepingFilesWithDeps,
    type EncryptedCollectionFileItem,
    updateItemCollectionsWithDeps,
} from "./remote-collection-mutations";
import {
    fetchCollectionShareesWithDeps,
    shareCollectionWithDeps,
    unshareCollectionWithDeps,
} from "./remote-collection-sharing";
import {
    createCollectionWithDeps,
    deleteCollectionWithDeps,
    ensureFavoritesCollectionWithDeps,
    ensureUncategorizedCollectionWithDeps,
    renameCollectionWithDeps,
} from "./remote-collections";
import {
    decryptCollectionKey,
    decryptFileKeyForRecord,
    downloadLockerFile,
    fetchLockerData,
    fetchLockerTrash,
    loadPersistedLockerState,
    syncLockerState,
} from "./remote-read";
import { RemoteIDResponseSchema } from "./remote-types";
import {
    type LockerUploadProgress,
    uploadLockerFileWithDeps,
} from "./remote-uploads";

export {
    clearLockerCache,
    downloadLockerFile,
    fetchLockerData,
    fetchLockerTrash,
    loadPersistedLockerState,
    syncLockerState,
};

const utf8Decoder = new TextDecoder();

const RemoteFileShareLink = z.object({
    linkID: z.union([z.string(), z.number().transform(String)]),
    url: z.string(),
    ownerID: z.number(),
    fileID: z.number(),
    isDisabled: z.boolean().optional(),
    validTill: z.number().nullish(),
    deviceLimit: z.number().nullish(),
    passwordEnabled: z.boolean(),
    nonce: z.string().nullish(),
    memLimit: z.number().nullish(),
    opsLimit: z.number().nullish(),
    enableDownload: z.boolean(),
    createdAt: z.number(),
    encryptedFileKey: z.string().nullish(),
    encryptedFileKeyNonce: z.string().nullish(),
    kdfNonce: z.string().nullish(),
    kdfMemLimit: z.number().nullish(),
    kdfOpsLimit: z.number().nullish(),
    encryptedShareKey: z.string().nullish(),
});

export interface LockerFileShareLink {
    linkID: string;
    url: string;
    fileID?: number;
    validTill?: number | null;
    enableDownload?: boolean;
    passwordEnabled?: boolean;
}

export interface LockerFileShareLinkSummary {
    linkID: string;
    fileID: number;
    validTill?: number | null;
    enableDownload: boolean;
    passwordEnabled: boolean;
}

// ---------------------------------------------------------------------------
// File link helpers
// ---------------------------------------------------------------------------

const decodeUTF8B64 = (b64: string) => utf8Decoder.decode(b64ToBytes(b64));

const generateBase62Secret = (length: number) => {
    const charset =
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    const charsetLength = charset.length;
    const maxUnbiasedValue = 256 - (256 % charsetLength);
    let secret = "";

    while (secret.length < length) {
        const randomValues = crypto.getRandomValues(
            new Uint8Array(length - secret.length),
        );
        for (const value of randomValues) {
            if (value >= maxUnbiasedValue) continue;
            secret += charset[value % charsetLength]!;
        }
    }

    return secret;
};

const prepareFileLinkSecretPayload = async (fileKey: string) => {
    const secret = generateBase62Secret(12);
    const secretB64 = stringToB64(secret);
    const derivedKey = await deriveInteractiveKey(secret);
    const encryptedFileKey = await encryptBox(fileKey, derivedKey.key);
    const keyPair = await ensureUserKeyPair();
    const encryptedShareKey = await boxSeal(
        stringToB64(secretB64),
        keyPair.publicKey,
    );

    return {
        secret,
        metadata: {
            encryptedFileKey: encryptedFileKey.encryptedData,
            encryptedFileKeyNonce: encryptedFileKey.nonce,
            kdfNonce: derivedKey.salt,
            kdfMemLimit: derivedKey.memLimit,
            kdfOpsLimit: derivedKey.opsLimit,
            encryptedShareKey,
        },
    };
};

const resolveFileLinkSecret = async (
    link: z.infer<typeof RemoteFileShareLink>,
    generatedSecret: string,
) => {
    if (!link.encryptedShareKey) {
        return generatedSecret;
    }

    const decryptedSecretB64 = decodeUTF8B64(
        await boxSealOpen(link.encryptedShareKey, await ensureUserKeyPair()),
    );
    return decodeUTF8B64(decryptedSecretB64);
};

const infoItemTitle = (
    infoType: LockerItemType,
    infoData: Record<string, unknown>,
) => {
    const namedTitle =
        (infoData.title as string | undefined)?.trim() ||
        (infoData.name as string | undefined)?.trim();
    if (namedTitle) {
        return namedTitle;
    }

    switch (infoType) {
        case "note":
            return "Note";
        case "physicalRecord":
            return "Location";
        case "accountCredential":
            return "Secret";
        case "emergencyContact":
            return "Emergency Contact";
        case "file":
            return "File";
    }
};

const resolveCollectionIDsWithUncategorizedFallback = async (
    collectionIDs: number[],
    masterKey: string,
) =>
    collectionIDs.length > 0
        ? Array.from(new Set(collectionIDs))
        : [(await ensureUncategorizedCollection(masterKey)).id];

/**
 * Fetch Locker file share links for the current user.
 *
 * The backend endpoint is user-wide rather than per-file, so the client
 * filters to the latest non-disabled record per file.
 */
export const fetchLockerFileShareLinks = (): Promise<
    Map<number, LockerFileShareLinkSummary>
> => {
    // TODO: Re-enable this after GET /files/share-url is deployed on the API.
    return Promise.resolve(new Map<number, LockerFileShareLinkSummary>());
};

/**
 * Get or create a public share link for a Locker file.
 */
export const getOrCreateLockerFileShareLink = async (
    fileID: number,
    masterKey: string,
): Promise<LockerFileShareLink> => {
    const fileRecord = getEncryptedFileRecord(fileID);
    if (!fileRecord) {
        throw new Error(`File ${fileID} not found in cache`);
    }

    const fileKey = await decryptFileKeyForRecord(fileRecord, masterKey);
    const payload = await prepareFileLinkSecretPayload(fileKey);

    const res = await fetch(await apiURL("/files/share-url"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ fileID, app: "locker", ...payload.metadata }),
    });
    ensureOk(res);

    const link = RemoteFileShareLink.parse(await res.json());
    const secret = await resolveFileLinkSecret(link, payload.secret);

    return {
        linkID: link.linkID,
        url: `${link.url}#${secret}`,
        fileID: link.fileID,
        validTill: link.validTill,
        enableDownload: link.enableDownload,
        passwordEnabled: link.passwordEnabled,
    };
};

/**
 * Delete a public share link for a Locker file.
 */
export const deleteLockerFileShareLink = async (
    fileID: number,
    linkID?: string,
): Promise<void> => {
    const candidateIDs = [linkID, String(fileID)].filter(
        (candidate, index, values): candidate is string =>
            !!candidate && values.indexOf(candidate) === index,
    );

    let lastError: Error | undefined;
    for (const candidateID of candidateIDs) {
        const res = await fetch(
            await apiURL(`/files/share-url/${candidateID}`),
            { method: "DELETE", headers: await authenticatedRequestHeaders() },
        );
        if (res.ok) {
            return;
        }
        lastError = new Error(
            `Failed to delete link ${candidateID}: ${res.status} ${res.statusText}`,
        );
        if (candidateID !== String(fileID)) {
            continue;
        }
    }

    throw lastError ?? new Error("Failed to delete file share link");
};

// ---------------------------------------------------------------------------
// Create info item (note, credential, physical record, emergency contact)
// ---------------------------------------------------------------------------

/**
 * Create a new info item in the specified collection(s).
 *
 * This uses the `/files/meta` endpoint for metadata-only files (no file
 * content blob, no thumbnail). The info data is stored in pubMagicMetadata.
 *
 * @param collectionIDs The collection IDs to create the item in. Falls back
 * to the user's Uncategorized collection when empty.
 * @param infoType The item type (e.g. "note", "accountCredential").
 * @param infoData The item's structured data (matching the type's schema).
 * @param masterKey The user's master key.
 */
export const createInfoItem = async (
    collectionIDs: number[],
    infoType: LockerItemType,
    infoData: Record<string, unknown>,
    masterKey: string,
): Promise<void> => {
    const [collectionID, ...additionalCollectionIDs] =
        await resolveCollectionIDsWithUncategorizedFallback(
            collectionIDs,
            masterKey,
        );
    if (collectionID === undefined) {
        throw new Error("No collection selected");
    }
    const collectionRecord = getCollectionRecord(collectionID);
    if (!collectionRecord)
        throw new Error(`Collection ${collectionID} not in cache`);

    // Decrypt collection key
    const collectionKey = await decryptCollectionKey(
        collectionRecord,
        masterKey,
    );

    // Generate a random file key
    const fileKey = await generateKey();

    // Encrypt file key with collection key (SecretBox)
    const encryptedFileKey = await encryptBox(fileKey, collectionKey);

    // Build metadata (basic file metadata — title, creation time, file type)
    const now = Date.now(); // Epoch milliseconds, matching mobile Locker
    const title = infoItemTitle(infoType, infoData);
    const metadata = {
        title,
        creationTime: now,
        modificationTime: now,
        fileType: 4, // FileType.info
    };
    const metadataJSON = JSON.stringify(metadata);
    const encryptedMetadata = await encryptBlob(
        stringToB64(metadataJSON),
        fileKey,
    );

    // Build pubMagicMetadata with info field
    const pubMagicMetadata = {
        info: { type: infoType, data: infoData },
        noThumb: true,
    };
    const pubMMJSON = JSON.stringify(pubMagicMetadata);
    const encryptedPubMM = await encryptBlob(stringToB64(pubMMJSON), fileKey);

    // POST /files/meta
    const res = await fetch(await apiURL("/files/meta"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            collectionID,
            encryptedKey: encryptedFileKey.encryptedData,
            keyDecryptionNonce: encryptedFileKey.nonce,
            metadata: {
                encryptedData: encryptedMetadata.encryptedData,
                decryptionHeader: encryptedMetadata.decryptionHeader,
            },
            pubMagicMetadata: {
                version: 1,
                count: Object.keys(pubMagicMetadata).length,
                data: encryptedPubMM.encryptedData,
                header: encryptedPubMM.decryptionHeader,
            },
        }),
    });
    ensureOk(res);

    const created = RemoteIDResponseSchema.parse(await res.json());
    if (additionalCollectionIDs.length > 0) {
        await addFileToCollections(
            created.id,
            fileKey,
            additionalCollectionIDs,
            masterKey,
        );
    }
};

// ---------------------------------------------------------------------------
// Update info item (edit existing item's pubMagicMetadata)
// ---------------------------------------------------------------------------

/**
 * Update an existing info item's data by replacing its pubMagicMetadata.
 *
 * @param fileID The file/item ID to update.
 * @param infoType The item type.
 * @param infoData The new structured data.
 * @param masterKey The user's master key.
 */
export const updateInfoItem = async (
    fileID: number,
    infoType: LockerItemType,
    infoData: Record<string, unknown>,
    masterKey: string,
): Promise<void> => {
    const fileRecord = getEncryptedFileRecord(fileID);
    if (!fileRecord) throw new Error(`File ${fileID} not in cache`);

    const collectionRecord = getCollectionRecord(fileRecord.collectionID);
    if (!collectionRecord)
        throw new Error(`Collection ${fileRecord.collectionID} not in cache`);

    // Decrypt collection key → file key
    const collectionKey = await decryptCollectionKey(
        collectionRecord,
        masterKey,
    );
    const fileKey = await decryptBox(
        {
            encryptedData: fileRecord.encryptedKey,
            nonce: fileRecord.keyDecryptionNonce,
        },
        collectionKey,
    );

    const existingPubMagicMetadata = fileRecord.pubMagicMetadata
        ? ((await decryptMetadataJSON(
              {
                  encryptedData: fileRecord.pubMagicMetadata.data,
                  decryptionHeader: fileRecord.pubMagicMetadata.header,
              },
              fileKey,
          )) as Record<string, unknown>)
        : {};

    // Build updated pubMagicMetadata by merging into the existing public
    // metadata, mirroring mobile's MetadataUpdaterService behavior.
    const title = infoItemTitle(infoType, infoData);
    const pubMagicMetadata = {
        ...existingPubMagicMetadata,
        info: { type: infoType, data: infoData },
        noThumb: true,
        editedName: title,
        editedTime: Date.now(),
    };
    const pubMMJSON = JSON.stringify(pubMagicMetadata);
    const encryptedPubMM = await encryptBlob(stringToB64(pubMMJSON), fileKey);

    const version = fileRecord.pubMagicMetadata?.version ?? 1;

    // PUT /files/public-magic-metadata
    const res = await fetch(await apiURL("/files/public-magic-metadata"), {
        method: "PUT",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            metadataList: [
                {
                    id: fileID,
                    magicMetadata: {
                        version,
                        count: Object.keys(pubMagicMetadata).length,
                        data: encryptedPubMM.encryptedData,
                        header: encryptedPubMM.decryptionHeader,
                    },
                },
            ],
        }),
    });
    ensureOk(res);

    updateCachedPubMagicMetadata(fileID, {
        version: version + 1,
        data: encryptedPubMM.encryptedData,
        header: encryptedPubMM.decryptionHeader,
    });
};

export const updateFileItem = async (
    fileID: number,
    title: string,
    masterKey: string,
): Promise<void> => {
    const fileRecord = getEncryptedFileRecord(fileID);
    if (!fileRecord) throw new Error(`File ${fileID} not in cache`);

    const collectionRecord = getCollectionRecord(fileRecord.collectionID);
    if (!collectionRecord)
        throw new Error(`Collection ${fileRecord.collectionID} not in cache`);

    const collectionKey = await decryptCollectionKey(
        collectionRecord,
        masterKey,
    );
    const fileKey = await decryptBox(
        {
            encryptedData: fileRecord.encryptedKey,
            nonce: fileRecord.keyDecryptionNonce,
        },
        collectionKey,
    );

    const existingPubMagicMetadata = fileRecord.pubMagicMetadata
        ? ((await decryptMetadataJSON(
              {
                  encryptedData: fileRecord.pubMagicMetadata.data,
                  decryptionHeader: fileRecord.pubMagicMetadata.header,
              },
              fileKey,
          )) as Record<string, unknown>)
        : {};

    const pubMagicMetadata = {
        ...existingPubMagicMetadata,
        noThumb: true,
        editedName: title.trim(),
        editedTime: Date.now(),
    };
    const pubMMJSON = JSON.stringify(pubMagicMetadata);
    const encryptedPubMM = await encryptBlob(stringToB64(pubMMJSON), fileKey);
    const version = fileRecord.pubMagicMetadata?.version ?? 1;

    const res = await fetch(await apiURL("/files/public-magic-metadata"), {
        method: "PUT",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            metadataList: [
                {
                    id: fileID,
                    magicMetadata: {
                        version,
                        count: Object.keys(pubMagicMetadata).length,
                        data: encryptedPubMM.encryptedData,
                        header: encryptedPubMM.decryptionHeader,
                    },
                },
            ],
        }),
    });
    ensureOk(res);

    updateCachedPubMagicMetadata(fileID, {
        version: version + 1,
        data: encryptedPubMM.encryptedData,
        header: encryptedPubMM.decryptionHeader,
    });
};

export const updateItemCollections = async (
    fileID: number,
    collectionIDs: number[],
    masterKey: string,
): Promise<void> => {
    await updateItemCollectionsWithDeps(fileID, collectionIDs, {
        currentUserID: ensureLocalUser().id,
        masterKey,
        deps: createCollectionMutationDeps(),
    });
};

// ---------------------------------------------------------------------------
// Trash operations
// ---------------------------------------------------------------------------

/**
 * Move files to trash.
 *
 * @param fileIDs The file IDs to trash.
 * @param collectionID The collection the files belong to.
 */
export const trashFiles = async (
    fileIDs: number[],
    collectionID: number,
): Promise<void> => {
    const res = await fetch(await apiURL("/files/trash"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            items: fileIDs.map((fileID) => ({ fileID, collectionID })),
        }),
    });
    ensureOk(res);
};

/**
 * Permanently delete files from trash.
 *
 * @param fileIDs The file IDs to permanently delete.
 */
export const permanentlyDeleteFromTrash = async (
    fileIDs: number[],
): Promise<void> => {
    const res = await fetch(await apiURL("/trash/delete"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ fileIDs }),
    });
    ensureOk(res);
};

/**
 * Empty the entire trash.
 */
export const emptyTrash = async (lastUpdatedAt: number): Promise<void> => {
    const res = await fetch(await apiURL("/trash/empty"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ lastUpdatedAt }),
    });
    ensureOk(res);
};

const addFileToCollections = async (
    fileID: number,
    fileKey: string,
    targetCollectionIDs: number[],
    masterKey: string,
): Promise<void> => {
    for (const targetCollectionID of targetCollectionIDs) {
        const collectionRecord = getCollectionRecord(targetCollectionID);
        if (!collectionRecord) {
            throw new Error(`Collection ${targetCollectionID} not in cache`);
        }

        const collectionKey = await decryptCollectionKey(
            collectionRecord,
            masterKey,
        );
        const encryptedFileKey = await encryptBox(fileKey, collectionKey);

        const res = await fetch(await apiURL("/collections/add-files"), {
            method: "POST",
            headers: {
                ...(await authenticatedRequestHeaders()),
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                collectionID: targetCollectionID,
                files: [
                    {
                        id: fileID,
                        encryptedKey: encryptedFileKey.encryptedData,
                        keyDecryptionNonce: encryptedFileKey.nonce,
                    },
                ],
            }),
        });
        ensureOk(res);
    }
};

const COLLECTION_MUTATION_BATCH_SIZE = 100;

const batchValues = <T>(
    values: T[],
    batchSize = COLLECTION_MUTATION_BATCH_SIZE,
) => {
    const batches: T[][] = [];
    for (let i = 0; i < values.length; i += batchSize) {
        batches.push(values.slice(i, i + batchSize));
    }
    return batches;
};

const decryptFileKeyForCollection = async (
    fileID: number,
    collectionID: number,
    masterKey: string,
): Promise<string> => {
    const fileRecord = getEncryptedFileRecord(fileID, collectionID);
    if (!fileRecord) {
        throw new Error(
            `File ${fileID} not in cache for collection ${collectionID}`,
        );
    }

    const collectionRecord = getCollectionRecord(collectionID);
    if (!collectionRecord) {
        throw new Error(`Collection ${collectionID} not in cache`);
    }

    const collectionKey = await decryptCollectionKey(
        collectionRecord,
        masterKey,
    );
    return await decryptBox(
        {
            encryptedData: fileRecord.encryptedKey,
            nonce: fileRecord.keyDecryptionNonce,
        },
        collectionKey,
    );
};

const buildEncryptedFileMoveItem = async (
    fileID: number,
    fromCollectionID: number,
    toCollectionID: number,
    masterKey: string,
): Promise<EncryptedCollectionFileItem> => {
    const fileKey = await decryptFileKeyForCollection(
        fileID,
        fromCollectionID,
        masterKey,
    );
    const targetCollectionRecord = getCollectionRecord(toCollectionID);
    if (!targetCollectionRecord) {
        throw new Error(`Collection ${toCollectionID} not in cache`);
    }
    const targetCollectionKey = await decryptCollectionKey(
        targetCollectionRecord,
        masterKey,
    );
    const encryptedFileKey = await encryptBox(fileKey, targetCollectionKey);

    return {
        id: fileID,
        encryptedKey: encryptedFileKey.encryptedData,
        keyDecryptionNonce: encryptedFileKey.nonce,
    };
};

const removeFilesFromCollection = async (
    collectionID: number,
    fileIDs: number[],
): Promise<void> => {
    if (fileIDs.length === 0) {
        return;
    }

    for (const fileIDBatch of batchValues(fileIDs)) {
        const res = await fetch(await apiURL("/collections/v3/remove-files"), {
            method: "POST",
            headers: {
                ...(await authenticatedRequestHeaders()),
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ collectionID, fileIDs: fileIDBatch }),
        });
        ensureOk(res);
    }
};

const moveFilesBetweenCollections = async (
    fromCollectionID: number,
    toCollectionID: number,
    files: EncryptedCollectionFileItem[],
): Promise<void> => {
    if (files.length === 0) {
        return;
    }

    for (const fileBatch of batchValues(files)) {
        const res = await fetch(await apiURL("/collections/move-files"), {
            method: "POST",
            headers: {
                ...(await authenticatedRequestHeaders()),
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                fromCollectionID,
                toCollectionID,
                files: fileBatch,
            }),
        });
        ensureOk(res);
    }
};

const createCollectionMutationDeps = () => ({
    getCollectionIDsForFile,
    getCollectionRecord,
    ensureUncategorizedCollection,
    decryptFileKeyForCollection,
    buildEncryptedFileMoveItem,
    removeFilesFromCollection,
    moveFilesBetweenCollections,
    addFileToCollections,
});

/**
 * Restore files from trash to a collection.
 *
 * @param items The files to restore with their source collection IDs.
 * @param targetCollectionID The target collection.
 * @param masterKey The user's master key.
 */
export const restoreFromTrash = async (
    items: Pick<LockerItem, "id" | "collectionID">[],
    targetCollectionID: number,
    masterKey: string,
): Promise<void> => {
    const collectionRecord = getCollectionRecord(targetCollectionID);
    if (!collectionRecord)
        throw new Error(`Collection ${targetCollectionID} not in cache`);

    const collectionKey = await decryptCollectionKey(
        collectionRecord,
        masterKey,
    );

    const buildRestorePayload = async (
        candidateItems: Pick<LockerItem, "id" | "collectionID">[],
    ) => {
        const files: {
            id: number;
            encryptedKey: string;
            keyDecryptionNonce: string;
        }[] = [];
        const skippedFileIDs: number[] = [];

        for (const item of candidateItems) {
            const fileRecord = getEncryptedFileRecord(
                item.id,
                item.collectionID,
            );
            if (!fileRecord) {
                skippedFileIDs.push(item.id);
                continue;
            }

            // Decrypt file key using original collection key
            const origCollectionRecord = getCollectionRecord(
                fileRecord.collectionID,
            );
            if (!origCollectionRecord) {
                skippedFileIDs.push(item.id);
                continue;
            }

            const origCollectionKey = await decryptCollectionKey(
                origCollectionRecord,
                masterKey,
            );
            const fileKey = await decryptBox(
                {
                    encryptedData: fileRecord.encryptedKey,
                    nonce: fileRecord.keyDecryptionNonce,
                },
                origCollectionKey,
            );

            // Re-encrypt file key with target collection key
            const encryptedFileKey = await encryptBox(fileKey, collectionKey);
            files.push({
                id: item.id,
                encryptedKey: encryptedFileKey.encryptedData,
                keyDecryptionNonce: encryptedFileKey.nonce,
            });
        }

        return { files, skippedFileIDs };
    };

    let { files, skippedFileIDs } = await buildRestorePayload(items);
    if (files.length === 0 && skippedFileIDs.length > 0) {
        // Recover from stale cache by refetching trash metadata once.
        await fetchLockerTrash(masterKey);
        ({ files, skippedFileIDs } = await buildRestorePayload(items));
    }

    if (skippedFileIDs.length > 0) {
        log.warn(
            `Skipping ${skippedFileIDs.length} trash files during restore due to missing cache records`,
            skippedFileIDs,
        );
    }
    if (files.length === 0) {
        throw new Error(
            "Unable to restore files: missing encrypted metadata in local cache. Please refresh and try again.",
        );
    }

    const res = await fetch(await apiURL("/collections/restore-files"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ collectionID: targetCollectionID, files }),
    });
    ensureOk(res);
};

// ---------------------------------------------------------------------------
// Collection management
// ---------------------------------------------------------------------------

/**
 * Create a new collection.
 *
 * @param name The collection name.
 * @param masterKey The user's master key.
 * @returns The new collection's ID.
 */
export const createCollection = async (
    name: string,
    masterKey: string,
    type = "folder",
): Promise<number> => {
    return createCollectionWithDeps(name, masterKey, type);
};

const ensureUncategorizedCollection = async (masterKey: string) => {
    const currentUserID = ensureLocalUser().id;
    return ensureUncategorizedCollectionWithDeps(masterKey, {
        findCollectionByType: (type) =>
            findCollectionByType(type, currentUserID),
        refetchCollections: async (masterKey) => {
            await fetchLockerData(masterKey);
        },
    });
};

const ensureFavoritesCollection = async (masterKey: string) => {
    const currentUserID = ensureLocalUser().id;
    return ensureFavoritesCollectionWithDeps(masterKey, {
        findCollectionByType: (type) =>
            findCollectionByType(type, currentUserID),
        refetchCollections: async (resolvedMasterKey) => {
            await fetchLockerData(resolvedMasterKey);
        },
    });
};

/**
 * Rename a collection.
 *
 * @param collectionID The collection to rename.
 * @param newName The new name.
 * @param masterKey The user's master key.
 */
export const renameCollection = async (
    collectionID: number,
    newName: string,
    masterKey: string,
): Promise<void> => {
    await renameCollectionWithDeps(collectionID, newName, masterKey, {
        getCollectionRecord,
        decryptCollectionKey,
    });
};

/**
 * Delete a collection (moves to trash).
 *
 * @param collectionID The collection to delete.
 */
export const deleteCollection = async (
    collectionID: number,
    opts?: { keepFiles?: boolean },
): Promise<void> => {
    await deleteCollectionWithDeps(collectionID, opts);
};

export const deleteCollectionKeepingFiles = async (
    collection: LockerCollection,
    masterKey: string,
): Promise<void> => {
    await deleteCollectionKeepingFilesWithDeps(collection, {
        currentUserID: ensureLocalUser().id,
        masterKey,
        deps: createCollectionMutationDeps(),
    });
    await deleteCollection(collection.id, { keepFiles: true });
};

/**
 * Fetch the current list of participants for a shared collection.
 */
export const fetchCollectionSharees = async (
    collectionID: number,
): Promise<LockerCollectionParticipant[]> => {
    return fetchCollectionShareesWithDeps(collectionID, {
        getCollectionRecord,
        decryptCollectionKey,
        updateCollectionShareesInCache,
    });
};

/**
 * Share a collection with another Ente user as a viewer.
 */
export const shareCollection = async (
    collectionID: number,
    email: string,
    masterKey: string,
): Promise<LockerCollectionParticipant[]> => {
    return shareCollectionWithDeps(collectionID, email, masterKey, {
        getCollectionRecord,
        decryptCollectionKey,
        updateCollectionShareesInCache,
    });
};

/**
 * Remove a participant from a shared collection.
 */
export const unshareCollection = async (
    collectionID: number,
    email: string,
): Promise<LockerCollectionParticipant[]> => {
    return unshareCollectionWithDeps(collectionID, email, {
        getCollectionRecord,
        decryptCollectionKey,
        updateCollectionShareesInCache,
    });
};

/**
 * Leave a shared collection.
 */
export const leaveCollection = async (collectionID: number): Promise<void> => {
    const res = await fetch(
        await apiURL(`/collections/leave/${collectionID}`),
        { method: "POST", headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
};

/**
 * Mark or unmark a Locker item as Important.
 */
export const setItemImportant = async (
    fileID: number,
    shouldBeImportant: boolean,
    masterKey: string,
): Promise<boolean> => {
    const currentUserID = ensureLocalUser().id;
    const currentCollectionIDs = getCollectionIDsForFile(fileID);
    if (currentCollectionIDs.length === 0) {
        throw new Error(`File ${fileID} not found in cache`);
    }

    const favoritesCollection = findCollectionByType(
        "favorites",
        currentUserID,
    );
    if (!shouldBeImportant && !favoritesCollection) {
        return false;
    }

    const favoritesCollectionID =
        favoritesCollection?.id ??
        (await ensureFavoritesCollection(masterKey)).id;
    const nextCollectionIDs = shouldBeImportant
        ? Array.from(new Set([...currentCollectionIDs, favoritesCollectionID]))
        : currentCollectionIDs.filter(
              (collectionID) => collectionID !== favoritesCollectionID,
          );

    const hasChanged =
        nextCollectionIDs.length !== currentCollectionIDs.length ||
        nextCollectionIDs.some(
            (collectionID) => !currentCollectionIDs.includes(collectionID),
        );
    if (!hasChanged) {
        return false;
    }

    await updateItemCollectionsWithDeps(fileID, nextCollectionIDs, {
        currentUserID,
        masterKey,
        deps: createCollectionMutationDeps(),
    });
    return true;
};

// ---------------------------------------------------------------------------
// File upload
// ---------------------------------------------------------------------------

export type { LockerUploadProgress } from "./remote-uploads";

export const uploadLockerFile = async (
    file: File,
    collectionIDs: number[],
    masterKey: string,
    onProgress?: (progress: LockerUploadProgress) => void,
): Promise<number> => {
    const targetCollectionIDs =
        await resolveCollectionIDsWithUncategorizedFallback(
            collectionIDs,
            masterKey,
        );
    return uploadLockerFileWithDeps(
        file,
        targetCollectionIDs,
        masterKey,
        { getCollectionRecord, decryptCollectionKey, addFileToCollections },
        onProgress,
    );
};
