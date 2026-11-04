import { getSpreads, type Spread } from "@/lib/spreads";
import { useMemo } from "react";

export function useSpreads(pageCount: number): Spread[] {
    return useMemo(() => getSpreads(pageCount), [pageCount]);
}
