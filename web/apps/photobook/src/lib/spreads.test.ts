import assert from "node:assert/strict";
import { test } from "vitest";
import {
    getFlipPageIndex,
    getFlipPages,
    getSpreadLabel,
    getSpreadPageIndices,
    getSpreads,
} from "./spreads";

test("hardcover adds the binding sheets shown in the guide, on both ends", () => {
    assert.deepEqual(getSpreads(6, "Hardcover"), [
        { left: null, right: 0 },
        { left: "printer-blank", right: "printer-blank" },
        { left: "printer-blank", right: 1 },
        { left: 2, right: 3 },
        { left: 4, right: "printer-blank" },
        { left: "printer-blank", right: "printer-blank" },
        { left: 5, right: null },
    ]);
});

for (const binding of ["Hardcover", "Softcover"] as const) {
    test(`${binding} preserves content order, recto/verso placement and page jumps at supported counts`, () => {
        for (const count of [24, 100, 300]) {
            const spreads = getSpreads(count, binding);
            const physical = getFlipPages(count, binding);
            assert.equal(
                physical.filter((page) => page.pageIndex === null).length,
                binding === "Hardcover" ? 6 : 2,
            );
            assert.deepEqual(
                spreads.flatMap(getSpreadPageIndices),
                Array.from({ length: count }, (_, i) => i),
            );
            assert.equal(
                spreads.find((spread) => spread.right === 1)?.left,
                "printer-blank",
            );
            assert.equal(
                spreads.find((spread) => spread.left === count - 2)?.right,
                "printer-blank",
            );
            for (let index = 0; index < count; index++) {
                assert.equal(
                    physical[getFlipPageIndex(count, index, binding)!]!
                        .pageIndex,
                    index,
                );
            }
            for (let row = 1; row < spreads.length - 1; row++) {
                assert.equal(physical[row * 2 - 1]!.spreadIndex, row);
                assert.equal(physical[row * 2]!.spreadIndex, row);
            }
        }
    });
}

test("all-blank hardcover spreads have a label and never fabricate a numbered page", () => {
    const spreads = getSpreads(24, "Hardcover");
    for (const spread of [spreads[1]!, spreads.at(-2)!]) {
        assert.equal(getSpreadLabel(spread, 24), "Blank pages");
        assert.deepEqual(getSpreadPageIndices(spread), []);
    }
});

test("content starts on the right and the last even content page faces a printer blank", () => {
    assert.deepEqual(getSpreads(6, "Softcover"), [
        { left: null, right: 0 },
        { left: "printer-blank", right: 1 },
        { left: 2, right: 3 },
        { left: 4, right: "printer-blank" },
        { left: 5, right: null },
    ]);
});

test("all real pages appear exactly once in export order, with even content on the left", () => {
    for (const count of [4, 6, 24, 100, 300]) {
        const spreads = getSpreads(count, "Softcover");
        assert.deepEqual(
            spreads.flatMap(getSpreadPageIndices),
            Array.from({ length: count }, (_, i) => i),
        );
        for (const spread of spreads.slice(1, -1)) {
            if (typeof spread.left === "number")
                assert.equal(spread.left % 2, 0);
            if (typeof spread.right === "number")
                assert.equal(spread.right % 2, 1);
        }
        assert.equal(
            spreads
                .flatMap((spread) => [spread.left, spread.right])
                .filter((page) => page === "printer-blank").length,
            2,
        );
    }
});

test("empty and cover-only books do not gain spurious content pages", () => {
    assert.deepEqual(getSpreads(0, "Softcover"), []);
    assert.deepEqual(getSpreads(1, "Softcover"), [{ left: null, right: 0 }]);
    assert.deepEqual(getSpreads(2, "Softcover"), [
        { left: null, right: 0 },
        { left: 1, right: null },
    ]);
});

test("odd legacy page counts retain the last content page and a separate back cover", () => {
    assert.deepEqual(getSpreads(5, "Softcover"), [
        { left: null, right: 0 },
        { left: "printer-blank", right: 1 },
        { left: 2, right: 3 },
        { left: 4, right: null },
    ]);
});

test("flip preview includes physical blanks while keeping real book indices intact", () => {
    assert.deepEqual(getFlipPages(6, "Softcover"), [
        { pageIndex: 0, spreadIndex: 0 },
        { pageIndex: null, spreadIndex: 1 },
        { pageIndex: 1, spreadIndex: 1 },
        { pageIndex: 2, spreadIndex: 2 },
        { pageIndex: 3, spreadIndex: 2 },
        { pageIndex: 4, spreadIndex: 3 },
        { pageIndex: null, spreadIndex: 3 },
        { pageIndex: 5, spreadIndex: 4 },
    ]);
    for (const count of [0, 1, 2, 5, 6, 24, 300]) {
        const realIndices = getFlipPages(count, "Softcover").flatMap((page) =>
            page.pageIndex === null ? [] : [page.pageIndex],
        );
        assert.deepEqual(
            realIndices,
            Array.from({ length: count }, (_, i) => i),
        );
    }
});

test("flip events and restored preview indices map both sides to the same spread", () => {
    const spreads = getSpreads(24, "Softcover");
    const preview = getFlipPages(24, "Softcover");
    for (let spreadIndex = 0; spreadIndex < spreads.length; spreadIndex++) {
        const physicalStart = spreadIndex === 0 ? 0 : 2 * spreadIndex - 1;
        const physicalIndices =
            spreadIndex === 0 || spreadIndex === spreads.length - 1
                ? [physicalStart]
                : [physicalStart, physicalStart + 1];
        for (const index of physicalIndices)
            assert.equal(preview[index]!.spreadIndex, spreadIndex);
        assert.deepEqual(
            physicalIndices.flatMap((index) =>
                preview[index]!.pageIndex === null
                    ? []
                    : [preview[index]!.pageIndex],
            ),
            getSpreadPageIndices(spreads[spreadIndex]!),
        );
    }
});

test("page labels exclude printer blanks and keep content numbering unchanged", () => {
    const spreads = getSpreads(24, "Softcover");
    assert.deepEqual(
        spreads.map((spread) => getSpreadLabel(spread, 24)),
        [
            "Cover",
            "1",
            "2–3",
            "4–5",
            "6–7",
            "8–9",
            "10–11",
            "12–13",
            "14–15",
            "16–17",
            "18–19",
            "20–21",
            "22",
            "Back cover",
        ],
    );
    assert.equal(getSpreadLabel(undefined, 0), "");
    assert.deepEqual(
        getSpreadPageIndices(spreads[1]!),
        [1],
        "opening blank has no edit/scroll target",
    );
    assert.deepEqual(getSpreadPageIndices(spreads.at(-2)!), [22]);
});

test("page jumps use editor numbers rather than the inserted printer blanks", () => {
    assert.deepEqual(
        Array.from({ length: 6 }, (_, index) =>
            getFlipPageIndex(6, index, "Softcover"),
        ),
        [0, 2, 3, 4, 5, 7],
    );
    assert.equal(getFlipPageIndex(24, 22, "Softcover"), 23);
    assert.equal(
        getFlipPageIndex(24, 23, "Softcover"),
        25,
        "back cover skips the final printer blank",
    );
    assert.equal(
        getFlipPageIndex(5, 4, "Softcover"),
        5,
        "odd legacy books have no final printer blank",
    );
    assert.equal(getFlipPageIndex(1, 0, "Softcover"), 0);
    for (const index of [-1, 6, 1.5, NaN, Infinity])
        assert.equal(getFlipPageIndex(6, index, "Softcover"), null);
    assert.equal(getFlipPageIndex(0, 0, "Softcover"), null);
});
