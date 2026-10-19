import { describe, expect, it } from "vitest";
import { layoutPostGrid } from "../src/utils/post-grid";

const photosWithRatios = (ratios: number[]) =>
    ratios.map((frameAspectRatio) => ({ frameAspectRatio }));

describe("post grid mosaic", () => {
    for (const width of [288, 304, 374, 414, 768]) {
        for (const [name, ratios] of Object.entries({
            portraits: [0.5, 0.75, 0.6, 0.8, 0.75, 0.9, 0.75],
            landscapes: [1.5, 2, 1.8, 1.3, 2.5, 1.5, 1.6],
            squares: Array<number>(12).fill(1),
            mixed: [0.6, 1.5, 1.8, 1, 0.8, 3, 1.5, 0.75, 2, 1, 0.5],
        })) {
            it(`fits ${name} at ${width}px without overlap or extra cropping`, () => {
                const { tiles, height } = layoutPostGrid(
                    photosWithRatios(ratios),
                    width,
                );
                expect(tiles).toHaveLength(ratios.length);
                tiles.forEach((tile, index) => {
                    expect(tile.width).toBeGreaterThan(0);
                    expect(tile.height).toBeGreaterThan(0);
                    expect(tile.left).toBeGreaterThanOrEqual(0);
                    expect(tile.top).toBeGreaterThanOrEqual(0);
                    expect(tile.left + tile.width).toBeLessThanOrEqual(
                        width + 0.001,
                    );
                    expect(tile.top + tile.height).toBeLessThanOrEqual(
                        height + 0.001,
                    );
                    expect(tile.width / tile.height).toBeCloseTo(
                        Math.max(0.75, ratios[index]!),
                    );
                    for (const previous of tiles.slice(0, index)) {
                        expect(tile.top).toBeGreaterThanOrEqual(previous.top);
                        const horizontalGap = Math.max(
                            tile.left - previous.left - previous.width,
                            previous.left - tile.left - tile.width,
                        );
                        const verticalGap =
                            tile.top - previous.top - previous.height;
                        expect(
                            Math.max(horizontalGap, verticalGap),
                        ).toBeGreaterThanOrEqual(8 - 0.001);
                    }
                });
                expect(height).toBeCloseTo(
                    Math.max(...tiles.map((tile) => tile.top + tile.height)),
                );
            });
        }
    }

    it("varies widths and alternates tall photos across the grid", () => {
        const { tiles } = layoutPostGrid(
            photosWithRatios(Array<number>(12).fill(1)),
            374,
        );
        expect(
            new Set(tiles.map((tile) => Math.round(tile.width))).size,
        ).toBeGreaterThan(2);
        expect(tiles.some((tile) => tile.width > 220 && tile.left == 0)).toBe(
            true,
        );
        expect(tiles.some((tile) => tile.width > 220 && tile.left > 0)).toBe(
            true,
        );
    });

    it("gives a wide panorama the full width", () => {
        const { tiles } = layoutPostGrid(
            photosWithRatios([3, 0.75, 1.5, 1.8]),
            374,
        );
        expect(tiles[0]!.width).toBe(374);
        expect(tiles[0]!.height).toBeCloseTo(374 / 3);
    });

    it("mixes grouped and full-width landscape photos on narrow screens", () => {
        const { tiles } = layoutPostGrid(
            photosWithRatios([1.5, 2, 1.8, 1.3, 2.5, 1.5, 1.6]),
            288,
        );
        expect(tiles[0]!.width).toBe(288);
        expect(tiles[1]!.width).toBeLessThan(288);
        expect(tiles[1]!.top).toBe(tiles[2]!.top);
    });

    it("fits a row with unequal widths and aligned bottoms", () => {
        const { tiles } = layoutPostGrid(photosWithRatios([1, 0.75]), 374);
        expect(tiles[0]!.top).toBe(tiles[1]!.top);
        expect(tiles[0]!.height).toBe(tiles[1]!.height);
        expect(tiles[0]!.width).toBeGreaterThan(tiles[1]!.width);
        expect(tiles[0]!.width + 8 + tiles[1]!.width).toBeCloseTo(374);
    });

    it("preserves the full-width layout for small collections", () => {
        const { tiles } = layoutPostGrid(
            photosWithRatios([0.5, 1.5, 1]),
            374,
            true,
        );
        expect(tiles.every((tile) => tile.width == 374 && tile.left == 0)).toBe(
            true,
        );
        expect(tiles[0]!.height).toBeCloseTo(374 / 0.75);
    });

    it("uses the frame ratio before dimensions and keeps unknown dimensions square", () => {
        const { tiles } = layoutPostGrid(
            [
                { frameAspectRatio: 0.5, width: 200, height: 100 },
                { width: 150, height: 100 },
                {},
            ],
            374,
        );
        expect(tiles.map((tile) => tile.width / tile.height)).toEqual([
            expect.closeTo(0.75),
            expect.closeTo(1.5),
            expect.closeTo(1),
        ]);
    });

    it("keeps completed groups stable when older posts are appended", () => {
        const photos = photosWithRatios([
            0.75, 1.5, 1.8, 1, 0.8, 3, 1.5, 0.75, 2, 1,
        ]);
        const before = layoutPostGrid(photos, 374);
        const after = layoutPostGrid(
            [...photos, ...photosWithRatios([1.2, 0.75, 1.5])],
            374,
        );
        expect(after.tiles.slice(0, photos.length - 2)).toEqual(
            before.tiles.slice(0, photos.length - 2),
        );
        expect(layoutPostGrid(photos, 374)).toEqual(before);
    });

    it.each([288, 374, 768])(
        "keeps every displayed tile stable across feed batches at %ipx",
        (width) => {
            const ratios = [0.75, 1.5, 1.8, 1, 0.8, 3, 1.5, 0.75, 2, 1];
            const photos = Array.from({ length: 40 }, (_, index) => ({
                frameAspectRatio: ratios[index % ratios.length]!,
                batchIndex:
                    index < 20 ? undefined : Math.floor((index - 20) / 10) + 1,
            }));
            for (const count of [20, 30]) {
                const before = layoutPostGrid(photos.slice(0, count), width);
                const after = layoutPostGrid(
                    photos.slice(0, count + 10),
                    width,
                );
                expect(after.tiles).toHaveLength(count + 10);
                expect(after.tiles.slice(0, count)).toEqual(before.tiles);
                expect(after.tiles[count]!.top).toBeCloseTo(before.height + 8);
            }
        },
    );

    it.each([1, 2, 3])(
        "finishes a %i-post batch before starting the next row",
        (count) => {
            const photos = photosWithRatios(Array<number>(count).fill(1));
            const { tiles } = layoutPostGrid(
                [...photos, { frameAspectRatio: 1, batchIndex: 1 }],
                374,
            );
            const firstBatch = tiles.slice(0, count);
            const bottom = Math.max(
                ...firstBatch.map((tile) => tile.top + tile.height),
            );
            expect(Math.min(...firstBatch.map((tile) => tile.left))).toBe(0);
            expect(
                Math.max(...firstBatch.map((tile) => tile.left + tile.width)),
            ).toBeCloseTo(374);
            expect(tiles[count]!.top).toBeCloseTo(bottom + 8);
            if (count > 1)
                expect(firstBatch.every((tile) => tile.width < 374)).toBe(true);
        },
    );

    it("has no height before measurement or without photos", () => {
        expect(layoutPostGrid(photosWithRatios([1, 0.75]), 0)).toEqual({
            tiles: [],
            height: 0,
        });
        expect(layoutPostGrid([], 374)).toEqual({ tiles: [], height: 0 });
    });
});
