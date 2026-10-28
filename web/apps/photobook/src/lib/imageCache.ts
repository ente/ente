const MAX_ENTRIES = 250;

interface CacheEntry {
    img: HTMLImageElement;
    url: string;
}

const cache = new Map<string, CacheEntry>();

interface PendingEntry {
    url: string;
    promise: Promise<HTMLImageElement>;
}

const pending = new Map<string, PendingEntry>();

function isUsable(img: HTMLImageElement): boolean {
    return img.complete && img.naturalWidth > 0;
}

function touch(photoId: string, entry: CacheEntry): void {
    cache.delete(photoId);
    cache.set(photoId, entry);
}

function insert(photoId: string, entry: CacheEntry): void {
    cache.delete(photoId); // ensure we move, not duplicate
    cache.set(photoId, entry);
    while (cache.size > MAX_ENTRIES) {
        const oldest = cache.keys().next();
        if (oldest.done) break;
        cache.delete(oldest.value);
    }
}

export function getCachedImage(photoId: string): HTMLImageElement | null {
    const entry = cache.get(photoId);
    if (entry && isUsable(entry.img)) {
        touch(photoId, entry);
        return entry.img;
    }
    return null;
}

export function getCachedUrl(photoId: string): string | null {
    const entry = cache.get(photoId);
    return entry ? entry.url : null;
}

export function loadImageCached(
    photoId: string,
    url: string,
): Promise<HTMLImageElement> {
    const existing = cache.get(photoId);
    if (existing?.url === url && isUsable(existing.img)) {
        touch(photoId, existing);
        return Promise.resolve(existing.img);
    }

    // Only coalesce if the in-flight request is for the same URL
    const inflight = pending.get(photoId);
    if (inflight?.url === url) return inflight.promise;

    const promise = new Promise<HTMLImageElement>((resolve, reject) => {
        const img = new window.Image();
        img.onload = () => {
            insert(photoId, { img, url });
            pending.delete(photoId);
            resolve(img);
        };
        img.onerror = (e) => {
            pending.delete(photoId);
            reject(new Error("Failed to load photo", { cause: e }));
        };
        img.src = url;
    });
    pending.set(photoId, { url, promise });
    return promise;
}

export function clearImageCache(): void {
    cache.clear();
    pending.clear();
}
