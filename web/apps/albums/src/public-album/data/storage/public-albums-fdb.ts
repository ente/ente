/**
 * @file Public albums app specific files DB. See: [Note: Files DB].
 */

import {
    LocalCollections,
    LocalEnteFiles,
    localForage,
    LocalTimestamp,
    transformFilesIfNeeded,
} from "ente-gallery/services/files-db";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";

/**
 * Return all public collections present in our local database.
 *
 * Use {@link savePublicCollections} to update the database.
 */
const savedPublicCollections = async (): Promise<Collection[]> =>
    LocalCollections.parse(
        (await localForage.getItem("public-collections")) ?? [],
    );

/**
 * Replace the list of public collections stored in our local database.
 *
 * This is the setter corresponding to {@link savedPublicCollections}.
 */
const savePublicCollections = (collections: Collection[]) =>
    localForage.setItem("public-collections", collections);

/**
 * Return the saved public collection with the given {@link key} if present in
 * our local database.
 *
 * Use {@link savePublicCollection} to save collections in our local database.
 *
 * @param key The collection key that can be used to identify the public album
 * we want from amongst all the locally saved public albums.
 */
export const savedPublicCollectionByKey = async (
    collectionKey: string,
): Promise<Collection | undefined> =>
    savedPublicCollections().then((cs) =>
        cs.find((c) => c.key == collectionKey),
    );

/**
 * Save a public collection to our local database.
 *
 * The collection can later be retrieved using {@link savedPublicCollection}.
 * The collection can be removed using {@link removePublicCollection}.
 */
export const savePublicCollection = async (collection: Collection) => {
    const collections = await savedPublicCollections();
    await savePublicCollections([
        collection,
        ...collections.filter((c) => c.id != collection.id),
    ]);
};

/**
 * Remove a public collection, identified using its collection key, from our
 * local database.
 *
 * @param key The collection key that can be used to identify the public album
 * we want to remove.
 */
export const removePublicCollectionByKey = async (collectionKey: string) => {
    const collections = await savedPublicCollections();
    await savePublicCollections([
        ...collections.filter((c) => c.key != collectionKey),
    ]);
};

/**
 * Zod schema for a nullish string, with `null` transformed to `undefined`.
 */
const LocalString = z.string().nullish().transform(nullToUndefined);

/**
 * Return the last saved referral code present in our local database.
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
export const savedLastPublicCollectionReferralCode = async () =>
    LocalString.parse(await localForage.getItem("public-referral-code"));

/**
 * Update the referral code present in our local database.
 *
 * This is the setter corresponding to
 * {@link savedLastPublicCollectionReferralCode}.
 */
