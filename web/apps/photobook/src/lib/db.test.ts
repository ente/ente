import localforage from "localforage";
import assert from "node:assert/strict";
import { beforeAll, beforeEach, test, vi } from "vitest";

import {
    getLayoutMetrics,
    getVariantPreview,
    getVariantsForCount,
} from "./layouts";
import type { BookState } from "./types";

let getBookState: typeof import("./db").getBookState;
let storedBook: unknown = null;

beforeAll(async () => {
    const createInstance = localforage.createInstance.bind(localforage);
    const createInstanceMock = vi
        .spyOn(localforage, "createInstance")
        .mockImplementation((options: LocalForageOptions) => {
            const store = createInstance(options);
            if (options.storeName === "metadata") {
                vi.spyOn(store, "getItem").mockImplementation((key: string) => {
                    assert.equal(key, "bookState");
                    return Promise.resolve(storedBook);
                });
            }
            return store;
        });
    ({ getBookState } = await import("./db"));
    createInstanceMock.mockRestore();
});

beforeEach(() => {
    storedBook = null;
});

const legacyBook: BookState = {
    pages: [
        {
            id: "saved-page",
            slots: [
                {
                    id: "saved-slot",
                    photoId: "saved-photo",
                    ...getVariantPreview("1-moderate")[0]!,
                    cropX: 0.3,
                    cropY: 0.7,
                    cropZoom: 1.5,
                },
            ],
            textBlocks: [],
            topCaption: "Saved caption",
            bottomCaption: "",
            layoutVariant: "1-moderate",
        },
    ],
    currentSpreadIndex: 2,
};

test("returns null when no book has been saved", async () => {
    assert.equal(await getBookState(), null);
});

test("restores the book title without changing page content", async () => {
    storedBook = { ...structuredClone(legacyBook), title: "Summer in Delhi" };
    assert.deepEqual(await getBookState(), storedBook);
});

test("ignores invalid titles in saved books", async () => {
    storedBook = { ...structuredClone(legacyBook), title: 123 };
    assert.deepEqual(await getBookState(), legacyBook);
});

test("restores centered page text with and without photos", async () => {
    for (const slots of [[], legacyBook.pages[0]!.slots]) {
        storedBook = {
            ...legacyBook,
            pages: [
                { ...legacyBook.pages[0]!, slots, centerText: "Summer\n2026" },
            ],
        };
        assert.deepEqual(await getBookState(), storedBook);
    }
});

test("restores the selected binding and paper at 210 mm with the saved book", async () => {
    storedBook = {
        ...structuredClone(legacyBook),
        printSelection: { productId: "hardcover-gloss-150", sizeMm: 210 },
    };
    assert.deepEqual(await getBookState(), storedBook);
});

test("discards obsolete or unsupported print selections while retaining book content", async () => {
    for (const printSelection of [
        null,
        { productId: "unknown", sizeMm: 210 },
        { productId: "hardcover-gloss-150", sizeMm: 211 },
        { productId: "softcover-gloss-150", sizeMm: 211 },
    ]) {
        storedBook = { ...structuredClone(legacyBook), printSelection };
        assert.deepEqual(await getBookState(), legacyBook);
    }
});

test("restores books without a format ID without changing content", async () => {
    storedBook = structuredClone(legacyBook);

    const restored = await getBookState();

    assert.deepEqual(restored, legacyBook);
    assert.deepEqual(storedBook, legacyBook);
});

for (const formatId of [
    "square-210",
    "a5-portrait",
    undefined,
    null,
    "unknown-format",
    "",
    123,
    {},
    "toString",
    "__proto__",
]) {
    test(`discards obsolete format ID (${JSON.stringify(formatId)}) while preserving the book`, async () => {
        storedBook = { ...structuredClone(legacyBook), formatId };

        assert.deepEqual(await getBookState(), legacyBook);
        assert.deepEqual(storedBook, { ...legacyBook, formatId });
    });
}

