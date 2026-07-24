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

/**
 * Create a new album (a collection of type "album") on remote, and return its
 * local representation.
 *
 * Remote only, does not modify local state.
 *
 * @param albumName The name to use for the new album.
 */
export const createAlbum = (albumName: string) =>
    createCollection(albumName, "album");

/**
 * Create a new quick link collection on remote, and return its local
 * representation.
 *
 * Remote only, does not modify local state.
 *
 * @param name The name to use for the new quick link collection.
 */
export const createQuickLinkCollection = (name: string) =>
    createCollection(name, "album", {
        subType: CollectionSubType.quicklink,
        visibility: ItemVisibility.visible,
    });

/**
 * Create a new hidden album on remote, and return its local representation.
 *
 * Remote only, does not modify local state.
 *
 * @param albumName The name to use for the new hidden album.
 */
export const createHiddenAlbum = (albumName: string) =>
    createCollection(albumName, "album", { visibility: ItemVisibility.hidden });

/**
 * Create a new collection on remote, and return its local representation.
 *
 * Remote only, does not modify local state.
 *
 * @param name The name of the new collection.
 *
 * @param type The type of the new collection.
 *
 * @param magicMetadataData Optional metadata to use as the collection's private
 * mutable metadata when creating the new collection.
 */
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

/**
 * Given a {@link RemoteCollection}, first obtain its decryption key, and then
 * use that to decrypt and return the collection itself.
 */
const decryptRemoteKeyAndCollection = async (collection: RemoteCollection) =>
    decryptRemoteCollection(collection, await decryptCollectionKey(collection));

/**
 * Return the decrypted collection key (as a base64 string) for the given
 * {@link RemoteCollection}.
 */
export const decryptCollectionKey = async (
    collection: RemoteCollection,
): Promise<string> => {
    const { owner, encryptedKey, keyDecryptionNonce } = collection;
    if (owner.id == ensureLocalUser().id) {
        // The collection key of collections owned by the user is encrypted with
        // the user's master key. The nonce will be present in such cases.
        return decryptBox(
            { encryptedData: encryptedKey, nonce: keyDecryptionNonce! },
            await ensureMasterKeyFromSession(),
        );
    } else {
        // The collection key of collections shared with the user is encrypted
        // with the user's public key.
        return boxSealOpen(encryptedKey, await ensureUserKeyPair());
    }
};

/**
 * Zod schema for a remote response containing a single collection.
 */
const CollectionResponse = z.object({ collection: RemoteCollection });

/**
 * Create a collection on remote with the provided data, and return the new
 * remote collection object returned by remote on success.
 */
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

/**
 * Fetch a collection from remote by its ID.
 *
 * Remote only, does not use or modify local state.
 *
 * This is not expected to be needed in the normal flow of things, since we
 * fetch collections en masse, and efficiently, using the collection diff
 * requests.
 *
 * @param collectionID The ID of the collection to fetch.
 *
 * @returns The collection obtained from remote after decrypting its contents.
 */
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

/**
 * Zod schema for a remote response containing a an array of collections.
 */
const CollectionsResponse = z.object({
    collections: z.array(RemoteCollection),
});

/**
 * An collection upsert or deletion obtained as a result of
 * {@link getCollections} invocation.
 *
 * Each change either contains the latest data associated with the collection
 * that has been created or updated, or has a flag set to indicate that the
 * corresponding collection has been deleted.
 */
export interface CollectionChange {
    /**
     * The ID of the collection.
     */
    id: number;
    /**
     * The added or updated collection, or `undefined` for deletions.
     *
     * - This will be set to the (decrypted) collection if it was added or
     *   updated on remote.
     *
     * - This will not be set if the corresponding collection was deleted on
     *   remote.
     */
    collection?: Collection;
    /**
     * Epoch microseconds denoting when this collection was last changed
     * (created or updated or deleted).
     */
    updationTime: number;
}

/**
 * Pull the latest collections from remote.
 *
 * This function uses a delta diff, pulling only changes since the timestamp
 * saved by the last pull.
 *
 * @returns the latest list of collections, reflecting both the state in our
 * local database and on remote.
 */
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
            // Collection was deleted on remote.
            await removeCollectionIDLastSyncTime(id);
            collectionsByID.delete(id);
        }
    }

    const updatedCollections = [...collectionsByID.values()];

    await saveCollections(updatedCollections);
    await saveCollectionsUpdationTime(sinceTime);

    return updatedCollections;
};

/**
 * Fetch all collections that have been added or updated on remote since
 * {@link sinceTime}, with markers for those that have been deleted.
 *
 * @param sinceTime The {@link updationTime} of the latest collection that was
 * fetched in a previous set of changes. This allows us to resume fetching from
 * that point. Pass 0 to fetch from the beginning.
 *
 * @returns An array of {@link CollectionChange}s. It is guaranteed that there
 * will be at most one entry for a given collection in the result array. See:
 * [Note: Diff response will have at most one entry for an id]
 */
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

/**
 * Fetch all files from remote and update our local database.
 *
 * Each time it updates the local database, the {@link onSetCollectionFiles}
 * callback is also invoked to give the caller a chance to bring its own
 * in-memory state up to speed.
 *
 * @param collections The user's collections. These are assumed to be the latest
 * collections on remote (that is, the pull for collections should happen prior
 * to calling this function).
 *
 * @param onSetCollectionFiles An optional callback invoked when the locally
 * saved collection files were replaced by the provided {@link collectionFiles}.
 *
 * The callback is optional because we might be called in a context where we
 * just want to update the local database, and there is no other in-memory state
 * we need to keep in sync.
 *
 * The callback can be invoked multiple times for each pull (once for each batch
 * of changes received, for each collection that was updated).
 *
 * @returns true if one or more files were updated locally, false otherwise.
 */
