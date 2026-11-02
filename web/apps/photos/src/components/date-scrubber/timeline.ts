export interface TimelineRow {
    height: number;
    dates?: Date[];
}

export interface TimelineMonth {
    date: Date;
    offset: number;
    yearStart: boolean;
}

/** Index the rendered rows, including non-photo headers and footers. */
export const createTimeline = (rows: TimelineRow[]) => {
    const offsets: number[] = [];
    const months: TimelineMonth[] = [];
    const seenMonths = new Set<string>();
    const seenYears = new Set<number>();
    let totalHeight = 0;
    rows.forEach(({ height, dates }) => {
        offsets.push(totalHeight);
        for (const date of dates ?? []) {
            if (!Number.isFinite(date.getTime())) continue;
            const year = date.getFullYear();
            const key = `${year}-${date.getMonth()}`;
            if (seenMonths.has(key)) continue;
            seenMonths.add(key);
            months.push({
                date,
                offset: totalHeight,
                yearStart: !seenYears.has(year),
            });
            seenYears.add(year);
        }
        totalHeight += height;
    });
    return { offsets, months, totalHeight };
};

export type Timeline = ReturnType<typeof createTimeline>;

/** Normalize wheel input without consuming horizontal gestures or pinch zoom. */
export const wheelScrollDelta = (
    event: Pick<WheelEvent, "deltaY" | "deltaX" | "deltaMode" | "ctrlKey">,
    pageHeight: number,
) => {
    if (event.ctrlKey || Math.abs(event.deltaX) > Math.abs(event.deltaY))
        return 0;
    const unit =
        event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? pageHeight : 1;
    return event.deltaY * unit;
};

/** Last entry at or before the offset; shared rows use their first month. */
export const indexAtOffset = (offsets: number[], offset: number) => {
    let low = 0;
    let high = offsets.length;
    while (low < high) {
        const middle = (low + high) >>> 1;
        if (offsets[middle]! <= offset) low = middle + 1;
        else high = middle;
    }
    const index = Math.max(0, low - 1);
    // Resolve identical offsets deterministically without a linear scan.
    const value = offsets[index];
    high = index;
    low = 0;
    while (low < high) {
        const middle = (low + high) >>> 1;
        if (offsets[middle]! < value!) low = middle + 1;
        else high = middle;
    }
    return low;
};

/** Step between populated months, skipping duplicate targets on shared rows. */
export const adjacentMonthOffset = (
    offsets: number[],
    offset: number,
    direction: "older" | "newer",
) => {
    // Browsers round scrollTop while thumbnail rows have fractional heights.
    const current = indexAtOffset(offsets, offset + 1);
    const currentOffset = offsets[current] ?? 0;
    if (direction === "older")
        return offsets.find(
            (value) => value > Math.max(offset + 1, currentOffset),
        );
    const previous = indexAtOffset(offsets, currentOffset - 1);
    return previous === current ? 0 : offsets[previous];
};

/** Leave mobile-style year labels room, with denser month dots between them. */
export const timelineMarkers = (
    months: TimelineMonth[],
    maxOffset: number,
    trackHeight: number,
) => {
    if (maxOffset <= 0 || trackHeight <= 0) return [];
    const positions: { position: number; yearStart: boolean }[] = [];
    return [
        ...months.filter((month) => month.yearStart),
        ...months.filter((month) => !month.yearStart),
    ].flatMap((month) => {
        const position =
            (Math.min(month.offset, maxOffset) / maxOffset) * trackHeight;
        if (
            positions.some((other) => {
                const gap =
                    month.yearStart && other.yearStart
                        ? 48
                        : month.yearStart || other.yearStart
                          ? 24
                          : 12;
                return Math.abs(other.position - position) < gap;
            })
        )
            return [];
        positions.push({ position, yearStart: month.yearStart });
        return [{ ...month, position }];
    });
};
