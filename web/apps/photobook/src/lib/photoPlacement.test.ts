import assert from "node:assert/strict";
import { test } from "vitest";
import { makeBlankPage } from "./bookPages";
import { applyVariant } from "./layouts";
import {
    availablePhotoSpaces,
    normalizeFrontCover,
    photoDestinationError,
    placeImportedPhotos,
} from "./photoPlacement";
import type { Photo } from "./types";

const photos: Photo[] = Array.from({ length: 10 }, (_, index) => ({
    id: `photo-${index}`,
    fileName: `${index}.jpg`,
    width: 1200,
    height: 800,
    dateTaken: 100 - index,
}));
const makeBook = () => [
    {
        ...makeBlankPage(),
        slots: applyVariant("1-full", [photos[0]!.id]),
        layoutVariant: "1-full",
    },
    { ...makeBlankPage(), centerText: "Our holiday", topCaption: "Summer" },
    makeBlankPage(),
    makeBlankPage(),
];

test("adding to a selected blank page keeps its identity, text and surrounding pages", () => {
    const pages = makeBook();
    const original = structuredClone(pages);
    const added = photos.slice(1, 4);
    const result = placeImportedPhotos(pages, photos, added, {
        kind: "page",
        pageId: pages[1]!.id,
    });
    assert.equal(result.length, pages.length);
    assert.equal(result[1]!.id, pages[1]!.id);
    assert.equal(result[1]!.centerText, "Our holiday");
    assert.equal(result[1]!.topCaption, "Summer");
    assert.deepEqual(
        result[1]!.slots.map((slot) => slot.photoId),
        added.map((photo) => photo.id),
    );
    for (const index of [0, 2, 3])
        assert.strictEqual(result[index]!, pages[index]!);
    assert.deepEqual(
        pages,
        original,
        "the previous state remains available for Undo",
    );
});

test("adding to a partly filled page preserves existing photo IDs and crop edits", () => {
    const pages = makeBook();
    pages[1] = {
        ...pages[1]!,
        slots: applyVariant("1-moderate", [photos[1]!.id]),
        layoutVariant: "1-moderate",
    };
    const oldSlot = pages[1].slots[0]!;
    Object.assign(oldSlot, { cropX: 0.25, cropY: 0.7, cropZoom: 1.6 });
    const result = placeImportedPhotos(pages, photos, photos.slice(2, 5), {
        kind: "page",
        pageId: pages[1].id,
    });
    assert.equal(result[1]!.slots.length, 4);
    const preserved = result[1]!.slots[0]!;
    for (const key of ["id", "photoId", "cropX", "cropY", "cropZoom"] as const)
        assert.equal(preserved[key], oldSlot[key]);
    assert.equal(availablePhotoSpaces(result[1]!), 0);
});

test("end placement appends in selection order before the back cover, independent of photo dates", () => {
    const pages = makeBook();
    const original = structuredClone(pages);
    const added = photos.slice(1, 10);
    const result = placeImportedPhotos(pages, photos, added, { kind: "end" });
    assert.deepEqual(pages, original);
    assert.deepEqual(
        result.slice(0, -1).slice(0, pages.length - 1),
        pages.slice(0, -1),
    );
    assert.strictEqual(result.at(-1), pages.at(-1));
    const newPages = result.slice(pages.length - 1, -1);
    assert.deepEqual(
        newPages.map((page) => page.slots.length),
        [4, 4, 1, 0],
    );
    assert.deepEqual(
        newPages.flatMap((page) => page.slots.map((slot) => slot.photoId)),
        added.map((photo) => photo.id),
    );
    assert.equal(result.length % 2, 0);
    assert.deepEqual(result.at(-1)!.slots, []);
});

test("invalid or full destinations reject the entire selection without changing the book", () => {
    const pages = makeBook();
    pages[1] = {
        ...pages[1]!,
        slots: applyVariant(
            "3-top1-bot2",
            photos.slice(1, 4).map((photo) => photo.id),
        ),
    };
    const original = structuredClone(pages);
    for (const pageId of [pages[1].id, pages.at(-1)!.id, "missing-page"]) {
        const destination = { kind: "page" as const, pageId };
        assert.ok(photoDestinationError(pages, destination, 2));
        assert.throws(() =>
            placeImportedPhotos(pages, photos, photos.slice(4, 6), destination),
        );
        assert.deepEqual(pages, original);
    }
    assert.equal(photoDestinationError(pages, { kind: "end" }, 9), null);
});

