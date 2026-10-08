import { expect, test } from "vitest";
import type { SpacePost } from "../src/services/space";
import type { LocalSpaceFeedPost } from "../src/state/app-state";
import { homeFeedEntries } from "../src/utils/home-feed";

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
