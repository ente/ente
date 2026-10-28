import { BOOK_SIZE_MM } from "./bookFormats";
import { normalizeBookPages } from "./bookPages";
import type { BookPage } from "./types";

// Page ranges checked 2026-10-26. Counts include both covers; printer-added
// binding sheets and inside covers are excluded. The app supports only
// 210 × 210 mm square pages for both hardcover and softcover.
// The app uses a shared 24-page minimum for both cover types.
// https://www.prodigi.com/blog/photo-books-technical-guide/
// https://www.prodigi.com/products/books-and-magazines/hardcover-photo-book/
// https://www.prodigi.com/products/books-and-magazines/softcover-photo-book/

export const PRINT_PRODUCTS = [
    {
        id: "hardcover-gloss-200",
        binding: "Hardcover",
        paper: "Gloss · 200 gsm",
        minPages: 24,
        maxPages: 300,
        sizesMm: [BOOK_SIZE_MM],
    },
    {
        id: "hardcover-gloss-150",
        binding: "Hardcover",
        paper: "Gloss · 150 gsm",
        minPages: 24,
        maxPages: 500,
        sizesMm: [BOOK_SIZE_MM],
    },
    {
        id: "hardcover-mohawk-120",
        binding: "Hardcover",
        paper: "Mohawk uncoated · 120 gsm",
        minPages: 24,
        maxPages: 300,
        sizesMm: [BOOK_SIZE_MM],
    },
    {
        id: "softcover-gloss-150",
        binding: "Softcover",
        paper: "Gloss · 150 gsm",
        minPages: 24,
        maxPages: 300,
        sizesMm: [BOOK_SIZE_MM],
    },
    {
        id: "softcover-mohawk-120",
        binding: "Softcover",
        paper: "Mohawk uncoated · 120 gsm",
        minPages: 24,
        maxPages: 300,
        sizesMm: [BOOK_SIZE_MM],
    },
] as const;

export type PrintProduct = (typeof PRINT_PRODUCTS)[number];
export type PrintBinding = PrintProduct["binding"];
export interface PrintSelection {
    productId: PrintProduct["id"];
    sizeMm: number;
}

export const DEFAULT_PRINT_SELECTION: PrintSelection = {
    productId: "hardcover-gloss-200",
    sizeMm: BOOK_SIZE_MM,
};

export function getPrintBinding(selection?: PrintSelection): PrintBinding {
    return getPrintProduct(selection?.productId)?.binding ?? "Hardcover";
}

export function getBindingPrintSelection(
    binding: PrintBinding,
): PrintSelection {
    return {
        productId:
            binding === "Hardcover"
                ? "hardcover-gloss-200"
                : "softcover-gloss-150",
        sizeMm: BOOK_SIZE_MM,
    };
}

export function getPrintProduct(id: unknown): PrintProduct | undefined {
    return PRINT_PRODUCTS.find((product) => product.id === id);
}

export function isPrintSelection(value: unknown): value is PrintSelection {
    if (!value || typeof value !== "object") return false;
    const selection = value as Partial<PrintSelection>;
    const product = getPrintProduct(selection.productId);
    return (
        !!product &&
        (product.sizesMm as readonly number[]).includes(selection.sizeMm!)
    );
}

export function getPrintExportError(
    selection: PrintSelection,
    pageCount: number,
): string | null {
    const product = getPrintProduct(selection.productId);
    if (!product) return "Choose a print product before downloading.";
    if (!(product.sizesMm as readonly number[]).includes(selection.sizeMm)) {
        return `Only ${BOOK_SIZE_MM} × ${BOOK_SIZE_MM} mm books are supported.`;
    }
    if (pageCount < product.minPages || pageCount > product.maxPages) {
        const belowMinimum = pageCount < product.minPages;
        const difference = belowMinimum
            ? product.minPages - pageCount
            : pageCount - product.maxPages;
        const pageLabel = difference === 1 ? "page" : "pages";
        return belowMinimum
            ? `Add ${difference} more ${pageLabel} to reach ${product.minPages}, including covers.`
            : `Remove ${difference} ${pageLabel} to stay within ${product.maxPages}, including covers.`;
    }
    if (pageCount % 2 !== 0)
        return "The print product requires an even number of pages, including covers.";
    return null;
}

export class PrintExportValidationError extends Error {
    constructor(message: string) {
        super(message);
        this.name = "PrintExportValidationError";
    }
}

export function preparePrintExport(
    inputPages: BookPage[],
    selection: PrintSelection,
): BookPage[] {
    const pages = normalizeBookPages(inputPages);
    const error = getPrintExportError(selection, pages.length);
    if (error) throw new PrintExportValidationError(error);
    return pages;
}
