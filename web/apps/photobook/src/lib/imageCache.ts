const MAX_BYTES = 64 * 1024 * 1024;

const cache = new Map<string, HTMLImageElement>();
const pending = new Map<string, Promise<HTMLImageElement>>();
let bytes = 0;

export function evictCachedImage(url: string): void {
    const image = cache.get(url);
    if (image) {
        bytes -= image.naturalWidth * image.naturalHeight * 4;
        cache.delete(url);
    }
    pending.delete(url);
}

export function getCachedImage(url: string): HTMLImageElement | null {
    const image = cache.get(url);
    if (!image) return null;
    cache.delete(url);
    cache.set(url, image);
    return image;
}

export function loadImageCached(url: string): Promise<HTMLImageElement> {
    const existing = getCachedImage(url);
    if (existing) return Promise.resolve(existing);
    const inflight = pending.get(url);
    if (inflight) return inflight;

    const promise = new Promise<HTMLImageElement>((resolve, reject) => {
        const image = new window.Image();
        image.decoding = "async";
        image.onload = () => {
            if (pending.get(url) === promise) {
                pending.delete(url);
                cache.set(url, image);
                bytes += image.naturalWidth * image.naturalHeight * 4;
                while (bytes > MAX_BYTES && cache.size > 0) {
                    evictCachedImage(cache.keys().next().value!);
                }
            }
            resolve(image);
        };
        image.onerror = (cause) => {
            if (pending.get(url) === promise) pending.delete(url);
            reject(new Error("Failed to load photo", { cause }));
        };
        image.src = url;
    });
    pending.set(url, promise);
    return promise;
}

export function clearImageCache(): void {
    cache.clear();
    pending.clear();
    bytes = 0;
}
