import assert from "node:assert/strict";
import { test } from "vitest";
import { normalizeBookPages } from "./bookPages";
import {
    applyVariant,
    chooseBestVariantKey,
    defaultVariantKeyForCount,
    generateAutoLayout,
    getLayoutMetrics,
    getMirrorVariant,
    getVariantPreview,
    getVariantsForCount,
} from "./layouts";
import type { Photo } from "./types";

const photos: Photo[] = Array.from({ length: 12 }, (_, i) => ({
    id: `photo-${i}`,
    fileName: `${i}.jpg`,
    width: i % 2 === 0 ? 1200 : 800,
    height: i % 2 === 0 ? 800 : 1200,
    dateTaken: i,
}));

function bounds(slots: ReturnType<typeof getVariantPreview>) {
    return {
        left: Math.min(...slots.map((s) => s.x)),
        top: Math.min(...slots.map((s) => s.y)),
        right: Math.max(...slots.map((s) => s.x + s.width)),
        bottom: Math.max(...slots.map((s) => s.y + s.height)),
    };
}

function assertSameBounds(
    actual: ReturnType<typeof bounds>,
    expected: ReturnType<typeof bounds>,
) {
    for (const edge of ["left", "top", "right", "bottom"] as const) {
        assert.ok(
            Math.abs(actual[edge] - expected[edge]) < 1e-9,
            `${edge} margin matches`,
        );
    }
}

test("single-photo pages use the same outer margins as multi-photo grids", () => {
    const single = bounds(
        getVariantPreview(chooseBestVariantKey(photos.slice(0, 1))),
    );
    for (const key of [
        "2-side",
        "2-stacked",
        "3-left1-right2",
        "4-grid",
        "4-equal-cols",
    ]) {
        assertSameBounds(single, bounds(getVariantPreview(key)));
    }
    assert.equal(defaultVariantKeyForCount(1), "1-moderate");
});

test("all standard layouts have equal 25 mm margins on every side", () => {
    const keys = new Set(
        [1, 2, 3, 4].flatMap((count) =>
            getVariantsForCount(count)
                .flatMap((variant) => [
                    variant.key,
                    getMirrorVariant(variant.key),
                ])
                .filter((key): key is string => !!key && key !== "1-full"),
        ),
    );
    const margin = (25 / 210) * 100;
    for (const key of keys) {
        assertSameBounds(bounds(getVariantPreview(key)), {
            left: margin,
            top: margin,
            right: 100 - margin,
            bottom: 100 - margin,
        });
    }
});

test("extra padding is an optional front-cover layout", () => {
    assert.deepEqual(
        getVariantsForCount(1).map((variant) => variant.key),
        ["1-moderate", "1-full"],
    );
    assert.deepEqual(
        getVariantsForCount(1, true).map((variant) => variant.key),
        ["1-padded", "1-moderate", "1-full"],
    );
    const inset = bounds(getVariantPreview("1-padded"));
    const standard = bounds(getVariantPreview("1-moderate"));
    assert.ok(inset.left > standard.left && inset.top > standard.top);
    assert.ok(inset.right < standard.right && inset.bottom < standard.bottom);
    assert.equal(
        inset.left,
        inset.top,
        "extra-inset covers also use equal horizontal and vertical padding",
    );
    assert.equal(inset.right, inset.bottom);
});

test("four-photo staggered layouts are selectable, retain every photo, and never overlap", () => {
    const primary = "4-staggered";
    const mirror = "4-staggered-reverse";
    assert.ok(
        getVariantsForCount(4).some((variant) => variant.key === primary),
    );
    assert.ok(
        !getVariantsForCount(4).some((variant) => variant.key === mirror),
    );
    assert.ok(
        !getVariantsForCount(3).some((variant) => variant.key === primary),
    );
    assert.equal(getMirrorVariant(primary), mirror);
    assert.equal(getMirrorVariant(mirror), primary);

    const ids = photos.slice(0, 4).map((photo) => photo.id);
    const standard = bounds(getVariantPreview("4-grid"));
    for (const key of [primary, mirror]) {
        const slots = applyVariant(key, ids);
        assert.deepEqual(
            slots.map((slot) => slot.photoId),
            ids,
        );
        assert.equal(new Set(slots.map((slot) => slot.id)).size, 4);
        assertSameBounds(bounds(slots), standard);
        assert.deepEqual(
            slots.map(({ x, y, width, height }) => ({ x, y, width, height })),
            getVariantPreview(key),
            "the picker uses the same geometry as the page and export",
        );
        for (const [i, slot] of slots.entries()) {
            assert.ok(slot.width > 0 && slot.height > 0);
            for (const other of slots.slice(i + 1)) {
                const overlapW =
                    Math.min(slot.x + slot.width, other.x + other.width) -
                    Math.max(slot.x, other.x);
                const overlapH =
                    Math.min(slot.y + slot.height, other.y + other.height) -
                    Math.max(slot.y, other.y);
                assert.ok(
                    overlapW <= 0 || overlapH <= 0,
                    `${key}: photo frames do not overlap`,
                );
            }
        }
    }
});

