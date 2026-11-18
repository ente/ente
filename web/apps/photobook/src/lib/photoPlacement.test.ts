import assert from "node:assert/strict";
import { test } from "vitest";
import { makeBlankPage } from "./bookPages";
import { applyVariant } from "./layouts";
import {
    availablePhotoSpaces,
    normalizeFrontCover,
    photoDestinationError,
    placeGalleryPhoto,
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

test("gallery imports retain every photo without adding pages at the print limit", () => {
    const pages = Array.from({ length: 100 }, makeBlankPage);
    const added = Array.from({ length: 600 }, (_, index) => ({
        ...photos[0]!,
        id: `added-${index}`,
    }));
    const destination = { kind: "gallery" as const };
    assert.equal(photoDestinationError(pages, destination, added.length), null);
    assert.strictEqual(
        placeImportedPhotos(pages, added, added, destination),
        pages,
    );
    assert.equal(added.length, 600);
});

test("gallery drops reuse photos and preserve existing crops, captions and page count", () => {
    const pages = makeBook();
    pages[1]!.slots = applyVariant("1-moderate", [photos[1]!.id]);
    const slot = pages[1]!.slots[0]!;
    Object.assign(slot, { cropX: 0.2, cropY: 0.7, cropZoom: 1.4 });
    const original = structuredClone(pages);
    const result = placeGalleryPhoto(
        pages,
        photos,
        photos[0]!.id,
        pages[1]!.id,
    );
    assert.equal(result.length, pages.length);
    assert.strictEqual(result[0], pages[0]);
    assert.equal(result[1]!.slots[1]!.photoId, photos[0]!.id);
    assert.equal(result[1]!.centerText, pages[1]!.centerText);
    assert.equal(result[1]!.topCaption, pages[1]!.topCaption);
    for (const key of ["id", "photoId", "cropX", "cropY", "cropZoom"] as const)
        assert.equal(result[1]!.slots[0]![key], slot[key]);
    assert.deepEqual(pages, original);
});

test("gallery replacement preserves the slot layout and resets only its crop", () => {
    const pages = makeBook();
    const slot = pages[0]!.slots[0]!;
    Object.assign(slot, { cropX: 0.2, cropY: 0.7, cropZoom: 2 });
    const original = structuredClone(pages);
    const result = placeGalleryPhoto(
        pages,
        photos,
        photos[2]!.id,
        pages[0]!.id,
        slot.id,
    );
    assert.deepEqual(result[0]!.slots[0], {
        ...slot,
        photoId: photos[2]!.id,
        cropX: 0.5,
        cropY: 0.5,
        cropZoom: 1,
    });
    assert.equal(result[0]!.layoutVariant, pages[0]!.layoutVariant);
    assert.equal(result.length, pages.length);
    assert.deepEqual(pages, original);
});

test("gallery drops fill empty slots at 100 pages and cannot spill onto new pages or the back cover", () => {
    const pages = Array.from({ length: 100 }, makeBlankPage);
    pages[1]!.slots = applyVariant(
        "4-grid",
        photos.slice(0, 4).map((photo) => photo.id),
    );
    const full = pages[1]!;
    assert.strictEqual(
        placeGalleryPhoto(pages, photos, photos[4]!.id, full.id),
        pages,
    );
    const slot = full.slots[2]!;
    slot.photoId = null;
    const result = placeGalleryPhoto(
        pages,
        photos,
        photos[4]!.id,
        full.id,
        slot.id,
    );
    assert.equal(result[1]!.slots[2]!.photoId, photos[4]!.id);
    assert.equal(result[1]!.slots.length, 4);
    assert.equal(result.length, 100);
    assert.strictEqual(
        placeGalleryPhoto(pages, photos, photos[4]!.id, pages.at(-1)!.id),
        pages,
    );
    assert.strictEqual(
        placeGalleryPhoto(pages, photos, "missing", full.id),
        pages,
    );
    assert.strictEqual(
        placeGalleryPhoto(pages, photos, photos[4]!.id, full.id, "missing"),
        pages,
    );
});

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

test("a selection fills the chosen page and inserts overflow before the following pages", () => {
    const pages = makeBook();
    pages[1] = {
        ...pages[1]!,
        slots: applyVariant(
            "3-top1-bot2",
            photos.slice(1, 4).map((photo) => photo.id),
        ),
    };
    const original = structuredClone(pages);
    const result = placeImportedPhotos(pages, photos, photos.slice(4), {
        kind: "page",
        pageId: pages[1].id,
    });
    const filled = result.slice(1, 4);
    assert.deepEqual(
        filled.map((page) => page.slots.length),
        [4, 4, 1],
    );
    assert.deepEqual(
        filled.flatMap((page) => page.slots.map((slot) => slot.photoId)),
        photos.slice(1).map((photo) => photo.id),
    );
    assert.equal(result[1]!.id, pages[1].id);
    assert.strictEqual(result[0], pages[0]);
    assert.strictEqual(result[4], pages[2]);
    assert.strictEqual(result[5], pages[3]);
    assert.deepEqual(pages, original);
});

test("adding to an already full page starts a new page immediately after it", () => {
    const pages = makeBook();
    pages[1] = {
        ...pages[1]!,
        slots: applyVariant(
            "4-grid",
            photos.slice(1, 5).map((photo) => photo.id),
        ),
        layoutVariant: "4-grid",
    };
    const result = placeImportedPhotos(pages, photos, [photos[5]!], {
        kind: "page",
        pageId: pages[1].id,
    });
    assert.strictEqual(result[1], pages[1]);
    assert.deepEqual(
        result[2]!.slots.map((slot) => slot.photoId),
        [photos[5]!.id],
    );
    assert.strictEqual(result[3], pages[2]);
    assert.strictEqual(result.at(-1), pages.at(-1));
    assert.equal(result.length % 2, 0);
});

test("invalid destinations reject the entire selection without changing the book", () => {
    const pages = makeBook();
    const original = structuredClone(pages);
    for (const pageId of [pages.at(-1)!.id, "missing-page"]) {
        const destination = { kind: "page" as const, pageId };
        assert.ok(photoDestinationError(pages, destination, 2));
        assert.throws(() =>
            placeImportedPhotos(pages, photos, photos.slice(4, 6), destination),
        );
        assert.deepEqual(pages, original);
    }
    assert.equal(photoDestinationError(pages, { kind: "end" }, 9), null);
});

test("at the page limit, photos can fill existing slots or replace the front cover", () => {
    for (const count of [100, 102]) {
        const pages = Array.from({ length: count }, makeBlankPage);
        pages[1]!.slots = applyVariant("2-side", [
            photos[0]!.id,
            photos[1]!.id,
        ]);
        const destination = { kind: "page" as const, pageId: pages[1]!.id };
        const filled = placeImportedPhotos(
            pages,
            photos,
            photos.slice(2, 4),
            destination,
        );
        assert.equal(filled.length, count);
        assert.equal(filled[1]!.slots.length, 4);
        assert.match(
            photoDestinationError(pages, destination, 3)!,
            /2 more photos/,
        );
        assert.throws(() =>
            placeImportedPhotos(pages, photos, photos.slice(2, 5), destination),
        );
        assert.equal(pages[1]!.slots.length, 2);
        assert.ok(photoDestinationError(filled, destination, 1));
        assert.ok(photoDestinationError(pages, { kind: "end" }, 1));
        assert.equal(
            photoDestinationError(
                pages,
                { kind: "page", pageId: pages[0]!.id },
                1,
            ),
            null,
        );
    }
});

test("overflow fills the remaining pages up to the print limit, including blank padding", () => {
    const pages = Array.from({ length: 98 }, makeBlankPage);
    pages[1]!.slots = applyVariant(
        "3-left1-right2",
        photos.slice(0, 3).map((photo) => photo.id),
    );
    const added = photos.map((photo) => ({ ...photo, id: `new-${photo.id}` }));
    const allPhotos = [...photos, ...added];
    const destination = { kind: "page" as const, pageId: pages[1]!.id };
    for (const count of [2, 9]) {
        const result = placeImportedPhotos(
            pages,
            allPhotos,
            added.slice(0, count),
            destination,
        );
        assert.equal(result.length, 100);
        assert.equal(result[1]!.slots.length, 4);
        assert.equal(result[2]!.slots.length, count === 2 ? 1 : 4);
        assert.deepEqual(
            result.flatMap((p) => p.slots.map((slot) => slot.photoId)),
            allPhotos
                .slice(0, 3)
                .concat(added.slice(0, count))
                .map((photo) => photo.id),
        );
    }
    assert.throws(() =>
        placeImportedPhotos(pages, allPhotos, added, destination),
    );
    assert.equal(photoDestinationError(pages, { kind: "end" }, 8), null);
    assert.ok(photoDestinationError(pages, { kind: "end" }, 9));
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
