import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    cachedSpaceMediaBlobURL,
    cachedSpaceMediaBlobURLIfPresent,
    clearSpaceMediaCache,
    clearSpaceMediaURLCache,
    rememberCachedSpaceVideoBlob,
    spacePostMediaCacheKey,
    spaceProfileMediaCacheKey,
} from "../src/services/media-cache";
import { SpaceMediaRateLimitError } from "../src/services/media-load";

vi.mock("ente-accounts/services/accounts-db", () => ({
    savedPartialLocalUser: () => ({ id: 1 }),
}));
vi.mock("ente-base/origins", () => ({
    apiOrigin: () => Promise.resolve("https://api.example.com"),
}));
vi.mock("ente-base/blob-cache", () => ({
    blobCache: () => Promise.resolve({ get: () => undefined, put: vi.fn() }),
    clearBlobCache: vi.fn(),
}));
vi.mock("ente-base/log", () => ({ default: { warn: vi.fn() } }));

const stored = new Map<string, Response>();
const createURL = vi.fn<(blob: Blob | MediaSource) => string>();
let pageURL: string;
const cacheURL = (key: string | Request) =>
    typeof key == "string" ? new URL(key, pageURL).href : key.url;
const cache = {
    match: vi.fn((key: string | Request) =>
        Promise.resolve(stored.get(cacheURL(key))?.clone()),
    ),
    keys: () =>
        Promise.resolve([...stored.keys()].map((key) => new Request(key))),
    put: vi.fn((key: string, response: Response) => {
        stored.set(cacheURL(key), response);
        return Promise.resolve();
    }),
    delete: (key: string | Request) =>
        Promise.resolve(stored.delete(cacheURL(key))),
};

const assets = [
    { key: spaceProfileMediaCacheKey("space", "avatar", "avatar", 1) },
    { key: spaceProfileMediaCacheKey("space", "cover", "cover", 1) },
    { key: spacePostMediaCacheKey("space", "photo") },
    { key: spacePostMediaCacheKey("space", "video"), mediaType: "video/mp4" },
];

beforeEach(() => {
    vi.useFakeTimers();
    clearSpaceMediaURLCache();
    stored.clear();
    pageURL = "https://space.test/app";
    createURL.mockReset().mockReturnValue("blob:media");
    vi.stubGlobal("caches", {
        open: () => Promise.resolve(cache),
        delete: () => {
            stored.clear();
            return Promise.resolve(true);
        },
    });
    vi.spyOn(URL, "createObjectURL").mockImplementation(createURL);
    vi.spyOn(URL, "revokeObjectURL").mockImplementation(() => undefined);
});

afterEach(() => {
    clearSpaceMediaURLCache();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    vi.useRealTimers();
});

test.each(assets)(
    "a 429 from $key pauses all uncached media downloads",
    async (asset) => {
        const download = vi.fn().mockResolvedValue(new Uint8Array([1]));
        await cachedSpaceMediaBlobURL("cached-photo", download);
        download.mockClear();
        const failure = await cachedSpaceMediaBlobURL(
            asset.key,
            () =>
                Promise.reject(
                    Object.assign(new Error("Rate limit"), { status: 429 }),
                ),
            asset.mediaType,
        ).catch((error: unknown) => error);
        expect(failure).toBeInstanceOf(SpaceMediaRateLimitError);

        await vi.advanceTimersByTimeAsync(59_999);
        for (const other of assets) {
            await expect(
                cachedSpaceMediaBlobURL(other.key, download, other.mediaType),
            ).rejects.toBe(failure);
        }
        await expect(
            cachedSpaceMediaBlobURL("cached-photo", download),
        ).resolves.toBe("blob:media");
        expect(download).not.toHaveBeenCalled();

        await vi.advanceTimersByTimeAsync(1);
        for (const other of assets) {
            await expect(
                cachedSpaceMediaBlobURL(other.key, download, other.mediaType),
            ).resolves.toBe("blob:media");
        }
        expect(download).toHaveBeenCalledTimes(assets.length);
    },
);

test("video bytes survive player disposal and memory-cache clearing", async () => {
    const download = vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3]));
    const first = await cachedSpaceMediaBlobURL("video", download, "video/mp4");
    URL.revokeObjectURL(first);
    clearSpaceMediaURLCache();
    await cachedSpaceMediaBlobURL("video", download, "video/mp4");
    expect(download).toHaveBeenCalledOnce();
    expect(createURL).toHaveBeenCalledTimes(2);
    expect(await (createURL.mock.calls[1]![0] as Blob).bytes()).toEqual(
        new Uint8Array([1, 2, 3]),
    );
});

