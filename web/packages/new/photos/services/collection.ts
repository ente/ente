import { ensureLocalUser } from "ente-accounts/services/user";
import { blobCache } from "ente-base/blob-cache";
import {
    boxSeal,
    boxSealOpen,
    decryptBox,
    encryptBox,
    generateKey,
} from "ente-base/crypto";
import { haveWindow } from "ente-base/env";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { ensureMasterKeyFromSession } from "ente-base/session";
import { groupFilesByCollectionID } from "ente-gallery/utils/file";
import {
    CollectionSubType,
    decryptRemoteCollection,
    findUserUncategorizedCollection,
    maxAlbumDescriptionLength,
    RemoteCollection,
    RemotePublicURL,
    type Collection,
    type CollectionNewParticipantRole,
    type CollectionOrder,
    type CollectionPrivateMagicMetadataData,
    type CollectionPublicMagicMetadataData,
    type CollectionShareeMagicMetadataData,
    type CollectionType,
    type PublicURL,
} from "ente-media/collection";
import {
    decryptRemoteFile,
    FileDiffResponse,
    type EnteFile,
} from "ente-media/file";
import { ItemVisibility, metadataHash } from "ente-media/file-metadata";
import {
    createMagicMetadata,
    encryptMagicMetadata,
} from "ente-media/magic-metadata";
import { batch, splitByPredicate } from "ente-utils/array";
import { z } from "zod";
import { batched, type UpdateMagicMetadataRequest } from "./file";
import {
    removeCollectionIDLastSyncTime,
    saveCollectionFiles,
    saveCollectionLastSyncTime,
    saveCollections,
    saveCollectionsUpdationTime,
    savedCollectionFiles,
    savedCollectionLastSyncTime,
    savedCollections,
    savedCollectionsUpdationTime,
} from "./photos-fdb";
import { ensureUserKeyPair, getPublicKey } from "./user";

const uncategorizedCollectionName = "Uncategorized";
const defaultHiddenCollectionName = ".hidden";
export const defaultHiddenCollectionUserFacingName = "Hidden";
const favoritesCollectionName = "Favorites";
const copyRequestBatchSize = 100;

export const createAlbum = (albumName: string) =>
    createCollection(albumName, "album");

export const createQuickLinkCollection = (name: string) =>
    createCollection(name, "album", {
        subType: CollectionSubType.quicklink,
        visibility: ItemVisibility.visible,
    });

export const createHiddenAlbum = (albumName: string) =>
    createCollection(albumName, "album", { visibility: ItemVisibility.hidden });

const createCollection = async (
    name: string,
    type: CollectionType,
    magicMetadataData?: CollectionPrivateMagicMetadataData,
): Promise<Collection> => {
    const collectionKey = await generateKey();
    const { encryptedData: encryptedKey, nonce: keyDecryptionNonce } =
        await encryptBox(collectionKey, await ensureMasterKeyFromSession());
    const { encryptedData: encryptedName, nonce: nameDecryptionNonce } =
        await encryptBox(new TextEncoder().encode(name), collectionKey);
    const magicMetadata = magicMetadataData
        ? await encryptMagicMetadata(
              createMagicMetadata(magicMetadataData),
              collectionKey,
          )
        : undefined;

    const remoteCollection = await postCollections({
        encryptedKey,
        keyDecryptionNonce,
        encryptedName,
        nameDecryptionNonce,
        type,
        ...(magicMetadata && { magicMetadata }),
    });

    return decryptRemoteKeyAndCollection(remoteCollection);
};

const decryptRemoteKeyAndCollection = async (collection: RemoteCollection) =>
    decryptRemoteCollection(collection, await decryptCollectionKey(collection));

export const decryptCollectionKey = async (
    collection: RemoteCollection,
): Promise<string> => {
    const { owner, encryptedKey, keyDecryptionNonce } = collection;
    // Owned keys use the master key; shared keys use a sealed box.
    if (owner.id == ensureLocalUser().id) {
        return decryptBox(
            { encryptedData: encryptedKey, nonce: keyDecryptionNonce! },
            await ensureMasterKeyFromSession(),
        );
    } else {
        return boxSealOpen(encryptedKey, await ensureUserKeyPair());
    }
};

const CollectionResponse = z.object({ collection: RemoteCollection });

const postCollections = async (
    collectionData: Partial<RemoteCollection>,
): Promise<RemoteCollection> => {
    const res = await fetch(await apiURL("/collections"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify(collectionData),
    });
    ensureOk(res);
    return CollectionResponse.parse(await res.json()).collection;
};

