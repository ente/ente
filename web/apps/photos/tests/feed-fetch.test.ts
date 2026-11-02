import type { Collection } from "ente-media/collection";
import type { Comment } from "ente-new/photos/services/comment";
import {
    getAnonProfiles,
    getSocialUpdates,
    getUnifiedSocialDiff,
} from "ente-new/photos/services/social";
import { beforeEach, expect, test, vi } from "vitest";
import { fetchFeedData } from "../src/services/feed-fetch";

vi.mock("ente-base/log", () => ({ default: { warn: vi.fn() } }));
vi.mock("ente-new/photos/services/social", () => ({
    getAnonProfiles: vi.fn(),
    getUnifiedSocialDiff: vi.fn(),
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
const diff = (
    overrides: Partial<Awaited<ReturnType<typeof getUnifiedSocialDiff>>> = {},
) => ({
    comments: [],
    reactions: [],
    hasMoreComments: false,
    hasMoreReactions: false,
    commentsUpdatedAt: 0,
    reactionsUpdatedAt: 0,
    ...overrides,
});
const fetchFeed = (signal = new AbortController().signal) =>
    fetchFeedData([album], signal);

beforeEach(() => vi.resetAllMocks());

test("fetches from zero on every refresh and paginates independent cursors", async () => {
    vi.mocked(getSocialUpdates).mockResolvedValue([
        {
            collectionID: 10,
            commentsUpdatedAt: 300,
            reactionsUpdatedAt: 60,
            anonProfilesUpdatedAt: 7,
        },
    ]);
    vi.mocked(getUnifiedSocialDiff)
        .mockResolvedValueOnce(
            diff({
                comments: [record("parent", 200, true), record("new", 210)],
                commentsUpdatedAt: 210,
                reactionsUpdatedAt: 60,
                hasMoreComments: true,
            }),
        )
        .mockResolvedValueOnce(
            diff({
                comments: [record("next", 300)],
                commentsUpdatedAt: 300,
                reactionsUpdatedAt: 60,
            }),
        );
    vi.mocked(getAnonProfiles).mockResolvedValue(new Map([["guest", "Sam"]]));
    const signal = new AbortController().signal;
    const result = await fetchFeed(signal);
    expect(result.failed).toBe(false);
    expect(result.socialByCollection[10]).toEqual({
        comments: [
            record("parent", 200, true),
            record("new", 210),
            record("next", 300),
        ],
        reactions: [],
        anonNames: { guest: "Sam" },
    });
    expect(getUnifiedSocialDiff).toHaveBeenNthCalledWith(1, 10, "album-key", {
        commentsSinceTime: 0,
        reactionsSinceTime: 0,
        signal,
    });
    expect(getUnifiedSocialDiff).toHaveBeenNthCalledWith(2, 10, "album-key", {
        commentsSinceTime: 210,
        reactionsSinceTime: 60,
        signal,
    });
    vi.mocked(getUnifiedSocialDiff).mockResolvedValue(diff());
    await fetchFeed(signal);
    expect(getUnifiedSocialDiff).toHaveBeenNthCalledWith(3, 10, "album-key", {
        commentsSinceTime: 0,
        reactionsSinceTime: 0,
        signal,
    });
});

test("discards an incomplete album when a later page fails", async () => {
    vi.mocked(getSocialUpdates).mockResolvedValue([
        { collectionID: 10, commentsUpdatedAt: 300 },
    ]);
    vi.mocked(getUnifiedSocialDiff)
        .mockResolvedValueOnce(
            diff({
                comments: [record("new", 200)],
                commentsUpdatedAt: 200,
                hasMoreComments: true,
            }),
        )
        .mockRejectedValueOnce(new Error("Offline"));
    const result = await fetchFeed();
    expect(result.failed).toBe(true);
    expect(result.socialByCollection).toEqual({});
});

test("only fetches accessible albums with activity", async () => {
    vi.mocked(getSocialUpdates).mockResolvedValue([
        { collectionID: 10, commentsUpdatedAt: 0 },
        { collectionID: 11, commentsUpdatedAt: 500 },
    ]);
    const result = await fetchFeed();
    expect(getUnifiedSocialDiff).not.toHaveBeenCalled();
    expect(Object.keys(result.socialByCollection)).toEqual(["10"]);
});

test("cancels an obsolete refresh", async () => {
    const controller = new AbortController();
    vi.mocked(getSocialUpdates).mockResolvedValue([
        { collectionID: 10, commentsUpdatedAt: 200 },
    ]);
    vi.mocked(getUnifiedSocialDiff).mockImplementationOnce(() => {
        controller.abort();
        return Promise.resolve(diff({ commentsUpdatedAt: 200 }));
    });
    await expect(fetchFeed(controller.signal)).rejects.toThrow();
});

test("stops pagination when a cursor does not advance", async () => {
    vi.mocked(getSocialUpdates).mockResolvedValue([
        { collectionID: 10, commentsUpdatedAt: 200 },
    ]);
    vi.mocked(getUnifiedSocialDiff).mockResolvedValue(
        diff({ hasMoreComments: true }),
    );
    const result = await fetchFeed();
    expect(result.failed).toBe(true);
    expect(result.socialByCollection).toEqual({});
    expect(getUnifiedSocialDiff).toHaveBeenCalledOnce();
});

test("preserves fetched activity when anonymous profiles fail", async () => {
    vi.mocked(getSocialUpdates).mockResolvedValue([
        {
            collectionID: 10,
            commentsUpdatedAt: 200,
            anonProfilesUpdatedAt: 100,
        },
    ]);
    vi.mocked(getUnifiedSocialDiff).mockResolvedValue(
        diff({ comments: [record("comment", 200)], commentsUpdatedAt: 200 }),
    );
    vi.mocked(getAnonProfiles).mockRejectedValue(new Error("Unavailable"));
    const result = await fetchFeed();
    expect(result.failed).toBe(true);
    expect(result.socialByCollection[10]).toEqual({
        comments: [record("comment", 200)],
        reactions: [],
        anonNames: {},
    });
});

test("still cancels when the anonymous-profile request is aborted", async () => {
    const controller = new AbortController();
    vi.mocked(getSocialUpdates).mockResolvedValue([
        { collectionID: 10, anonProfilesUpdatedAt: 100 },
    ]);
    vi.mocked(getAnonProfiles).mockImplementation(() => {
        controller.abort();
        return Promise.reject(new Error("Aborted"));
    });
    await expect(fetchFeed(controller.signal)).rejects.toThrow();
});
