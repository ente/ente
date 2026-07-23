/**
 * @file Public albums storage facade for embed app
 *
 * This provides the same interface as public-albums-fdb but uses in-memory storage
 * instead of IndexedDB/localStorage. This ensures isolation between different
 * iframe embeds while maintaining API compatibility.
 */

import {
    LocalCollections,
    LocalEnteFiles,
    LocalTimestamp,
    transformFilesIfNeeded,
} from "ente-gallery/services/files-db";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import { inMemoryStorage } from "./in-memory-storage";

/**
 * Return all public collections present in our local storage.
 *
 * Use {@link savePublicCollections} to update the storage.
 */
const savedPublicCollections = (): Collection[] =>
    LocalCollections.parse(inMemoryStorage.getItem("public-collections") ?? []);

/**
 * Replace the list of public collections stored in our local storage.
 *
 * This is the setter corresponding to {@link savedPublicCollections}.
 */
const savePublicCollections = (collections: Collection[]) =>
    inMemoryStorage.setItem("public-collections", collections);

/**
 * Return the saved public collection with the given {@link key} if present in
 * our local storage.
 *
 * Use {@link savePublicCollection} to save collections in our local storage.
 *
 * @param key The collection key that can be used to identify the public album
 * we want from amongst all the locally saved public albums.
 */
export const savedPublicCollectionByKey = (
    collectionKey: string,
): Collection | undefined => {
    const collections = savedPublicCollections();
    return collections.find((c) => c.key == collectionKey);
};

/**
 * Save a public collection to our local storage.
 *
 * The collection can later be retrieved using {@link savedPublicCollection}.
 * The collection can be removed using {@link removePublicCollection}.
 */
export const savePublicCollection = (collection: Collection) => {
    const collections = savedPublicCollections();
    savePublicCollections([
        collection,
        ...collections.filter((c) => c.id != collection.id),
    ]);
};

/**
 * Remove a public collection, identified using its collection key, from our
 * local storage.
 *
 * @param key The collection key that can be used to identify the public album
 * we want to remove.
 */
export const removePublicCollectionByKey = (collectionKey: string) => {
    const collections = savedPublicCollections();
    savePublicCollections([
        ...collections.filter((c) => c.key != collectionKey),
    ]);
};

/**
 * Zod schema for a nullish string, with `null` transformed to `undefined`.
 */
const LocalString = z.string().nullish().transform(nullToUndefined);

/**
 * Return the last saved referral code present in our local storage.
 *
 * See: [Note: Public albums referral code]. A few more details specific to the
 * persistence of the referral code:
 *
 * 1. The public albums app persists only the referral code for the latest
 *    public album that was fetched.
 *
 * 2. This saved value can be read by
 *    {@link savedLastPublicCollectionReferralCode}.
 *
 * 3. It gets updated as part of {@link publicAlbumsRemotePull}, which writes
 *    out a new value using {@link saveLastPublicCollectionReferralCode}.
 */
export const savedLastPublicCollectionReferralCode = () =>
    LocalString.parse(inMemoryStorage.getItem("public-referral-code"));

/**
 * Update the referral code present in our local storage.
 *
 * This is the setter corresponding to
 * {@link savedLastPublicCollectionReferralCode}.
 */
export const saveLastPublicCollectionReferralCode = (referralCode: string) => {
    inMemoryStorage.setItem("public-referral-code", referralCode);
};

const LocalSavedPublicCollectionFilesEntry = z.object({
    /**
     * The collection, identified by its access token.
     *
     * See: [Note: Public album access token]
     */
    collectionUID: z.string(),
    files: LocalEnteFiles,
});

type LocalSavedPublicCollectionFilesEntry = z.infer<
    typeof LocalSavedPublicCollectionFilesEntry
>;

/**
 * Return all files for a public collection present in our local storage.
 *
 * Use {@link savePublicCollectionFiles} to update the list of files in the
 * storage, and {@link removePublicCollectionFiles} to remove them.
 *
 * @param accessToken The access token that identifies the public album whose
 * files we want.
 */
export const savedPublicCollectionFiles = (accessToken: string): EnteFile[] => {
    const entry = pcfEntries().find((e) => e.collectionUID == accessToken);
    return transformFilesIfNeeded(entry ? entry.files : []);
};

/**
 * A convenience routine to read the storage entries for "public-collection-files".
 */
const pcfEntries = () => {
    // A local alias to avoid the code from looking scary.
    type ES = LocalSavedPublicCollectionFilesEntry[];

    // See: [Note: Avoiding Zod parsing for large DB arrays] for why we use an
    // (implied) cast here instead of parsing using the Zod schema.
    const entries = inMemoryStorage.getItem(
        "public-collection-files",
    ) as ES | null;
    return entries ?? [];
};

/**
 * Replace the list of files for a public collection in our local storage.
 *
 * This is the setter corresponding to {@link savedPublicCollectionFiles}.
 *
 * @param accessToken The access token that identifies the public album whose
 * files we want to update.
 *
 * @param files The files to save.
 */
export const savePublicCollectionFiles = (
    accessToken: string,
    files: EnteFile[],
): void => {
    inMemoryStorage.setItem("public-collection-files", [
        { collectionUID: accessToken, files },
        ...pcfEntries().filter((e) => e.collectionUID != accessToken),
    ]);
};