test("staggered layouts anchor the large photos at the outer edges and inset the smaller ones", () => {
    const [largeTop, smallTop, smallBottom, largeBottom] =
        getVariantPreview("4-staggered");
    assert.ok(largeTop && smallTop && smallBottom && largeBottom);
    const { left, top, cw, ch, hGap, vGap } = getLayoutMetrics();
    assertSameBounds(bounds([largeTop, largeBottom]), {
        left,
        top,
        right: left + cw,
        bottom: top + ch,
    });
    assert.ok(
        largeTop.width > smallTop.width && largeTop.height > smallTop.height,
    );
    assert.ok(
        largeBottom.width > smallBottom.width &&
            largeBottom.height > smallBottom.height,
    );
    assert.ok(smallTop.y > top && smallTop.x + smallTop.width < left + cw);
    assert.ok(
        smallBottom.x > left && smallBottom.y + smallBottom.height < top + ch,
    );
    for (const [actual, expected] of [
        [smallTop.x - (largeTop.x + largeTop.width), hGap],
        [largeBottom.x - (smallBottom.x + smallBottom.width), hGap],
        [smallBottom.y - (largeTop.y + largeTop.height), vGap],
        [largeBottom.y - (smallTop.y + smallTop.height), vGap],
    ] as const) {
        assert.ok(
            Math.abs(actual - expected) < 1e-9,
            "uses the standard gap between neighboring photos",
        );
    }

    const mirrored = getVariantPreview("4-staggered-reverse");
    assert.ok(
        mirrored[0]!.x > mirrored[1]!.x && mirrored[3]!.x < mirrored[2]!.x,
    );
    assertSameBounds(
        bounds([mirrored[0]!, mirrored[3]!]),
        bounds([largeTop, largeBottom]),
    );
});

test("auto-layout uses standard margins for interior single photos and a photo-free back cover", () => {
    const pages = generateAutoLayout(photos);
    assert.equal(pages[0]!.layoutVariant, "1-full");
    assert.deepEqual(bounds(pages[0]!.slots), {
        left: 0,
        top: 0,
        right: 100,
        bottom: 100,
    });
    const standard = bounds(getVariantPreview("2-side"));
    const singles = pages.slice(1).filter((page) => page.slots.length === 1);
    assert.ok(singles.length >= 1, "includes an interior single-photo page");
    for (const page of singles) {
        assert.equal(page.layoutVariant, "1-moderate");
        assertSameBounds(bounds(page.slots), standard);
    }
    assert.deepEqual(pages.at(-1)?.slots, []);
    assert.equal(pages.length % 2, 0);
    assert.deepEqual(
        pages.flatMap((page) => page.slots.map((slot) => slot.photoId)),
        photos.map((photo) => photo.id),
    );
});

test("auto-layout retains every photo and keeps even page counts for small and large books", () => {
    for (const count of [0, 1, 2, 3, 4, 5, 6, 11, 20, 31, 100]) {
        const input = Array.from({ length: count }, (_, i) => ({
            ...photos[i % photos.length]!,
            id: `photo-${i}`,
            dateTaken: i,
        }));
        const pages = generateAutoLayout(input);
        assert.equal(
            pages.length % 2,
            0,
            `${count} photos produce an even page count`,
        );
        assert.deepEqual(
            pages.flatMap((page) => page.slots.map((slot) => slot.photoId)),
            input.map((photo) => photo.id),
        );
        if (count > 0) {
            assert.deepEqual(
                pages.at(-1)?.slots,
                [],
                `${count} photos leave the back cover photo-free`,
            );
        }
    }
});

