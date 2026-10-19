import { expect, test } from "vitest";
import {
    dragVideoTrim,
    type VideoTrimHandle,
} from "../src/components/video-trim/geometry";

test("dragging either handle past ten seconds keeps the opposite edge fixed", () => {
    const range = { start: 8, end: 18 };
    expect(dragVideoTrim(range, "end", 20, 40, 10)).toEqual(range);
    expect(dragVideoTrim(range, "start", -20, 40, 10)).toEqual(range);
    expect(dragVideoTrim(range, "start", 11, 40, 10)).toEqual({
        start: 11,
        end: 18,
    });
    expect(dragVideoTrim(range, "end", 15, 40, 10)).toEqual({
        start: 8,
        end: 15,
    });
});

test("moving the range past ten seconds preserves its length in either direction", () => {
    const later = dragVideoTrim({ start: 0, end: 10 }, "move", 17, 40, 10);
    expect(later).toEqual({ start: 17, end: 27 });
    expect(dragVideoTrim(later, "move", 5, 40, 10)).toEqual({
        start: 5,
        end: 15,
    });
    expect(dragVideoTrim(later, "move", 100, 40, 10)).toEqual({
        start: 30,
        end: 40,
    });
    expect(dragVideoTrim(later, "move", -100, 40, 10)).toEqual({
        start: 0,
        end: 10,
    });
});

test.each([
    { handle: "end" as const, outside: [23, 21, 19, 18], inside: 17 },
    { handle: "start" as const, outside: [2, 4, 6, 8], inside: 9 },
])(
    "$handle keeps its grab point after overshooting",
    ({ handle, outside, inside }) => {
        const original = { start: 8, end: 18 };
        let range = original;
        for (const position of outside) {
            range = dragVideoTrim(range, handle, position, 40, 10);
            expect(range).toEqual(original);
        }
        expect(dragVideoTrim(range, handle, inside, 40, 10)).toEqual({
            ...original,
            [handle]: inside,
        });
    },
);

test("moving the range keeps its grab point beyond either end of the video", () => {
    let range = { start: 30, end: 40 };
    for (const position of [38, 35, 32, 30]) {
        range = dragVideoTrim(range, "move", position, 40, 10);
        expect(range).toEqual({ start: 30, end: 40 });
    }
    expect(dragVideoTrim(range, "move", 29, 40, 10)).toEqual({
        start: 29,
        end: 39,
    });
    range = { start: 0, end: 10 };
    for (const position of [-8, -5, -2, 0]) {
        range = dragVideoTrim(range, "move", position, 40, 10);
        expect(range).toEqual({ start: 0, end: 10 });
    }
    expect(dragVideoTrim(range, "move", 1, 40, 10)).toEqual({
        start: 1,
        end: 11,
    });
});

test.each([0, 15, 30, 40])(
    "holding a ten-second range at position %s does not advance it",
    (position) => {
        const original = { start: 0, end: 10 };
        const expected = dragVideoTrim(original, "move", position, 40, 10);
        let range = expected;
        for (let frame = 0; frame < 300; frame++) {
            range = dragVideoTrim(range, "move", position, 40, 10);
            expect(range).toEqual(expected);
        }
        expect(range.end - range.start).toBe(10);
    },
);

test("moving a shortened range across the full video preserves its duration", () => {
    const original = { start: 4, end: 9 };
    expect(dragVideoTrim(original, "move", 18, 40, 10)).toEqual({
        start: 18,
        end: 23,
    });
    expect(dragVideoTrim(original, "move", 40, 40, 10)).toEqual({
        start: 35,
        end: 40,
    });
    expect(dragVideoTrim(original, "move", -5, 40, 10)).toEqual({
        start: 0,
        end: 5,
    });
});

test.each([0.02, 4, 10, 40, 180])(
    "drags stay valid for a %s-second video",
    (duration) => {
        const range = { start: 0, end: Math.min(10, duration) };
        for (const handle of ["start", "end", "move"] as VideoTrimHandle[])
            for (const position of [-200, -1, 0, 1, 200]) {
                const next = dragVideoTrim(
                    range,
                    handle,
                    position,
                    duration,
                    10,
                );
                expect(next.start).toBeGreaterThanOrEqual(0);
                expect(next.end).toBeLessThanOrEqual(duration);
                expect(next.end - next.start).toBeGreaterThanOrEqual(
                    Math.min(1 / 30, duration) - 1e-10,
                );
                expect(next.end - next.start).toBeLessThanOrEqual(10 + 1e-10);
            }
    },
);
