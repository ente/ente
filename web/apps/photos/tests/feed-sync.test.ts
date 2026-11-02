import { getKV, setKV } from "ente-base/kv";
import type { Collection } from "ente-media/collection";
import type { Comment } from "ente-new/photos/services/comment";
import {
    getAnonProfiles,
    getCollectionSocialDiff,
    getSocialUpdates,
} from "ente-new/photos/services/social";
import { beforeEach, expect, test, vi } from "vitest";
import { emptyFeedSocialData } from "../src/services/feed";
import {
    readFeedSnapshot,
    syncFeedSnapshot,
    type FeedSnapshot,
} from "../src/services/feed-sync";

vi.mock("ente-base/kv", () => ({ getKV: vi.fn(), setKV: vi.fn() }));
vi.mock("ente-base/origins", () => ({
    apiOrigin: () => Promise.resolve("https://api.ente.io"),
}));
vi.mock("ente-base/log", () => ({ default: { warn: vi.fn() } }));
vi.mock("ente-new/photos/services/social", () => ({
    getAnonProfiles: vi.fn(),
    getCollectionSocialDiff: vi.fn(),
    getSocialUpdates: vi.fn(),
}));
const album = { id: 10, key: "album-key" } as Collection;
const record = (id: string, updatedAt: number, isDeleted = false): Comment => ({
    id,
    collectionID: 10,
    fileID: 1,
    userID: 2,
    createdAt: 1,
    updatedAt,
    text: id,
    isDeleted,
});
const snapshot = (): FeedSnapshot => ({
    version: 1,
    sharedPhotoCutoff: 42,
    collections: {
        10: {
            ...emptyFeedSocialData(),
            comments: [record("old", 100)],
            commentsUpdatedAt: 100,
        },
    },
});
const diff = (
    overrides: Partial<
        Awaited<ReturnType<typeof getCollectionSocialDiff>>
    > = {},
) => ({
    comments: [],
    reactions: [],
    hasMoreComments: false,
    hasMoreReactions: false,
    commentsUpdatedAt: 100,
    reactionsUpdatedAt: 0,
    ...overrides,
});
const sync = (
    saved = snapshot(),
    albums = [album],
    signal = new AbortController().signal,
) => syncFeedSnapshot(1, albums, saved, signal);

beforeEach(() => {
    vi.resetAllMocks();
});

test("persists the first-use cutoff before attempting a network sync", async () => {
    const initial = await readFeedSnapshot(1);
    expect(initial.sharedPhotoCutoff).toBeGreaterThan(0);
    expect(setKV).toHaveBeenCalledWith(
        "photos-feed:v1:https://api.ente.io:1",
        initial,
    );
    vi.mocked(getKV).mockResolvedValue(initial);
    expect(await readFeedSnapshot(1)).toEqual(initial);
    expect(setKV).toHaveBeenCalledOnce();
});

test("paginates independent cursors, merges edits and removes tombstones", async () => {
    const saved = snapshot();
    saved.collections[10]!.reactions = [
        { ...record("like", 50), reactionType: "<3" },
    ];
    saved.collections[10]!.reactionsUpdatedAt = 50;
    vi.mocked(getSocialUpdates).mockResolvedValue([
        {
            collectionID: 10,
            commentsUpdatedAt: 300,
            reactionsUpdatedAt: 60,
            anonProfilesUpdatedAt: 7,
        },
    ]);
    vi.mocked(getCollectionSocialDiff)
        .mockResolvedValueOnce(
            diff({
                comments: [record("old", 200, true), record("new", 210)],
                commentsUpdatedAt: 210,
                reactions: [{ ...record("like", 60, true), reactionType: "" }],
                reactionsUpdatedAt: 60,
                hasMoreComments: true,
            }),
        )
        .mockResolvedValueOnce(
            diff({
                comments: [record("new", 300)],
                commentsUpdatedAt: 300,
                reactionsUpdatedAt: 60,
            }),
        );
    vi.mocked(getAnonProfiles).mockResolvedValue(new Map([["guest", "Sam"]]));
    const result = await sync(saved);
    expect(result.failed).toBe(false);
    expect(result.snapshot.collections[10]).toMatchObject({
        comments: [record("old", 200, true), record("new", 300)],
        reactions: [],
        commentsUpdatedAt: 300,
        reactionsUpdatedAt: 60,
        anonNames: { guest: "Sam" },
    });
    expect(getCollectionSocialDiff).toHaveBeenNthCalledWith(
        1,
        10,
        "album-key",
        { commentsSinceTime: 99, reactionsSinceTime: 49 },
        expect.any(AbortSignal),
    );
    expect(getCollectionSocialDiff).toHaveBeenNthCalledWith(
        2,
        10,
        "album-key",
        { commentsSinceTime: 210, reactionsSinceTime: 60 },
        expect.any(AbortSignal),
    );
    expect(saved.collections[10]!.comments).toEqual([record("old", 100)]);
});

test("keeps a complete cached collection if a later page fails", async () => {
    const saved = snapshot();
    vi.mocked(getSocialUpdates).mockResolvedValue([
        { collectionID: 10, commentsUpdatedAt: 300 },
    ]);
    vi.mocked(getCollectionSocialDiff)
        .mockResolvedValueOnce(
            diff({
                comments: [record("new", 200)],
                commentsUpdatedAt: 200,
                hasMoreComments: true,
            }),
        )
        .mockRejectedValueOnce(new Error("Offline"));
    const result = await sync(saved);
    expect(result.failed).toBe(true);
    expect(result.snapshot.collections[10]).toEqual(saved.collections[10]);
});

test("does not refetch unchanged albums and discards inaccessible cached activity", async () => {
    const saved = snapshot();
    saved.collections[11] = emptyFeedSocialData();
    vi.mocked(getSocialUpdates).mockResolvedValue([
        { collectionID: 10, commentsUpdatedAt: 100 },
        { collectionID: 11, commentsUpdatedAt: 500 },
    ]);
    const result = await sync(saved);
    expect(getCollectionSocialDiff).not.toHaveBeenCalled();
    expect(Object.keys(result.snapshot.collections)).toEqual(["10"]);
});

test("aborting a refresh cannot persist a partially updated snapshot", async () => {
    const controller = new AbortController();
    vi.mocked(getSocialUpdates).mockResolvedValue([
        { collectionID: 10, commentsUpdatedAt: 200 },
    ]);
    vi.mocked(getCollectionSocialDiff).mockImplementationOnce(() => {
        controller.abort();
        return Promise.resolve(diff({ commentsUpdatedAt: 200 }));
    });
    await expect(
        sync(snapshot(), [album], controller.signal),
    ).rejects.toThrow();
    expect(setKV).not.toHaveBeenCalled();
});

test("stops a non-advancing page and keeps its old cursor for retry", async () => {
    vi.mocked(getSocialUpdates).mockResolvedValue([
        { collectionID: 10, commentsUpdatedAt: 200 },
    ]);
    vi.mocked(getCollectionSocialDiff).mockResolvedValue(
        diff({ commentsUpdatedAt: 99, hasMoreComments: true }),
    );
    const result = await sync();
    expect(result.failed).toBe(true);
    expect(result.snapshot.collections[10]!.commentsUpdatedAt).toBe(100);
    expect(getCollectionSocialDiff).toHaveBeenCalledOnce();
});
