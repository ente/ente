import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import { getKV, removeKV, setKV } from "ente-base/kv";
import { apiOrigin } from "ente-base/origins";
import { beforeEach, expect, test, vi } from "vitest";
import {
    cacheCurrentSpaceFeedPage,
    clearSpaceFeedMemoryCache,
    loadCachedSpaceFeed,
    patchCachedSpaceFeedPost,
    prependCachedSpaceFeedPost,
    removeCachedSpaceFeedPost,
    removeCachedSpaceFeedPostsBySpace,
} from "../src/services/feed-cache";
import type { SpacePost } from "../src/services/space";

vi.mock("ente-accounts/services/accounts-db", () => ({
    savedPartialLocalUser: vi.fn(),
}));
vi.mock("ente-base/kv", () => ({
    getKV: vi.fn(),
    setKV: vi.fn(),
    removeKV: vi.fn(),
}));
vi.mock("ente-base/log", () => ({ default: { warn: vi.fn() } }));
vi.mock("ente-base/origins", () => ({ apiOrigin: vi.fn() }));

const storage = new Map<string, unknown>();
const post = (postId: number, spaceId = "friend"): SpacePost => ({
    avatarUrl: "blob:avatar",
    caption: "A photo",
    friendID: spaceId,
    imageAsset: {
        encryptedPostKey: "encrypted-key",
        keyVersion: 1,
        objectKey: `photo-${postId}`,
        postId,
        spaceId,
    },
    imageUrl: "blob:photo",
    name: spaceId,
    postId,
    spaceId,
    thumbHash: "3OcRJYB4d3h/iIeHeEh3eIhw+j3A",
    timestampMs: postId,
    viewerLiked: false,
});

beforeEach(() => {
    vi.resetAllMocks();
    storage.clear();
    clearSpaceFeedMemoryCache();
    vi.mocked(savedPartialLocalUser).mockReturnValue({ id: 1 });
    vi.mocked(apiOrigin).mockResolvedValue("https://api.example.com");
    vi.mocked(getKV).mockImplementation((key) =>
        Promise.resolve(storage.get(key)),
    );
    vi.mocked(setKV).mockImplementation((key, value) => {
        storage.set(key, structuredClone(value));
        return Promise.resolve();
    });
    vi.mocked(removeKV).mockImplementation((key) => {
        storage.delete(key);
        return Promise.resolve();
    });
});

test("restores cached cards and pagination after a reload without expired blob URLs", async () => {
    await cacheCurrentSpaceFeedPage("self", {
        items: [post(2), post(1, "self")],
        nextCursor: "older",
    });
    clearSpaceFeedMemoryCache();
    const cached = await loadCachedSpaceFeed("self");
    expect(cached?.items.map((item) => item.postId)).toEqual([2, 1]);
    expect(cached?.nextCursor).toBe("older");
    expect(cached?.items[0]?.imageAsset).toEqual(post(2).imageAsset);
    expect(cached?.items[0]?.thumbHash).toBe(post(2).thumbHash);
    expect(cached?.items[0]).not.toHaveProperty("imageUrl");
    expect(cached?.items[0]).not.toHaveProperty("avatarUrl");
});

test("persists the first publication before a feed has been cached", async () => {
    await prependCachedSpaceFeedPost("self", post(1, "self"));
    clearSpaceFeedMemoryCache();
    const cached = await loadCachedSpaceFeed("self");
    expect(cached?.items.map((item) => item.postId)).toEqual([1]);
    expect(cached?.dirty).toBe(true);
});

