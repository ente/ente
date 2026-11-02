import { useBook } from "@/context/book";
import { getPrintBinding } from "@/lib/printProducts";
import { getSpreads, type Spread } from "@/lib/spreads";
import { useMemo } from "react";

export function useSpreads(pageCount: number): Spread[] {
    const { book } = useBook();
    const binding = getPrintBinding(book.printSelection);
    return useMemo(() => getSpreads(pageCount, binding), [pageCount, binding]);
}