function makePhotos(count: number): Photo[] {
    return Array.from({ length: count }, (_, i) => ({
        ...photos[i % photos.length]!,
        id: `photo-${i}`,
        dateTaken: i,
    }));
}

test("auto-layout fills every interior page whenever there are at least two interior photos", () => {
    for (const count of [
        ...Array.from({ length: 198 }, (_, i) => i + 3),
        500,
        1000,
    ]) {
        const input = makePhotos(count);
        const pages = generateAutoLayout(input);
        assert.equal(pages.length % 2, 0);
        for (const page of pages.slice(1, -1)) {
            assert.ok(
                page.slots.length >= 1 && page.slots.length <= 4,
                `${count} photos: all content pages are populated`,
            );
            assert.equal(
                getVariantPreview(page.layoutVariant!).length,
                page.slots.length,
            );
        }
        assert.deepEqual(
            pages.flatMap((page) => page.slots.map((slot) => slot.photoId)),
            input.map((photo) => photo.id),
        );
        assert.strictEqual(
            normalizeBookPages(pages),
            pages,
            "export normalization needs no extra padding",
        );
    }
});

test("splits the final pair across pages 33 and 34 instead of leaving page 34 blank", () => {
    const pages = generateAutoLayout(makePhotos(75));
    assert.equal(pages.length, 36);
    assert.deepEqual(
        pages[33]!.slots.map((slot) => slot.photoId),
        ["photo-73"],
    );
    assert.deepEqual(
        pages[34]!.slots.map((slot) => slot.photoId),
        ["photo-74"],
    );
    assert.deepEqual(pages[35]!.slots, [], "back cover stays photo-free");
    const cycle = [2, 3, 1, 4, 2, 3, 1, 2];
    assert.deepEqual(
        pages.slice(1, 33).map((page) => page.slots.length),
        Array.from({ length: 32 }, (_, i) => cycle[i % cycle.length]!),
    );
});

test("chooses a split that keeps adjacent portraits together and reduces cropping", () => {
    for (const orientations of [
        ["landscape", "portrait", "portrait"],
        ["portrait", "portrait", "landscape"],
    ]) {
        const input = makePhotos(4);
        orientations.forEach((orientation, i) => {
            input[i + 1]!.width = orientation === "landscape" ? 1200 : 800;
            input[i + 1]!.height = orientation === "landscape" ? 800 : 1200;
        });
        const pages = generateAutoLayout(input);
        const expected = orientations[0] === "landscape" ? [1, 2] : [2, 1];
        assert.deepEqual(
            pages.slice(1, -1).map((page) => page.slots.length),
            expected,
        );
        const pair = pages.find((page) => page.slots.length === 2)!;
        assert.equal(pair.layoutVariant, "2-side");
        assert.deepEqual(
            pair.slots.map((slot) => slot.photoId),
            input
                .filter((photo) => photo.width < photo.height)
                .map((photo) => photo.id),
        );
    }
});

test("preserves an already-even grouping", () => {
    const pages = generateAutoLayout(makePhotos(6));
    assert.deepEqual(
        pages.map((page) => page.slots.map((slot) => slot.photoId)),
        [
            ["photo-0"],
            ["photo-1", "photo-2"],
            ["photo-3", "photo-4", "photo-5"],
            [],
        ],
    );
});

test("keeps chronological order and stable ordering for equal timestamps without mutating input", () => {
    const ordered = makePhotos(6).map((photo, i) => ({
        ...photo,
        dateTaken: Math.floor(i / 2),
    }));
    const input = [
        ordered[3]!,
        ordered[0]!,
        ordered[5]!,
        ordered[4]!,
        ordered[1]!,
        ordered[2]!,
    ];
    const original = structuredClone(input);
    const pages = generateAutoLayout(input);
    assert.deepEqual(
        pages.flatMap((page) => page.slots.map((slot) => slot.photoId)),
        ["photo-0", "photo-1", "photo-3", "photo-2", "photo-5", "photo-4"],
    );
    assert.deepEqual(input, original);
});

test("one interior photo retains the unavoidable blank without duplicating photos", () => {
    const pages = generateAutoLayout(makePhotos(2));
    assert.deepEqual(
        pages.map((page) => page.slots.map((slot) => slot.photoId)),
        [["photo-0"], ["photo-1"], [], []],
    );
});
