import log from "ente-base/log";

const cacheName = "space-videos";
const maxCacheBytes = 100 * 1024 * 1024;
const loads = new Map<string, Promise<Blob>>();
let writes = Promise.resolve();
let generation = 0;

export const cachedSpaceVideoBlobIfPresent = async (key: string) => {
    const pending = loads.get(key);
    if (pending) return pending;
    try {
        await writes;
        const response = await (await caches.open(cacheName)).match(`/${key}`);
        return await response?.blob();
    } catch (error) {
        log.warn("Failed to read Space video cache", error);
        return undefined;
    }
};

export const rememberSpaceVideoBlob = (key: string, blob: Blob) => {
    const current = generation;
    const write = writes
        .then(async () => {
            if (current != generation || blob.size > maxCacheBytes) return;
            const cache = await caches.open(cacheName);
            if (await cache.match(`/${key}`)) return;
            const entries = await Promise.all(
                (await cache.keys()).map(async (request) => ({
                    request,
                    size: Number(
                        (await cache.match(request))?.headers.get(
                            "Content-Length",
                        ),
                    ),
                })),
            );
            let size = entries.reduce((total, entry) => total + entry.size, 0);
            for (const entry of entries) {
                if (size + blob.size <= maxCacheBytes) break;
                await cache.delete(entry.request);
                size -= entry.size;
            }
            await cache.put(
                `/${key}`,
                new Response(blob, {
                    headers: { "Content-Length": String(blob.size) },
                }),
            );
        })
        .catch((error: unknown) => {
            log.warn("Failed to write Space video cache", error);
        });
    writes = write;
    return write;
};

export const cachedSpaceVideoBlob = (
    key: string,
    load: () => Promise<Blob>,
) => {
    const pending = loads.get(key);
    if (pending) return pending;
    const current = generation;
    const promise = (async () => {
        const cached = await cachedSpaceVideoBlobIfPresent(key);
        if (cached) return cached;
        const blob = await load();
        if (current == generation) await rememberSpaceVideoBlob(key, blob);
        return blob;
    })().finally(() => {
        if (loads.get(key) == promise) loads.delete(key);
    });
    loads.set(key, promise);
    return promise;
};

export const clearSpaceVideoLoads = () => {
    generation++;
    loads.clear();
};

export const clearSpaceVideoCache = () => {
    clearSpaceVideoLoads();
    writes = writes
        .then(async () => {
            await caches.delete(cacheName);
        })
        .catch((error: unknown) => {
            log.warn("Failed to clear Space video cache", error);
        });
    return writes;
};
