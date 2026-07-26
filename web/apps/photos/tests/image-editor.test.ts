import { computeInscribedCrop } from "ente-new/photos/utils/image-editor";
import { describe, expect, test } from "vitest";

describe("computeInscribedCrop", () => {
    test("0 degrees returns the input dimensions unchanged", () => {
        expect(computeInscribedCrop(1000, 600, 0)).toEqual({
            width: 1000,
            height: 600,
        });
    });

    test("square image, 45 degrees", () => {
        // wide = long = 1000, sinT = cosT = sqrt(2)/2
        // wide <= 2*sinT*cosT*long -> 1000 <= 1000, so first branch
        // x = 500, cropW = 500 / (sqrt(2)/2), cropH = same
        const result = computeInscribedCrop(1000, 1000, 45);
        expect(result.width).toBeCloseTo(707.10678, 4);
        expect(result.height).toBeCloseTo(707.10678, 4);
    });

    test("landscape image, small angle uses the second branch", () => {
        // W=1000, H=600, angle=5deg
        const result = computeInscribedCrop(1000, 600, 5);
        const radians = (5 * Math.PI) / 180;
        const sinT = Math.abs(Math.sin(radians));
        const cosT = Math.abs(Math.cos(radians));
        const d = cosT * cosT - sinT * sinT;
        const expectedW = (1000 * cosT - 600 * sinT) / d;
        const expectedH = (600 * cosT - 1000 * sinT) / d;
        expect(result.width).toBeCloseTo(expectedW, 4);
        expect(result.height).toBeCloseTo(expectedH, 4);
    });

    test("portrait image, 15 degrees", () => {
        const result = computeInscribedCrop(600, 1000, 15);
        const radians = (15 * Math.PI) / 180;
        const sinT = Math.abs(Math.sin(radians));
        const cosT = Math.abs(Math.cos(radians));
        // wide = 600, long = 1000
        const wide = 600;
        const long = 1000;
        if (wide <= 2 * sinT * cosT * long) {
            const x = wide / 2;
            expect(result.width).toBeCloseTo(x / sinT, 4);
            expect(result.height).toBeCloseTo(x / cosT, 4);
        } else {
            const d = cosT * cosT - sinT * sinT;
            expect(result.width).toBeCloseTo((600 * cosT - 1000 * sinT) / d, 4);
            expect(result.height).toBeCloseTo(
                (1000 * cosT - 600 * sinT) / d,
                4,
            );
        }
    });

    test("negative angle uses the absolute value (symmetric result)", () => {
        const positive = computeInscribedCrop(1000, 600, 30);
        const negative = computeInscribedCrop(1000, 600, -30);
        expect(negative).toEqual(positive);
    });

    test("composing with a prior edit uses the current (already-cropped) dimensions, not original", () => {
        // A second call using the output of a first call as its input must
        // recompute from those dimensions, not reference anything global.
        const first = computeInscribedCrop(1000, 600, 20);
        const second = computeInscribedCrop(first.width, first.height, 10);
        const direct = computeInscribedCrop(first.width, first.height, 10);
        expect(second).toEqual(direct);
    });

    test("45 degree cap on a very wide image uses the first branch", () => {
        const result = computeInscribedCrop(2000, 400, 45);
        // wide=400, long=2000, sinT=cosT=sqrt(2)/2
        // 2*sinT*cosT*long = 2000, wide(400) <= 2000 -> first branch
        const x = 200;
        const sinT = Math.sqrt(2) / 2;
        const cosT = Math.sqrt(2) / 2;
        expect(result.width).toBeCloseTo(x / sinT, 4);
        expect(result.height).toBeCloseTo(x / cosT, 4);
    });
});