export const saveLastPublicCollectionReferralCode = async (
    referralCode: string,
) => {
    await localForage.setItem("public-referral-code", referralCode);
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
 * Return all files for a public collection present in our local database.
 *
 * Use {@link savePublicCollectionFiles} to update the list of files in the
 * database, and {@link removePublicCollectionFiles} to remove them.
 *
 * @param accessToken The access token that identifies the public album whose
 * files we want.
 */
export const savedPublicCollectionFiles = async (
    accessToken: string,
): Promise<EnteFile[]> => {
    const entry = (await pcfEntries()).find(
        (e) => e.collectionUID == accessToken,
    );
    return transformFilesIfNeeded(entry ? entry.files : []);
};

/**
 * A convenience routine to read the DB entries for "public-collection-files".
 */
const pcfEntries = async () => {
    // A local alias to avoid the code from looking scary.
    type ES = LocalSavedPublicCollectionFilesEntry[];

    // See: [Note: Avoiding Zod parsing for large DB arrays] for why we use an
    // (implied) cast here instead of parsing using the Zod schema.
    const entries = await localForage.getItem<ES>("public-collection-files");
    return entries ?? [];
};

/**
 * Replace the list of files for a public collection in our local database.
 *
 * This is the setter corresponding to {@link savedPublicCollectionFiles}.
 *
 * @param accessToken The access token that identifies the public album whose
 * files we want to update.
 *
 * @param files The files to save.
 */
export const savePublicCollectionFiles = async (
    accessToken: string,
    files: EnteFile[],
): Promise<void> => {
    await localForage.setItem("public-collection-files", [
        { collectionUID: accessToken, files },
        ...(await pcfEntries()).filter((e) => e.collectionUID != accessToken),
    ]);
};

/**
 * Remove the list of files, in any, in our local database for the given
 * collection (identified by its {@link accessToken}).
 */
export const removePublicCollectionFiles = async (
    accessToken: string,
): Promise<void> => {
    await localForage.setItem("public-collection-files", [
        ...(await pcfEntries()).filter((e) => e.collectionUID != accessToken),
    ]);
};

/**
 * Return the locally persisted "last sync time" for a public collection that we
 * have pulled from remote. This can be used to perform a paginated delta pull
 * from the saved time onwards.
 *
 * Use {@link savePublic CollectionLastSyncTime} to update the value saved in
 * the database, and {@link removePublicCollectionLastSyncTime} to remove the
 * saved value from the database.
 *
 * @param accessToken The access token that identifies the public album whose
 * last sync time we want.
 */
export const savedPublicCollectionLastSyncTime = async (accessToken: string) =>
    LocalTimestamp.parse(
        await localForage.getItem(`public-${accessToken}-time`),
    );

/**
 * Update the locally persisted timestamp that will be returned by subsequent
 * calls to {@link savedPublicCollectionLastSyncTime}.
 */
export const savePublicCollectionLastSyncTime = async (
    accessToken: string,
    time: number,
) => {
    await localForage.setItem(`public-${accessToken}-time`, time);
};

/**
 * Remove the locally persisted timestamp, if any, previously saved for a
 * collection using {@link savedPublicCollectionLastSyncTime}.
 */
export const removePublicCollectionLastSyncTime = async (
    accessToken: string,
) => {
    await localForage.removeItem(`public-${accessToken}-time`);
};

/**
 * Return the access token JWT, if any, present in our local database for the
 * given public collection (as identified by its {@link accessToken}).
 *
 * Use {@link savePublicCollectionAccessTokenJWT} to save the value, and
 * {@link removePublicCollectionAccessTokenJWT} to remove it.
 */
export const savedPublicCollectionAccessTokenJWT = async (
    accessToken: string,
) =>
    LocalString.parse(
        await localForage.getItem(`public-${accessToken}-passkey`),
    );

/**
 * Update the access token JWT in our local database for the given public
 * collection (as identified by its {@link accessToken}).
 *
 * This is the setter corresponding to
 * {@link savedPublicCollectionAccessTokenJWT}.
 */
export const savePublicCollectionAccessTokenJWT = async (
    accessToken: string,
    passwordJWT: string,
) => {
    await localForage.setItem(`public-${accessToken}-passkey`, passwordJWT);
};

/**
 * Remove the access token JWT in our local database for the given public
 * collection (as identified by its {@link accessToken}).
 */
export const removePublicCollectionAccessTokenJWT = async (
    accessToken: string,
) => {
    await localForage.removeItem(`public-${accessToken}-passkey`);
};

const publicCollectionLinkDeviceTokenKey = (
    apiOrigin: string,
    accessToken: string,
) => `public-collection-link-device-token:${apiOrigin}:${accessToken}`;

export const savedPublicCollectionLinkDeviceToken = async (
    apiOrigin: string,
    accessToken: string,
) =>
    LocalString.parse(
        await localForage.getItem(
            publicCollectionLinkDeviceTokenKey(apiOrigin, accessToken),
        ),
    );

export const savePublicCollectionLinkDeviceToken = async (
    apiOrigin: string,
    accessToken: string,
    linkDeviceToken: string,
) => {
    await localForage.setItem(
        publicCollectionLinkDeviceTokenKey(apiOrigin, accessToken),
        linkDeviceToken,
    );
};

export const removePublicCollectionLinkDeviceToken = async (
    apiOrigin: string,
    accessToken: string,
) => {
    await localForage.removeItem(
        publicCollectionLinkDeviceTokenKey(apiOrigin, accessToken),
    );
};

/**
 * Return the previously saved uploader name, if any, present in our local
 * database corresponding to a public collection.
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
 * public collection, in the local database so that it can prefill it the next
 * time there is an upload from the same client.
 *
 * @param accessToken The access token that identifies the public album whose
 * saved uploader name we want.
 */
export const savedPublicCollectionUploaderName = async (accessToken: string) =>
    LocalString.parse(
        await localForage.getItem(`public-${accessToken}-uploaderName`),
    );

/**
 * Update the uploader name present in our local database corresponding to a
 * public collection.
 *
 * This is the setter corresponding to
 * {@link savedPublicCollectionUploaderName}.
 */
export const savePublicCollectionUploaderName = async (
    accessToken: string,
    uploaderName: string,
) => {
    await localForage.setItem(
        `public-${accessToken}-uploaderName`,
        uploaderName,
    );
};
