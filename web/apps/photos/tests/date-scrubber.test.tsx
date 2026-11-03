import { createTheme, ThemeProvider } from "@mui/material";
import type { EnteFile } from "ente-media/file";
import { fileCreationPhotoDate } from "ente-media/file-metadata";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";
import { DateScrubber } from "../src/components/date-scrubber/DateScrubber";
import {
    adjacentMonthOffset,
    createTimeline,
    indexAtOffset,
    timelineMarkers,
    wheelScrollDelta,
} from "../src/components/date-scrubber/timeline";

let resolvedLanguage = "en-US";

vi.mock("react-i18next", () => ({
    useTranslation: () => ({
        t: (key: string, values?: { date: string }) =>
            values ? `Jump to ${values.date}` : key,
        i18n: { resolvedLanguage },
    }),
}));

const november = new Date(2026, 10, 2);
const october = new Date(2026, 9, 4);
const december = new Date(2025, 11, 25);
const timelineOf = (...rows: [height: number, ...dates: Date[]][]) =>
    createTimeline(rows.map(([height, ...dates]) => ({ height, dates })));

describe("date scrubber timeline", () => {
    test("forwards wheel and trackpad deltas while preserving horizontal gestures and zoom", () => {
        const wheel = { deltaY: 120, deltaX: 0, deltaMode: 0, ctrlKey: false };
        for (const [overrides, expected] of [
            [{}, 120],
            [{ deltaY: -2.5 }, -2.5],
            [{ deltaY: 3, deltaMode: 1 }, 48],
            [{ deltaY: 1, deltaMode: 2 }, 600],
            [{ ctrlKey: true }, 0],
            [{ deltaX: 200 }, 0],
            [{ deltaY: 0 }, 0],
        ] as const)
            expect(wheelScrollDelta({ ...wheel, ...overrides }, 600)).toBe(
                expected,
            );
    });
    test("keyboard navigation skips the content header and shared-month rows", () => {
        const offsets = [120, 120, 500, 900];
        for (const [offset, direction, expected] of [
            [0, "older", 500],
            [0, "newer", 0],
            [120, "older", 500],
            [500, "newer", 120],
            [600, "older", 900],
            [1000, "older", undefined],
            [1000, "newer", 500],
        ] as const)
            expect(adjacentMonthOffset(offsets, offset, direction)).toBe(
                expected,
            );
        for (const [direction, expected] of [
            ["older", 900.8],
            ["newer", 120.4],
        ] as const)
            expect(
                adjacentMonthOffset([120.4, 500.6, 900.8], 500, direction),
            ).toBe(expected);
    });
    test("includes headers, date rows, and footers in exact scroll offsets", () => {
        const timeline = timelineOf(
            [80],
            [40],
            [180, november, november],
            [180, november],
            [40],
            [180, december],
            [100],
        );
        expect(timeline.totalHeight).toBe(800);
        expect(timeline.offsets).toEqual([0, 80, 120, 300, 480, 520, 700]);
        expect(
            timeline.months.map(({ offset, yearStart }) => ({
                offset,
                row: indexAtOffset(timeline.offsets, offset),
                yearStart,
            })),
        ).toEqual([
            { offset: 120, row: 2, yearStart: true },
            { offset: 520, row: 5, yearStart: true },
        ]);
    });
    test("indexes sparse months sharing a row without inventing empty months", () => {
        const { months } = timelineOf(
            [180, november, october],
            [180, december],
        );
        expect(months.map(({ date }) => date.getMonth())).toEqual([10, 9, 11]);
        expect(months.map(({ offset }) => offset)).toEqual([0, 0, 180]);
        expect(months.map(({ yearStart }) => yearStart)).toEqual([
            true,
            false,
            true,
        ]);
        expect(
            [0, 100, 180].map((offset) => indexAtOffset([0, 0, 180], offset)),
        ).toEqual([0, 0, 2]);
    });
    test("finds row boundaries, including before photos and within the footer", () => {
        const offsets = [0, 80, 120, 300, 480, 520, 700];
        expect(
            [-10, 0, 119, 120, 699, 1000].map((offset) =>
                indexAtOffset(offsets, offset),
            ),
        ).toEqual([0, 0, 1, 2, 5, 6]);
        expect(timelineOf()).toEqual({
            offsets: [],
            months: [],
            totalHeight: 0,
        });
    });
    test("looks up a distant row in a large library with logarithmic work", () => {
        let reads = 0;
        const offsets = new Proxy(
            Array.from({ length: 100_000 }, (_, index) => index * 180),
            {
                get(target, property, receiver) {
                    reads++;
                    return Reflect.get(target, property, receiver) as unknown;
                },
            },
        );
        expect(indexAtOffset(offsets, 99_999 * 180)).toBe(99_999);
        expect(reads).toBeLessThan(60);
    });
    test("uses edited photo-local dates instead of original upload metadata", () => {
        const file = {
            metadata: { creationTime: 1 },
            pubMagicMetadata: { data: { dateTime: "2026-11-02T12:30:00" } },
        } as EnteFile;
        const { months } = timelineOf(
            [180, fileCreationPhotoDate(file)],
            [180, new Date(NaN)],
        );
        expect(months).toHaveLength(1);
        expect(months[0]!.date.getFullYear()).toBe(2026);
        expect(months[0]!.date.getMonth()).toBe(10);
    });
    test("gives year labels 48px of space and clamps the last marker", () => {
        const { months } = timelineOf(
            [10, november],
            [10, october],
            [100, december],
        );
        const markers = timelineMarkers(months, 100, 200);
        expect(markers.map(({ yearStart }) => yearStart)).toEqual([true]);
        expect(markers.map(({ position }) => position)).toEqual([0]);
        expect(timelineMarkers(months, 0, 200)).toEqual([]);
        expect(timelineMarkers(months, 5, 200).at(-1)?.position).toBe(200);
    });
    test("keeps month dots 12px apart and clear of the year chips", () => {
        const { months } = timelineOf(
            [24, november],
            [12, october],
            [8, new Date(2026, 8, 1)],
            [60, new Date(2026, 7, 1)],
            [100, december],
        );
        expect(
            timelineMarkers(months, 200, 200).map(({ position }) => position),
        ).toEqual([0, 104, 24, 36]);
    });
    test("rebuilds offsets after a resize or deletion", () => {
        expect(
            timelineOf([180, november], [180, october]).months[1]!.offset,
        ).toBe(180);
        expect(
            timelineOf([90, november], [90, october]).months[1]!.offset,
        ).toBe(90);
        expect(timelineOf([90, october]).months).toHaveLength(1);
    });
});

