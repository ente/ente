import { afterEach, expect, test, vi } from "vitest";
import { PreviewCache } from "./previewCache";

afterEach(() => vi.restoreAllMocks());

test("overlapping consumers keep one URL until the last release", async () => {
    const create = vi
        .spyOn(URL, "createObjectURL")
        .mockReturnValue("blob:preview");
    const revoke = vi
        .spyOn(URL, "revokeObjectURL")
        .mockImplementation(() => undefined);
    const load = vi.fn().mockResolvedValue(new Blob(["image"]));
    const change = vi.fn<(urls: Map<string, string>) => void>();
    const cache = new PreviewCache(load, change);
    const first = cache.retain(["photo", "photo"]);
    const second = cache.retain(["photo"]);
    await Promise.resolve();
    expect(load).toHaveBeenCalledTimes(1);
    expect(create).toHaveBeenCalledTimes(1);
    first();
    expect(revoke).not.toHaveBeenCalled();
    second();
    expect(revoke).toHaveBeenCalledWith("blob:preview");
    expect(change.mock.lastCall?.[0].size).toBe(0);
});

test("late reads cannot resurrect released or reset previews", async () => {
    const create = vi.spyOn(URL, "createObjectURL");
    let complete!: (blob: Blob) => void;
    const cache = new PreviewCache(
        () =>
            new Promise((resolve) => {
                complete = resolve;
            }),
        vi.fn(),
    );
    const release = cache.retain(["photo"]);
    release();
    complete(new Blob(["image"]));
    await Promise.resolve();
    expect(create).not.toHaveBeenCalled();
    cache.retain(["other"]);
    cache.clear();
    complete(new Blob(["image"]));
    await Promise.resolve();
    expect(create).not.toHaveBeenCalled();
});

test("an original arriving during an IndexedDB read wins, and offscreen originals create no URL", async () => {
    const create = vi
        .spyOn(URL, "createObjectURL")
        .mockReturnValue("blob:original");
    vi.spyOn(URL, "revokeObjectURL").mockImplementation(() => undefined);
    let complete!: (blob: Blob) => void;
    const change = vi.fn<(urls: Map<string, string>) => void>();
    const cache = new PreviewCache(
        () =>
            new Promise((resolve) => {
                complete = resolve;
            }),
        change,
    );
    const release = cache.retain(["photo"]);
    const original = new Blob(["original"]);
    cache.refresh("photo", original);
    complete(new Blob(["thumbnail"]));
    await Promise.resolve();
    cache.refresh("offscreen", original);
    expect(create).toHaveBeenCalledTimes(1);
    expect(create).toHaveBeenCalledWith(original);
    expect(change.mock.lastCall?.[0].get("photo")).toBe("blob:original");
    release();
});

test("traversing a large book keeps only the active window's URLs", async () => {
    let id = 0;
    const create = vi
        .spyOn(URL, "createObjectURL")
        .mockImplementation(() => `blob:${++id}`);
    const revoke = vi
        .spyOn(URL, "revokeObjectURL")
        .mockImplementation(() => undefined);
    let active = new Map<string, string>();
    const cache = new PreviewCache(
        () => Promise.resolve(new Blob(["image"])),
        (urls) => {
            active = urls;
        },
    );
    let release: () => void = () => undefined;
    for (let page = 0; page < 300; page++) {
        const nextRelease = cache.retain(
            Array.from({ length: 6 }, (_, i) => String(page + i)),
        );
        release();
        release = nextRelease;
        await Promise.resolve();
        expect(active.size).toBe(6);
    }
    release();
    expect(active.size).toBe(0);
    expect(revoke).toHaveBeenCalledTimes(create.mock.calls.length);
});
