import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import { getKV, removeKV, setKV } from "ente-base/kv";
import { apiOrigin } from "ente-base/origins";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    cacheCurrentSpaceFeedPage,
    clearSpaceFeedMemoryCache,
    loadCachedSpaceFeed,
    loadSpaceFeedSession,
    patchCachedSpaceFeedPost,
    prependCachedSpaceFeedPost,
    rememberSpaceFeedSessionPosts,
    removeCachedSpaceFeedPost,
    removeCachedSpaceFeedPostsBySpace,
    spaceFeedSessionItems,
} from "../src/services/feed-cache";
import type { SpacePost } from "../src/services/space";
import { homeFeedEntries } from "../src/utils/home-feed";

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

afterEach(() => vi.useRealTimers());

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

test("restores all twenty posts and their cursor, then keeps the cache bounded when posting", async () => {
    const posts = Array.from({ length: 20 }, (_, index) => post(20 - index));
    await cacheCurrentSpaceFeedPage("self", {
        items: posts,
        nextCursor: "after-twenty",
    });
    clearSpaceFeedMemoryCache();
    const restored = (await loadCachedSpaceFeed("self"))!;
    expect(restored.items.map((post) => post.postId)).toEqual(
        posts.map((post) => post.postId),
    );
    expect(restored.nextCursor).toBe("after-twenty");

    await prependCachedSpaceFeedPost("self", post(21, "self"));
    clearSpaceFeedMemoryCache();
    const afterPosting = (await loadCachedSpaceFeed("self"))!;
    expect(afterPosting.items.map((post) => post.postId)).toEqual([
        21,
        ...posts.slice(0, 19).map((post) => post.postId),
    ]);
    expect(afterPosting.nextCursor).toBeUndefined();
    expect(afterPosting.dirty).toBe(true);
});

