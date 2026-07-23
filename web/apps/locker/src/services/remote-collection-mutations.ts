import type { LockerCollection } from "@/types";

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
        masterKey: string,
    ) => Promise<string>;
    buildEncryptedFileMoveItem: (
        fileID: number,
        fromCollectionID: number,
        toCollectionID: number,
        masterKey: string,
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
        masterKey: string,
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
        ? await decryptFileKeyForCollection(
              fileID,
              sourceCollectionIDForAdd,
              masterKey,
          )
        : null;

    // Mirror mobile's safer ordering: establish explicit new memberships
    // before we remove or auto-move any existing ones.
    if (collectionIDsToAdd.length > 0) {
        if (!sourceFileKeyForAdd) {
            throw new Error(`File ${fileID} has no source collection`);
        }
        await addFileToCollections(
            fileID,
            sourceFileKeyForAdd,
            collectionIDsToAdd,
            masterKey,
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
                masterKey,
            ),
        ]);
    }
};

/**
 * Rehomes or detaches every file from the collection before the caller
 * deletes the collection record itself. This helper intentionally does not
 * issue the final collection delete request.
 */
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
                masterKey,
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