export const pullCollectionFiles = async (
    collections: Collection[],
    onSetCollectionFiles: ((files: EnteFile[]) => void) | undefined,
) => {
    let didUpdateFiles = false;

    const savedFiles = await savedCollectionFiles();

    // Prune collections files for which we no longer have a collection.
    const collectionIDs = new Set(collections.map((c) => c.id));
    let files = savedFiles.filter((f) => collectionIDs.has(f.collectionID));

    // Update both the saved and in-memory files to reflect the pruning.
    if (files.length != savedFiles.length) {
        await saveCollectionFiles(files);
        onSetCollectionFiles?.(files);
        didUpdateFiles = true;
    }

    for (const collection of collections) {
        let sinceTime = (await savedCollectionLastSyncTime(collection)) ?? 0;
        if (sinceTime == collection.updationTime) {
            // The updationTime of a collection is guaranteed to be >= the
            // updationTime of any file in the collection.
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

        // There might be a difference between the latest updation time of a
        // file in the collection, and the latest time of the collection itself,
        // if something about the collection itself changed, not the files in it
        // (e.g. if the collection was renamed).
        //
        // In such cases, advance the sync time to match the collection's update
        // time so we don't do an unnecessary collection diff the next time.
        await saveCollectionLastSyncTime(collection, collection.updationTime);
    }

    return didUpdateFiles;
};

/**
 * Fetch all files in the given collection have been created or updated since
 * {@link sinceTime}.
 *
 * Remote only, does not modify local state.
 *
 * @param collection The ID of the collection whose updates we want to fetch.
 *
 * @param sinceTime The timestamp of most recently update for the collection
 * that we have already pulled. This serves both as a pagination mechanish, and
 * a way to fetch a delta diff the next time the client needs to pull changes
 * from remote.
 */
const getCollectionDiff = async (collectionID: number, sinceTime: number) => {
    const res = await fetch(
        await apiURL("/collections/v2/diff", { collectionID, sinceTime }),
        { headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
    return FileDiffResponse.parse(await res.json());
};

/**
 * Clear cached thumbnail of an existing file if the thumbnail data has changed.
 *
 * This function in expected to be called when we are processing a collection
 * diff, updating our local state to reflect files that were updated on remote.
 * This is an opportune moment to invalidate any cached thumbnails for files
 * whose thumbnail content has changed.
 *
 * An example of when such invalidation is necessary:
 *
 * 1. Take a photo on mobile, and let it sync via the mobile app to us (web).
 * 2. Edit the photo outside of Ente (e.g. using Apple Photos).
 * 3. When the Ente mobile client next comes into foreground, it'll update the
 *    remote thumbnail for the existing file to reflect the changes.
 *
 * @param existingFile The {@link EnteFile} we had in our local database before
 * processing the diff response. Pass `undefined` to indicate that there was no
 * existing file corresponding to {@link updatedFile}; in such a case this
 * function is a no-op.
 *
 * @param updatedFile The update {@link EntneFile} (with the same file ID as the
 * {@link existingFile}) which we got in the diff response.
 */
const clearCachedThumbnailIfContentChanged = async (
    existingFile: EnteFile | undefined,
    updatedFile: EnteFile,
) => {
    if (!existingFile) return;

    // The hashes of the files differ, which indicates that the change was in
    // the file's contents, not the metadata itself, and thus we should refresh
    // the thumbnail.
    if (
        metadataHash(existingFile.metadata) !=
        metadataHash(updatedFile.metadata)
    ) {
        // This is an infrequent occurrence, so we lazily get the cache.
        const thumbnailCache = await blobCache("thumbs");
        await thumbnailCache.delete(updatedFile.id.toString());
    }
};

/**
 * Return all collections (both normal and hidden) that are present in our
 * local database.
 */
export const savedAllCollections = (): Promise<Collection[]> =>
    savedCollections();

/**
 * Return all normal (non-hidden) collections that are present in our local
 * database.
 */
export const savedNormalCollections = (): Promise<Collection[]> =>
    savedCollections().then(
        (cs) => splitByPredicate(cs, isHiddenCollection)[1],
    );

/**
 * Return all hidden collections that are present in our local database.
 */
export const savedHiddenCollections = (
    currentUserID?: number,
): Promise<Collection[]> =>
    savedCollections().then(
        (cs) =>
            splitByPredicate(cs, (c) =>
                isHiddenCollection(c, currentUserID),
            )[0],
    );

/**
 * Return a map of the (user-facing) collection name, indexed by collection ID.
 */
export const createCollectionNameByID = (collections: Collection[]) =>
    new Map(collections.map((c) => [c.id, collectionUserFacingName(c)]));

/**
 * Return the "user facing" name of the given collection.
 *
 * Usually this is the same as the collection name, but it might be a different
 * string for special collections like default hidden collections.
 */
export const collectionUserFacingName = (collection: Collection) =>
    isDefaultHiddenCollection(collection)
        ? defaultHiddenCollectionUserFacingName
        : collection.name;

/**
 * A CollectionFileItem represents a file in a API request to add, move or
 * restore files to a particular collection.
 */
interface CollectionFileItem {
    /**
     * The file's ID.
     */
    id: number;
    /**
     * The file's key (as a base64 string), encrypted with the key of the
     * collection to which it is being added or moved.
     */
    encryptedKey: string;
    /**
     * The nonce (as a base64 string) that was used during the encryption of
     * {@link encryptedKey}.
     */
    keyDecryptionNonce: string;
}

const CopyFilesResponse = z.object({
    oldToNewFileIDMap: z.record(z.string(), z.number()),
});

/**
 *
 * @param collection
 * @returns the current role of the user in the collection.
 * if the currentUser is the owner then OWNER, else if
 * it was shared then checks the sharees list to find the role
 * which could be either VIEWER or COLLABORATOR.
 */
const currentUserRoleInCollection = (collection: Collection) => {
    const userID = ensureLocalUser().id;
    if (collection.owner.id == userID) return "OWNER";
    return collection.sharees.find((sharee) => sharee.id == userID)?.role;
};

/**
 *
 * @param collection
 * @returns true if the user can add files to a collection,
 * only the OWNER, ADMIN and COLLABORATOR can actually add
 * file to a collection.
 */
export const canAddFilesToCollection = (collection: Collection) => {
    const role = currentUserRoleInCollection(collection);
    return role == "OWNER" || role == "ADMIN" || role == "COLLABORATOR";
};

/**
 *
 * @param collection
 * @returns whether the current user can directly
 * upload to the collection.
 *
 * A user can directly upload to a collection if he/she
 * is the owner of that particular collection.
 */
export const canDirectlyUploadToCollection = (collection: Collection) =>
    collection.owner.id == ensureLocalUser().id;

/**
 * Make a remote request to add the given {@link files} to the given
 * {@link collection}.
 *
 * Remote only, does not modify local state.
 */
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

/**
 * Make a remote request to restore the given {@link files} to the given
 * {@link collection}.
 *
 * Remote only, does not modify local state.
 */
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

/**
 * Make a remote request to move the given {@link files} (which may be in
 * different collections) to the given {@link collection}.
 *
 * This is a higher level primitive than {@link moveFromCollection} that first
 * segregates the files into per-collection sets, and then performs
 * {@link moveFromCollection} for each such set.
 *
 * Remote only, does not modify local state.
 */
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

/**
 * Make a remote request to move the given {@link files} from a collection (as
 * identified by its {@link fromCollectionID}) to the given
 * {@link toCollection}.
 *
 * Remote only, does not modify local state.
 */
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
/**
 *
 * @param files
 * @returns list of unique files from the files argument.
 *
 * This function just iterates through the files and then
 * stores the file.id and skips any files for which the
 * file.id has been already been seen to prevent duplicates.
 */
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

/**
 *
 * @param collectionID
 * @param collectionFiles
 * @returns Filters the collectionFiles and create a
 * new set with the fileIds of files which belong
 * to the collection having it's id collectionID.
 */
const fileIDsInCollection = (
    collectionID: number,
    collectionFiles: EnteFile[],
): Set<number> =>
    new Set(
        collectionFiles
            .filter((file) => file.collectionID == collectionID)
            .map((file) => file.id),
    );

/**
 *
 * @param file
 * @returns A composite key of the form `${metadataHash}:${fileType}`, used to
 * detect content-equivalent files. Returns undefined if the file has no
 * metadata hash.
 */
const hashAndTypeKey = (file: EnteFile) => {
    const hash = metadataHash(file.metadata);
    if (!hash) return undefined;
    return `${hash}:${file.metadata.fileType}`;
};

/**
 *
 * @param files
 * @param currentUserID
 * @returns A Mapping which has a unique ${hash}:${file.metadata.fileType} key
 * for each of the file which is owned by the current user.
 *
 * This map is currently used in flows where the current user performs actions
 * on shared-files/shared albums, where we check if the current user by any chance
 * have a copy of the files on which the action is being performed on.
 */
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

// Bridges shared favorite toggles before the remote add/move has been pulled
// into local DB.
const pendingFavoriteFilesByHashAndType = new Map<string, EnteFile>();
let pendingUserFavoritesCollection: Collection | undefined;
let pendingUserFavoritesCollectionPromise: Promise<Collection> | undefined;

/**
 *
 * @param sourceFiles The files the user originally performed the actions on. It could be owned/non-owned files.
 *
 * @param favoriteFiles The actual files that were added/removed from the favorites. For shared files
 * this maybe a different user-owned equivalent file.
 *
 * @param userID The userId of the current loggedIn user.
 *
 * If the user favorites a shared file X, the actual Favorites entry may be user-owned file Y.
 * Before remote pull updates local DB, the UI may still only know about shared file X. This
 * helper remembers:
 *
 * X hash:type -> Y
 *
 * Then if the user immediately unfavorites or favorites again, the code can resolve the real
 * favorite file Y instead of trying to operate on shared file X.
 *
 * This also records owned source files, so an owned favorite can immediately
 * resolve shared hash-equivalent rows before the remote pull updates local DB.
 *
 */
const rememberPendingFavoriteFiles = (
    sourceFiles: EnteFile[],
    favoriteFiles: EnteFile[],
    userID: number,
) => {
    // Creating a map by hashAndType for the files which where favorited now
    const favoriteFilesByHashAndType = userOwnedEquivalentFilesByHashAndType(
        favoriteFiles,
        userID,
    );

    // Iterating through the sourceFiles to check whether the files which where
    // favorited have a hashAndType match in favoriteFilesByHashAndType
    // if so storing the file in the pendingFavoriteFilesByHashAndType
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

/**
 *
 * @param files The files which are to be favorited/un-favorited
 * @param userID The userId of the current loggedIn user.
 * @returns
 *
 *  remainingFiles: The files which doesn't have an user-owned copy yet and therefore considered
 * as a shared-file/non-owned file
 *
 *  pendingFiles: The files which already have an owned copy. It could the file was
 *  already owned by the user or because of a prior favoriting the file now has a owned copy.
 */
const splitPendingFavoriteFiles = (files: EnteFile[], userID: number) => {
    const pendingFiles: EnteFile[] = [];

    // Files for which the current user is the owner.
    const remainingFiles: EnteFile[] = [];
    const seenPendingFileIDs = new Set<number>();

    /**
     * Iterating through the files and then pushing the file to the remainingFiles array
     * if it's an owned file or if it's a shared file without an remembered user-owned equivalent
     *
     * For non-owned/shared files, getting the metadataKey of the file and checking
     * if the pendingFavoriteFilesByHashAndType has it, if so it means the file already
     * has a owned copy, like it was favorited before and the remote pull is yet to happen.
     *
     * If so then pushing the file to the pendingFiles else pushing it to the remainingFiles.
     */
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

/**
 *
 * @param fileIDs
 * @returns
 *
 * We had introduced a variable to store the files which
 * where just favorited, so that they aren't copied again
 * as the remotePull doesn't occur after the favoriting action.
 */
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

/**
 *
 * @param dstCollection
 * @param files
 * @returns a new List with each file having their id, ownerID and collectionId
 * updated. the fileId points to the id of the newly created file,
 * the ownerId points to the id of the currentUser and collectionId points to the
 * dstCollection.id
 */
export const copyFiles = async (
    dstCollection: Collection,
    files: EnteFile[],
): Promise<EnteFile[]> => {
    if (!files.length) return [];

    /**
     * Getting the currentUserId and then ensuring that the
     * dstCollection is indeed owned by that person. We only support
     * uploading to owned collection so hence this verification.
     */
    const currentUserID = ensureLocalUser().id;
    if (dstCollection.owner.id != currentUserID) {
        throw new Error("Destination collection must be owned by the actor");
    }

    // Filtering out any duplicates from the list of files to be copied
    const uniqueFiles = uniqueFilesByID(files);
    const copiedFiles: EnteFile[] = [];

    /**
     * Callers are expected to pass only files which aren't owned by the
     * currentUser (the batch validation below enforces this). Since these files
     * are already uploaded to Ente, they will belong to some source collection,
     * so we group them by their source collectionID and iterate per-group.
     */
    for (const [srcCollectionID, sourceFiles] of groupFilesByCollectionID(
        uniqueFiles,
    ).entries()) {
        for (const batchFiles of batch(sourceFiles, copyRequestBatchSize)) {
            /**
             * As said earlier this is strictly for files which aren't owned
             * by the currentUser and only such files can be copied so thus
             * doing a final validation.
             */
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

            // Encrypting the files with the dstCollection Key
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

            // This is just the server responding back with,
            // the old file with ID X is now a new file with ID Y.
            const { oldToNewFileIDMap } = CopyFilesResponse.parse(
                await res.json(),
            );

            // Iterating through files and checking if they exist
            // in the mapping, which indicates the file was copied successfully.
            for (const file of batchFiles) {
                const copiedFileID = oldToNewFileIDMap[file.id.toString()];
                if (!copiedFileID) {
                    throw new Error(`Failed to copy file ${file.id}`);
                }

                // If success then updating the copiedFiles array.
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

/**
 * This function is currenly used in the upload to shared album flow.
 * For uploading a file to a shared-album for which the currentUser
 * doesn't have an equivalent copy, the file first has to be uploaded to the
 * user's uncategorized so the user now owns a copy of the file.
 *
 * @returns the uncategorized album of the currentUser.
 */
const savedUserUncategorizedCollection = async () => {
    const userID = ensureLocalUser().id;
    return findUserUncategorizedCollection(await savedCollections(), userID);
};

/**
 *
 * Checking whether the currentUser already has a uncategorized Collection,
 * if so then returning the reference to that else creating the same
 * and then returning the instance of the newly created collection.
 *
 * @returns the uncategorized collection of the currentUser if it already
 * exists, otherwise the newly created uncategorized collection.
 */
export const savedOrCreateUserUncategorizedCollection = async () =>
    (await savedUserUncategorizedCollection()) ??
    createUncategorizedCollection();

/**
 *
 * @param dstCollection
 * @param files
 *
 * This function classified the files which are to be added to the
 * dstCollection based on the ownership of each of the files.
 *
 * The filesToAdd() list is for files in otherOwnedFiles whose content can be
 * represented by an equivalent file already owned by the current user. If the
 * code finds a user-owned equivalent with the same metadata hash and file type,
 * it reuses that file and links it to the dstCollection.
 *
 * The filesToCopy() are for files owned by someone else for which
 * the current user has no equivalent copy. Those cannot be directly reused.
 * So a copy of them is created for the current user and then linked
 * with the dstCollection.
 */
export const addOrCopyToCollection = async (
    dstCollection: Collection,
    files: EnteFile[],
) => {
    const addedFiles: EnteFile[] = [];
    if (!files.length) return addedFiles;

    /**
     * The user who is adding the files to the dstCollection must be
     * either the OWNER, ADMIN or atleast a COLLABORATOR to add the file
     * to the album.
     *
     * Therefore checking before proceeding and if not then throwing error.
     */
    if (!canAddFilesToCollection(dstCollection)) {
        throw new Error("Current user cannot add files to this collection");
    }

    // Getting the ID of the currently logged-in user, collection files.
    const currentUserID = ensureLocalUser().id;
    const collectionFiles = await savedCollectionFiles();

    /**
     * Now since we have the files across all the collections and the
     * id of the collection to which we want to upload the files to
     *
     * Getting the file IDs which are already present in the dstCollection
     */
    const destinationFileIDs = fileIDsInCollection(
        dstCollection.id,
        collectionFiles,
    );
    /**
     * Getting the list of the files which aren't actually already present
     * in the destination. We don't want to upload files which already exist
     * in the destination therefore this check.
     *
     * Here files indiciate the files which the user wants to add to the album
     */
    const filesMissingFromDestination = uniqueFilesByID(files).filter(
        (file) => !destinationFileIDs.has(file.id),
    );

    // If all the files, already exists then,
    // we have nothing pending so returning.
    if (!filesMissingFromDestination.length) return addedFiles;

    /**
     * Files which are owned by the current user and not owned
     * both have different upload process therefore this filtering.
     */
    const [ownedFiles, otherOwnedFiles] = splitByPredicate(
        filesMissingFromDestination,
        (file) => file.ownerID == currentUserID,
    );

    /**
     * For files already owned by the current user, we only link existing files
     * to the destination collection. No content upload, no new file IDs, and no
     * removal from current collections—just membership entries on the server.
     *
     * It's a far more straightforward process compared to the upload of
     * non-owned files.
     */
    if (ownedFiles.length) {
        await addToCollection(dstCollection, ownedFiles);
        ownedFiles.forEach((file) => destinationFileIDs.add(file.id));
        addedFiles.push(...ownedFiles);
    }

    // If there are no files which are owned but by others
    // then skipping the rest of the process.
    if (!otherOwnedFiles.length) return addedFiles;

    /**
     * Say if user A uploaded a file X to a shared album and you
     * also have a copy of the same file let it be Y. Then when you try to
     * add the file X to a shared album instead of X it's Y being added.
     *
     * It's done by checking the metadatahash and fileType to see if the
     * user who is initating the action has a copy of the same file.
     */
    const userOwnedFilesByHashAndType = userOwnedEquivalentFilesByHashAndType(
        collectionFiles,
        currentUserID,
    );

    // Storing the user owned files which can be directly added
    const filesToAdd: EnteFile[] = [];
    // Storing other owned-files without an user-owned equivalent
    const filesToCopy: EnteFile[] = [];
    /**
     * Both the below Set(s) are for preventing duplication. Assume there are
     * two shared files X1 and X2 and then if both of them match the same owned
     * file Y then we need to prevent Y from being pushed to filesToAdd twice.
     * similarly for the filesToCopy as well
     */
    const seenAddFileIDs = new Set<number>();
    const seenCopyFileIDs = new Set<number>();

    for (const file of otherOwnedFiles) {
        const fileHashAndTypeKey = hashAndTypeKey(file);

        // Checking if the user has a file with matching hash
        const userOwnedEquivalent = fileHashAndTypeKey
            ? userOwnedFilesByHashAndType.get(fileHashAndTypeKey)
            : undefined;
        const shouldAddOwnedEquivalent = !!userOwnedEquivalent;

        // If the file needs to be added or copied then pushing
        // the file ID into corresponding variables.
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

    /**
     * If you are wondering why we need this check again because we did it
     * once at the filesMissingFromDestination. the filesToAdd might have
     * different or new IDs which weren't there in the files earlier.
     *
     * For otherOwnedFiles, the code may replace thesource file X
     * with a different user owned equivalent Y.
     */
    const reusableOwnedFiles = uniqueFilesByID(filesToAdd).filter(
        (file) => !destinationFileIDs.has(file.id),
    );

    /**
     * Adding the files to the dstCollection.
     * fyi: these are the files for which the currentUser
     * had a equivalent copy with a matching metadata + fileType.
     */
    if (reusableOwnedFiles.length) {
        await addToCollection(dstCollection, reusableOwnedFiles);
        reusableOwnedFiles.forEach((file) => destinationFileIDs.add(file.id));
        addedFiles.push(...reusableOwnedFiles);
    }

    if (!filesToCopy.length) return addedFiles;

    /**
     * To directly upload to a collection, the currentUser must be the
     * the owner of the same, checking that and if not then,
     */
    const copyDestination = canDirectlyUploadToCollection(dstCollection)
        ? dstCollection
        : await savedOrCreateUserUncategorizedCollection();

    /**
     * If the user owns the dstCollection then copyDestination will have reference
     * of that collection in it else, it will be having the reference for the uncategorized
     * collection to which the files is copied to.
     */
    const copiedFiles = await copyFiles(copyDestination, filesToCopy);

    if (copyDestination.id != dstCollection.id) {
        /**
         * The copiedFiles variable have the reference of the files which are
         * uploaded to the uncatgroized and now these files have a proper EnteFile
         * schema, therefore now we can add these files to the dstCollection after checking
         * the fileIds doesn't already exist there.
         */
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

/**
 * Return an array of {@link CollectionFileItem}s, one for each file in
 * {@link files}, containing the corresponding file' ID and keys, but this time
 * encrypted using the key of the given {@link collection}.
 */
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

/**
 * Make a remote request to move the given {@link files} to trash.
 *
 * @param files The {@link EnteFile}s to move to trash. The API request needs
 * both a file ID and a collection ID, but there should be at most one entry for
 * a particular fileID in this array.
 *
 * Remote only, does not modify local state.
 */
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

/**
 * Make a remote request to delete the given {@link fileIDs} from trash.
 *
 * Remote only, does not modify local state.
 */
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

/**
 * Remove the given files from the specified collection owned by the user.
 *
 * Reads local state but does not modify it. The effects are on remote.
 *
 * @param collection A collection (either owned by the user, or shared with the
 * user).
 *
 * @param files The files to remove from the collection. The files owned by the
 * user will be removed. If the collection is not owned by the user, then any
 * files that are not owned by the user will not be processed (unless the user
 * is an admin of the collection). In such cases, this function will return a
 * count less than the count of the provided files (after having removed what
 * can be removed).
 *
 * @returns The count of files that were processed. This can be less than the
 * count of the provided {@link files} if some files were not processed because
 * because they belong to other users (and {@link collection} also does not
 * belong to the current user, and the user is not an admin).
 *
 * [Note: Removing files from a collection]
 *
 * There are four scenarios
 *
 *                             own file      shared file
 *     own collection             M               R
 *     admin in collection        R               R
 *     others collection          R         not supported
 *
 *     M (move)   when both collection and file belongs to user
 *     R (remove) when only one of them belongs to the user, or user is admin
 *
 * The move operation is not supported across ownership boundaries. The remove
 * operation is only supported across ownership boundaries, but the user should
 * have ownership of either the file or collection (not both), or be an admin.
 *
 * In more detail, the above scenarios can be described this way.
 *
 * 1. Move: If the user owns both the collection and the file they're trying to
 *    remove from the collection, then instead of a remove the client needs to
 *    move it to a different user owned collection in which it already exists
 *    (such a move acts as a remove). If it doesn't exist in any other user
 *    owned collection, then move it to the user's "Uncategorized" collection.
 *    The intent is that a "remove from collection" should not remove the last
 *    copy of a file (thus deleting it).
 *
 * 2. Remove: If the user does not own the file being removed, or owns the file
 *    being removed but does not own the collection from which it is being
 *    removed, they can remove it from the collection using the POST
 *    "/collections/v3/remove-files".
 *
 * 3. Admin remove: If the user is an admin of a collection they don't own, they
 *    can remove any file from the collection (including files they don't own).
 *
 * 4. Not supported: Removing a file the user does not own from a collection
 *    that the user does not own and is not an admin of.
 *
 * The "remove from collection" primitive is provided to the user both as a UI
 * action (on selecting files in a collection), and as an implicit action if the
 * user chooses the option to "keep files" when deleting a collection.
 *
 * This entire shebang is implemented by the following set of functions:
 *
 * 1. [Public] {@link removeFromCollection} - Handles both own and others
 *    collections by delegating to the one of the following functions.
 *
 * 2. [Public] {@link removeFromOwnCollection} - Handles both cases for own
 *    collections by delegating to either "Move" or "Remove"
 *
 * 3. [Private] {@link removeFromOthersCollection} - Handles cases for other's
 *    collections. If the user is an admin, they can remove all files. Otherwise
 *    only the user's own files can be removed.
 *
 * 4. [Private] {@link removeOwnFilesFromOwnCollection} implements the "Move".
 *
 * 5. [Private] {@link removeNonCollectionOwnerFiles} implements the "Remove".
 */
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
    // Check if user is an admin of this collection
    const isAdmin =
        collection.sharees.find((s) => s.id == userID)?.role == "ADMIN";

    if (isAdmin) {
        // Admins can remove all files from the collection
        if (files.length) {
            await removeNonCollectionOwnerFiles(collection.id, files);
        }
        return files.length;
    }

    // Non-admins can only remove their own files
    const [userFiles] = splitByPredicate(files, (f) => f.ownerID == userID);
    if (userFiles.length) {
        await removeNonCollectionOwnerFiles(collection.id, userFiles);
    }
    return userFiles.length;
};

/**
 * Remove the given user owned files from the given collection also owned by the
 * user, ensuring that at least one user owned instance is retained for them
 * (either in a different user owned collection in which they already existed,
 * or in the user's "Uncategorized" collection as a fallback).
 *
 * Reads local state but does not modify it. The effects are on remote.
 *
 * This is used as a subroutine of [Note: Removing files from a collection].
 */
const removeOwnFilesFromOwnCollection = async (
    collectionID: number,
    filesToRemove: EnteFile[],
) => {
    const userID = ensureLocalUser().id;
    const collections = await savedCollections();
    const collectionFiles = await savedCollectionFiles();

    const collectionsByID = new Map(collections.map((c) => [c.id, c]));

    // This set keeps a running track of file IDs that still need to be removed.
    // It is seeded with the original set of files we were asked to remove.
    const filesToRemoveIDs = new Set(filesToRemove.map((f) => f.id));
    // A predicate that checks if the given file is still pending removal.
    const pendingRemove = (f: EnteFile) => filesToRemoveIDs.has(f.id);

    const collectionFilesToRemove = collectionFiles.filter(pendingRemove);
    const groups = groupFilesByCollectionID(collectionFilesToRemove);
    for (const [targetCollectionID, filesInCollection] of groups.entries()) {
        // Ignore the source collection itself.
        if (targetCollectionID == collectionID) continue;

        const targetCollection = collectionsByID.get(targetCollectionID)!;
        // We want a copy to exist in at least one other user owned collection.
        if (targetCollection.owner.id != userID) continue;
        // We'll move to uncategorized after the loop (if they still remain).
        if (targetCollection.type == "uncategorized") continue;

        const filesInCollectionToRemove =
            filesInCollection.filter(pendingRemove);
        if (!filesInCollectionToRemove.length) continue;

        // The file already exists in the target collection, but this acts as
        // "remove" from the source.
        await moveFromCollection(
            collectionID,
            targetCollection,
            filesInCollectionToRemove,
        );

        // Mark the files we just moved as been taken care of.
        filesInCollectionToRemove.forEach((f) => filesToRemoveIDs.delete(f.id));
    }

    // Any files that were not moved so far, move them to uncategorized,
    // creating uncategorized if needed.
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

/**
 * Remove the provided files from the provided collection on remote.
 *
 * Only files which do not belong to the collection owner can be removed from
 * the collection using this endpoint. That is,
 *
 * - Either the user owns the collection and the all files being removed are
 *   owned by somebody else, or
 *
 * - The user owns all the files being removed, but the collection belongs to
 *   somebody else.
 *
 * If the collection owner wants to remove files owned by them, then their
 * client should first move those files first to other collections owned by the
 * collection owner.
 *
 * Remote only, does not modify local state.
 *
 * See also: [Note: Removing files from a collection].
 *
 * @param collectionID The ID of collection from which to remove the files.
 *
 * @param files A list of files which do not belong to the user, and which we
 * the user wants to remove from the given collection.
 */
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

/**
 * Delete a collection on remote.
 *
 * Reads local state but does not modify it. The effects are on remote.
 *
 * @param collectionID The ID of the collection to delete.
 *
 * @param opts Deletion options. In particular, if {@link keepFiles} is true,
 *  then the any of the user's files that only exist in this collection are
 *  first moved to another one of the user's collection (or Uncategorized if no
 *  such collection exists) before deleting the collection.
 *
 * See: [Note: Removing files from a collection]
 */
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

/**
 * Rename a collection on remote.
 *
 * Remote only, does not modify local state.
 *
 * @param collection The collection to rename.
 *
 * @param newName The new name of the collection
 */
export const renameCollection = async (
    collection: Collection,
    newName: string,
) => {
    if (collection.magicMetadata?.data.subType == CollectionSubType.quicklink) {
        // Convert quicklinks to a regular collection before giving them a name.
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

/**
 * Change the visibility (normal, archived, hidden) of a collection on remote.
 *
 * Remote only, does not modify local state.
 *
 * This function works with both collections owned by the user, and collections
 * shared with the user.
 *
 * @param collection The collection whose visibility we want to change.
 *
 * @param visibility The new visibility (normal, archived, hidden).
 */
export const updateCollectionVisibility = async (
    collection: Collection,
    visibility: ItemVisibility,
) =>
    collection.owner.id == ensureLocalUser().id
        ? updateCollectionPrivateMagicMetadata(collection, { visibility })
        : updateCollectionShareeMagicMetadata(collection, { visibility });

/**
 * Change the pinned state of a collection on remote.
 *
 * Remote only, does not modify local state.
 *
 * This function works only for collections owned by the user.
 *
 * @param collection The collection whose order we want to change.
 *
 * @param order Whether on not the collection is pinned.
 */
export const updateCollectionOrder = async (
    collection: Collection,
    order: CollectionOrder,
) => updateCollectionPrivateMagicMetadata(collection, { order });

/**
 * Change the order (pin/unpin) of a shared collection on remote for the sharee.
 *
 * Remote only, does not modify local state.
 *
 * This function works only for collections shared with the user (not owned).
 *
 * @param collection The shared collection whose order we want to change.
 *
 * @param order Whether on not the collection is pinned by the sharee.
 */
export const updateShareeCollectionOrder = async (
    collection: Collection,
    order: CollectionOrder,
) => updateCollectionShareeMagicMetadata(collection, { order });

/**
 * Change the sort order of the files with a collection on remote.
 *
 * Remote only, does not modify local state.
 *
 * This function works only for collections owned by the user.
 *
 * @param collection The collection whose file sort order we want to change.
 *
 * @param asc If true, then the files are sorted ascending (oldest first).
 * Otherwise they are sorted descending (newest first).
 */
export const updateCollectionSortOrder = async (
    collection: Collection,
    asc: boolean,
) => updateCollectionPublicMagicMetadata(collection, { asc });

/**
 * Change the cover photo of a collection on remote.
 *
 * Remote only, does not modify local state.
 *
 * This function works only for collections owned by the user.
 *
 * @param collection The collection whose cover we want to change.
 *
 * @param coverID The file ID to set as the cover.
 *
 * Pass `0` to reset to the default cover.
 */
export const updateCollectionCover = async (
    collection: Collection,
    coverID: number,
) => updateCollectionPublicMagicMetadata(collection, { coverID });

/**
 * Change the layout type of a collection on remote.
 *
 * Remote only, does not modify local state.
 *
 * This function works only for collections owned by the user.
 *
 * @param collection The collection whose layout we want to change.
 *
 * @param layout The layout type ("masonry", "grouped", "continuous", "trip").
 */
export const updateCollectionLayout = async (
    collection: Collection,
    layout: string,
) => updateCollectionPublicMagicMetadata(collection, { layout });

/**
 * Update the private magic metadata of a collection on remote.
 *
 * Remote only, does not modify local state.
 *
 * @param collection The collection whose magic metadata we want to update.
 *
 * The existing magic metadata of this collection is used both to obtain the
 * current magic metadata version, and the existing contents on top of which the
 * updates are applied, so it is imperative that both these values are up to
 * sync with remote otherwise the update will fail.
 *
 * @param updates A non-empty subset of
 * {@link CollectionPrivateMagicMetadataData} entries.
 *
 * See: [Note: Magic metadata data cannot have nullish values]
 */
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

/**
 * Update the private magic metadata of a single collection on remote.
 */
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

/**
 * Update the public magic metadata of a collection on remote.
 *
 * Remote only, does not modify local state.
 *
 * This is a variant of {@link updateCollectionPrivateMagicMetadata} that works
 * with the {@link pubMagicMetadata} of a collection.
 */
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

/**
 * Update the public magic metadata of a single collection on remote.
 */
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

/**
 * Update the per-sharee magic metadata of a collection on remote.
 *
 * Remote only, does not modify local state.
 *
 * This is a variant of {@link updateCollectionPrivateMagicMetadata} that works
 * with the {@link sharedMagicMetadata} of a collection.
 */
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

/**
 * Update the sharee magic metadata of a single shared collection on remote.
 */
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

/**
 * Create a new collection of type "favorites" for the user on remote, and
 * return its local representation.
 *
 * Remote only, does not modify local state.
 *
 * Each user can have at most one collection of type "favorites" owned by them.
 * While this function does not enforce the constraint locally, it will fail
 * because remote will enforce the constraint and fail the request when we
 * attempt to create a second collection of type "favorites".
 */
const createFavoritesCollection = () =>
    createCollection(favoritesCollectionName, "favorites");

/**
 * Create a new collection of type "uncategorized" for the user on remote, and
 * return its local representation.
 *
 * Remote only, does not modify local state.
 *
 * Each user can have at most one collection of type "uncategorized" owned by
 * them. While this function does not enforce the constraint locally, it will
 * fail because remote will enforce the constraint and fail the request when we
 * attempt to create a second collection of type "uncategorized".
 */
export const createUncategorizedCollection = () =>
    createCollection(uncategorizedCollectionName, "uncategorized");

/**
 * Return the user's own favorites collection if one is found in the local
 * database. Otherwise create a new one and return that.
 *
 * Reads local state but does not modify it. The effects are on remote.
 */
const savedOrCreateUserFavoritesCollection = async () => {
    const favoritesCollection = await savedUserFavoritesCollection();
    if (favoritesCollection) return favoritesCollection;

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

/**
 * Return the user's own favorites collection if present in the local database,
 * or one created during this session before the next remote pull.
 */
export const savedUserFavoritesCollection = async () => {
    const userID = ensureLocalUser().id;
    const collections = await savedCollections();
    return (
        collections.find(
            (collection) =>
                // See: [Note: User and shared favorites]
                collection.type == "favorites" && collection.owner.id == userID,
        ) ??
        (pendingUserFavoritesCollection?.owner.id == userID
            ? pendingUserFavoritesCollection
            : undefined)
    );
};

/**
 * Mark the provided {@link files} as the user's favorites by adding them to the
 * user's favorites collection.
 *
 * If the user doesn't yet have a favorites collection, it is created.
 *
 * Reads local state but does not modify it. The effects are on remote.
 */
export const addToFavoritesCollection = async (files: EnteFile[]) => {
    const userID = ensureLocalUser().id;

    // Currenly we can only favorite shared files which have a proper metadataHash
    // therefore filtering to check if there are files without this data.
    const hashlessSharedFile = files.find(
        (file) => file.ownerID != userID && !hashAndTypeKey(file),
    );

    // If there are files without metadata hash to be favorited, then rejecting the change
    if (hashlessSharedFile) {
        throw new Error("Cannot favorite shared files without metadata hash");
    }

    // Getting the favorites collection of the user, if there is no favorite collection
    // for this particular user at the moment this function actaully creates one.

    const favoritesCollection = await savedOrCreateUserFavoritesCollection();

    // Splitting the files based on their ownership.
    const { pendingFiles, remainingFiles } = splitPendingFavoriteFiles(
        files,
        userID,
    );

    // Pending files need to be just added to the favorite collection,
    // since they already have a user-owned copy so routing them that way.
    if (pendingFiles.length) {
        await addToCollection(favoritesCollection, pendingFiles);
    }

    // Remaining files are those files which aren't owned by the current user
    // right now, therefore they have to be copied to the Favorites album instead
    // of adding. Therefore they are going to the addOrCopyToCollection.
    const addedFiles = await addOrCopyToCollection(
        favoritesCollection,
        remainingFiles,
    );

    // This function update the local variable pendingFavoriteFilesByHashAndType which maintains a map
    // of the files which were recently favorited/un-favorited to prevent
    // duplicate copying of the shared files into the user's album
    rememberPendingFavoriteFiles(
        files,
        pendingFiles.concat(addedFiles),
        userID,
    );
};

export const removeFromFavoritesCollection = async (files: EnteFile[]) => {
    const userID = ensureLocalUser().id;

    // Getting the saved Favorites collection of the user and if there is
    // no such collection existing then we throw an error.
    const favoritesCollection = await savedUserFavoritesCollection();
    if (!favoritesCollection) {
        throw new Error("Favorites collection does not exist");
    }

    // The files now might have files which are from shared-albums as well
    // Before removing them from the favorites we need to resolve to a
    // owned-equivalent of the same file.
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

/**
 *
 * @param favoritesCollection
 * @param files
 * @returns
 *
 *
 * If the user has marked a shared-file/non-owned file as favorite,
 * every single instance of that file with the matching metadataHash key
 * will be shown as favorite for the user
 *
 * This includes any files which are in the shared album as well.
 * Such files owner as well as the collection id will be different.
 *
 * Therefore we are looping through the files which the user wants to unfavorite
 * and then checking if there are any files like the above.
 *
 * if so then
 */

const resolveFavoritesFilesForRemoval = async (
    favoritesCollection: Collection,
    files: EnteFile[],
) => {
    const userID = ensureLocalUser().id;

    // Looping through user's favorites and then creating a map with the user's
    // favorite files and their metadataHash key. This is used below to resolve
    // to the user-owned files which is to be unfavorited.
    const favoriteFilesByHashAndType = userOwnedEquivalentFilesByHashAndType(
        (await savedCollectionFiles()).filter(
            (file) => file.collectionID == favoritesCollection.id,
        ),
        userID,
    );

    /**
     * Iterating through the files which are to be unfavorited
     * and checking if they contain any files which belong to a
     * shared album(i.e. their owner as well as collectionId will differ)
     *
     * if so then getting the user-owned
     * equivalent of the file using it's metadataHash and favoriteFilesByHashAndType
     * mapping and then returning it.
     */
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

/**
 * Return the default hidden collection for the user if one is found in the
 * local database. Otherwise create a new one and return that.
 *
 * Reads local state but does not modify it. The effects are on remote.
 */
const savedOrCreateDefaultHiddenCollection = async () =>
    (await savedDefaultHiddenCollection()) ?? createDefaultHiddenCollection();

/**
 * Return the user's default hidden collection, if any, present in the
 * local database.
 */
const savedDefaultHiddenCollection = async () =>
    (await savedCollections()).find((collection) =>
        isDefaultHiddenCollection(collection),
    );

/**
 * Create a new collection with hidden visibility on remote, marking it as the
 * default hidden collection, and return its local representation.
 *
 * Remote only, does not modify local state.
 *
 * See also: [Note: Multiple "default" hidden collections].
 */
const createDefaultHiddenCollection = () =>
    createCollection(defaultHiddenCollectionName, "album", {
        subType: CollectionSubType.defaultHidden,
        visibility: ItemVisibility.hidden,
    });

/**
 * Return true if the provided collection is the default hidden collection.
 *
 * See also: [Note: Multiple "default" hidden collections].
 */
export const isDefaultHiddenCollection = (collection: Collection) =>
    collection.magicMetadata?.data.subType == CollectionSubType.defaultHidden;

/**
 * Extract the IDs of all the "default" hidden collections.
 *
 * [Note: Multiple "default" hidden collections].
 *
 * Normally, there is only expected to be one such collection. But to provide
 * clients laxity in synchronization, we don't enforce this and instead allow
 * for multiple such default hidden collections to exist.
 */
export const findDefaultHiddenCollectionIDs = (collections: Collection[]) =>
    new Set<number>(
        collections
            .filter(isDefaultHiddenCollection)
            .map((collection) => collection.id),
    );

/**
 * Return `true` if the given collection is hidden.
 *
 * Hidden collections are those that have their visibility set to hidden for
 * the current user (owner or sharee).
 *
 * In one instance, the isHiddenCollection function is called outside of a window, like
 * for the people tab's review suggestions, this function was trigged from a worker.
 * In that case, since the worker has no access to the localStorage, we need to pass the currentUserID
 * explicitly.
 */
export const isHiddenCollection = (
    collection: Collection,
    currentUserID?: number,
) => {
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

/**
 * Return `true` if the given collection is archived.
 *
 * Archived collections are those that have their visibility set to hidden in the
 * collection's private magic metadata or per-sharee private metadata.
 */
export const isArchivedCollection = (collection: Collection) =>
    collection.magicMetadata?.data.visibility == ItemVisibility.archived ||
    collection.sharedMagicMetadata?.data.visibility == ItemVisibility.archived;

/**
 * Return `true` if the current user can remove files from all participants in
 * the given collection.
 *
 * This is true if the user is either:
 * - The owner of the collection, or
 * - An admin of the collection
 *
 * This is used to determine if the user can remove files added by other users
 * from a shared collection.
 */
export const canRemoveFilesFromAllParticipants = (collection: Collection) => {
    const userID = ensureLocalUser().id;
    if (collection.owner.id == userID) return true;
    // Check if the user is an admin of this collection
    const sharee = collection.sharees.find((s) => s.id == userID);
    return sharee?.role == "ADMIN";
};

/**
 * Hide the provided {@link files} by moving them to the default hidden
 * collection.
 *
 * If the default hidden collection does not already exist, it is created.
 *
 * Reads local state but does not modify it. The effects are on remote.
 *
 * Since now we also support upload to shared album on desktop/web, the files
 * got as params will also have shared files in them, whose collectionID
 * points to the shared album. And moving files from those collections aren't
 * possible.
 *
 * Therefore for such files are being removed instead of moving.
 */
export const hideFiles = async (files: EnteFile[]) => {
    const userID = ensureLocalUser().id;
    const defaultHiddenCollection =
        await savedOrCreateDefaultHiddenCollection();
    const collections = await savedCollections();
    const collectionsByID = new Map(collections.map((c) => [c.id, c]));

    /**
     * Grouping the files based on their collectionID, so if a file exists
     * in a user-owned collection and non-user owned collection for those files
     * where will be two entries based on their collectionID
     *
     * the owned-collection file will be moved using /move-files endpoint
     * wherease the non-owned collection file will be removed from the shared collection
     * using the /
     */
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
            await removeFromCollection(collection, collectionFiles);
        }
    }
};

/**
 * Share the provided collection with another Ente user.
 *
 * Remote only, does not modify local state.
 *
 * @param collection The {@link Collection} to share.
 *
 * @param withUserEmail The email of the Ente user with whom to share it.
 *
 * @param role The desired role for the new participant.
 */
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

/**
 * Stop sharing a collection on remote with the given user.
 *
 * Remote only, does not modify local state.
 *
 * @param collectionID The ID of the collection to stop sharing with the user
 * having the given {@link email}.
 *
 * @param email The email of the Ente user with whom to stop sharing.
 */
export const unshareCollection = async (collectionID: number, email: string) =>
    ensureOk(
        await fetch(await apiURL("/collections/unshare"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({ collectionID, email }),
        }),
    );

/**
 * The subset of public URL attributes that can be customized by the user when
 * creating a link.
 */
export type CreatePublicURLAttributes = Pick<
    Partial<PublicURL>,
    | "enableCollect"
    | "enableJoin"
    | "enableComment"
    | "validTill"
    | "deviceLimit"
>;

/**
 * Create a new public link for the given collection.
 *
 * Remote only, does not modify local state.
 *
 * @param collectionID The ID of the collection for which the public link should
 * be created.
 *
 * @param attributes Optional attributes to set when creating the public link.
 */
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

/**
 * The subset of public URL attributes that can be updated by the user after the
 * link has already been created.
 */
export type UpdatePublicURLAttributes = Omit<
    Partial<PublicURL>,
    "url" | "enablePassword"
> & { disablePassword?: boolean; passHash?: string };

/**
 * Update the attributes of an existing public link for a shared collection.
 *
 * Remote only, does not modify local state.
 *
 * @param collectionID The ID of the collection whose public link to update.
 *
 * @param updates The public link attributes to modify. Only attributes
 * corresponding to entries with non nullish values will be updated, all the
 * other existing attributes will remain unmodified.
 *
 * @returns the updated public URL.
 */
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

/**
 * Delete the public link for the collection with given {@link collectionID}.
 *
 * Remote only, does not modify local state.
 */
export const deleteShareURL = async (collectionID: number) =>
    ensureOk(
        await fetch(await apiURL(`/collections/share-url/${collectionID}`), {
            method: "DELETE",
            headers: await authenticatedRequestHeaders(),
        }),
    );

/**
 * Leave a collection which had previously been shared with the user.
 *
 * Remote only, does not modify local state.
 *
 * @param collectionID The ID of the shared collection to leave.
 */
export const leaveSharedCollection = async (collectionID: number) =>
    ensureOk(
        await fetch(await apiURL(`/collections/leave/${collectionID}`), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
        }),
    );

/**
 * Zod schema for a collection action (used for pending removal actions).
 */
const CollectionAction = z.object({
    collectionID: z.number(),
    fileID: z.number().nullish(),
});

type CollectionAction = z.infer<typeof CollectionAction>;

/**
 * Zod schema for the pending removal actions response.
 */
const PendingRemovalActionsResponse = z.object({
    actions: z.array(CollectionAction).nullish(),
});

/**
 * Fetch pending removal actions from remote.
 *
 * Remote only, does not modify local state.
 *
 * Pending removal actions indicate files that have been removed from a
 * collection by the owner or an admin, and should be moved to the user's
 * uncategorized collection if they exist locally.
 *
 * @returns A list of {@link CollectionAction} objects representing files that
 * should be moved to uncategorized.
 */
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

/**
 * Process pending removal actions by moving affected files to the user's
 * uncategorized collection.
 *
 * This function fetches pending removal actions from remote, identifies which
 * files are affected, and moves them to the uncategorized collection. This
 * ensures that files removed from shared collections by owners/admins are not
 * lost but instead moved to a safe location.
 *
 * @param collections The current list of collections (used to find affected
 * files).
 *
 * Reads local state but does not modify it. The effects are on remote.
 */
export const movePendingRemovalActionsToUncategorized = async (
    collections: Collection[],
) => {
    const userID = ensureLocalUser().id;
    const pendingActions = await fetchPendingRemovalActions();
    if (!pendingActions.length) return;

    // Group file IDs by collection ID
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

    // Get all files from local storage
    const collectionFiles = await savedCollectionFiles();

    // Group files by collection ID for efficient lookup
    const filesByCollectionID = groupFilesByCollectionID(collectionFiles);

    // Create a map of collection ID to collection for quick lookup
    const collectionByID = new Map(collections.map((c) => [c.id, c]));

    // Lazily initialized target collections (only created if needed)
    let uncategorizedCollection: Collection | undefined;
    let defaultHiddenCollection: Collection | undefined;

    // Process each collection with pending removal actions
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

        // Determine target collection based on whether source is hidden
        const isSourceHidden =
            sourceCollection && isHiddenCollection(sourceCollection);

        let targetCollection: Collection;
        if (isSourceHidden) {
            // Move files from hidden collections to default hidden collection
            if (!defaultHiddenCollection) {
                defaultHiddenCollection =
                    collections.find(isDefaultHiddenCollection) ??
                    (await createDefaultHiddenCollection());
            }
            targetCollection = defaultHiddenCollection;
        } else {
            // Move files from normal collections to uncategorized
            if (!uncategorizedCollection) {
                uncategorizedCollection =
                    findUserUncategorizedCollection(collections, userID) ??
                    (await createUncategorizedCollection());
            }
            targetCollection = uncategorizedCollection;
        }

        // Move files to target collection (this also removes them from the
        // source collection, which is the primary goal here)
        await moveFromCollection(collectionID, targetCollection, filesToMove);
    }
};

/**
 * Remove files from the uncategorized collection if they exist in other
 * user-owned albums.
 *
 * This is a cleanup operation that helps users remove duplicates from their
 * uncategorized collection. Files that exist both in uncategorized and in
 * other albums are moved out of uncategorized to one of those albums.
 *
 * Reads local state but does not modify it. The effects are on remote.
 *
 * @param uncategorizedCollection The user's uncategorized collection.
 */
export const cleanUncategorized = async (
    uncategorizedCollection: Collection,
): Promise<number> => {
    const userID = ensureLocalUser().id;
    const collections = await savedCollections();
    const collectionFiles = await savedCollectionFiles();

    // Get files in the uncategorized collection
    const uncategorizedFiles = collectionFiles.filter(
        (f) => f.collectionID == uncategorizedCollection.id,
    );

    if (!uncategorizedFiles.length) return 0;

    // Build a map from file ID to the collections it belongs to (excluding
    // uncategorized itself)
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

    // Filter to only user-owned normal collections (not hidden, not shared)
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

    // Find files that exist in other user-owned collections
    const filesToClean = uncategorizedFiles.filter((file) => {
        const otherCollectionIDs = fileIDToCollectionIDs.get(file.id);
        if (!otherCollectionIDs) return false;
        // Check if any of these collections are user-owned normal collections
        return otherCollectionIDs.some((cid) =>
            userOwnedCollectionIDs.has(cid),
        );
    });

    if (!filesToClean.length) return 0;

    // Group files by their target collection for efficient batching
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

    // Move files in batches per target collection
    let cleanedCount = 0;
    for (const [targetCollectionID, files] of filesByTargetCollection) {
        const targetCollection = collectionsByID.get(targetCollectionID);
        if (!targetCollection) continue;

        // Move files from uncategorized to the target collection.
        // This effectively removes them from uncategorized since they already
        // exist in the target.
        await moveFromCollection(
            uncategorizedCollection.id,
            targetCollection,
            files,
        );
        cleanedCount += files.length;
    }

    return cleanedCount;
};