test("shrinks an existing thirty-post cache without losing the visit cutoff or skipping posts", async () => {
    await cacheCurrentSpaceFeedPage(
        "self",
        { items: [post(30)] },
        undefined,
        100,
    );
    const [key] = vi.mocked(setKV).mock.calls[0]!;
    const snapshot = (await loadCachedSpaceFeed("self"))!;
    const posts = Array.from({ length: 30 }, (_, index) => post(30 - index));
    storage.set(key, { ...snapshot, items: posts, nextCursor: "after-thirty" });
    clearSpaceFeedMemoryCache();
    const restored = (await loadCachedSpaceFeed("self"))!;
    expect(restored.items.map((post) => post.postId)).toEqual(
        posts.slice(0, 20).map((post) => post.postId),
    );
    expect(restored.nextCursor).toBeUndefined();
    expect(restored.dirty).toBe(true);
    expect(restored.lastVisitedAtMs).toBe(100);
    expect((await loadSpaceFeedSession("self"))?.newPostsSinceMs).toBe(100);
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

test("remembers the previous visit across reloads and cache mutations", async () => {
    await cacheCurrentSpaceFeedPage("self", { items: [post(2)] });
    expect(
        (await loadCachedSpaceFeed("self"))?.lastVisitedAtMs,
    ).toBeUndefined();
    await cacheCurrentSpaceFeedPage(
        "self",
        { items: [post(2)] },
        undefined,
        100,
    );
    clearSpaceFeedMemoryCache();
    expect((await loadCachedSpaceFeed("self"))?.lastVisitedAtMs).toBe(100);
    await prependCachedSpaceFeedPost("self", post(3, "self"));
    await patchCachedSpaceFeedPost("self", 2, { viewerLiked: true });
    await removeCachedSpaceFeedPost("self", 3);
    await cacheCurrentSpaceFeedPage("self", { items: [post(2)] });
    expect((await loadCachedSpaceFeed("self"))?.lastVisitedAtMs).toBe(100);
    await cacheCurrentSpaceFeedPage(
        "self",
        { items: [post(2)] },
        undefined,
        200,
    );
    clearSpaceFeedMemoryCache();
    expect((await loadCachedSpaceFeed("self"))?.lastVisitedAtMs).toBe(200);
    expect(await loadCachedSpaceFeed("other")).toBeUndefined();
});

test("a rejected refresh does not consume a visit", async () => {
    await cacheCurrentSpaceFeedPage(
        "self",
        { items: [post(2)] },
        undefined,
        100,
    );
    const cached = await loadCachedSpaceFeed("self");
    await prependCachedSpaceFeedPost("self", post(3));
    expect(
        await cacheCurrentSpaceFeedPage(
            "self",
            { items: [post(2)] },
            { syncedAtMs: cached?.syncedAtMs },
            200,
        ),
    ).toBe(false);
    expect((await loadCachedSpaceFeed("self"))?.lastVisitedAtMs).toBe(100);
});

test("the latest cutoff survives navigation and advances only on a new app session", async () => {
    await cacheCurrentSpaceFeedPage(
        "self",
        { items: [post(100)] },
        undefined,
        100,
    );
    const session = (await loadSpaceFeedSession("self"))!;
    expect(session.newPostsSinceMs).toBe(100);
    await cacheCurrentSpaceFeedPage(
        "self",
        { items: [post(150), post(100)] },
        undefined,
        200,
    );
    session.presentedPostIdentities.add("post:150");
    const returned = (await loadSpaceFeedSession("self"))!;
    expect(returned).toBe(session);
    expect(returned.newPostsSinceMs).toBe(100);
    expect(returned.latestPosts.map((post) => post.postId)).toEqual([150]);
    expect(returned.presentedPostIdentities.has("post:150")).toBe(true);

    clearSpaceFeedMemoryCache();
    const reopened = (await loadSpaceFeedSession("self"))!;
    expect(reopened.newPostsSinceMs).toBe(200);
    expect(reopened.latestPosts).toEqual([]);
    expect(reopened.presentedPostIdentities.size).toBe(0);
});

test.each(["pagination", "publication"])(
    "%s leaves unfetched friend posts new on the next app opening",
    async (action) => {
        vi.useFakeTimers();
        vi.setSystemTime(200);
        await cacheCurrentSpaceFeedPage(
            "self",
            { items: [post(120)], nextCursor: "older" },
            undefined,
            200,
        );
        const session = (await loadSpaceFeedSession("self"))!;
        const unseenPost = post(250);
        const ownPost = post(300, "self");
        vi.setSystemTime(300);
        if (action == "pagination") {
            await rememberSpaceFeedSessionPosts("self", [post(110)]);
        } else {
            await prependCachedSpaceFeedPost("self", ownPost);
            expect(session.latestPosts.map((post) => post.postId)).toEqual([
                300,
            ]);
        }
        expect((await loadCachedSpaceFeed("self"))?.lastVisitedAtMs).toBe(200);

        vi.setSystemTime(400);
        clearSpaceFeedMemoryCache();
        const reopened = (await loadSpaceFeedSession("self"))!;
        const items =
            action == "publication"
                ? [ownPost, unseenPost, post(120)]
                : [unseenPost, post(120)];
        await cacheCurrentSpaceFeedPage("self", { items }, undefined, 400);
        expect(reopened.newPostsSinceMs).toBe(200);
        expect(reopened.latestPosts.map((post) => post.postId)).toEqual([250]);
        expect(
            homeFeedEntries(
                spaceFeedSessionItems(reopened, items),
                [],
                reopened.newPostsSinceMs,
                new Set(reopened.latestPosts.map((post) => post.postId)),
                "self",
            ).latest.map((entry) => entry.identity),
        ).toEqual(["post:250"]);
        expect((await loadCachedSpaceFeed("self"))?.lastVisitedAtMs).toBe(400);
    },
);

test("returning to the feed retains more than twenty latest posts while disk caching stays bounded", async () => {
    await cacheCurrentSpaceFeedPage(
        "self",
        { items: [post(100)] },
        undefined,
        100,
    );
    const session = (await loadSpaceFeedSession("self"))!;
    const posts = Array.from({ length: 45 }, (_, index) => post(145 - index));
    await cacheCurrentSpaceFeedPage(
        "self",
        { items: posts.slice(0, 20), nextCursor: "older" },
        undefined,
        200,
    );
    await rememberSpaceFeedSessionPosts("self", posts.slice(20));
    await cacheCurrentSpaceFeedPage("self", {
        items: posts.slice(0, 20),
        nextCursor: "older",
    });
    expect(await loadSpaceFeedSession("self")).toBe(session);
    expect(
        spaceFeedSessionItems(session, posts.slice(0, 20)).map(
            (post) => post.postId,
        ),
    ).toEqual(posts.map((post) => post.postId));
    expect((await loadCachedSpaceFeed("self"))?.items).toHaveLength(20);
    clearSpaceFeedMemoryCache();
    expect((await loadCachedSpaceFeed("self"))?.items).toHaveLength(20);
    expect((await loadSpaceFeedSession("self"))?.latestPosts).toEqual([]);
});

test.each([{ remaining: [150] }, { remaining: [] }])(
    "a complete refresh removes deleted latest posts when remaining IDs are $remaining",
    async ({ remaining }) => {
        await cacheCurrentSpaceFeedPage("self", { items: [] }, undefined, 100);
        const session = (await loadSpaceFeedSession("self"))!;
        await cacheCurrentSpaceFeedPage("self", {
            items: [post(150), post(140)],
            nextCursor: "older",
        });
        await rememberSpaceFeedSessionPosts("self", [post(120)]);

        const items = remaining.map((id) => post(id));
        await cacheCurrentSpaceFeedPage("self", { items });
        expect(await loadSpaceFeedSession("self")).toBe(session);
        expect(session.latestPosts.map((post) => post.postId)).toEqual(
            remaining,
        );
        expect(
            spaceFeedSessionItems(session, items).map((post) => post.postId),
        ).toEqual(remaining);
    },
);

test("a partial refresh removes missing latest posts in its range and retains older pages", async () => {
    await cacheCurrentSpaceFeedPage("self", { items: [] }, undefined, 100);
    const session = (await loadSpaceFeedSession("self"))!;
    await cacheCurrentSpaceFeedPage("self", {
        items: [post(160), post(150), post(140), post(130)],
        nextCursor: "older",
    });
    await rememberSpaceFeedSessionPosts("self", [post(120), post(110)]);
    session.presentedPostIdentities.add("post:150");

    const items = [post(170), { ...post(150), caption: "Updated" }, post(130)];
    await cacheCurrentSpaceFeedPage("self", { items, nextCursor: "older" });
    expect(session.latestPosts.map((post) => post.postId)).toEqual([
        170, 150, 130, 120, 110,
    ]);
    expect(
        spaceFeedSessionItems(session, items).map((post) => post.postId),
    ).toEqual([170, 150, 130, 120, 110]);
    expect(
        session.latestPosts.find((post) => post.postId == 150)?.caption,
    ).toBe("Updated");
    expect(session.newPostsSinceMs).toBe(100);
    expect(session.presentedPostIdentities.has("post:150")).toBe(true);
});

test("a refresh uses post IDs to distinguish posts at the same boundary timestamp", async () => {
    await cacheCurrentSpaceFeedPage("self", { items: [] }, undefined, 100);
    const session = (await loadSpaceFeedSession("self"))!;
    await cacheCurrentSpaceFeedPage("self", {
        items: [151, 150, 149].map((id) => ({ ...post(id), timestampMs: 150 })),
        nextCursor: "older",
    });
    await rememberSpaceFeedSessionPosts("self", [post(140)]);

    await cacheCurrentSpaceFeedPage("self", {
        items: [post(160), post(150)],
        nextCursor: "older",
    });
    expect(session.latestPosts.map((post) => post.postId)).toEqual([
        160, 150, 149, 140,
    ]);
});

test("edits and deletions from other pages update retained latest posts outside the disk cache", async () => {
    await cacheCurrentSpaceFeedPage(
        "self",
        { items: [post(100)] },
        undefined,
        100,
    );
    const session = (await loadSpaceFeedSession("self"))!;
    const posts = Array.from({ length: 15 }, (_, index) => post(115 - index));
    await cacheCurrentSpaceFeedPage("self", {
        items: posts.slice(0, 10),
        nextCursor: "older",
    });
    await rememberSpaceFeedSessionPosts("self", posts.slice(10));
    await patchCachedSpaceFeedPost("self", 101, {
        caption: "Edited elsewhere",
        viewerLiked: true,
    });
    expect(
        session.latestPosts.find((post) => post.postId == 101),
    ).toMatchObject({ caption: "Edited elsewhere", viewerLiked: true });
    await removeCachedSpaceFeedPost("self", 101);
    expect(session.latestPosts.some((post) => post.postId == 101)).toBe(false);
    await removeCachedSpaceFeedPostsBySpace("self", "friend");
    expect(session.latestPosts).toEqual([]);
});

test("a first-session publication stays latest until the next app opening", async () => {
    const session = (await loadSpaceFeedSession("self"))!;
    const ownPost = post(session.newPostsSinceMs + 1, "self");
    await prependCachedSpaceFeedPost("self", ownPost);
    expect(await loadSpaceFeedSession("self")).toBe(session);
    expect(session.latestPosts.map((post) => post.postId)).toEqual([
        ownPost.postId,
    ]);
    await cacheCurrentSpaceFeedPage("self", { items: [ownPost] });
    expect(session.latestPosts.map((post) => post.postId)).toEqual([
        ownPost.postId,
    ]);
    clearSpaceFeedMemoryCache();
    expect((await loadSpaceFeedSession("self"))?.latestPosts).toEqual([]);
});

test("latest sessions are isolated between accounts, spaces and servers", async () => {
    const session = (await loadSpaceFeedSession("self"))!;
    await prependCachedSpaceFeedPost("self", post(1, "self"));
    expect((await loadSpaceFeedSession("other"))?.latestPosts).toEqual([]);
    vi.mocked(savedPartialLocalUser).mockReturnValue({ id: 2 });
    expect((await loadSpaceFeedSession("self"))?.latestPosts).toEqual([]);
    vi.mocked(savedPartialLocalUser).mockReturnValue({ id: 1 });
    vi.mocked(apiOrigin).mockResolvedValue("https://other.example.com");
    expect((await loadSpaceFeedSession("self"))?.latestPosts).toEqual([]);
    vi.mocked(apiOrigin).mockResolvedValue("https://api.example.com");
    expect(await loadSpaceFeedSession("self")).toBe(session);
});