test.each(["en-US", "en-US-u-ca-buddhist"])(
    "renders Gregorian month labels and hidden year chips in %s",
    (language) => {
        resolvedLanguage = language;
        const markup = renderToStaticMarkup(
            <ThemeProvider theme={createTheme()}>
                <DateScrubber
                    timeline={timelineOf(
                        [500, november],
                        [500, october],
                        [500, december],
                    )}
                    height={300}
                    scrollOffset={0}
                    onSeek={vi.fn()}
                    onScrollBy={vi.fn()}
                />
            </ThemeProvider>,
        );
        resolvedLanguage = "en-US";
        expect(markup).toContain('role="slider"');
        expect(markup).toContain('aria-orientation="vertical"');
        expect(markup).toContain('aria-valuetext="November 2026"');
        expect(markup).toContain('aria-label="Jump to December 2025"');
        expect(markup).not.toContain('role="tooltip"');
        expect(markup).not.toMatch(/>November 2026</);
        expect(markup).toMatch(/>2026</);
        expect(markup).toMatch(/>2025</);
        expect(markup).toContain("date-year-label");
        expect(markup).toContain("opacity:0");
        expect(markup).toContain("pointer-events:none");
        expect(markup).toContain("border-radius:6px");
        expect(markup).toContain("height:3px");
    },
);

test.each([
    [400, "November 2026"],
    [450, "December 2025"],
])(
    "labels the oldest month at the scroll limit (offset %i)",
    (offset, label) => {
        const markup = renderToStaticMarkup(
            <ThemeProvider theme={createTheme()}>
                <DateScrubber
                    timeline={timelineOf([700, november], [50, december])}
                    height={300}
                    scrollOffset={offset}
                    onSeek={vi.fn()}
                    onScrollBy={vi.fn()}
                />
            </ThemeProvider>,
        );
        expect(markup).toContain(`aria-valuetext="${label}"`);
    },
);

test("moves to the preceding reachable month from the scroll limit", () => {
    expect(adjacentMonthOffset([0, 300, 700], 450, "newer", 450)).toBe(300);
    expect(adjacentMonthOffset([0, 300, 450, 700], 450, "newer", 450)).toBe(
        300,
    );
});
