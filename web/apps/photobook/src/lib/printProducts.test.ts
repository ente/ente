import assert from "node:assert/strict";
import { test } from "vitest";
import { makeBlankPage } from "./bookPages";
import { applyVariant } from "./layouts";
import {
    canDeletePage,
    DEFAULT_PRINT_SELECTION,
    getBindingPrintSelection,
    getPrintBinding,
    getPrintExportError,
    NO_PHOTOS_ERROR,
    preparePrintExport,
    PRINT_PRODUCTS,
    PrintExportValidationError,
    type PrintSelection,
} from "./printProducts";

const pages = (count: number) =>
    Array.from({ length: count }, (_, index) => ({
        ...makeBlankPage(),
        slots: index === 0 ? applyVariant("1-full", ["cover-photo"]) : [],
    }));

test("pages can only be deleted above the 24-page print minimum", () => {
    assert.equal(canDeletePage(22), false);
    assert.equal(canDeletePage(24), false);
    assert.equal(canDeletePage(26), true);
});

test("a book needs a placed photo before preview or print", () => {
    const book = Array.from({ length: 24 }, makeBlankPage);
    book[1]!.topCaption = "Summer";
    book[1]!.slots = applyVariant("1-full", []);
    assert.equal(
        getPrintExportError(DEFAULT_PRINT_SELECTION, book),
        NO_PHOTOS_ERROR,
    );
    assert.throws(
        () => preparePrintExport(book, DEFAULT_PRINT_SELECTION),
        PrintExportValidationError,
    );
    book[2]!.slots = applyVariant("1-full", ["holiday-photo"]);
    assert.equal(getPrintExportError(DEFAULT_PRINT_SELECTION, book), null);
});

test("the cover selection uses 210 mm and a 100-page limit", () => {
    assert.equal(getPrintBinding(), undefined);
    for (const binding of ["Layflat", "Softcover"] as const) {
        const selection = getBindingPrintSelection(binding);
        assert.equal(getPrintBinding(selection), binding);
        assert.equal(selection.sizeMm, 210);
        assert.equal(getPrintExportError(selection, pages(24)), null);
        assert.equal(getPrintExportError(selection, pages(100)), null);
        assert.ok(getPrintExportError(selection, pages(16)));
        assert.ok(getPrintExportError(selection, pages(102)));
        assert.equal(preparePrintExport(pages(24), selection).length, 24);
    }
});

for (const [productId, min, max] of [
    ["layflat-gloss-190", 24, 100],
    ["softcover-gloss-150", 24, 100],
    ["softcover-mohawk-120", 24, 100],
] as const) {
    test(`${productId} enforces its ${min}–${max} page range at both boundaries`, () => {
        const selection = { productId, sizeMm: 210 };
        for (const count of [min, max]) {
            assert.equal(getPrintExportError(selection, pages(count)), null);
            assert.equal(
                preparePrintExport(pages(count), selection).length,
                count,
            );
        }
        for (const count of [min - 2, max + 2]) {
            assert.match(
                getPrintExportError(selection, pages(count))!,
                /including covers/,
            );
            assert.throws(
                () => preparePrintExport(pages(count), selection),
                PrintExportValidationError,
            );
        }
        assert.match(
            getPrintExportError(selection, pages(min + 1))!,
            /even number/,
        );
    });
}

test("limits use the normalized export count, including blank interior pages and both covers", () => {
    assert.equal(
        preparePrintExport(pages(23), DEFAULT_PRINT_SELECTION).length,
        24,
    );
    assert.equal(
        preparePrintExport(pages(99), DEFAULT_PRINT_SELECTION).length,
        100,
    );
    assert.throws(
        () => preparePrintExport(pages(101), DEFAULT_PRINT_SELECTION),
        /Remove 2 pages to stay within 100/,
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
    const book = pages(100);
    book[99]!.slots = applyVariant("1-full", ["old-back-photo"]);
    const original = structuredClone(book);
    assert.throws(
        () => preparePrintExport(book, DEFAULT_PRINT_SELECTION),
        /Remove 2 pages to stay within 100/,
    );
    assert.deepEqual(book, original);
});

test("every print product accepts only 210 mm square pages", () => {
    for (const product of PRINT_PRODUCTS) {
        assert.deepEqual(product.sizesMm, [210]);
        for (const sizeMm of [0, 209, 211, NaN, Infinity]) {
            const selection = { productId: product.id, sizeMm };
            assert.match(
                getPrintExportError(selection, pages(24))!,
                /Only 210 × 210 mm books are supported/,
            );
            assert.throws(
                () => preparePrintExport(pages(24), selection),
                PrintExportValidationError,
            );
        }
    }
    assert.match(
        getPrintExportError(
            { productId: "unknown", sizeMm: 210 } as unknown as PrintSelection,
            pages(24),
        )!,
        /Choose a print product/,
    );
});