test("restores every photo in order and preserves shared post edits", async () => {
    const original = post(3);
    original.photos = ["cover", "second", "third"].map((objectKey, index) => ({
        imageAsset: { ...original.imageAsset!, objectKey },
        imageUrl: `blob:${objectKey}`,
        height: 800 + index,
        width: 1200,
        thumbHash: `hash-${index}`,
    }));
    await cacheCurrentSpaceFeedPage("self", { items: [original] });
    await patchCachedSpaceFeedPost("self", 3, {
        caption: "Edited caption",
        viewerLiked: true,
    });
    const firstRead = await loadCachedSpaceFeed("self");
    firstRead!.items[0]!.photos![1]!.imageAsset!.objectKey =
        "changed by caller";
    clearSpaceFeedMemoryCache();
    const restored = (await loadCachedSpaceFeed("self"))!.items[0]!;
    expect(restored).toMatchObject({
        caption: "Edited caption",
        viewerLiked: true,
    });
    expect(
        restored.photos?.map((photo) => photo.imageAsset?.objectKey),
    ).toEqual(["cover", "second", "third"]);
    expect(restored.photos?.map((photo) => photo.height)).toEqual([
        800, 801, 802,
    ]);
    expect(restored.photos?.every((photo) => !("imageUrl" in photo))).toBe(
        true,
    );
    expect(original.photos[1]?.imageUrl).toBe("blob:second");
});

test("serializes new posts, likes, edits and deletions without losing changes", async () => {
    await cacheCurrentSpaceFeedPage("self", {
        items: [post(2), post(1)],
        nextCursor: "older",
    });
    await Promise.all([
        prependCachedSpaceFeedPost("self", post(3, "self")),
        patchCachedSpaceFeedPost("self", 2, { viewerLiked: true }),
        patchCachedSpaceFeedPost("self", 3, { caption: "Edited" }),
        removeCachedSpaceFeedPost("self", 1),
    ]);
    const cached = await loadCachedSpaceFeed("self");
    expect(cached?.items.map((item) => item.postId)).toEqual([3, 2]);
    expect(cached?.items[0]?.caption).toBe("Edited");
    expect(cached?.items[1]?.viewerLiked).toBe(true);
    expect(cached?.nextCursor).toBeUndefined();
    await removeCachedSpaceFeedPostsBySpace("self", "friend");
    expect(
        (await loadCachedSpaceFeed("self"))?.items.map((item) => item.postId),
    ).toEqual([3]);
});

test("keeps cached feeds separate across spaces, accounts and servers", async () => {
    await cacheCurrentSpaceFeedPage("self", { items: [post(1)] });
    expect(await loadCachedSpaceFeed("other")).toBeUndefined();
    vi.mocked(savedPartialLocalUser).mockReturnValue({ id: 2 });
    expect(await loadCachedSpaceFeed("self")).toBeUndefined();
    vi.mocked(savedPartialLocalUser).mockReturnValue({ id: 1 });
    vi.mocked(apiOrigin).mockResolvedValue("https://other.example.com");
    expect(await loadCachedSpaceFeed("self")).toBeUndefined();
});

test("storage failures do not fail posting or feed refresh", async () => {
    vi.mocked(setKV).mockRejectedValue(new Error("Storage unavailable"));
    await expect(
        prependCachedSpaceFeedPost("self", post(1)),
    ).resolves.toBeUndefined();
    await expect(
        cacheCurrentSpaceFeedPage("self", { items: [post(2)] }),
    ).resolves.toBe(true);
    expect((await loadCachedSpaceFeed("self"))?.items[0]?.postId).toBe(2);
});

test("a delayed refresh cannot overwrite a publication or deletion", async () => {
    await cacheCurrentSpaceFeedPage("self", { items: [post(2), post(1)] });
    const cached = await loadCachedSpaceFeed("self");
    await prependCachedSpaceFeedPost("self", post(3, "self"));
    await removeCachedSpaceFeedPost("self", 1);
    expect(
        await cacheCurrentSpaceFeedPage(
            "self",
            { items: [post(2), post(1)] },
            { syncedAtMs: cached?.syncedAtMs },
        ),
    ).toBe(false);
    expect(
        (await loadCachedSpaceFeed("self"))?.items.map((item) => item.postId),
    ).toEqual([3, 2]);
});