test("preserves the optional front-cover inset while migrating other old single-photo insets", async () => {
    const saved = {
        ...legacyBook,
        pages: ["front", "interior", "back"].map((id) => ({
            ...structuredClone(legacyBook.pages[0]!),
            id,
            layoutVariant: "1-padded",
            paddingH: 1,
            paddingV: 2,
        })),
    };
    storedBook = structuredClone(saved);

    const restored = await getBookState();
    assert.deepEqual(restored, {
        ...saved,
        pages: saved.pages.map(({ paddingH, paddingV, ...page }, index) => {
            const layoutVariant = index === 0 ? "1-padded" : "1-moderate";
            return {
                ...page,
                layoutVariant,
                slots: page.slots.map((slot) => ({
                    ...slot,
                    ...getVariantPreview(layoutVariant)[0]!,
                })),
            };
        }),
    });
    assert.deepEqual(storedBook, saved);

    storedBook = restored;
    assert.deepEqual(await getBookState(), restored, "migration is idempotent");
});

test("removes saved padding from a grid while retaining empty slots and crop settings", async () => {
    const page = {
        ...structuredClone(legacyBook.pages[0]!),
        layoutVariant: "2-side",
        slots: [
            { ...legacyBook.pages[0]!.slots[0]! },
            {
                ...legacyBook.pages[0]!.slots[0]!,
                id: "empty-slot",
                photoId: null,
            },
        ],
    };
    storedBook = {
        ...legacyBook,
        pages: [{ ...page, paddingH: 2, paddingV: 3 }],
    };

    const restored = await getBookState();
    assert.ok(restored);
    assert.deepEqual(restored.pages[0], {
        ...page,
        slots: page.slots.map((slot, index) => ({
            ...slot,
            ...getVariantPreview("2-side")[index]!,
        })),
    });
});

test("retains the full-bleed cover layout when removing saved padding", async () => {
    const page = {
        ...structuredClone(legacyBook.pages[0]!),
        layoutVariant: "1-full",
    };
    storedBook = {
        ...legacyBook,
        pages: [{ ...page, paddingH: 1, paddingV: 1 }],
    };

    assert.deepEqual((await getBookState())!.pages[0], {
        ...page,
        slots: page.slots.map((slot) => ({
            ...slot,
            x: 0,
            y: 0,
            width: 100,
            height: 100,
        })),
    });
});

test("expands saved four-column strips to the padded height without losing edits", async () => {
    const positions = getVariantPreview("4-equal-cols");
    const page = {
        ...structuredClone(legacyBook.pages[0]!),
        layoutVariant: "4-equal-cols",
        slots: positions.map((position, index) => ({
            ...legacyBook.pages[0]!.slots[0]!,
            ...position,
            id: `slot-${index}`,
            photoId: index === 3 ? null : `photo-${index}`,
            y: 20,
            height: 60,
        })),
    };
    const saved = { ...legacyBook, pages: [legacyBook.pages[0]!, page] };
    storedBook = structuredClone(saved);

    const restored = await getBookState();
    assert.deepEqual(restored, {
        ...saved,
        pages: [
            saved.pages[0]!,
            {
                ...page,
                slots: page.slots.map((slot, index) => ({
                    ...slot,
                    ...positions[index]!,
                })),
            },
        ],
    });
    assert.deepEqual(
        storedBook,
        saved,
        "loading leaves the saved input intact",
    );
    storedBook = restored;
    assert.deepEqual(await getBookState(), restored, "migration is idempotent");
});

test("normalizes older single-photo pages without a layout key", async () => {
    const { layoutVariant, ...page } = structuredClone(legacyBook.pages[0]!);
    storedBook = { ...legacyBook, pages: [page, { ...page, id: "interior" }] };

    const restored = await getBookState();
    assert.deepEqual(restored!.pages[0], {
        ...page,
        layoutVariant: "1-full",
        slots: page.slots.map((slot) => ({
            ...slot,
            x: 0,
            y: 0,
            width: 100,
            height: 100,
        })),
    });
    assert.deepEqual(restored!.pages[1]!, {
        ...page,
        id: "interior",
        layoutVariant: "1-moderate",
        slots: page.slots.map((slot) => ({
            ...slot,
            ...getVariantPreview("1-moderate")[0]!,
        })),
    });
});

