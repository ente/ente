import { BOOK_SIZE_MM } from "./bookFormats";
import { normalizeBookPages } from "./bookPages";
import type { BookPage } from "./types";

export const PRINT_PRODUCTS = [
    {
        id: "layflat-gloss-190",
        binding: "Layflat",
        paper: "Gloss · 190 gsm",
        minPages: 24,
        maxPages: 100,
        sizesMm: [BOOK_SIZE_MM],
    },
    {
        id: "softcover-gloss-150",
        binding: "Softcover",
        paper: "Gloss · 150 gsm",
        minPages: 24,
        maxPages: 100,
        sizesMm: [BOOK_SIZE_MM],
    },
    {
        id: "softcover-mohawk-120",
        binding: "Softcover",
        paper: "Mohawk uncoated · 120 gsm",
        minPages: 24,
        maxPages: 100,
        sizesMm: [BOOK_SIZE_MM],
    },
] as const;

export type PrintProduct = (typeof PRINT_PRODUCTS)[number];
export type PrintBinding = PrintProduct["binding"];
export const PRINT_BINDINGS = [
    "Layflat",
    "Softcover",
] as const satisfies readonly PrintBinding[];

export function getPrintBindingLabel(binding: PrintBinding) {
    const inches = (BOOK_SIZE_MM / 25.4).toFixed(1);
    return `${binding} (${inches} x ${inches}")`;
}

export function getSpineTitle(title?: string) {
    const text = title?.trim() ?? "";
    return text === "Untitled photobook (for spine)" ? "" : text;
}

export interface PrintSelection {
    productId: PrintProduct["id"];
    sizeMm: number;
}

export const DEFAULT_PRINT_SELECTION: PrintSelection = {
    productId: "layflat-gloss-190",
    sizeMm: BOOK_SIZE_MM,
};

export function getPrintBinding(
    selection?: PrintSelection,
): PrintBinding | undefined {
    return getPrintProduct(selection?.productId)?.binding;
}

export function getBindingPrintSelection(
    binding: PrintBinding,
): PrintSelection {
    return {
        productId:
            binding === "Layflat" ? "layflat-gloss-190" : "softcover-gloss-150",
        sizeMm: BOOK_SIZE_MM,
    };
}

export function getPrintProduct(id: unknown): PrintProduct | undefined {
    return PRINT_PRODUCTS.find((product) => product.id === id);
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
