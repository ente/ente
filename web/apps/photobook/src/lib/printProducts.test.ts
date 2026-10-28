import assert from "node:assert/strict";
import { test } from "vitest";
import { makeBlankPage } from "./bookPages";
import { applyVariant } from "./layouts";
import {
    DEFAULT_PRINT_SELECTION,
    getBindingPrintSelection,
    getPrintBinding,
    getPrintExportError,
    isPrintSelection,
    preparePrintExport,
    PRINT_PRODUCTS,
    PrintExportValidationError,
    type PrintSelection,
} from "./printProducts";

const pages = (count: number) =>
    Array.from({ length: count }, () => makeBlankPage());

test("the cover selection uses 210 mm and the shared 24–300 page limits", () => {
    assert.equal(getPrintBinding(), "Hardcover");
    for (const binding of ["Hardcover", "Softcover"] as const) {
        const selection = getBindingPrintSelection(binding);
        assert.equal(getPrintBinding(selection), binding);
        assert.equal(selection.sizeMm, 210);
        assert.equal(getPrintExportError(selection, 24), null);
        assert.equal(getPrintExportError(selection, 300), null);
        assert.ok(getPrintExportError(selection, 22));
        assert.ok(getPrintExportError(selection, 302));
        assert.equal(preparePrintExport(pages(24), selection).length, 24);
    }
});

for (const [productId, min, max] of [
    ["hardcover-gloss-200", 24, 300],
    ["hardcover-gloss-150", 24, 500],
    ["hardcover-mohawk-120", 24, 300],
    ["softcover-gloss-150", 24, 300],
    ["softcover-mohawk-120", 24, 300],
] as const) {
    test(`${productId} enforces its ${min}–${max} page range at both boundaries`, () => {
        const selection = { productId, sizeMm: 210 };
        for (const count of [min, max]) {
            assert.equal(getPrintExportError(selection, count), null);
            assert.equal(
                preparePrintExport(pages(count), selection).length,
                count,
            );
        }
        for (const count of [min - 2, max + 2]) {
            assert.match(
                getPrintExportError(selection, count)!,
                /including covers/,
            );
            assert.throws(
                () => preparePrintExport(pages(count), selection),
                PrintExportValidationError,
            );
        }
        assert.match(getPrintExportError(selection, min + 1)!, /even number/);
    });
}

test("limits use the normalized export count, including blank interior pages and both covers", () => {
    assert.equal(
        preparePrintExport(pages(23), DEFAULT_PRINT_SELECTION).length,
        24,
    );
    assert.equal(
        preparePrintExport(pages(299), DEFAULT_PRINT_SELECTION).length,
        300,
    );
    assert.throws(
        () => preparePrintExport(pages(301), DEFAULT_PRINT_SELECTION),
        /Remove 2 pages to stay within 300/,
    );
    const softcover: PrintSelection = {
        productId: "softcover-gloss-150",
        sizeMm: 210,
    };
    assert.equal(preparePrintExport(pages(23), softcover).length, 24);
    assert.throws(
        () => preparePrintExport(pages(21), softcover),
        /Add 2 more pages to reach 24/,
    );
});

test("moving an old back-cover photo inside is included before checking the maximum", () => {
    const book = pages(300);
    book[299]!.slots = applyVariant("1-full", ["old-back-photo"]);
    const original = structuredClone(book);
    assert.throws(
        () => preparePrintExport(book, DEFAULT_PRINT_SELECTION),
        /Remove 2 pages to stay within 300/,
    );
    assert.deepEqual(book, original);
});

test("every print product accepts only 210 mm square pages", () => {
    for (const product of PRINT_PRODUCTS) {
        assert.deepEqual(product.sizesMm, [210]);
        assert.ok(isPrintSelection({ productId: product.id, sizeMm: 210 }));
        for (const sizeMm of [0, 209, 211, NaN, Infinity]) {
            const selection = { productId: product.id, sizeMm };
            assert.equal(isPrintSelection(selection), false);
            assert.match(
                getPrintExportError(selection, 24)!,
                /Only 210 × 210 mm books are supported/,
            );
            assert.throws(
                () => preparePrintExport(pages(24), selection),
                PrintExportValidationError,
            );
        }
    }
    for (const value of [
        undefined,
        null,
        {},
        { productId: "unknown", sizeMm: 210 },
        { productId: "softcover-gloss-150" },
        { ...DEFAULT_PRINT_SELECTION, sizeMm: "210" },
    ]) {
        assert.equal(isPrintSelection(value), false);
    }
    assert.match(
        getPrintExportError(
            { productId: "unknown", sizeMm: 210 } as unknown as PrintSelection,
            24,
        )!,
        /Choose a print product/,
    );
});