export const getCollectionByID = async (
    collectionID: number,
): Promise<Collection> => {
    const res = await fetch(await apiURL(`/collections/${collectionID}`), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    const { collection } = CollectionResponse.parse(await res.json());
    return decryptRemoteKeyAndCollection(collection);
};

const CollectionsResponse = z.object({
    collections: z.array(RemoteCollection),
});

export interface CollectionChange {
    id: number;
    collection?: Collection;
    updationTime: number;
}

export const pullCollections = async (): Promise<Collection[]> => {
    const collections = await savedCollections();
    let sinceTime = (await savedCollectionsUpdationTime()) ?? 0;

    const changes = await getCollections(sinceTime);

    if (!changes.length) return collections;

    const collectionsByID = new Map(collections.map((c) => [c.id, c]));
    for (const { id, updationTime, collection } of changes) {
        sinceTime = Math.max(sinceTime, updationTime);
        if (collection) {
            collectionsByID.set(id, collection);
        } else {
            await removeCollectionIDLastSyncTime(id);
            collectionsByID.delete(id);
        }
    }

    const updatedCollections = [...collectionsByID.values()];

    await saveCollections(updatedCollections);
    await saveCollectionsUpdationTime(sinceTime);

    return updatedCollections;
};

const getCollections = async (
    sinceTime: number,
): Promise<CollectionChange[]> => {
    const res = await fetch(await apiURL("/collections/v2", { sinceTime }), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    const { collections } = CollectionsResponse.parse(await res.json());
    return Promise.all(
        collections.map(async (c) => ({
            id: c.id,
            updationTime: c.updationTime,
            collection: c.isDeleted
                ? undefined
                : await decryptRemoteKeyAndCollection(c),
        })),
    );
};

export const pullCollectionFiles = async (
    collections: Collection[],
    onSetCollectionFiles: ((files: EnteFile[]) => void) | undefined,
) => {
    let didUpdateFiles = false;

    const savedFiles = await savedCollectionFiles();

    // Collection deletion has no file tombstone; prune by surviving IDs.
    const collectionIDs = new Set(collections.map((c) => c.id));
    let files = savedFiles.filter((f) => collectionIDs.has(f.collectionID));

    if (files.length != savedFiles.length) {
        await saveCollectionFiles(files);
        onSetCollectionFiles?.(files);
        didUpdateFiles = true;
    }

    for (const collection of collections) {
        let sinceTime = (await savedCollectionLastSyncTime(collection)) ?? 0;
        if (sinceTime == collection.updationTime) {
            continue;
        }

        const [thisCollectionFiles, otherFiles] = splitByPredicate(
            files,
            (f) => f.collectionID == collection.id,
        );

        const thisCollectionFilesByID = new Map(
            thisCollectionFiles.map((f) => [f.id, f]),
        );

        while (true) {
            const { diff, hasMore } = await getCollectionDiff(
                collection.id,
                sinceTime,
            );
            if (!diff.length) break;

            for (const change of diff) {
                sinceTime = Math.max(sinceTime, change.updationTime);
                if (change.isDeleted) {
                    thisCollectionFilesByID.delete(change.id);
                } else {
                    const file = await decryptRemoteFile(
                        change,
                        collection.key,
                    );
                    await clearCachedThumbnailIfContentChanged(
                        thisCollectionFilesByID.get(change.id),
                        file,
                    );
                    thisCollectionFilesByID.set(change.id, file);
                }
            }

            files = otherFiles.concat([...thisCollectionFilesByID.values()]);

            await saveCollectionFiles(files);
            await saveCollectionLastSyncTime(collection, sinceTime);
            onSetCollectionFiles?.(files);
            didUpdateFiles = true;

            if (!hasMore) break;
        }

        // Collection metadata can advance without producing a file diff.
        await saveCollectionLastSyncTime(collection, collection.updationTime);
    }

    return didUpdateFiles;
};

const getCollectionDiff = async (collectionID: number, sinceTime: number) => {
    const res = await fetch(
        await apiURL("/collections/v2/diff", { collectionID, sinceTime }),
        { headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
    return FileDiffResponse.parse(await res.json());
};

const clearCachedThumbnailIfContentChanged = async (
    existingFile: EnteFile | undefined,
    updatedFile: EnteFile,
) => {
    if (!existingFile) return;

    // Content changes invalidate thumbnails; metadata-only changes do not.
    if (
        metadataHash(existingFile.metadata) !=
        metadataHash(updatedFile.metadata)
    ) {
        const thumbnailCache = await blobCache("thumbs");
        await thumbnailCache.delete(updatedFile.id.toString());
    }
};

export const savedAllCollections = (): Promise<Collection[]> =>
    savedCollections();

export const savedNormalCollections = (): Promise<Collection[]> =>
    savedCollections().then(
        (cs) => splitByPredicate(cs, isHiddenCollection)[1],
    );

export const savedHiddenCollections = (
    currentUserID?: number,
): Promise<Collection[]> =>
    savedCollections().then(
        (cs) =>
            splitByPredicate(cs, (c) =>
                isHiddenCollection(c, currentUserID),
            )[0],
    );

export const createCollectionNameByID = (collections: Collection[]) =>
    new Map(collections.map((c) => [c.id, collectionUserFacingName(c)]));

export const collectionUserFacingName = (collection: Collection) =>
    isDefaultHiddenCollection(collection)
        ? defaultHiddenCollectionUserFacingName
        : collection.name;

interface CollectionFileItem {
    id: number;
    encryptedKey: string;
    keyDecryptionNonce: string;
}

const CopyFilesResponse = z.object({
    oldToNewFileIDMap: z.record(z.string(), z.number()),
});

const currentUserRoleInCollection = (collection: Collection) => {
    const userID = ensureLocalUser().id;
    if (collection.owner.id == userID) return "OWNER";
    return collection.sharees.find((sharee) => sharee.id == userID)?.role;
};

export const canAddFilesToCollection = (collection: Collection) => {
    const role = currentUserRoleInCollection(collection);
    return role == "OWNER" || role == "ADMIN" || role == "COLLABORATOR";
};

export const canDirectlyUploadToCollection = (collection: Collection) =>
    collection.owner.id == ensureLocalUser().id;

export const addToCollection = async (
    collection: Collection,
    files: EnteFile[],
) =>
    batched(files, async (batchFiles) => {
        const encryptedFileKeys = await encryptWithCollectionKey(
            collection,
            batchFiles,
        );
        ensureOk(
            await fetch(await apiURL("/collections/add-files"), {
                method: "POST",
                headers: await authenticatedRequestHeaders(),
                body: JSON.stringify({
                    collectionID: collection.id,
                    files: encryptedFileKeys,
                }),
            }),
        );
    });

export const restoreToCollection = async (
    collection: Collection,
    files: EnteFile[],
) =>
    batched(files, async (batchFiles) => {
        const encryptedFileKeys = await encryptWithCollectionKey(
            collection,
            batchFiles,
        );
        ensureOk(
            await fetch(await apiURL("/collections/restore-files"), {
                method: "POST",
                headers: await authenticatedRequestHeaders(),
                body: JSON.stringify({
                    collectionID: collection.id,
                    files: encryptedFileKeys,
                }),
            }),
        );
    });

export const moveToCollection = async (
    collection: Collection,
    files: EnteFile[],
) =>
    Promise.all(
        groupFilesByCollectionID(files)
            .entries()
            .filter(([cid]) => cid != collection.id)
            .map(([cid, cf]) => moveFromCollection(cid, collection, cf)),
    );

export const moveFromCollection = async (
    fromCollectionID: number,
    toCollection: Collection,
    files: EnteFile[],
) =>
    batched(files, async (batchFiles) => {
        const encryptedFileKeys = await encryptWithCollectionKey(
            toCollection,
            batchFiles,
        );
        ensureOk(
            await fetch(await apiURL("/collections/move-files"), {
                method: "POST",
                headers: await authenticatedRequestHeaders(),
                body: JSON.stringify({
                    fromCollectionID: fromCollectionID,
                    toCollectionID: toCollection.id,
                    files: encryptedFileKeys,
                }),
            }),
        );
    });
const uniqueFilesByID = (files: EnteFile[]) => {
    const seen = new Set<number>();
    const uniqueFiles: EnteFile[] = [];

    for (const file of files) {
        if (seen.has(file.id)) continue;
        seen.add(file.id);
        uniqueFiles.push(file);
    }

    return uniqueFiles;
};

const fileIDsInCollection = (
    collectionID: number,
    collectionFiles: EnteFile[],
): Set<number> =>
    new Set(
        collectionFiles
            .filter((file) => file.collectionID == collectionID)
            .map((file) => file.id),
    );

const hashAndTypeKey = (file: EnteFile) => {
    const hash = metadataHash(file.metadata);
    if (!hash) return undefined;
    return `${hash}:${file.metadata.fileType}`;
};

const userOwnedEquivalentFilesByHashAndType = (
    files: EnteFile[],
    currentUserID: number,
) => {
    const equivalents = new Map<string, EnteFile>();

    for (const file of files) {
        if (file.ownerID != currentUserID) continue;

        const key = hashAndTypeKey(file);
        if (!key || equivalents.has(key)) continue;
        equivalents.set(key, file);
    }

    return equivalents;
};

// Bridge repeated shared favorite toggles before the next pull.
const pendingFavoriteFilesByHashAndType = new Map<string, EnteFile>();
let pendingUserFavoritesCollection: Collection | undefined;
let pendingUserFavoritesCollectionPromise: Promise<Collection> | undefined;

const rememberPendingFavoriteFiles = (
    sourceFiles: EnteFile[],
    favoriteFiles: EnteFile[],
    userID: number,
) => {
    const favoriteFilesByHashAndType = userOwnedEquivalentFilesByHashAndType(
        favoriteFiles,
        userID,
    );

    for (const sourceFile of sourceFiles) {
        const hashAndType = hashAndTypeKey(sourceFile);
        const favoriteFile = hashAndType
            ? favoriteFilesByHashAndType.get(hashAndType)
            : undefined;
        if (hashAndType && favoriteFile) {
            pendingFavoriteFilesByHashAndType.set(hashAndType, favoriteFile);
        }
    }
};

const splitPendingFavoriteFiles = (files: EnteFile[], userID: number) => {
    const pendingFiles: EnteFile[] = [];

    const remainingFiles: EnteFile[] = [];
    const seenPendingFileIDs = new Set<number>();

    for (const file of files) {
        if (file.ownerID == userID) {
            remainingFiles.push(file);
            continue;
        }

        const key = hashAndTypeKey(file);
        const pendingFavoriteFile = key
            ? pendingFavoriteFilesByHashAndType.get(key)
            : undefined;

        if (pendingFavoriteFile) {
            if (!seenPendingFileIDs.has(pendingFavoriteFile.id)) {
                seenPendingFileIDs.add(pendingFavoriteFile.id);
                pendingFiles.push(pendingFavoriteFile);
            }
        } else {
            remainingFiles.push(file);
        }
    }

    return { pendingFiles, remainingFiles };
};

const forgetPendingFavoriteFileIDs = (fileIDs: number[]) => {
    if (!fileIDs.length) return;

    const deletedFileIDs = new Set(fileIDs);
    for (const [
        key,
        pendingFavoriteFile,
    ] of pendingFavoriteFilesByHashAndType.entries()) {
        if (deletedFileIDs.has(pendingFavoriteFile.id)) {
            pendingFavoriteFilesByHashAndType.delete(key);
        }
    }
};

export const copyFiles = async (
    dstCollection: Collection,
    files: EnteFile[],
): Promise<EnteFile[]> => {
    if (!files.length) return [];

    // Copying creates owned IDs, so the destination must be owned.
    const currentUserID = ensureLocalUser().id;
    if (dstCollection.owner.id != currentUserID) {
        throw new Error("Destination collection must be owned by the actor");
    }

    const uniqueFiles = uniqueFilesByID(files);
    const copiedFiles: EnteFile[] = [];

    for (const [srcCollectionID, sourceFiles] of groupFilesByCollectionID(
        uniqueFiles,
    ).entries()) {
        for (const batchFiles of batch(sourceFiles, copyRequestBatchSize)) {
            if (
                batchFiles.some(
                    (file) =>
                        file.ownerID == currentUserID ||
                        file.collectionID != srcCollectionID,
                )
            ) {
                throw new Error(
                    "Can only copy files owned by other users from the source collection",
                );
            }

            const encryptedFileKeys = await encryptWithCollectionKey(
                dstCollection,
                batchFiles,
            );

            const res = await fetch(await apiURL("/files/copy"), {
                method: "POST",
                headers: await authenticatedRequestHeaders(),
                body: JSON.stringify({
                    dstCollectionID: dstCollection.id,
                    srcCollectionID,
                    files: encryptedFileKeys,
                }),
            });
            ensureOk(res);

            const { oldToNewFileIDMap } = CopyFilesResponse.parse(
                await res.json(),
            );

            for (const file of batchFiles) {
                const copiedFileID = oldToNewFileIDMap[file.id.toString()];
                if (!copiedFileID) {
                    throw new Error(`Failed to copy file ${file.id}`);
                }

                copiedFiles.push({
                    ...file,
                    id: copiedFileID,
                    ownerID: currentUserID,
                    collectionID: dstCollection.id,
                });
            }
        }
    }

    return copiedFiles;
};

const savedUserUncategorizedCollection = async () => {
    const userID = ensureLocalUser().id;
    return findUserUncategorizedCollection(await savedCollections(), userID);
};

export const savedOrCreateUserUncategorizedCollection = async () =>
    (await savedUserUncategorizedCollection()) ??
    createUncategorizedCollection();

export const addOrCopyToCollection = async (
    dstCollection: Collection,
    files: EnteFile[],
) => {
    const addedFiles: EnteFile[] = [];
    if (!files.length) return addedFiles;

    if (!canAddFilesToCollection(dstCollection)) {
        throw new Error("Current user cannot add files to this collection");
    }

    const currentUserID = ensureLocalUser().id;
    const collectionFiles = await savedCollectionFiles();

    const destinationFileIDs = fileIDsInCollection(
        dstCollection.id,
        collectionFiles,
    );
    const filesMissingFromDestination = uniqueFilesByID(files).filter(
        (file) => !destinationFileIDs.has(file.id),
    );

    if (!filesMissingFromDestination.length) return addedFiles;

    const [ownedFiles, otherOwnedFiles] = splitByPredicate(
        filesMissingFromDestination,
        (file) => file.ownerID == currentUserID,
    );

    if (ownedFiles.length) {
        await addToCollection(dstCollection, ownedFiles);
        ownedFiles.forEach((file) => destinationFileIDs.add(file.id));
        addedFiles.push(...ownedFiles);
    }

    if (!otherOwnedFiles.length) return addedFiles;

    // Reuse an owned hash/type equivalent; copy only when none exists.
    const userOwnedFilesByHashAndType = userOwnedEquivalentFilesByHashAndType(
        collectionFiles,
        currentUserID,
    );

    const filesToAdd: EnteFile[] = [];
    const filesToCopy: EnteFile[] = [];
    const seenAddFileIDs = new Set<number>();
    const seenCopyFileIDs = new Set<number>();

    for (const file of otherOwnedFiles) {
        const fileHashAndTypeKey = hashAndTypeKey(file);

        const userOwnedEquivalent = fileHashAndTypeKey
            ? userOwnedFilesByHashAndType.get(fileHashAndTypeKey)
            : undefined;
        const shouldAddOwnedEquivalent = !!userOwnedEquivalent;

        if (shouldAddOwnedEquivalent) {
            if (!seenAddFileIDs.has(userOwnedEquivalent.id)) {
                seenAddFileIDs.add(userOwnedEquivalent.id);
                filesToAdd.push(userOwnedEquivalent);
            }
        } else if (!seenCopyFileIDs.has(file.id)) {
            seenCopyFileIDs.add(file.id);
            filesToCopy.push(file);
        }
    }

    const reusableOwnedFiles = uniqueFilesByID(filesToAdd).filter(
        (file) => !destinationFileIDs.has(file.id),
    );

    if (reusableOwnedFiles.length) {
        await addToCollection(dstCollection, reusableOwnedFiles);
        reusableOwnedFiles.forEach((file) => destinationFileIDs.add(file.id));
        addedFiles.push(...reusableOwnedFiles);
    }

    if (!filesToCopy.length) return addedFiles;

    // A shared destination cannot own the copy; stage it in Uncategorized.
    const copyDestination = canDirectlyUploadToCollection(dstCollection)
        ? dstCollection
        : await savedOrCreateUserUncategorizedCollection();

    const copiedFiles = await copyFiles(copyDestination, filesToCopy);

    if (copyDestination.id != dstCollection.id) {
        const filesToAddAfterCopy = uniqueFilesByID(copiedFiles).filter(
            (file) => !destinationFileIDs.has(file.id),
        );
        if (filesToAddAfterCopy.length) {
            await addToCollection(dstCollection, filesToAddAfterCopy);
            filesToAddAfterCopy.forEach((file) =>
                destinationFileIDs.add(file.id),
            );
            addedFiles.push(...filesToAddAfterCopy);
        }
    } else {
        addedFiles.push(...copiedFiles);
    }

    return addedFiles;
};

const encryptWithCollectionKey = async (
    collection: Collection,
    files: EnteFile[],
): Promise<CollectionFileItem[]> =>
    Promise.all(
        files.map(async (file) => {
            const box = await encryptBox(file.key, collection.key);
            return {
                id: file.id,
                encryptedKey: box.encryptedData,
                keyDecryptionNonce: box.nonce,
            };
        }),
    );

export const moveToTrash = async (files: EnteFile[]) => {
    await batched(files, async (batchFiles) =>
        ensureOk(
            await fetch(await apiURL("/files/trash"), {
                method: "POST",
                headers: await authenticatedRequestHeaders(),
                body: JSON.stringify({
                    items: batchFiles.map((file) => ({
                        fileID: file.id,
                        collectionID: file.collectionID,
                    })),
                }),
            }),
        ),
    );
    forgetPendingFavoriteFileIDs(files.map((file) => file.id));
};

export const deleteFromTrash = async (fileIDs: number[]) => {
    await batched(fileIDs, async (batchIDs) =>
        ensureOk(
            await fetch(await apiURL("/trash/delete"), {
                method: "POST",
                headers: await authenticatedRequestHeaders(),
                body: JSON.stringify({ fileIDs: batchIDs }),
            }),
        ),
    );
    forgetPendingFavoriteFileIDs(fileIDs);
};

// The remove endpoint crosses ownership boundaries.
// Owned files leave owned collections by moving, so one copy survives.
export const removeFromCollection = async (
    collection: Collection,
    files: EnteFile[],
): Promise<number> =>
    collection.owner.id == ensureLocalUser().id
        ? removeFromOwnCollection(collection.id, files)
        : removeFromOthersCollection(collection, files);

export const removeFromOwnCollection = async (
    collectionID: number,
    files: EnteFile[],
) => {
    const userID = ensureLocalUser().id;
    const [userFiles, nonUserFiles] = splitByPredicate(
        files,
        (f) => f.ownerID == userID,
    );
    if (userFiles.length) {
        await removeOwnFilesFromOwnCollection(collectionID, userFiles);
    }
    if (nonUserFiles.length) {
        await removeNonCollectionOwnerFiles(collectionID, nonUserFiles);
    }
    return files.length;
};

const removeFromOthersCollection = async (
    collection: Collection,
    files: EnteFile[],
) => {
    const userID = ensureLocalUser().id;
    const isAdmin =
        collection.sharees.find((s) => s.id == userID)?.role == "ADMIN";

    if (isAdmin) {
        if (files.length) {
            await removeNonCollectionOwnerFiles(collection.id, files);
        }
        return files.length;
    }

    const [userFiles] = splitByPredicate(files, (f) => f.ownerID == userID);
    if (userFiles.length) {
        await removeNonCollectionOwnerFiles(collection.id, userFiles);
    }
    return userFiles.length;
};

// Preserve one owned instance, falling back to Uncategorized.
const removeOwnFilesFromOwnCollection = async (
    collectionID: number,
    filesToRemove: EnteFile[],
) => {
    const userID = ensureLocalUser().id;
    const collections = await savedCollections();
    const collectionFiles = await savedCollectionFiles();

    const collectionsByID = new Map(collections.map((c) => [c.id, c]));

    const filesToRemoveIDs = new Set(filesToRemove.map((f) => f.id));
    const pendingRemove = (f: EnteFile) => filesToRemoveIDs.has(f.id);

    const collectionFilesToRemove = collectionFiles.filter(pendingRemove);
    const groups = groupFilesByCollectionID(collectionFilesToRemove);
    for (const [targetCollectionID, filesInCollection] of groups.entries()) {
        if (targetCollectionID == collectionID) continue;

        const targetCollection = collectionsByID.get(targetCollectionID)!;
        if (targetCollection.owner.id != userID) continue;
        if (targetCollection.type == "uncategorized") continue;

        const filesInCollectionToRemove =
            filesInCollection.filter(pendingRemove);
        if (!filesInCollectionToRemove.length) continue;

        await moveFromCollection(
            collectionID,
            targetCollection,
            filesInCollectionToRemove,
        );

        filesInCollectionToRemove.forEach((f) => filesToRemoveIDs.delete(f.id));
    }

    const remainingFiles = filesToRemove.filter(pendingRemove);
    if (remainingFiles.length) {
        const uncategorizedCollection =
            findUserUncategorizedCollection(collections, userID) ??
            (await createUncategorizedCollection());

        await moveFromCollection(
            collectionID,
            uncategorizedCollection,
            remainingFiles,
        );
    }
};

const removeNonCollectionOwnerFiles = async (
    collectionID: number,
    files: EnteFile[],
) =>
    batched(files, async (batchFiles) =>
        ensureOk(
            await fetch(await apiURL("/collections/v3/remove-files"), {
                method: "POST",
                headers: await authenticatedRequestHeaders(),
                body: JSON.stringify({
                    collectionID,
                    fileIDs: batchFiles.map((f) => f.id),
                }),
            }),
        ),
    );

export const deleteCollection = async (
    collectionID: number,
    opts?: { keepFiles?: boolean },
) => {
    const keepFiles = opts?.keepFiles ?? false;

    if (keepFiles) {
        const collectionFiles = await savedCollectionFiles();
        await removeFromOwnCollection(
            collectionID,
            collectionFiles.filter((f) => f.collectionID == collectionID),
        );
    }

    ensureOk(
        await fetch(
            await apiURL(`/collections/v3/${collectionID}`, {
                collectionID,
                keepFiles,
            }),
            { method: "DELETE", headers: await authenticatedRequestHeaders() },
        ),
    );
};

export const renameCollection = async (
    collection: Collection,
    newName: string,
) => {
    // Named quick links become regular collections.
    if (collection.magicMetadata?.data.subType == CollectionSubType.quicklink) {
        await updateCollectionPrivateMagicMetadata(collection, {
            subType: CollectionSubType.default,
        });
    }
    const { encryptedData: encryptedName, nonce: nameDecryptionNonce } =
        await encryptBox(new TextEncoder().encode(newName), collection.key);
    await postCollectionsRename({
        collectionID: collection.id,
        encryptedName,
        nameDecryptionNonce,
    });
};

interface RenameRequest {
    collectionID: number;
    encryptedName: string;
    nameDecryptionNonce: string;
}

const postCollectionsRename = async (renameRequest: RenameRequest) =>
    ensureOk(
        await fetch(await apiURL("/collections/rename"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify(renameRequest),
        }),
    );

export const updateCollectionVisibility = async (
    collection: Collection,
    visibility: ItemVisibility,
) =>
    collection.owner.id == ensureLocalUser().id
        ? updateCollectionPrivateMagicMetadata(collection, { visibility })
        : updateCollectionShareeMagicMetadata(collection, { visibility });

export const updateCollectionOrder = async (
    collection: Collection,
    order: CollectionOrder,
) => updateCollectionPrivateMagicMetadata(collection, { order });

export const updateShareeCollectionOrder = async (
    collection: Collection,
    order: CollectionOrder,
) => updateCollectionShareeMagicMetadata(collection, { order });

export const updateCollectionSortOrder = async (
    collection: Collection,
    asc: boolean,
) => updateCollectionPublicMagicMetadata(collection, { asc });

const albumDescriptionSegmenter =
    typeof Intl !== "undefined" && "Segmenter" in Intl
        ? new Intl.Segmenter(undefined, { granularity: "grapheme" })
        : null;

export const albumDescriptionGraphemeCount = (description: string) =>
    albumDescriptionSegmenter
        ? Array.from(albumDescriptionSegmenter.segment(description)).length
        : Array.from(description).length;

export const updateCollectionDetails = async (
    collection: Collection,
    { description, coverID }: { description?: string; coverID?: number },
) => {
    const updates: CollectionPublicMagicMetadataData = {};
    if (description !== undefined) {
        const normalizedDescription = description.trim();
        if (
            albumDescriptionGraphemeCount(normalizedDescription) >
            maxAlbumDescriptionLength
        ) {
            throw new Error(
                `Album descriptions cannot exceed ${maxAlbumDescriptionLength} characters`,
            );
        }
        updates.caption = normalizedDescription;
    }
    if (coverID !== undefined) updates.coverID = coverID;

    return updateCollectionPublicMagicMetadata(collection, updates);
};

export const updateCollectionLayout = async (
    collection: Collection,
    layout: string,
) => updateCollectionPublicMagicMetadata(collection, { layout });

// Every metadata merge below requires current remote data and version.
const updateCollectionPrivateMagicMetadata = async (
    { id, key, magicMetadata }: Collection,
    updates: CollectionPrivateMagicMetadataData,
) =>
    putCollectionsMagicMetadata({
        id,
        magicMetadata: await encryptMagicMetadata(
            createMagicMetadata(
                { ...magicMetadata?.data, ...updates },
                magicMetadata?.version,
            ),
            key,
        ),
    });

const putCollectionsMagicMetadata = async (
    updateRequest: UpdateMagicMetadataRequest,
) =>
    ensureOk(
        await fetch(await apiURL("/collections/magic-metadata"), {
            method: "PUT",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify(updateRequest),
        }),
    );

const updateCollectionPublicMagicMetadata = async (
    { id, key, pubMagicMetadata }: Collection,
    updates: CollectionPublicMagicMetadataData,
) =>
    putCollectionsPublicMagicMetadata({
        id,
        magicMetadata: await encryptMagicMetadata(
            createMagicMetadata(
                { ...pubMagicMetadata?.data, ...updates },
                pubMagicMetadata?.version,
            ),
            key,
        ),
    });

const putCollectionsPublicMagicMetadata = async (
    updateRequest: UpdateMagicMetadataRequest,
) =>
    ensureOk(
        await fetch(await apiURL("/collections/public-magic-metadata"), {
            method: "PUT",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify(updateRequest),
        }),
    );

const updateCollectionShareeMagicMetadata = async (
    { id, key, sharedMagicMetadata }: Collection,
    updates: CollectionShareeMagicMetadataData,
) =>
    putCollectionsShareeMagicMetadata({
        id,
        magicMetadata: await encryptMagicMetadata(
            createMagicMetadata(
                { ...sharedMagicMetadata?.data, ...updates },
                sharedMagicMetadata?.version,
            ),
            key,
        ),
    });

const putCollectionsShareeMagicMetadata = async (
    updateRequest: UpdateMagicMetadataRequest,
) =>
    ensureOk(
        await fetch(await apiURL("/collections/sharee-magic-metadata"), {
            method: "PUT",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify(updateRequest),
        }),
    );

const createFavoritesCollection = () =>
    createCollection(favoritesCollectionName, "favorites");

export const createUncategorizedCollection = () =>
    createCollection(uncategorizedCollectionName, "uncategorized");

const savedOrCreateUserFavoritesCollection = async () => {
    const favoritesCollection = await savedUserFavoritesCollection();
    if (favoritesCollection) return favoritesCollection;

    // Avoid creating a second Favorites before the first one is pulled.
    pendingUserFavoritesCollectionPromise ??= createFavoritesCollection()
        .then((collection) => {
            pendingUserFavoritesCollection = collection;
            return collection;
        })
        .finally(() => {
            pendingUserFavoritesCollectionPromise = undefined;
        });

    return pendingUserFavoritesCollectionPromise;
};

export const savedUserFavoritesCollection = async () => {
    const userID = ensureLocalUser().id;
    const collections = await savedCollections();
    return (
        collections.find(
            (collection) =>
                collection.type == "favorites" && collection.owner.id == userID,
        ) ??
        (pendingUserFavoritesCollection?.owner.id == userID
            ? pendingUserFavoritesCollection
            : undefined)
    );
};

export const addToFavoritesCollection = async (files: EnteFile[]) => {
    const userID = ensureLocalUser().id;

    const hashlessSharedFile = files.find(
        (file) => file.ownerID != userID && !hashAndTypeKey(file),
    );

    if (hashlessSharedFile) {
        throw new Error("Cannot favorite shared files without metadata hash");
    }

    const favoritesCollection = await savedOrCreateUserFavoritesCollection();

    const { pendingFiles, remainingFiles } = splitPendingFavoriteFiles(
        files,
        userID,
    );

    if (pendingFiles.length) {
        await addToCollection(favoritesCollection, pendingFiles);
    }

    const addedFiles = await addOrCopyToCollection(
        favoritesCollection,
        remainingFiles,
    );

    rememberPendingFavoriteFiles(
        files,
        pendingFiles.concat(addedFiles),
        userID,
    );
};

export const removeFromFavoritesCollection = async (files: EnteFile[]) => {
    const userID = ensureLocalUser().id;

    const favoritesCollection = await savedUserFavoritesCollection();
    if (!favoritesCollection) {
        throw new Error("Favorites collection does not exist");
    }

    const resolvedFiles = await resolveFavoritesFilesForRemoval(
        favoritesCollection,
        files,
    );
    if (!resolvedFiles.length) return;

    await removeFromOwnCollection(
        favoritesCollection.id,
        uniqueFilesByID(resolvedFiles),
    );
    rememberPendingFavoriteFiles(files, resolvedFiles, userID);
};

const resolveFavoritesFilesForRemoval = async (
    favoritesCollection: Collection,
    files: EnteFile[],
) => {
    const userID = ensureLocalUser().id;

    const favoriteFilesByHashAndType = userOwnedEquivalentFilesByHashAndType(
        (await savedCollectionFiles()).filter(
            (file) => file.collectionID == favoritesCollection.id,
        ),
        userID,
    );

    return files.map((file) => {
        if (
            file.ownerID != userID &&
            file.collectionID != favoritesCollection.id
        ) {
            const key = hashAndTypeKey(file);
            const favoriteFile = key
                ? (favoriteFilesByHashAndType.get(key) ??
                  pendingFavoriteFilesByHashAndType.get(key))
                : undefined;
            if (!favoriteFile) {
                throw new Error("Could not resolve favorite file for removal");
            }
            return favoriteFile;
        }
        return file;
    });
};

const savedOrCreateDefaultHiddenCollection = async () =>
    (await savedDefaultHiddenCollection()) ?? createDefaultHiddenCollection();

const savedDefaultHiddenCollection = async () =>
    (await savedCollections()).find((collection) =>
        isDefaultHiddenCollection(collection),
    );

const createDefaultHiddenCollection = () =>
    createCollection(defaultHiddenCollectionName, "album", {
        subType: CollectionSubType.defaultHidden,
        visibility: ItemVisibility.hidden,
    });

export const isDefaultHiddenCollection = (collection: Collection) =>
    collection.magicMetadata?.data.subType == CollectionSubType.defaultHidden;

// Concurrent clients may create more than one default-hidden collection.
export const findDefaultHiddenCollectionIDs = (collections: Collection[]) =>
    new Set<number>(
        collections
            .filter(isDefaultHiddenCollection)
            .map((collection) => collection.id),
    );

export const isHiddenCollection = (
    collection: Collection,
    currentUserID?: number,
) => {
    // Workers must pass this ID because they cannot read the browser session.
    const userID =
        currentUserID ?? (haveWindow() ? ensureLocalUser().id : undefined);

    if (userID === undefined) {
        throw new Error(
            "isHiddenCollection: currentUserID is required outside window context",
        );
    }
    if (collection.owner.id == userID) {
        return (
            collection.magicMetadata?.data.visibility == ItemVisibility.hidden
        );
    }
    return (
        collection.sharedMagicMetadata?.data.visibility == ItemVisibility.hidden
    );
};

export const isArchivedCollection = (collection: Collection) =>
    collection.magicMetadata?.data.visibility == ItemVisibility.archived ||
    collection.sharedMagicMetadata?.data.visibility == ItemVisibility.archived;

export const canRemoveFilesFromAllParticipants = (collection: Collection) => {
    const userID = ensureLocalUser().id;
    if (collection.owner.id == userID) return true;
    const sharee = collection.sharees.find((s) => s.id == userID);
    return sharee?.role == "ADMIN";
};

export const hideFiles = async (files: EnteFile[]) => {
    const userID = ensureLocalUser().id;
    const defaultHiddenCollection =
        await savedOrCreateDefaultHiddenCollection();
    const collections = await savedCollections();
    const collectionsByID = new Map(collections.map((c) => [c.id, c]));

    for (const [collectionID, collectionFiles] of groupFilesByCollectionID(
        files,
    ).entries()) {
        if (collectionID == defaultHiddenCollection.id) continue;

        const collection = collectionsByID.get(collectionID);
        if (!collection) {
            throw new Error(`Collection ${collectionID} not found`);
        }

        if (collection.owner.id == userID) {
            await moveFromCollection(
                collectionID,
                defaultHiddenCollection,
                collectionFiles,
            );
        } else {
            // Shared collections cannot move files across ownership.
            await removeFromCollection(collection, collectionFiles);
        }
    }
};

export const shareCollection = async (
    collection: Collection,
    withUserEmail: string,
    role: CollectionNewParticipantRole,
) => {
    const publicKey = await getPublicKey(withUserEmail);
    const encryptedKey = await boxSeal(collection.key, publicKey);

    ensureOk(
        await fetch(await apiURL("/collections/share"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({
                collectionID: collection.id,
                email: withUserEmail,
                role,
                encryptedKey,
            }),
        }),
    );
};

export const unshareCollection = async (collectionID: number, email: string) =>
    ensureOk(
        await fetch(await apiURL("/collections/unshare"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({ collectionID, email }),
        }),
    );

export type CreatePublicURLAttributes = Pick<
    Partial<PublicURL>,
    | "enableCollect"
    | "enableJoin"
    | "enableComment"
    | "validTill"
    | "deviceLimit"
>;

export const createPublicURL = async (
    collectionID: number,
    attributes?: CreatePublicURLAttributes,
): Promise<PublicURL> => {
    const enableComment = true;
    const res = await fetch(await apiURL("/collections/share-url"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify({ collectionID, enableComment, ...attributes }),
    });
    ensureOk(res);
    return z.object({ result: RemotePublicURL }).parse(await res.json()).result;
};

export type UpdatePublicURLAttributes = Omit<
    Partial<PublicURL>,
    "url" | "enablePassword"
> & { disablePassword?: boolean; passHash?: string };

export const updatePublicURL = async (
    collectionID: number,
    updates: UpdatePublicURLAttributes,
): Promise<PublicURL> => {
    const res = await fetch(await apiURL("/collections/share-url"), {
        method: "PUT",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify({ collectionID, ...updates }),
    });
    ensureOk(res);
    return z.object({ result: RemotePublicURL }).parse(await res.json()).result;
};

export const deleteShareURL = async (collectionID: number) =>
    ensureOk(
        await fetch(await apiURL(`/collections/share-url/${collectionID}`), {
            method: "DELETE",
            headers: await authenticatedRequestHeaders(),
        }),
    );

export const leaveSharedCollection = async (collectionID: number) =>
    ensureOk(
        await fetch(await apiURL(`/collections/leave/${collectionID}`), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
        }),
    );

const CollectionAction = z.object({
    collectionID: z.number(),
    fileID: z.number().nullish(),
});

type CollectionAction = z.infer<typeof CollectionAction>;

const PendingRemovalActionsResponse = z.object({
    actions: z.array(CollectionAction).nullish(),
});

export const fetchPendingRemovalActions = async (): Promise<
    CollectionAction[]
> => {
    const res = await fetch(
        await apiURL("/collection-actions/pending-remove"),
        { headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
    const { actions } = PendingRemovalActionsResponse.parse(await res.json());
    return actions ?? [];
};

export const movePendingRemovalActionsToUncategorized = async (
    collections: Collection[],
) => {
    const userID = ensureLocalUser().id;
    const pendingActions = await fetchPendingRemovalActions();
    if (!pendingActions.length) return;

    const collectionToFileIDs = new Map<number, Set<number>>();
    for (const action of pendingActions) {
        if (action.fileID == null) continue;
        const fileIDs = collectionToFileIDs.get(action.collectionID);
        if (fileIDs) {
            fileIDs.add(action.fileID);
        } else {
            collectionToFileIDs.set(
                action.collectionID,
                new Set([action.fileID]),
            );
        }
    }

    if (!collectionToFileIDs.size) return;

    const collectionFiles = await savedCollectionFiles();

    const filesByCollectionID = groupFilesByCollectionID(collectionFiles);

    const collectionByID = new Map(collections.map((c) => [c.id, c]));

    let uncategorizedCollection: Collection | undefined;
    let defaultHiddenCollection: Collection | undefined;

    for (const [
        collectionID,
        pendingFileIDs,
    ] of collectionToFileIDs.entries()) {
        const sourceCollection = collectionByID.get(collectionID);
        const filesInCollection = filesByCollectionID.get(collectionID) ?? [];
        const filesToMove = filesInCollection.filter((file) =>
            pendingFileIDs.has(file.id),
        );

        if (!filesToMove.length) continue;

        const isSourceHidden =
            sourceCollection && isHiddenCollection(sourceCollection);

        // Rescue removals without changing their hidden/visible boundary.
        let targetCollection: Collection;
        if (isSourceHidden) {
            if (!defaultHiddenCollection) {
                defaultHiddenCollection =
                    collections.find(isDefaultHiddenCollection) ??
                    (await createDefaultHiddenCollection());
            }
            targetCollection = defaultHiddenCollection;
        } else {
            if (!uncategorizedCollection) {
                uncategorizedCollection =
                    findUserUncategorizedCollection(collections, userID) ??
                    (await createUncategorizedCollection());
            }
            targetCollection = uncategorizedCollection;
        }

        await moveFromCollection(collectionID, targetCollection, filesToMove);
    }
};

export const cleanUncategorized = async (
    uncategorizedCollection: Collection,
): Promise<number> => {
    const userID = ensureLocalUser().id;
    const collections = await savedCollections();
    const collectionFiles = await savedCollectionFiles();

    const uncategorizedFiles = collectionFiles.filter(
        (f) => f.collectionID == uncategorizedCollection.id,
    );

    if (!uncategorizedFiles.length) return 0;

    const fileIDToCollectionIDs = new Map<number, number[]>();
    for (const file of collectionFiles) {
        if (file.collectionID == uncategorizedCollection.id) continue;
        const existing = fileIDToCollectionIDs.get(file.id);
        if (existing) {
            existing.push(file.collectionID);
        } else {
            fileIDToCollectionIDs.set(file.id, [file.collectionID]);
        }
    }

    const userOwnedCollectionIDs = new Set(
        collections
            .filter(
                (c) =>
                    c.owner.id == userID &&
                    c.type != "uncategorized" &&
                    !isHiddenCollection(c),
            )
            .map((c) => c.id),
    );

    const collectionsByID = new Map(collections.map((c) => [c.id, c]));

    const filesToClean = uncategorizedFiles.filter((file) => {
        const otherCollectionIDs = fileIDToCollectionIDs.get(file.id);
        if (!otherCollectionIDs) return false;
        return otherCollectionIDs.some((cid) =>
            userOwnedCollectionIDs.has(cid),
        );
    });

    if (!filesToClean.length) return 0;

    const filesByTargetCollection = new Map<number, EnteFile[]>();
    for (const file of filesToClean) {
        const otherCollectionIDs = fileIDToCollectionIDs.get(file.id)!;
        const targetCollectionID = otherCollectionIDs.find((cid) =>
            userOwnedCollectionIDs.has(cid),
        );
        if (!targetCollectionID) continue;

        const existing = filesByTargetCollection.get(targetCollectionID) ?? [];
        existing.push(file);
        filesByTargetCollection.set(targetCollectionID, existing);
    }

    let cleanedCount = 0;
    for (const [targetCollectionID, files] of filesByTargetCollection) {
        const targetCollection = collectionsByID.get(targetCollectionID);
        if (!targetCollection) continue;

        await moveFromCollection(
            uncategorizedCollection.id,
            targetCollection,
            files,
        );
        cleanedCount += files.length;
    }

    return cleanedCount;
};