test.each([
    ["/app", "/app/profile"],
    ["/app/profile", "/app"],
])("a video cached on %s is reused on %s", async (from, to) => {
    const download = vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3]));
    pageURL = `https://space.test${from}`;
    await cachedSpaceMediaBlobURL("video", download, "video/mp4");
    pageURL = `https://space.test${to}`;
    clearSpaceMediaURLCache();
    expect(
        await cachedSpaceMediaBlobURLIfPresent("video", "video/mp4"),
    ).toBeDefined();
    await cachedSpaceMediaBlobURL("video", download, "video/mp4");
    await rememberCachedSpaceVideoBlob(
        "video",
        new Blob(["video"], { type: "video/mp4" }),
    );
    expect(download).toHaveBeenCalledOnce();
    expect(stored.size).toBe(1);
});

test("concurrent players share a download and receive their own playback URLs", async () => {
    createURL
        .mockReturnValueOnce("blob:first")
        .mockReturnValueOnce("blob:second");
    let finish!: (bytes: Uint8Array) => void;
    const download = vi.fn(
        () =>
            new Promise<Uint8Array>((resolve) => {
                finish = resolve;
            }),
    );
    const first = cachedSpaceMediaBlobURL("video", download, "video/mp4");
    const second = cachedSpaceMediaBlobURL("video", download, "video/mp4");
    await vi.waitFor(() => expect(download).toHaveBeenCalledOnce());
    finish(new Uint8Array([7]));
    expect(new Set(await Promise.all([first, second]))).toEqual(
        new Set(["blob:first", "blob:second"]),
    );
    expect(createURL).toHaveBeenCalledTimes(2);
    expect(createURL.mock.calls[0]![0]).toBe(createURL.mock.calls[1]![0]);
});

test("a published video is available from the cache without downloading", async () => {
    const blob = new Blob(["published video"], { type: "video/mp4" });
    await rememberCachedSpaceVideoBlob("video", blob);
    clearSpaceMediaURLCache();
    expect(await cachedSpaceMediaBlobURLIfPresent("video", "video/mp4")).toBe(
        "blob:media",
    );
    const cached = createURL.mock.calls[0]![0] as Blob;
    expect(await cached.text()).toBe("published video");
    expect(cached.type).toBe("video/mp4");
});

test("video caching evicts older clips to stay within 100 MiB", async () => {
    const blob = new Blob(["video"], { type: "video/mp4" });
    Object.defineProperty(blob, "size", { value: 40 * 1024 * 1024 });
    await rememberCachedSpaceVideoBlob("first", blob);
    await Promise.all([
        rememberCachedSpaceVideoBlob("second", blob),
        rememberCachedSpaceVideoBlob("second", blob),
    ]);
    expect(stored.size).toBe(2);
    expect(
        await cachedSpaceMediaBlobURLIfPresent("first", "video/mp4"),
    ).toBeDefined();
    await rememberCachedSpaceVideoBlob("third", blob);
    expect(
        await cachedSpaceMediaBlobURLIfPresent("first", "video/mp4"),
    ).toBeUndefined();
    expect(
        await cachedSpaceMediaBlobURLIfPresent("second", "video/mp4"),
    ).toBeDefined();
    expect(
        await cachedSpaceMediaBlobURLIfPresent("third", "video/mp4"),
    ).toBeDefined();
});

test("clearing media also clears saved videos and prevents late downloads from repopulating them", async () => {
    await rememberCachedSpaceVideoBlob(
        "saved",
        new Blob(["video"], { type: "video/mp4" }),
    );
    let finish!: (bytes: Uint8Array) => void;
    const download = vi.fn(
        () =>
            new Promise<Uint8Array>((resolve) => {
                finish = resolve;
            }),
    );
    const pending = cachedSpaceMediaBlobURL("pending", download, "video/mp4");
    await vi.waitFor(() => expect(download).toHaveBeenCalledOnce());
    await clearSpaceMediaCache();
    finish(new Uint8Array([1]));
    await pending;
    expect(stored.size).toBe(0);
});

test("a full browser cache does not prevent video playback", async () => {
    cache.put.mockRejectedValueOnce(
        new DOMException("Full", "QuotaExceededError"),
    );
    await expect(
        cachedSpaceMediaBlobURL(
            "video",
            () => Promise.resolve(new Uint8Array([1])),
            "video/mp4",
        ),
    ).resolves.toBe("blob:media");
});
