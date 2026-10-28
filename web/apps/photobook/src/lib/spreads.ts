import type { PrintBinding } from "./printProducts";

// null is the empty space beside a closed cover. A printer blank is a visible,
// non-editable page supplied by the printer, never a page in the export.
type SpreadPageRef = number | "printer-blank" | null;

export interface Spread {
    left: SpreadPageRef;
    right: SpreadPageRef;
}

export function getSpreads(pageCount: number, binding: PrintBinding): Spread[] {
    if (pageCount === 0) return [];
    const spreads: Spread[] = [{ left: null, right: 0 }];
    if (pageCount === 1) return spreads;

    if (pageCount > 2) {
        if (binding === "Hardcover")
            spreads.push({ left: "printer-blank", right: "printer-blank" });
        spreads.push({ left: "printer-blank", right: 1 });
        for (let i = 2; i < pageCount - 1; i += 2) {
            spreads.push({
                left: i,
                right: i + 1 < pageCount - 1 ? i + 1 : "printer-blank",
            });
        }
        if (binding === "Hardcover")
            spreads.push({ left: "printer-blank", right: "printer-blank" });
    }

    spreads.push({ left: pageCount - 1, right: null });
    return spreads;
}

export function getSpreadPageIndices(spread: Spread): number[] {
    return [spread.left, spread.right].filter(
        (page): page is number => typeof page === "number",
    );
}

export function getSpreadLabel(
    spread: Spread | undefined,
    pageCount: number,
): string {
    if (!spread) return "";
    const indices = getSpreadPageIndices(spread);
    if (indices.length === 0) return "Blank pages";
    if (indices.includes(0)) return "Cover";
    if (indices.includes(pageCount - 1)) return "Back cover";
    return indices.join("–");
}

export function getFlipPages(
    pageCount: number,
    binding: PrintBinding,
): { pageIndex: number | null; spreadIndex: number }[] {
    return getSpreads(pageCount, binding).flatMap((spread, spreadIndex) =>
        [spread.left, spread.right]
            .filter((page) => page !== null)
            .map((page) => ({
                pageIndex: typeof page === "number" ? page : null,
                spreadIndex,
            })),
    );
}

export function getFlipPageIndex(
    pageCount: number,
    pageIndex: number,
    binding: PrintBinding,
): number | null {
    if (!Number.isInteger(pageIndex) || pageIndex < 0 || pageIndex >= pageCount)
        return null;
    const index = getFlipPages(pageCount, binding).findIndex(
        (page) => page.pageIndex === pageIndex,
    );
    return index < 0 ? null : index;
}
