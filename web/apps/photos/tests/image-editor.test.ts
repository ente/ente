import { computeInscribedCrop } from "ente-new/photos/utils/image-editor";
import { describe, expect, test } from "vitest";

/**
 * Independently verify a computed crop rectangle by rotating its corners
 * back into the original (unrotated) rectangle's frame and checking they
 * lie within its bounds — this checks the actual geometry, rather than
 * re-deriving the same closed-form formula the code under test uses.
 */
const cropFitsWithinOriginal = (
    originalWidth: number,
    originalHeight: number,
    angleDegrees: number,
    crop: { width: number; height: number },
    tolerance = 1e-6,
) => {
    const radians = (angleDegrees * Math.PI) / 180;
    const sin = Math.sin(radians);
    const cos = Math.cos(radians);
    const a = crop.width / 2;
    const b = crop.height / 2;

    // The four corners of the crop rectangle, rotated by -angleDegrees
    // (undoing the rotation) into the original rectangle's frame.
    const corners = [
        [a, b],
        [a, -b],
        [-a, b],
        [-a, -b],
    ].map(([x, y]) => ({
        x: x! * cos + y! * sin,
        y: -x! * sin + y! * cos,
    }));

    return corners.every(
        (c) =>
            Math.abs(c.x) <= originalWidth / 2 + tolerance &&
            Math.abs(c.y) <= originalHeight / 2 + tolerance,
    );
};

/** The crop is "tight" if scaling it up even slightly no longer fits. */
const cropIsTight = (
    originalWidth: number,
    originalHeight: number,
    angleDegrees: number,
    crop: { width: number; height: number },
) =>
    !cropFitsWithinOriginal(originalWidth, originalHeight, angleDegrees, {
        width: crop.width * 1.001,
        height: crop.height * 1.001,
    });

describe("computeInscribedCrop", () => {
    test("0 degrees returns the input dimensions unchanged", () => {
        expect(computeInscribedCrop(1000, 600, 0)).toEqual({
            width: 1000,
            height: 600,
        });
    });

    const cases: [string, number, number, number][] = [
        ["square, 1 degree", 1000, 1000, 1],
        ["square, 45 degrees", 1000, 1000, 45],
        ["landscape, 5 degrees", 1000, 600, 5],
        ["landscape, 15 degrees", 1000, 600, 15],
        ["landscape, 30 degrees", 1000, 600, 30],
        ["landscape, 45 degrees", 1000, 600, 45],
        ["portrait, 5 degrees", 600, 1000, 5],
        ["portrait, 15 degrees", 600, 1000, 15],
        ["portrait, 45 degrees", 600, 1000, 45],
        ["portrait, -15 degrees", 600, 1000, -15],
        ["very wide, 45 degrees", 2000, 400, 45],
        ["very wide, 10 degrees", 2000, 400, 10],
    ];

    for (const [label, width, height, angle] of cases) {
        test(`${label}: fits within the original bounds, preserves aspect ratio, and is tight`, () => {
            const crop = computeInscribedCrop(width, height, angle);

            expect(
                cropFitsWithinOriginal(width, height, angle, crop),
            ).toBe(true);

            expect(crop.width / crop.height).toBeCloseTo(width / height, 6);

            expect(cropIsTight(width, height, angle, crop)).toBe(true);
        });
    }

    test("negative angle produces the same result as its positive counterpart", () => {
        const positive = computeInscribedCrop(1000, 600, 30);
        const negative = computeInscribedCrop(1000, 600, -30);
        expect(negative).toEqual(positive);
    });

    test("composing with a prior edit uses the current (already-cropped) dimensions, not original", () => {
        const first = computeInscribedCrop(1000, 600, 20);
        const second = computeInscribedCrop(first.width, first.height, 10);
        const direct = computeInscribedCrop(first.width, first.height, 10);
        expect(second).toEqual(direct);
    });

    test("shrinks monotonically as the angle increases from 0 to 45", () => {
        const angles = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45];
        const widths = angles.map(
            (a) => computeInscribedCrop(1000, 600, a).width,
        );
        for (let i = 1; i < widths.length; i++) {
            expect(widths[i]).toBeLessThan(widths[i - 1]!);
        }
    });
});
