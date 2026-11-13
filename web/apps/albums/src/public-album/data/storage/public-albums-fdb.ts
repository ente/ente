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

const savedPublicCollections = async (): Promise<Collection[]> =>
    LocalCollections.parse(
        (await localForage.getItem("public-collections")) ?? [],
    );

const savePublicCollections = (collections: Collection[]) =>
    localForage.setItem("public-collections", collections);

export const savedPublicCollectionByKey = async (
    collectionKey: string,
): Promise<Collection | undefined> =>
    savedPublicCollections().then((cs) =>
        cs.find((c) => c.key == collectionKey),
    );

export const savePublicCollection = async (collection: Collection) => {
    const collections = await savedPublicCollections();
    await savePublicCollections([
        collection,
        ...collections.filter((c) => c.id != collection.id),
    ]);
};

export const removePublicCollectionByKey = async (collectionKey: string) => {
    const collections = await savedPublicCollections();
    await savePublicCollections([
        ...collections.filter((c) => c.key != collectionKey),
    ]);
};

const LocalString = z.string().nullish().transform(nullToUndefined);

export const savedLastPublicCollectionReferralCode = async () =>
    LocalString.parse(await localForage.getItem("public-referral-code"));

export const saveLastPublicCollectionReferralCode = async (
    referralCode: string,
) => {
    await localForage.setItem("public-referral-code", referralCode);
};

const LocalSavedPublicCollectionFilesEntry = z.object({
    collectionUID: z.string(),
    files: LocalEnteFiles,
});

type LocalSavedPublicCollectionFilesEntry = z.infer<
    typeof LocalSavedPublicCollectionFilesEntry
>;

export const savedPublicCollectionFiles = async (
    accessToken: string,
): Promise<EnteFile[]> => {
    const entry = (await pcfEntries()).find(
        (e) => e.collectionUID == accessToken,
    );
    return transformFilesIfNeeded(entry ? entry.files : []);
};

const pcfEntries = async () => {
    type ES = LocalSavedPublicCollectionFilesEntry[];

    // Zod parsing is too slow for these large file arrays.
    const entries = await localForage.getItem<ES>("public-collection-files");
    return entries ?? [];
};

export const savePublicCollectionFiles = async (
    accessToken: string,
    files: EnteFile[],
): Promise<void> => {
    await localForage.setItem("public-collection-files", [
        { collectionUID: accessToken, files },
        ...(await pcfEntries()).filter((e) => e.collectionUID != accessToken),
    ]);
};

export const removePublicCollectionFiles = async (
    accessToken: string,
): Promise<void> => {
    await localForage.setItem("public-collection-files", [
        ...(await pcfEntries()).filter((e) => e.collectionUID != accessToken),
    ]);
};

export const savedPublicCollectionLastSyncTime = async (accessToken: string) =>
    LocalTimestamp.parse(
        await localForage.getItem(`public-${accessToken}-time`),
    );

export const savePublicCollectionLastSyncTime = async (
    accessToken: string,
    time: number,
) => {
    await localForage.setItem(`public-${accessToken}-time`, time);
};

export const removePublicCollectionLastSyncTime = async (
    accessToken: string,
) => {
    await localForage.removeItem(`public-${accessToken}-time`);
};

export const savedPublicCollectionAccessTokenJWT = async (
    accessToken: string,
) =>
    LocalString.parse(
        await localForage.getItem(`public-${accessToken}-passkey`),
    );

export const savePublicCollectionAccessTokenJWT = async (
    accessToken: string,
    passwordJWT: string,
) => {
    await localForage.setItem(`public-${accessToken}-passkey`, passwordJWT);
};

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

export const savedPublicCollectionUploaderName = async (accessToken: string) =>
    LocalString.parse(
        await localForage.getItem(`public-${accessToken}-uploaderName`),
    );

export const savePublicCollectionUploaderName = async (
    accessToken: string,
    uploaderName: string,
) => {
    await localForage.setItem(
        `public-${accessToken}-uploaderName`,
        uploaderName,
    );
};
