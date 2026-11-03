import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    clearImageCache,
    evictCachedImage,
    getCachedImage,
    loadImageCached,
} from "./imageCache";

class TestImage {
    static created: TestImage[] = [];
    naturalWidth = 1080;
    naturalHeight = 1080;
    onload = vi.fn<() => void>();
    src = "";
    constructor() {
        TestImage.created.push(this);
    }
}

beforeEach(() => {
    clearImageCache();
    TestImage.created = [];
    vi.stubGlobal("window", { Image: TestImage });
});
afterEach(() => {
    clearImageCache();
    vi.unstubAllGlobals();
});

test("thumbnail and preview loads coexist and identical requests are deduplicated", async () => {
    const thumbnail = loadImageCached("blob:thumbnail");
    const preview = loadImageCached("blob:preview");
    expect(loadImageCached("blob:preview")).toBe(preview);
    TestImage.created.forEach((image) => image.onload());
    expect(await thumbnail).not.toBe(await preview);
    expect(getCachedImage("blob:thumbnail")).toBe(await thumbnail);
    expect(getCachedImage("blob:preview")).toBe(await preview);
});

test("decoded image retention is limited by bytes and recently used images survive", async () => {
    for (let i = 0; i < 14; i++) {
        const load = loadImageCached(String(i));
        TestImage.created.at(-1)!.onload();
        await load;
    }
    expect(getCachedImage("0")).not.toBeNull();
    const next = loadImageCached("14");
    TestImage.created.at(-1)!.onload();
    await next;
    expect(getCachedImage("0")).not.toBeNull();
    expect(getCachedImage("1")).toBeNull();
});

test("eviction and reset invalidate loads still in flight", async () => {
    const first = loadImageCached("first");
    evictCachedImage("first");
    TestImage.created.at(-1)!.onload();
    await first;
    expect(getCachedImage("first")).toBeNull();
    const second = loadImageCached("second");
    clearImageCache();
    TestImage.created.at(-1)!.onload();
    await second;
    expect(getCachedImage("second")).toBeNull();
});
