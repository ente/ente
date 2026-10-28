import assert from "node:assert/strict";
import { test } from "vitest";
import {
    isBlankPage,
    isRequiredBlankPage,
    makeBlankPage,
    normalizeBookPages,
} from "./bookPages";
import { applyVariant } from "./layouts";

test("a page with centered text is not disposable blank-page padding", () => {
    const page = { ...makeBlankPage(), centerText: "Our holiday" };
    assert.equal(isBlankPage(page), false);
    assert.equal(isBlankPage({ ...page, centerText: "" }), true);
});

test("the only blank interior page is required to preserve the even print count", () => {
    const pages = [
        makeBlankPage(),
        { ...makeBlankPage(), centerText: "Our holiday" },
        makeBlankPage(),
        makeBlankPage(),
    ];
    assert.equal(isRequiredBlankPage(pages, pages[2]!.id), true);
    assert.equal(
        isRequiredBlankPage(pages, pages[0]!.id),
        false,
        "front cover is not interior padding",
    );
    assert.equal(
        isRequiredBlankPage(pages, pages[3]!.id),
        false,
        "back cover is not interior padding",
    );
    assert.equal(
        isRequiredBlankPage(pages, pages[1]!.id),
        false,
        "pages with content can still be deleted",
    );
    assert.equal(
        isRequiredBlankPage(
            [pages[0]!, pages[2]!, pages[1]!, pages[3]!],
            pages[2]!.id,
        ),
        true,
        "moving the blank does not remove the requirement",
    );
});

test("another blank interior page allows deletion without recreating padding", () => {
    const pages = Array.from({ length: 4 }, makeBlankPage);
    assert.equal(isRequiredBlankPage(pages, pages[1]!.id), false);
    assert.equal(isRequiredBlankPage(pages, pages[2]!.id), false);
});

test("a required blank becomes removable when it gets content", () => {
    const pages = [
        makeBlankPage(),
        { ...makeBlankPage(), centerText: "Our holiday" },
        makeBlankPage(),
        makeBlankPage(),
    ];
    for (const content of [
        { centerText: "Last day" },
        { slots: applyVariant("1-full", ["photo"]) },
        { bottomCaption: "Goodbye" },
    ]) {
        const populated = pages.map((page, index) =>
            index === 2 ? { ...page, ...content } : page,
        );
        assert.equal(isRequiredBlankPage(populated, pages[2]!.id), false);
    }
});

test("odd or empty books have no blank that must be kept for parity", () => {
    const pages = [makeBlankPage(), makeBlankPage(), makeBlankPage()];
    assert.equal(isRequiredBlankPage(pages, pages[1]!.id), false);
    assert.equal(isRequiredBlankPage([], "missing"), false);
});

test("migrates back-cover photos into the interior without changing crops or text", () => {
    const front = {
        ...makeBlankPage(),
        slots: applyVariant("1-full", ["front-photo"]),
        layoutVariant: "1-full",
    };
    const back = {
        ...makeBlankPage(),
        slots: applyVariant("1-moderate", ["back-photo"]),
        layoutVariant: "1-moderate",
        topCaption: "Last day",
        textBlocks: [
            {
                id: "text",
                text: "Goodbye",
                x: 20,
                y: 30,
                width: 40,
                height: 10,
                style: "body" as const,
                alignment: "left" as const,
                color: "#333",
                rotation: 0,
                fontSize: 2.5,
            },
        ],
    };
    back.slots[0] = {
        ...back.slots[0]!,
        cropX: 0.2,
        cropY: 0.8,
        cropZoom: 1.5,
    };
    const pages = [front, makeBlankPage(), makeBlankPage(), back];
    const original = structuredClone(pages);

    const normalized = normalizeBookPages(pages);

    assert.equal(normalized.length, 6);
    assert.deepEqual(normalized.slice(0, 4), original);
    assert.deepEqual(normalized.at(-1)?.slots, []);
    assert.deepEqual(normalized.at(-2)?.slots, []);
    assert.deepEqual(pages, original, "does not mutate saved state");
    assert.strictEqual(
        normalizeBookPages(normalized),
        normalized,
        "does not move or duplicate pages on subsequent saves",
    );
});

test("preserves intentional blank pages and adds even-count padding before the existing back cover", () => {
    const pages = Array.from({ length: 5 }, makeBlankPage);
    pages[1]!.topCaption = "Content";
    pages[4]!.topCaption = "Back-cover text";
    const normalized = normalizeBookPages(pages);

    assert.equal(normalized.length, 6);
    assert.deepEqual(normalized.slice(0, 4), pages.slice(0, 4));
    assert.strictEqual(normalized.at(-1), pages.at(-1));
    assert.equal(normalized[4]!.topCaption, "");
    assert.strictEqual(normalizeBookPages(normalized), normalized);
});

test("leaves even books and empty books unchanged", () => {
    const empty: ReturnType<typeof makeBlankPage>[] = [];
    const pages = Array.from({ length: 24 }, makeBlankPage);
    assert.strictEqual(normalizeBookPages(empty), empty);
    assert.strictEqual(normalizeBookPages(pages), pages);
});

test("adds a back cover to a single-page book and removes empty back-cover frames", () => {
    const front = makeBlankPage();
    const normalized = normalizeBookPages([front]);
    assert.equal(normalized.length, 2);
    assert.strictEqual(normalized[0]!, front);

    const back = {
        ...makeBlankPage(),
        slots: [{ ...applyVariant("1-full", ["unused"])[0]!, photoId: null }],
        layoutVariant: "1-full",
    };
    const cleaned = normalizeBookPages([front, back]);
    assert.equal(cleaned.at(-1)?.id, back.id);
    assert.deepEqual(cleaned.at(-1)?.slots, []);
    assert.equal(cleaned.at(-1)?.layoutVariant, undefined);
});
