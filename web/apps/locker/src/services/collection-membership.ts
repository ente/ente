import type { LockerCollection } from "@/types";
import { ensureLocalUser } from "ente-accounts/services/user";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { decryptBox, encryptBox } from "ente-locker-wasm";
import { deleteCollection, ensureUncategorizedCollection } from "./collections";
import {
    getCollectionIDsForFile,
    getCollectionRecord,
    getEncryptedFileRecord,
} from "./locker-cache";
import { decryptCollectionKey } from "./sync/decrypt";

interface CollectionRecordLike {
    id: number;
    ownerID: number;
    type: string;
}

export interface EncryptedCollectionFileItem {
    id: number;
    encryptedKey: string;
    keyDecryptionNonce: string;
}

interface CollectionMutationDeps {
    getCollectionIDsForFile: (fileID: number) => number[];
    getCollectionRecord: (
        collectionID: number,
    ) => CollectionRecordLike | undefined;
    ensureUncategorizedCollection: (
        masterKey: string,
    ) => Promise<CollectionRecordLike>;
    decryptFileKeyForCollection: (
        fileID: number,
        collectionID: number,
    ) => Promise<string>;
    buildEncryptedFileMoveItem: (
        fileID: number,
        fromCollectionID: number,
        toCollectionID: number,
    ) => Promise<EncryptedCollectionFileItem>;
    removeFilesFromCollection: (
        collectionID: number,
        fileIDs: number[],
    ) => Promise<void>;
    moveFilesBetweenCollections: (
        fromCollectionID: number,
        toCollectionID: number,
        files: EncryptedCollectionFileItem[],
    ) => Promise<void>;
    addFileToCollections: (
        fileID: number,
        fileKey: string,
        targetCollectionIDs: number[],
    ) => Promise<void>;
}

interface CollectionMutationContext {
    currentUserID: number;
    masterKey: string;
    deps: CollectionMutationDeps;
}

const AUTO_MOVE_EXCLUDED_COLLECTION_TYPES = new Set([
    "favorites",
    "uncategorized",
]);

const appendMapValue = <K, V>(map: Map<K, V[]>, key: K, value: V) => {
    const existingValues = map.get(key);
    if (existingValues) {
        existingValues.push(value);
        return;
    }
    map.set(key, [value]);
};

const createCachedUncategorizedResolver = (
    loadUncategorizedCollection: () => Promise<CollectionRecordLike>,
) => {
    let uncategorizedCollection: CollectionRecordLike | undefined;
    return async () => {
        uncategorizedCollection ??= await loadUncategorizedCollection();
        return uncategorizedCollection;
    };
};

const isAutoMoveCandidateCollection = (
    collectionID: number,
    currentUserID: number,
    getCollectionRecord: (
        collectionID: number,
    ) => CollectionRecordLike | undefined,
    sourceCollectionID?: number,
) => {
    if (collectionID === sourceCollectionID) {
        return false;
    }

    const collection = getCollectionRecord(collectionID);
    return (
        !!collection &&
        collection.ownerID === currentUserID &&
        !AUTO_MOVE_EXCLUDED_COLLECTION_TYPES.has(collection.type)
    );
};

const resolveAutoMoveTargetCollectionID = async ({
    currentUserID,
    sourceCollectionID,
    preferredCollectionIDs,
    getCollectionRecord,
    getUncategorizedCollection,
}: {
    currentUserID: number;
    sourceCollectionID: number;
    preferredCollectionIDs: number[];
    getCollectionRecord: (
        collectionID: number,
    ) => CollectionRecordLike | undefined;
    getUncategorizedCollection: () => Promise<CollectionRecordLike>;
}) => {
    const existingTargetCollectionID = preferredCollectionIDs.find(
        (candidateCollectionID) =>
            isAutoMoveCandidateCollection(
                candidateCollectionID,
                currentUserID,
                getCollectionRecord,
                sourceCollectionID,
            ),
    );
    if (existingTargetCollectionID) {
        return existingTargetCollectionID;
    }

    return (await getUncategorizedCollection()).id;
};