/**
 * Remove the list of files, in any, in our local storage for the given
 * collection (identified by its {@link accessToken}).
 */
export const removePublicCollectionFiles = (accessToken: string): void => {
    inMemoryStorage.setItem("public-collection-files", [
        ...pcfEntries().filter((e) => e.collectionUID != accessToken),
    ]);
};

/**
 * Return the locally persisted "last sync time" for a public collection that we
 * have pulled from remote. This can be used to perform a paginated delta pull
 * from the saved time onwards.
 *
 * Use {@link savePublic CollectionLastSyncTime} to update the value saved in
 * the storage, and {@link removePublicCollectionLastSyncTime} to remove the
 * saved value from the storage.
 *
 * @param accessToken The access token that identifies the public album whose
 * last sync time we want.
 */
export const savedPublicCollectionLastSyncTime = (accessToken: string) =>
    LocalTimestamp.parse(inMemoryStorage.getItem(`public-${accessToken}-time`));

/**
 * Update the locally persisted timestamp that will be returned by subsequent
 * calls to {@link savedPublicCollectionLastSyncTime}.
 */
export const savePublicCollectionLastSyncTime = (
    accessToken: string,
    time: number,
) => {
    inMemoryStorage.setItem(`public-${accessToken}-time`, time);
};

/**
 * Remove the locally persisted timestamp, if any, previously saved for a
 * collection using {@link savedPublicCollectionLastSyncTime}.
 */
export const removePublicCollectionLastSyncTime = (accessToken: string) => {
    inMemoryStorage.removeItem(`public-${accessToken}-time`);
};

/**
 * Return the access token JWT, if any, present in our local storage for the
 * given public collection (as identified by its {@link accessToken}).
 *
 * Use {@link savePublicCollectionAccessTokenJWT} to save the value, and
 * {@link removePublicCollectionAccessTokenJWT} to remove it.
 */
export const savedPublicCollectionAccessTokenJWT = (accessToken: string) =>
    LocalString.parse(inMemoryStorage.getItem(`public-${accessToken}-passkey`));

/**
 * Update the access token JWT in our local storage for the given public
 * collection (as identified by its {@link accessToken}).
 *
 * This is the setter corresponding to
 * {@link savedPublicCollectionAccessTokenJWT}.
 */
export const savePublicCollectionAccessTokenJWT = (
    accessToken: string,
    passwordJWT: string,
) => {
    inMemoryStorage.setItem(`public-${accessToken}-passkey`, passwordJWT);
};

/**
 * Remove the access token JWT in our local storage for the given public
 * collection (as identified by its {@link accessToken}).
 */
export const removePublicCollectionAccessTokenJWT = (accessToken: string) => {
    inMemoryStorage.removeItem(`public-${accessToken}-passkey`);
};

const publicCollectionLinkDeviceTokenKey = (
    apiOrigin: string,
    accessToken: string,
) => `public-collection-link-device-token:${apiOrigin}:${accessToken}`;

export const savedPublicCollectionLinkDeviceToken = (
    apiOrigin: string,
    accessToken: string,
) =>
    LocalString.parse(
        inMemoryStorage.getItem(
            publicCollectionLinkDeviceTokenKey(apiOrigin, accessToken),
        ),
    );

export const savePublicCollectionLinkDeviceToken = (
    apiOrigin: string,
    accessToken: string,
    linkDeviceToken: string,
) => {
    inMemoryStorage.setItem(
        publicCollectionLinkDeviceTokenKey(apiOrigin, accessToken),
        linkDeviceToken,
    );
};

export const removePublicCollectionLinkDeviceToken = (
    apiOrigin: string,
    accessToken: string,
) => {
    inMemoryStorage.removeItem(
        publicCollectionLinkDeviceTokenKey(apiOrigin, accessToken),
    );
};

/**
 * Return the previously saved uploader name, if any, present in our local
 * storage corresponding to a public collection.
 *
 * Use {@link savePublicCollectionUploaderName} to update the persisted value.
 *
 * [Note: Public albums uploader name]
 *
 * Whenever there is an upload to a public album, we ask the person doing the
 * upload for their name. This uploader name is attached as part of the public
 * magic metadata of the file so that other people know who uploaded the file.
 *
 * The public albums app also saves this value, keyed by an identifier for the
 * public collection, in the local storage so that it can prefill it the next
 * time there is an upload from the same client.
 *
 * @param accessToken The access token that identifies the public album whose
 * saved uploader name we want.
 */
export const savedPublicCollectionUploaderName = (accessToken: string) =>
    LocalString.parse(
        inMemoryStorage.getItem(`public-${accessToken}-uploaderName`),
    );

/**
 * Update the uploader name present in our local storage corresponding to a
 * public collection.
 *
 * This is the setter corresponding to
 * {@link savedPublicCollectionUploaderName}.
 */
export const savePublicCollectionUploaderName = (
    accessToken: string,
    uploaderName: string,
) => {
    inMemoryStorage.setItem(`public-${accessToken}-uploaderName`, uploaderName);
};