test("empty slots count as available and an empty front cover keeps its full-bleed layout", () => {
    const pages = makeBook();
    pages[0] = { ...pages[0]!, slots: [] };
    pages[1] = {
        ...pages[1]!,
        slots: applyVariant("2-side", [photos[1]!.id, photos[2]!.id]).map(
            (slot) => ({ ...slot, photoId: null }),
        ),
    };
    assert.equal(availablePhotoSpaces(pages[1]), 4);
    const result = placeImportedPhotos(pages, photos, [photos[0]!], {
        kind: "page",
        pageId: pages[0].id,
    });
    assert.equal(result[0]!.layoutVariant, "1-full");
    assert.equal(result[0]!.slots.length, 1);
    assert.strictEqual(
        placeImportedPhotos(pages, photos, [], { kind: "end" }),
        pages,
    );
});

test("a cover import replaces one image, preserves its title/layout, and can be undone", () => {
    const pages = makeBook();
    pages[0] = {
        ...pages[0]!,
        slots: applyVariant("1-padded", [photos[0]!.id]),
        layoutVariant: "1-padded",
        topCaption: "Our holiday",
    };
    pages[0].slots[0]!.cropZoom = 2;
    const original = structuredClone(pages);
    const destination = { kind: "page" as const, pageId: pages[0].id };
    assert.equal(photoDestinationError(pages, destination, 1), null);
    assert.equal(
        photoDestinationError(pages, destination, 2),
        "Choose one photo for the front cover.",
    );
    assert.throws(() =>
        placeImportedPhotos(pages, photos, photos.slice(1, 3), destination),
    );
    const result = placeImportedPhotos(
        pages,
        photos,
        [photos[1]!],
        destination,
    );
    assert.equal(result[0]!.slots.length, 1);
    assert.equal(result[0]!.slots[0]!.photoId, photos[1]!.id);
    assert.equal(
        result[0]!.slots[0]!.cropZoom,
        1,
        "new image starts with its own crop",
    );
    assert.equal(result[0]!.layoutVariant, "1-padded");
    assert.equal(result[0]!.topCaption, "Our holiday");
    assert.equal(result[0]!.id, pages[0].id);
    assert.equal(result.length, pages.length);
    assert.deepEqual(pages, original);
    assert.equal(
        availablePhotoSpaces(result[0]!, true),
        0,
        "dragging cannot append another cover photo",
    );
    assert.equal(availablePhotoSpaces(makeBlankPage(), true), 1);
});

test("old collage covers retain all photos and crops when limited to one cover photo", () => {
    const pages = makeBook();
    pages[0] = {
        ...pages[0]!,
        slots: applyVariant(
            "4-grid",
            photos.slice(0, 4).map((photo) => photo.id),
        ),
        layoutVariant: "4-grid",
        topCaption: "Our holiday",
    };
    pages[0].slots[2]!.cropZoom = 1.5;
    const original = structuredClone(pages);
    const result = normalizeFrontCover(pages);
    assert.equal(result[0]!.slots.length, 1);
    assert.equal(result[0]!.topCaption, "Our holiday");
    assert.equal(result[0]!.id, pages[0].id);
    assert.deepEqual(
        result
            .slice(0, 2)
            .flatMap((page) => page.slots.map((slot) => slot.photoId)),
        photos.slice(0, 4).map((photo) => photo.id),
    );
    assert.equal(result[1]!.slots[1]!.cropZoom, 1.5);
    assert.equal(result[1]!.slots[1]!.id, pages[0].slots[2]!.id);
    assert.strictEqual(result[2]!, pages[1]!);
    assert.strictEqual(result.at(-1), pages.at(-1));
    assert.equal(result.length % 2, 0);
    assert.deepEqual(pages, original);
    assert.strictEqual(normalizeFrontCover(result), result);
});
