import { beforeEach, expect, test, vi } from "vitest";
import type { FriendProfile } from "../src/data/friends";
import {
    clearSpaceHomePostsMemoryCache,
    loadSpaceHomePosts,
    markSpaceHomePostRead,
    refreshSpaceHomePosts,
} from "../src/services/home-posts";
import type { SpacePost } from "../src/services/space";

const { storage, loadCurrentHomePostsPage } = vi.hoisted(() => ({
    storage: new Map<string, unknown>(),
    loadCurrentHomePostsPage:
        vi.fn<
            typeof import("../src/services/space").loadCurrentHomePostsPage
        >(),
}));

vi.mock("ente-accounts/services/accounts-db", () => ({
    savedPartialLocalUser: () => ({ id: 1 }),
}));
vi.mock("ente-base/origins", () => ({
    apiOrigin: () => Promise.resolve("http://localhost:8080"),
}));
vi.mock("ente-base/kv", () => ({
    getKV: (key: string) => Promise.resolve(storage.get(key)),
    setKV: (key: string, value: unknown) => {
        storage.set(key, structuredClone(value));
        return Promise.resolve();
    },
    removeKV: (key: string) => {
        storage.delete(key);
        return Promise.resolve();
    },
}));
vi.mock("services/space", () => ({ loadCurrentHomePostsPage }));

const friend: FriendProfile = {
    id: "friend",
    spaceId: "friend",
    fullName: "Friend",
    username: "friend",
    friendsCount: 1,
};

const firstPost: SpacePost = {
    postId: 1,
    spaceId: friend.spaceId!,
    friendID: friend.id,
    name: friend.fullName,
    timestampMs: 2000,
    viewerLiked: false,
};

beforeEach(() => {
    clearSpaceHomePostsMemoryCache();
    storage.clear();
    loadCurrentHomePostsPage.mockReset();
});

test.each(["1000000:0", "0:0"])(
    "a friend's first post is unread after an empty feed with cursor %s",
    async (syncCursor) => {
        loadCurrentHomePostsPage.mockResolvedValueOnce({
            items: [],
            syncCursor,
        });
        await refreshSpaceHomePosts("self", [friend]);
        clearSpaceHomePostsMemoryCache();

        loadCurrentHomePostsPage.mockResolvedValueOnce({
            items: [firstPost],
            syncCursor: "3000000:0",
        });
        const refreshed = await refreshSpaceHomePosts("self", [friend]);

        expect(refreshed?.latestPosts).toEqual([firstPost]);
        expect(refreshed?.unreadPosts).toEqual([firstPost]);
        clearSpaceHomePostsMemoryCache();
        expect((await loadSpaceHomePosts("self"))?.unreadPosts).toEqual([
            firstPost,
        ]);

        await markSpaceHomePostRead("self", firstPost);
        expect((await loadSpaceHomePosts("self"))?.unreadPosts).toEqual([]);
    },
);

test("existing posts are read when the home feed is first initialized", async () => {
    loadCurrentHomePostsPage.mockResolvedValueOnce({
        items: [firstPost],
        syncCursor: "3000000:0",
    });

    const initialized = await refreshSpaceHomePosts("self", [friend]);

    expect(initialized?.latestPosts).toEqual([firstPost]);
    expect(initialized?.unreadPosts).toEqual([]);
});

test("existing posts from a newly added friend are read", async () => {
    loadCurrentHomePostsPage.mockResolvedValueOnce({
        items: [],
        syncCursor: "1000000:0",
    });
    await refreshSpaceHomePosts("self", []);
    loadCurrentHomePostsPage.mockResolvedValueOnce({
        items: [firstPost],
        syncCursor: "3000000:0",
    });

    const refreshed = await refreshSpaceHomePosts("self", [friend]);

    expect(refreshed?.latestPosts).toEqual([firstPost]);
    expect(refreshed?.unreadPosts).toEqual([]);
});
