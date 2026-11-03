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

/** Find the first offset that is outside a sorted prefix. */
const firstOffsetOutside = (
    offsets: number[],
    inPrefix: (offset: number) => boolean,
) => {
    let low = 0;
    let high = offsets.length;
    while (low < high) {
        const middle = (low + high) >>> 1;
        if (inPrefix(offsets[middle]!)) low = middle + 1;
        else high = middle;
    }
    return low;
};

/** Last entry at or before the offset; shared rows use their first month. */
export const indexAtOffset = (offsets: number[], offset: number) => {
    const end = firstOffsetOutside(offsets, (value) => value <= offset);
    if (end === 0) return 0;
    return firstOffsetOutside(offsets, (value) => value < offsets[end - 1]!);
};

/** Step between populated months, skipping duplicate targets on shared rows. */
export const adjacentMonthOffset = (
    offsets: number[],
    offset: number,
    direction: "older" | "newer",
) => {
    // Browsers round scrollTop while thumbnail rows have fractional heights.
    const roundedOffset = offset + 1;
    if (direction === "older") {
        const boundary = Math.max(roundedOffset, offsets[0] ?? 0);
        return offsets[
            firstOffsetOutside(offsets, (value) => value <= boundary)
        ];
    }
    const current = indexAtOffset(offsets, roundedOffset);
    const previous = indexAtOffset(offsets, (offsets[current] ?? 0) - 1);
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
