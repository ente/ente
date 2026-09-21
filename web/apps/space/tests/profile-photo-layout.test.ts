import { expect, test } from "vitest";
import {
    profilePhotoGap,
    profilePhotoMinRowHeight,
    profilePhotoRows,
} from "../src/utils/profile-photo-layout";

const photos = (ratios: number[]) =>
    ratios.map((aspectRatio, id) => ({ id, aspectRatio }));

test("a portrait and landscape share a row at their allocated widths", () => {
    const tiles = photos([3 / 4, 3 / 2]);
    expect(profilePhotoRows(tiles, 363)).toEqual([
        { aspectRatio: 2.25, height: 160, tiles },
    ]);
});

test("short landscape rows split without changing photo dimensions", () => {
    const tiles = photos([4 / 3, 5 / 4, 7 / 4]);
    const rows = profilePhotoRows(tiles, 328);
    expect(rows.map(({ tiles }) => tiles.length)).toEqual([2, 1]);
    expect(rows.flatMap(({ tiles }) => tiles)).toEqual(tiles);
});

test("portrait photos are limited to two per row", () => {
    expect(
        profilePhotoRows(photos([2 / 3, 3 / 4, 2 / 3]), 328).map(
            ({ tiles }) => tiles.length,
        ),
    ).toEqual([2, 1]);
});

test("a landscape stands alone so the final portrait can share a row", () => {
    const tiles = photos([16 / 9, 16 / 9, 9 / 16]);
    const rows = profilePhotoRows(tiles, 568);
    expect(rows.map(({ tiles }) => tiles.map(({ id }) => id))).toEqual([
        [0],
        [1, 2],
    ]);
    expect(rows[1]!.height).toBeCloseTo(565 / (16 / 9 + 9 / 16));
});

test("row grouping can shift earlier pairs to avoid a final portrait on its own", () => {
    const tiles = photos([3 / 4, 3 / 4, 16 / 9, 3 / 4, 9 / 16]);
    expect(
        profilePhotoRows(tiles, 363).map(({ tiles }) =>
            tiles.map(({ id }) => id),
        ),
    ).toEqual([[0, 1], [2], [3, 4]]);
});

test("an unavoidable standalone portrait is capped at a 4:5 preview", () => {
    const tiles = photos([9 / 16]);
    expect(profilePhotoRows(tiles, 328)).toEqual([
        { aspectRatio: 9 / 16, height: 410, tiles },
    ]);
});

test("paired portraits keep their original proportions", () => {
    const tiles = photos([9 / 16, 9 / 16]);
    expect(profilePhotoRows(tiles, 363)).toEqual([
        { aspectRatio: 18 / 16, height: 320, tiles },
    ]);
});

test("row grouping adapts to the available width and accounts for gaps", () => {
    const tiles = photos([1.5, 1.5, 1.5]);
    expect(
        profilePhotoRows(tiles, 302).map(({ tiles }) => tiles.length),
    ).toEqual([1, 1, 1]);
    expect(
        profilePhotoRows(tiles, 303).map(({ tiles }) => tiles.length),
    ).toEqual([2, 1]);
    expect(
        profilePhotoRows(tiles, 456).map(({ tiles }) => tiles.length),
    ).toEqual([2, 1]);
});

test("a panorama keeps its aspect ratio even when it cannot reach the minimum", () => {
    const tiles = photos([8, 1, 1]);
    const rows = profilePhotoRows(tiles, 328);
    expect(rows.map(({ tiles }) => tiles.length)).toEqual([1, 2]);
    expect(rows[0]!.aspectRatio).toBe(8);
});

test.each([288, 328, 358, 568])(
    "rows preserve order, fill a %ipx grid, and meet the minimum when possible",
    (width) => {
        const tiles = photos([1.5, 1.2, 1.8, 0.75, 0.6, 8, 0.05, 1, 2, 1.5]);
        const rows = profilePhotoRows(tiles, width);
        expect(rows.flatMap(({ tiles }) => tiles)).toEqual(tiles);
        for (const row of rows) {
            expect(row.tiles.length).toBeLessThanOrEqual(2);
            const gaps = (row.tiles.length - 1) * profilePhotoGap;
            expect(
                row.tiles.reduce(
                    (sum, tile) => sum + tile.aspectRatio * row.height,
                    gaps,
                ),
            ).toBeCloseTo(width);
            expect(row.height).toBeGreaterThanOrEqual(
                Math.min(
                    profilePhotoMinRowHeight,
                    width / row.tiles[0]!.aspectRatio,
                ),
            );
        }
    },
);

test("an empty grid has no rows", () => {
    expect(profilePhotoRows([], 328)).toEqual([]);
});

test("the grid waits for its width to be measured", () => {
    expect(profilePhotoRows(photos([3 / 4, 3 / 2]), 0)).toEqual([]);
});
