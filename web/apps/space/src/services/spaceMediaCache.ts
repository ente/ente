import { savedPartialLocalUser } from "ente-accounts-rs/services/accounts-db";
import { blobCache } from "ente-base/blob-cache";
import { apiOrigin } from "ente-base/origins";
import { blobPartForBytes } from "services/spaceProfilePayload";

const maxSpaceMediaCacheEntries = 128;
const spaceMediaURLCache = new Map<string, Promise<string>>();

export const spacePostMediaCacheKey = (spaceId: string, objectKey: string) =>
    ["post", spaceId, objectKey].join(":");

export const spaceProfileMediaCacheKey = (
    spaceId: string,
    assetType: "avatar" | "cover",
    objectID: string,
    keyVersion: number,
) => ["profile", spaceId, assetType, objectID, keyVersion].join(":");

const trimSpaceMediaURLCache = () => {
    while (spaceMediaURLCache.size > maxSpaceMediaCacheEntries) {
        const oldest = spaceMediaURLCache.entries().next().value;
        if (!oldest) break;
        spaceMediaURLCache.delete(oldest[0]);
        void oldest[1].then(
            (url) => URL.revokeObjectURL(url),
            () => undefined,
        );
    }
};

const blobForBytes = (bytes: Uint8Array, mediaType?: string) =>
    new Blob([blobPartForBytes(bytes)], { type: mediaType || undefined });

const sha256Hex = async (value: string) => {
    const digest = await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(value),
    );
    return Array.from(new Uint8Array(digest), (byte) =>
        byte.toString(16).padStart(2, "0"),
    ).join("");
};

const spaceMediaStorageKey = async (cacheKey: string) => {
    const userID = savedPartialLocalUser()?.id ?? "";
    const scopedKey = ["v1", await apiOrigin(), userID, cacheKey].join(":");
    return `space-media-${await sha256Hex(scopedKey)}`;
};

const spaceMediaCache = async () => {
    try {
        return await blobCache("space-media");
    } catch (error) {
        console.warn("Failed to open Space media cache", error);
        return undefined;
    }
};

const cachedSpaceMediaBlob = async (storageKey: string) => {
    try {
        return await (await spaceMediaCache())?.get(storageKey);
    } catch (error) {
        console.warn("Failed to read Space media cache", error);
        return undefined;
    }
};

const putSpaceMediaBlob = async (storageKey: string, blob: Blob) => {
    try {
        await (await spaceMediaCache())?.put(storageKey, blob);
    } catch (error) {
        console.warn("Failed to write Space media cache", error);
    }
};

const blobURLForSpaceMedia = async (
    storageKey: string,
    load: () => Promise<Uint8Array>,
    mediaType?: string,
) => {
    const cachedBlob = await cachedSpaceMediaBlob(storageKey);
    if (cachedBlob) return URL.createObjectURL(cachedBlob);

    const blob = blobForBytes(await load(), mediaType);
    await putSpaceMediaBlob(storageKey, blob);
    return URL.createObjectURL(blob);
};

export const cachedSpaceMediaBlobURL = async (
    cacheKey: string,
    load: () => Promise<Uint8Array>,
    mediaType?: string,
) => {
    const storageKey = await spaceMediaStorageKey(cacheKey);
    const cached = spaceMediaURLCache.get(storageKey);
    if (cached) {
        spaceMediaURLCache.delete(storageKey);
        spaceMediaURLCache.set(storageKey, cached);
        return cached;
    }

    const promise = blobURLForSpaceMedia(storageKey, load, mediaType).catch(
        (error: unknown) => {
            spaceMediaURLCache.delete(storageKey);
            throw error;
        },
    );
    spaceMediaURLCache.set(storageKey, promise);
    trimSpaceMediaURLCache();

    return promise;
};

export const rememberCachedSpaceMediaBlobURL = async (
    cacheKey: string,
    blob: Blob,
) => {
    const storageKey = await spaceMediaStorageKey(cacheKey);
    const cached = spaceMediaURLCache.get(storageKey);
    if (cached) return await cached;

    const url = URL.createObjectURL(blob);
    spaceMediaURLCache.set(storageKey, Promise.resolve(url));
    trimSpaceMediaURLCache();
    await putSpaceMediaBlob(storageKey, blob);
    return url;
};

export const clearSpaceMediaURLCache = () => {
    for (const promise of spaceMediaURLCache.values()) {
        void promise.then(
            (url) => URL.revokeObjectURL(url),
            () => undefined,
        );
    }
    spaceMediaURLCache.clear();
};