for (const marginMm of [16.8, 20, 25]) {
    test(`saved 14.8 by ${marginMm} mm margins become equal without losing edits`, async () => {
        const margin = (marginMm / 210) * 100;
        const horizontalMargin = (14.8 / 210) * 100;
        const oldMetrics = {
            ...getLayoutMetrics(),
            marginH: horizontalMargin,
            left: horizontalMargin,
            cw: 100 - 2 * horizontalMargin,
            marginV: margin,
            top: margin,
            ch: 100 - 2 * margin,
        };
        const pages = [1, 2, 3, 4]
            .flatMap((count) => getVariantsForCount(count))
            .filter((variant) => variant.key !== "1-full")
            .map((variant) => ({
                ...structuredClone(legacyBook.pages[0]!),
                id: variant.key,
                layoutVariant: variant.key,
                bottomCaption: "Saved bottom caption",
                textBlocks: [
                    {
                        id: "text",
                        text: "Saved text",
                        x: 30,
                        y: 40,
                        width: 20,
                        height: 10,
                        style: "body" as const,
                        alignment: "left" as const,
                        color: "#555555",
                        rotation: 15,
                        fontSize: 2.5,
                    },
                ],
                slots: variant
                    .generate(
                        Array.from(
                            { length: variant.photoCount },
                            (_, i) => `photo-${i}`,
                        ),
                        oldMetrics,
                    )
                    .map((slot, i) => ({
                        ...slot,
                        photoId: i === 1 ? null : slot.photoId,
                        cropX: 0.3,
                        cropY: 0.7,
                        cropZoom: 1.5,
                    })),
            }));
        const saved = { ...legacyBook, pages };
        storedBook = structuredClone(saved);

        const restored = await getBookState();
        assert.deepEqual(restored, {
            ...saved,
            pages: pages.map((page) => ({
                ...page,
                slots: page.slots.map((slot, i) => ({
                    ...slot,
                    ...getVariantPreview(page.layoutVariant)[i]!,
                })),
            })),
        });
        assert.deepEqual(
            storedBook,
            saved,
            "loading does not mutate the saved input",
        );
        storedBook = restored;
        assert.deepEqual(
            await getBookState(),
            restored,
            "loading again does not add more padding",
        );
    });
}

test("saved extra-inset covers gain equal margins while retaining their photo and text", async () => {
    const horizontalMargin = (20.72 / 210) * 100;
    const page = {
        ...structuredClone(legacyBook.pages[0]!),
        layoutVariant: "1-padded",
        slots: [
            {
                ...legacyBook.pages[0]!.slots[0]!,
                x: horizontalMargin,
                y: 14,
                width: 100 - 2 * horizontalMargin,
                height: 72,
            },
        ],
    };
    const saved = { ...legacyBook, pages: [page] };
    storedBook = structuredClone(saved);
    const restored = await getBookState();
    assert.deepEqual(restored, {
        ...saved,
        pages: [
            {
                ...page,
                slots: [
                    { ...page.slots[0]!, ...getVariantPreview("1-padded")[0]! },
                ],
            },
        ],
    });
    assert.deepEqual(storedBook, saved);
    storedBook = restored;
    assert.deepEqual(await getBookState(), restored);
});

test("caption spacing migration preserves full-bleed and extra-inset covers", async () => {
    for (const layoutVariant of ["1-full", "1-padded"]) {
        const page = {
            ...structuredClone(legacyBook.pages[0]!),
            layoutVariant,
            slots: [
                {
                    ...legacyBook.pages[0]!.slots[0]!,
                    ...getVariantPreview(layoutVariant)[0]!,
                },
            ],
        };
        const saved = { ...legacyBook, pages: [page] };
        storedBook = structuredClone(saved);
        assert.deepEqual(await getBookState(), saved);
    }
});
