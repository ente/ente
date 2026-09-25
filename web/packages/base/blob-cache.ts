import { isDesktop } from "./app";

const blobCacheNames = [
    "thumbs",
    "face-crops",
    "space-media",
    // Desktop only.
    "files",
] as const;

export type BlobCacheNamespace = (typeof blobCacheNames)[number];

export interface BlobCache {
    get: (key: string) => Promise<Blob | undefined>;
    has: (key: string) => Promise<boolean>;
    put: (key: string, blob: Blob) => Promise<void>;
    delete: (key: string) => Promise<boolean>;
}

const cachedCaches = new Map<BlobCacheNamespace, BlobCache>();

export const blobCache = async (
    name: BlobCacheNamespace,
): Promise<BlobCache> => {
    let c = cachedCaches.get(name);
    if (!c) cachedCaches.set(name, (c = await openBlobCache(name)));
    return c;
};

// Electron's custom protocols cannot use Cache API, so desktop uses OPFS.
// Browsers stay on Cache API because OPFS writes are not universally usable here.
const openBlobCache = async (name: BlobCacheNamespace): Promise<BlobCache> =>
    isDesktop ? openOPFSCacheWeb(name) : openWebCache(name);

export const clearBlobCache = async (name: BlobCacheNamespace) => {
    cachedCaches.delete(name);
    return isDesktop ? clearOPFSCache(name) : caches.delete(name);
};

const openWebCache = async (name: BlobCacheNamespace) => {
    const cache = await caches.open(name);
    return {
        get: async (key: string) => {
            const res = await cache.match(key);
            return await res?.blob();
        },
        has: async (key: string) => cache.match(key).then((v) => !!v),
        put: (key: string, blob: Blob) => cache.put(key, new Response(blob)),
        delete: (key: string) => cache.delete(key),
    };
};

const openOPFSCacheWeb = async (name: BlobCacheNamespace) => {
    const root = await navigator.storage.getDirectory();
    const caches = await root.getDirectoryHandle("cache", { create: true });
    const cache = await caches.getDirectoryHandle(name, { create: true });

    return {
        get: async (key: string) => {
            try {
                const fileHandle = await cache.getFileHandle(key);
                return await fileHandle.getFile();
            } catch (e) {
                if (e instanceof DOMException && e.name == "NotFoundError")
                    return undefined;
                throw e;
            }
        },
        has: async (key: string) => {
            try {
                await cache.getFileHandle(key);
                return true;
            } catch (e) {
                if (e instanceof DOMException && e.name == "NotFoundError")
                    return false;
                throw e;
            }
        },
        put: async (key: string, blob: Blob) => {
            const fileHandle = await cache.getFileHandle(key, { create: true });
            const writable = await fileHandle.createWritable();
            await writable.write(blob);
            await writable.close();
        },
        delete: async (key: string) => {
            try {
                await cache.removeEntry(key);
                return true;
            } catch (e) {
                if (e instanceof DOMException && e.name == "NotFoundError")
                    return false;
                throw e;
            }
        },
    };
};

export const clearBlobCaches = async () => {
    cachedCaches.clear();
    return isDesktop ? clearOPFSCaches() : clearWebCaches();
};

const clearWebCaches = () =>
    Promise.all(blobCacheNames.map((name) => caches.delete(name)));

const clearOPFSCache = async (name: BlobCacheNamespace) => {
    const root = await navigator.storage.getDirectory();
    try {
        const caches = await root.getDirectoryHandle("cache");
        await caches.removeEntry(name, { recursive: true });
        return true;
    } catch (e) {
        if (e instanceof DOMException && e.name == "NotFoundError")
            return false;
        throw e;
    }
};

const clearOPFSCaches = async () => {
    const root = await navigator.storage.getDirectory();
    await root.removeEntry("cache", { recursive: true });
};
