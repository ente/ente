import { LRUCache } from "lru-cache";
import StreamZip from "node-stream-zip";

const _cache = new LRUCache<string, StreamZip.StreamZipAsync>({
    max: 50,
    disposeAfter: (zip, zipPath) => {
        if (_refCount.has(zipPath)) {
            // Eviction must not close handles still in use.
            _cache.set(zipPath, zip);
        } else {
            void zip.close();
        }
    },
});

const _refCount = new Map<string, number>();

// Reopening multi-GB Takeout archives per entry turns seconds into hours.
export const openZip = (zipPath: string) => {
    let result = _cache.get(zipPath);
    if (!result) {
        result = new StreamZip.async({ file: zipPath });
        _cache.set(zipPath, result);
    }
    _refCount.set(zipPath, (_refCount.get(zipPath) ?? 0) + 1);
    return result;
};

export const markClosableZip = (zipPath: string) => {
    const rc = _refCount.get(zipPath);
    if (!rc) throw new Error(`Double close for ${zipPath}`);
    if (rc == 1) _refCount.delete(zipPath);
    else _refCount.set(zipPath, rc - 1);
};

export const clearOpenZipCache = () => {
    if (_refCount.size > 0) {
        const kvs = JSON.stringify([..._refCount.entries()]);
        throw new Error(
            `Attempting to clear zip file cache when some items are still in use: ${kvs}`,
        );
    }
    _cache.clear();
};
