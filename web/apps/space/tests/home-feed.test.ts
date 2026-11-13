import { expect, test } from "vitest";
import type { SpacePost } from "../src/services/space";
import type { LocalSpaceFeedPost } from "../src/state/app-state";
import {
    homeFeedEntries,
    homeFeedSeparatorBefore,
    type HomeFeedPost,
} from "../src/utils/home-feed";

const post = (postId: number, timestampMs: number): SpacePost => ({
    friendID: "friend",
    name: "Friend",
    postId,
    spaceId: "friend",
    timestampMs,
    viewerLiked: false,
});

test("the first visit puts all existing posts in the grid, including later pages", () => {
    const posts = [post(3, 300), post(2, 200), post(1, 100)];
    expect(homeFeedEntries(posts, [], undefined)).toEqual({
        latest: [],
        history: posts,
    });
    expect(homeFeedEntries(posts, [], 400)).toEqual({
        latest: [],
        history: posts,
    });
});

test("new posts stay full size for the visit and join history on the next visit", () => {
    const newest = post(3, 300);
    const existing = post(2, 200);
    const older = post(1, 100);
    const firstPage = homeFeedEntries([newest, existing], [], 200);
    expect(firstPage.latest.map((entry) => entry.identity)).toEqual(["post:3"]);
    expect(firstPage.history).toEqual([existing]);
    const nextPage = homeFeedEntries([newest, existing, older], [], 200);
    expect(nextPage.latest).toEqual(firstPage.latest);
    expect(nextPage.history).toEqual([existing, older]);
    expect(homeFeedEntries([newest, existing, older], [], 400)).toEqual({
        latest: [],
        history: [newest, existing, older],
    });
});

test("history keeps batch boundaries when new posts are shown as cards", () => {
    const posts: HomeFeedPost[] = [
        post(5, 500),
        post(4, 400),
        post(3, 300),
        { ...post(2, 200), batchIndex: 1 },
        { ...post(1, 100), batchIndex: 1 },
    ];
    const { latest, history } = homeFeedEntries(posts, [], 300);
    expect(latest.map((entry) => entry.identity)).toEqual(["post:5", "post:4"]);
    expect(history.map((item) => [item.postId, item.batchIndex])).toEqual([
        [3, undefined],
        [2, 1],
        [1, 1],
    ]);
});

test("upload completion does not duplicate a post or move it into the grid", () => {
    const uploaded = post(3, 300);
    const existing = post(2, 200);
    const local: LocalSpaceFeedPost = {
        id: "upload",
        post: uploaded,
        status: "ready",
    };
    const uploading = homeFeedEntries([existing], [local], 200);
    const refreshed = homeFeedEntries([uploaded, existing], [local], 200);
    expect(refreshed).toEqual(uploading);
    expect(refreshed.latest.map((entry) => entry.identity)).toEqual(["post:3"]);
    expect(refreshed.history).toEqual([existing]);
    const resolved = homeFeedEntries([uploaded, existing], [], 200);
    expect(resolved.latest.map((entry) => entry.identity)).toEqual(["post:3"]);
    expect(resolved.history).toEqual([existing]);
    expect(homeFeedEntries([uploaded, existing], [local], 400)).toEqual({
        latest: [],
        history: [uploaded, existing],
    });
});

test("pending and failed uploads remain cards even without a previous visit", () => {
    const pending: LocalSpaceFeedPost = {
        caption: "Uploading",
        frameAspectRatio: 1,
        friendID: "self",
        id: "upload",
        imageUrl: "blob:preview",
        name: "Me",
        photoCount: 1,
        spaceId: "self",
        status: "pending",
        timestampMs: 300,
    };
    for (const status of ["pending", "failed"] as const) {
        const result = homeFeedEntries([], [{ ...pending, status }], undefined);
        expect(result.latest.map((entry) => entry.identity)).toEqual([
            "local:upload",
        ]);
        expect(result.history).toEqual([]);
    }
});