export const updateItemCollectionsWithDeps = async (
    fileID: number,
    collectionIDs: number[],
    context: CollectionMutationContext,
): Promise<void> => {
    const { currentUserID, masterKey, deps } = context;
    const {
        getCollectionIDsForFile,
        getCollectionRecord,
        ensureUncategorizedCollection,
        decryptFileKeyForCollection,
        buildEncryptedFileMoveItem,
        removeFilesFromCollection,
        moveFilesBetweenCollections,
        addFileToCollections,
    } = deps;
    const currentCollectionIDs = getCollectionIDsForFile(fileID);
    const getUncategorizedCollection = createCachedUncategorizedResolver(() =>
        ensureUncategorizedCollection(masterKey),
    );
    const nextCollectionIDs = Array.from(
        new Set(
            collectionIDs.length > 0
                ? collectionIDs
                : [(await getUncategorizedCollection()).id],
        ),
    );
    const currentCollectionIDSet = new Set(currentCollectionIDs);
    const nextCollectionIDSet = new Set(nextCollectionIDs);
    const collectionIDsToAdd = nextCollectionIDs.filter(
        (collectionID) => !currentCollectionIDSet.has(collectionID),
    );
    const collectionIDsToRemove = currentCollectionIDs.filter(
        (collectionID) => !nextCollectionIDSet.has(collectionID),
    );
    const sourceCollectionIDForAdd =
        collectionIDsToAdd.length > 0
            ? (nextCollectionIDs.find((collectionID) =>
                  currentCollectionIDSet.has(collectionID),
              ) ?? currentCollectionIDs[0])
            : undefined;
    const sourceFileKeyForAdd = sourceCollectionIDForAdd
        ? await decryptFileKeyForCollection(fileID, sourceCollectionIDForAdd)
        : null;

    // Add the new memberships before removing existing ones so the file
    // always retains at least one collection membership.
    if (collectionIDsToAdd.length > 0) {
        if (!sourceFileKeyForAdd) {
            throw new Error(`File ${fileID} has no source collection`);
        }
        await addFileToCollections(
            fileID,
            sourceFileKeyForAdd,
            collectionIDsToAdd,
        );
    }

    for (const collectionID of collectionIDsToRemove) {
        const sourceCollectionRecord = getCollectionRecord(collectionID);
        if (!sourceCollectionRecord) {
            throw new Error(`Collection ${collectionID} not in cache`);
        }

        if (sourceCollectionRecord.ownerID !== currentUserID) {
            await removeFilesFromCollection(collectionID, [fileID]);
            continue;
        }

        const targetCollectionID = await resolveAutoMoveTargetCollectionID({
            currentUserID,
            sourceCollectionID: collectionID,
            preferredCollectionIDs: nextCollectionIDs,
            getCollectionRecord,
            getUncategorizedCollection,
        });
        if (targetCollectionID === collectionID) {
            continue;
        }
        await moveFilesBetweenCollections(collectionID, targetCollectionID, [
            await buildEncryptedFileMoveItem(
                fileID,
                collectionID,
                targetCollectionID,
            ),
        ]);
    }
};

// This helper only rehomes or detaches the collection's files; the caller is
// responsible for issuing the final collection delete request.
export const deleteCollectionKeepingFilesWithDeps = async (
    collection: LockerCollection,
    context: CollectionMutationContext,
): Promise<void> => {
    const { currentUserID, masterKey, deps } = context;
    const {
        getCollectionIDsForFile,
        getCollectionRecord,
        ensureUncategorizedCollection,
        buildEncryptedFileMoveItem,
        removeFilesFromCollection,
        moveFilesBetweenCollections,
    } = deps;
    const collectionID = collection.id;
    const getUncategorizedCollection = createCachedUncategorizedResolver(() =>
        ensureUncategorizedCollection(masterKey),
    );

    const fileIDsToRemove: number[] = [];
    const filesToMoveByTargetCollectionID = new Map<
        number,
        EncryptedCollectionFileItem[]
    >();

    for (const item of collection.items) {
        const isCurrentUserOwned =
            (item.ownerID ?? currentUserID) === currentUserID;
        if (!isCurrentUserOwned) {
            fileIDsToRemove.push(item.id);
            continue;
        }

        const targetCollectionID = await resolveAutoMoveTargetCollectionID({
            currentUserID,
            sourceCollectionID: collectionID,
            preferredCollectionIDs: getCollectionIDsForFile(item.id),
            getCollectionRecord,
            getUncategorizedCollection,
        });
        appendMapValue(
            filesToMoveByTargetCollectionID,
            targetCollectionID,
            await buildEncryptedFileMoveItem(
                item.id,
                collectionID,
                targetCollectionID,
            ),
        );
    }

    for (const [targetCollectionID, files] of filesToMoveByTargetCollectionID) {
        await moveFilesBetweenCollections(
            collectionID,
            targetCollectionID,
            files,
        );
    }

    await removeFilesFromCollection(collectionID, fileIDsToRemove);
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

export const addFileToCollections = async (
    fileID: number,
    fileKey: string,
    targetCollectionIDs: number[],
): Promise<void> => {
    for (const targetCollectionID of targetCollectionIDs) {
        const collectionRecord = getCollectionRecord(targetCollectionID);
        if (!collectionRecord) {
            throw new Error(`Collection ${targetCollectionID} not in cache`);
        }

        const collectionKey = await decryptCollectionKey(collectionRecord);
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

    const collectionKey = await decryptCollectionKey(collectionRecord);
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
): Promise<EncryptedCollectionFileItem> => {
    const fileKey = await decryptFileKeyForCollection(fileID, fromCollectionID);
    const targetCollectionRecord = getCollectionRecord(toCollectionID);
    if (!targetCollectionRecord) {
        throw new Error(`Collection ${toCollectionID} not in cache`);
    }
    const targetCollectionKey = await decryptCollectionKey(
        targetCollectionRecord,
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

export const createCollectionMutationDeps = () => ({
    getCollectionIDsForFile,
    getCollectionRecord,
    ensureUncategorizedCollection,
    decryptFileKeyForCollection,
    buildEncryptedFileMoveItem,
    removeFilesFromCollection,
    moveFilesBetweenCollections,
    addFileToCollections,
});

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
