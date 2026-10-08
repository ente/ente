import { expect, test } from "vitest";
import {
    spacePostFrameAspectRatio,
    viewerPhotosFromPost,
} from "../src/utils/post-photos";

test("matching portrait videos use their full frame before and after publication", () => {
    const drafts = [
        { width: 1440, height: 2560 },
        { width: 720, height: 1280 },
        { width: 720, height: 1280 },
    ];
    const published = drafts.map(() => ({ width: 576, height: 1024 }));

    expect(spacePostFrameAspectRatio(drafts)).toBe(9 / 16);
    expect(spacePostFrameAspectRatio(published)).toBe(9 / 16);
});

test.each([0, 1, 2])(
    "mixed video ratios use a square frame with cover index %i",
    (coverIndex) => {
        const videos = [
            { width: 1920, height: 1080 },
            { width: 1080, height: 1080 },
            { width: 1080, height: 1920 },
        ];
        const drafts = [
            ...videos.slice(coverIndex),
            ...videos.slice(0, coverIndex),
        ];
        const published = drafts.map(({ width, height }) => ({
            width: width / 2,
            height: height / 2,
        }));

        expect(spacePostFrameAspectRatio(drafts)).toBe(1);
        expect(spacePostFrameAspectRatio(published)).toBe(1);
    },
);

test("a single portrait keeps the feed height limit", () => {
    expect(spacePostFrameAspectRatio([{ width: 720, height: 1280 }])).toBe(
        3 / 4,
    );
});

test("matching ratios tolerate rounding during resizing", () => {
    expect(
        spacePostFrameAspectRatio([
            { width: 1920, height: 1080 },
            { width: 1024, height: 576 },
            { width: 854, height: 480 },
        ]),
    ).toBe(16 / 9);
});

test("profile navigation groups photos under their post and resets each counter", () => {
    const posts = [
        {
            postId: 1,
            name: "Maya",
            timestampMs: 1,
            caption: "A day out",
            viewerLiked: true,
            imageUrl: "blob:cover",
            photos: [
                { width: 1200, height: 800 },
                { imageUrl: "blob:portrait", width: 800, height: 1200 },
            ],
        },
        { postId: 2, name: "Maya", timestampMs: 2, imageUrl: "blob:single" },
    ];
    const slides = posts.flatMap(viewerPhotosFromPost);
    expect(
        slides.map((photo) => [
            photo.postId,
            photo.postPhotoIndex,
            photo.postPhotoCount,
        ]),
    ).toEqual([
        [1, 0, 2],
        [1, 1, 2],
        [2, 0, 1],
    ]);
    expect(slides.map((photo) => photo.imageUrl)).toEqual([
        "blob:cover",
        "blob:portrait",
        "blob:single",
    ]);
    expect(
        slides.slice(0, 2).map((photo) => [photo.caption, photo.viewerLiked]),
    ).toEqual([
        ["A day out", true],
        ["A day out", true],
    ]);
    expect(slides[1]).toMatchObject({ width: 800, height: 1200 });
});

test.each([
    { width: 800, height: 1200 },
    { width: 800, height: 800 },
])("preserves measured cover dimensions $width × $height", (dimensions) => {
    const slides = viewerPhotosFromPost({
        name: "Maya",
        timestampMs: 1,
        imageUrl: "blob:cover",
        ...dimensions,
        photos: [
            { width: undefined, height: undefined },
            { imageUrl: "blob:other" },
        ],
    });

    expect(slides[0]).toMatchObject(dimensions);
    expect(slides[1]?.width).toBeUndefined();
    expect(slides[1]?.height).toBeUndefined();
});

test.each([
    { width: 600, height: 900 },
    { width: 600, height: undefined },
    { width: undefined, height: 900 },
])("uses available cover metadata dimensions %o", (metadata) => {
    const [slide] = viewerPhotosFromPost({
        name: "Maya",
        timestampMs: 1,
        imageUrl: "blob:cover",
        width: 800,
        height: 1200,
        photos: [metadata],
    });

    expect(slide?.width).toBe(metadata.width ?? 800);
    expect(slide?.height).toBe(metadata.height ?? 1200);
});