test("a post published in this session stays latest after the server replaces the local upload", () => {
    const uploaded = { ...post(3, 200), spaceId: "self", friendID: "self" };
    const local: LocalSpaceFeedPost = {
        id: "upload",
        post: uploaded,
        status: "ready",
    };
    const latestPostIDs = new Set([uploaded.postId]);
    const localEntries = homeFeedEntries(
        [uploaded],
        [local],
        300,
        latestPostIDs,
        "self",
    );
    const remoteEntries = homeFeedEntries(
        [uploaded],
        [],
        300,
        latestPostIDs,
        "self",
    );
    expect(localEntries.latest.map((entry) => entry.identity)).toEqual([
        "post:3",
    ]);
    expect(remoteEntries.latest.map((entry) => entry.identity)).toEqual([
        "post:3",
    ]);
    expect(remoteEntries.history).toEqual([]);
    expect(homeFeedEntries([uploaded], [], 100, new Set(), "self")).toEqual({
        latest: [],
        history: [uploaded],
    });
});

test("the separator follows the latest/grid boundary even when older own posts sort first", () => {
    const own = { ...post(4, 400), spaceId: "self", friendID: "self" };
    const sections = homeFeedEntries(
        [own, post(3, 300), post(1, 100)],
        [],
        200,
        new Set(),
        "self",
    );
    expect(sections.latest.map((entry) => entry.identity)).toEqual(["post:3"]);
    expect(sections.history.map((item) => item.postId)).toEqual([4, 1]);
    expect(homeFeedSeparatorBefore(sections.latest, sections.history)).toBe(
        "post:4",
    );
});

test("the separator includes own new posts and waits for older history", () => {
    const uploaded = { ...post(4, 400), spaceId: "self", friendID: "self" };
    const local: LocalSpaceFeedPost = {
        id: "upload",
        post: uploaded,
        status: "ready",
    };
    const latestPostIDs = new Set([uploaded.postId]);
    const localOnly = homeFeedEntries(
        [post(1, 100)],
        [local],
        200,
        latestPostIDs,
        "self",
    );
    expect(homeFeedSeparatorBefore(localOnly.latest, localOnly.history)).toBe(
        "post:1",
    );
    const confirmed = homeFeedEntries(
        [uploaded, post(1, 100)],
        [],
        200,
        latestPostIDs,
        "self",
    );
    expect(homeFeedSeparatorBefore(confirmed.latest, confirmed.history)).toBe(
        "post:1",
    );
    const firstPage = homeFeedEntries([post(3, 300)], [], 200);
    expect(
        homeFeedSeparatorBefore(firstPage.latest, firstPage.history),
    ).toBeUndefined();
    const nextPage = homeFeedEntries([post(3, 300), post(1, 100)], [], 200);
    expect(homeFeedSeparatorBefore(nextPage.latest, nextPage.history)).toBe(
        "post:1",
    );
    const nextVisit = homeFeedEntries([post(3, 300), post(1, 100)], [], 400);
    expect(
        homeFeedSeparatorBefore(nextVisit.latest, nextVisit.history),
    ).toBeUndefined();
});

test("grid posts are newest first, with post IDs breaking timestamp ties", () => {
    const sections = homeFeedEntries(
        [post(1, 100), post(2, 200), post(3, 200)],
        [],
        400,
    );
    expect(sections.history.map((item) => item.postId)).toEqual([3, 2, 1]);
});

test.each(["pending", "failed"] as const)(
    "%s uploads retain their render key when the server confirms the post",
    (status) => {
        const pending = {
            frameAspectRatio: 1,
            friendID: "self",
            id: "upload",
            imageUrl: "blob:preview",
            name: "Me",
            photoCount: 1,
            spaceId: "self",
            status,
            timestampMs: 300,
        } satisfies LocalSpaceFeedPost;
        const before = homeFeedEntries([post(1, 100)], [pending], 200);
        expect(homeFeedSeparatorBefore(before.latest, before.history)).toBe(
            "post:1",
        );
        const confirmed = homeFeedEntries(
            [post(3, 300), post(1, 100)],
            [{ ...pending, postId: 3 }],
            200,
        );
        expect(confirmed.latest.map((entry) => entry.identity)).toEqual([
            "post:3",
        ]);
        expect(confirmed.latest[0]?.renderKey).toBe(
            before.latest[0]?.renderKey,
        );
        expect(confirmed.history.map((item) => item.postId)).toEqual([1]);
    },
);
