import { expect, test } from "vitest";
import {
    postQuoteErrorState,
    postQuoteKey,
    postQuotePhotoIndex,
} from "../src/utils/post-quote";
import { spaceRoutes } from "../src/utils/routes";

const photos = [
    { objectKey: "first" },
    { objectKey: "second" },
    { objectKey: "third" },
];

test("replies follow the selected photo across reordering", () => {
    expect(postQuotePhotoIndex(photos, "third")).toBe(2);
    expect(postQuotePhotoIndex([...photos].reverse(), "third")).toBe(0);
});

test("legacy replies show the sole photo or the post cover", () => {
    expect(postQuotePhotoIndex(photos.slice(0, 1))).toBe(0);
    expect(postQuotePhotoIndex(photos)).toBe(0);
});

test("missing references never fall back to the cover", () => {
    expect(postQuotePhotoIndex(photos, "missing")).toBe(-1);
    expect(postQuotePhotoIndex(photos, "")).toBe(-1);
    expect(postQuotePhotoIndex([], "third")).toBe(-1);
    expect(postQuotePhotoIndex([])).toBe(-1);
});

test("likes and replies to different photos have separate preview caches", () => {
    const post = { spaceId: "alice", postId: 42 };
    const keys = [
        post,
        { ...post, objectKey: "first" },
        { ...post, objectKey: "second" },
        { ...post, postId: 43, objectKey: "first" },
    ].map(postQuoteKey);
    expect(new Set(keys).size).toBe(keys.length);
});

test("photo URLs omit the storage path and preserve encoded photo IDs", () => {
    const objectKey = "space/alice/posts/photo #3?&+=.webp";
    const url = new URL(
        spaceRoutes.post("alice", 42, objectKey),
        "https://space.ente.io",
    );
    expect(url.pathname).toBe("/app/posts/alice/42");
    expect(url.searchParams.get("photo")).toBe("photo #3?&+=.webp");
    expect(spaceRoutes.post("alice", 42, "space/alice/posts/wo_second")).toBe(
        "/app/posts/alice/42?photo=wo_second",
    );
    expect(spaceRoutes.post("alice", 42)).toBe("/app/posts/alice/42");
});

test("unavailable posts and temporary failures have different states", () => {
    expect(postQuoteErrorState(new Error("Offline"))).toEqual({
        hasLoadError: true,
    });
    for (const name of ["content_unavailable", "permission_denied"]) {
        const error = new Error("Cannot access photo");
        error.name = name;
        expect(postQuoteErrorState(error)).toEqual({ isUnavailable: true });
    }
});
