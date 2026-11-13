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

const savedPublicCollections = (): Collection[] =>
    LocalCollections.parse(inMemoryStorage.getItem("public-collections") ?? []);

const savePublicCollections = (collections: Collection[]) =>
    inMemoryStorage.setItem("public-collections", collections);

export const savedPublicCollectionByKey = (
    collectionKey: string,
): Collection | undefined => {
    const collections = savedPublicCollections();
    return collections.find((c) => c.key == collectionKey);
};

export const savePublicCollection = (collection: Collection) => {
    const collections = savedPublicCollections();
    savePublicCollections([
        collection,
        ...collections.filter((c) => c.id != collection.id),
    ]);
};

export const removePublicCollectionByKey = (collectionKey: string) => {
    const collections = savedPublicCollections();
    savePublicCollections([
        ...collections.filter((c) => c.key != collectionKey),
    ]);
};

const LocalString = z.string().nullish().transform(nullToUndefined);

const LocalSavedPublicCollectionFilesEntry = z.object({
    collectionUID: z.string(),
    files: LocalEnteFiles,
});

type LocalSavedPublicCollectionFilesEntry = z.infer<
    typeof LocalSavedPublicCollectionFilesEntry
>;

export const savedPublicCollectionFiles = (accessToken: string): EnteFile[] => {
    const entry = pcfEntries().find((e) => e.collectionUID == accessToken);
    return transformFilesIfNeeded(entry ? entry.files : []);
};

const pcfEntries = () => {
    type ES = LocalSavedPublicCollectionFilesEntry[];

    // Deliberately cast instead of parsing with the Zod schema: parsing very
    // large file arrays is slow, and we ourselves wrote these entries.
    const entries = inMemoryStorage.getItem(
        "public-collection-files",
    ) as ES | null;
    return entries ?? [];
};

export const savePublicCollectionFiles = (
    accessToken: string,
    files: EnteFile[],
): void => {
    inMemoryStorage.setItem("public-collection-files", [
        { collectionUID: accessToken, files },
        ...pcfEntries().filter((e) => e.collectionUID != accessToken),
    ]);
};

export const removePublicCollectionFiles = (accessToken: string): void => {
    inMemoryStorage.setItem("public-collection-files", [
        ...pcfEntries().filter((e) => e.collectionUID != accessToken),
    ]);
};

export const savedPublicCollectionLastSyncTime = (accessToken: string) =>
    LocalTimestamp.parse(inMemoryStorage.getItem(`public-${accessToken}-time`));

export const savePublicCollectionLastSyncTime = (
    accessToken: string,
    time: number,
) => {
    inMemoryStorage.setItem(`public-${accessToken}-time`, time);
};

export const removePublicCollectionLastSyncTime = (accessToken: string) => {
    inMemoryStorage.removeItem(`public-${accessToken}-time`);
};

export const savedPublicCollectionAccessTokenJWT = (accessToken: string) =>
    LocalString.parse(inMemoryStorage.getItem(`public-${accessToken}-passkey`));

export const savePublicCollectionAccessTokenJWT = (
    accessToken: string,
    passwordJWT: string,
) => {
    inMemoryStorage.setItem(`public-${accessToken}-passkey`, passwordJWT);
};

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
