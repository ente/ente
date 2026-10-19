import { expect, test } from "vitest";
import {
    fullPhotoState,
    mixPhotoState,
    photoStateTravel,
    shownPhotoState,
    tilePhotoState,
    viewerBackgroundOpacity,
} from "../src/utils/viewer-geometry";

const tile = { x: 10, y: 20, w: 100, h: 100 };

test("a tile crops a wide photo to its centre", () => {
    expect(
        tilePhotoState(tile, { width: 200, height: 100 }, [12, 12, 12, 12]),
    ).toEqual({
        image: { x: -40, y: 20, w: 200, h: 100 },
        visible: tile,
        radii: [12, 12, 12, 12],
    });
});

test("a tile crops a tall photo to its centre", () => {
    expect(
        tilePhotoState(tile, { width: 300, height: 900 }, [0, 0, 0, 0]).image,
    ).toEqual({ x: 10, y: -80, w: 100, h: 300 });
});

test("a flight starts and ends exactly on its endpoints", () => {
    const from = tilePhotoState(
        tile,
        { width: 200, height: 100 },
        [12, 12, 12, 12],
    );
    const to = fullPhotoState({ x: 0, y: 100, w: 400, h: 200 });

    expect(mixPhotoState(from, to, 0)).toEqual(from);
    expect(mixPhotoState(from, to, 1)).toEqual(to);
    expect(mixPhotoState(from, to, 0.5)).toEqual({
        image: { x: -20, y: 60, w: 300, h: 150 },
        visible: { x: 5, y: 60, w: 250, h: 150 },
        radii: [6, 6, 6, 6],
    });
});

test("a spring overshoot never makes the corner radius negative", () => {
    const from = fullPhotoState(tile, [12, 12, 12, 12]);
    const to = fullPhotoState(tile);

    expect(mixPhotoState(from, to, 1.2).radii).toEqual([0, 0, 0, 0]);
});

test("Latest photos keep square bottom corners throughout closing", () => {
    const end = tilePhotoState(
        tile,
        { width: 200, height: 100 },
        [24, 24, 0, 0],
    );
    const rect = { x: 0, y: 100, w: 400, h: 200 };
    for (const from of [
        fullPhotoState(rect),
        fullPhotoState(rect, [12, 12, 0, 0]),
    ]) {
        for (const progress of [0, 0.25, 0.5, 0.75, 1]) {
            const radii = mixPhotoState(from, end, progress).radii;
            expect(radii.slice(2)).toEqual([0, 0]);
            expect(radii[0]).toBeGreaterThanOrEqual(from.radii[0]);
            expect(radii[0]).toBeLessThanOrEqual(24);
        }
        expect(mixPhotoState(from, end, 1).radii).toEqual([24, 24, 0, 0]);
    }
});

test("a photo that fits on screen closes whole", () => {
    const viewport = { x: 0, y: 0, w: 390, h: 844 };
    const dragged = { x: 40, y: 700, w: 300, h: 400 };

    expect(shownPhotoState(dragged, viewport, [8, 8, 8, 8])).toEqual(
        fullPhotoState(dragged, [8, 8, 8, 8]),
    );
});

test("a zoomed-in photo closes from the part on screen", () => {
    const viewport = { x: 0, y: 0, w: 390, h: 844 };
    const zoomed = { x: -500, y: -200, w: 1800, h: 2400 };

    expect(shownPhotoState(zoomed, viewport, [0, 0, 0, 0])).toEqual({
        image: zoomed,
        visible: viewport,
        radii: [0, 0, 0, 0],
    });
});

test("travel is the furthest any visible edge moves", () => {
    const from = fullPhotoState(tile);
    const to = fullPhotoState({ x: 0, y: 20, w: 300, h: 50 });

    expect(photoStateTravel(from, to)).toBe(190);
    expect(photoStateTravel(from, from)).toBe(0);
});

test("the background comes in ahead of the photo", () => {
    expect(viewerBackgroundOpacity(0)).toBe(0);
    expect(viewerBackgroundOpacity(0.5)).toBe(0.75);
    expect(viewerBackgroundOpacity(1)).toBe(1);
});

test("a spring overshoot never takes the background past its ends", () => {
    expect(viewerBackgroundOpacity(1.1)).toBe(1);
    expect(viewerBackgroundOpacity(-0.1)).toBe(0);
});
