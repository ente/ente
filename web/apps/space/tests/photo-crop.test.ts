import { expect, test } from "vitest";
import {
    cropWithAspect,
    fullImageCrop,
    moveImageCrop,
    resizeImageCrop,
    rotateImageCrop,
    rotatedImageSize,
    type CropHandle,
} from "../src/components/photo-crop/geometry";

const landscape = { width: 1200, height: 800 };
const portrait = { width: 800, height: 1200 };

test.each([1, 3 / 4, 16 / 9])(
    "fits aspect %s to landscape and portrait photos",
    (aspect) => {
        for (const size of [landscape, portrait]) {
            const crop = cropWithAspect(fullImageCrop(size), aspect, size);
            expect(crop.width / crop.height).toBeCloseTo(aspect);
            expect(crop.x).toBeCloseTo((size.width - crop.width) / 2);
            expect(crop.y).toBeCloseTo((size.height - crop.height) / 2);
            expect(crop.width <= size.width && crop.height <= size.height).toBe(
                true,
            );
            expect(
                Math.min(size.width - crop.width, size.height - crop.height),
            ).toBeCloseTo(0);
        }
    },
);

test("moves the crop to image boundaries without changing its size", () => {
    const crop = { x: 100, y: 200, width: 400, height: 300 };
    expect(moveImageCrop(crop, -2000, 2000, landscape)).toEqual({
        ...crop,
        x: 0,
        y: 500,
    });
    expect(moveImageCrop(crop, 2000, -2000, landscape)).toEqual({
        ...crop,
        x: 800,
        y: 0,
    });
});

test("resizes free edges without moving the opposite edge", () => {
    const crop = { x: 100, y: 200, width: 400, height: 300 };
    expect(resizeImageCrop(crop, "w", 80, 50, landscape, 24)).toEqual({
        x: 180,
        y: 200,
        width: 320,
        height: 300,
    });
    expect(resizeImageCrop(crop, "n", 80, 50, landscape, 24)).toEqual({
        x: 100,
        y: 250,
        width: 400,
        height: 250,
    });
});

test.each([undefined, 1, 3 / 4, 16 / 9])(
    "keeps aspect %s crops inside the photo at every drag boundary",
    (aspect) => {
        const handles: CropHandle[] = aspect
            ? ["nw", "ne", "se", "sw"]
            : ["nw", "n", "ne", "e", "se", "s", "sw", "w"];
        for (const size of [landscape, portrait, { width: 12, height: 8 }]) {
            const crop = aspect
                ? cropWithAspect(fullImageCrop(size), aspect, size)
                : fullImageCrop(size);
            for (const handle of handles) {
                for (const dx of [-3000, -40, 0, 40, 3000]) {
                    for (const dy of [-3000, -40, 0, 40, 3000]) {
                        const next = resizeImageCrop(
                            crop,
                            handle,
                            dx,
                            dy,
                            size,
                            24,
                            aspect,
                        );
                        expect(next.x).toBeGreaterThanOrEqual(-1e-10);
                        expect(next.y).toBeGreaterThanOrEqual(-1e-10);
                        expect(next.x + next.width).toBeLessThanOrEqual(
                            size.width + 1e-10,
                        );
                        expect(next.y + next.height).toBeLessThanOrEqual(
                            size.height + 1e-10,
                        );
                        expect(next.width).toBeGreaterThan(0);
                        expect(next.height).toBeGreaterThan(0);
                        if (aspect)
                            expect(next.width / next.height).toBeCloseTo(
                                aspect,
                            );
                    }
                }
            }
        }
    },
);

test("rotates the selected region clockwise and restores it after four turns", () => {
    const original = { x: 100, y: 200, width: 400, height: 300 };
    let crop = rotateImageCrop(original, landscape);
    expect(crop).toEqual({ x: 300, y: 100, width: 300, height: 400 });
    for (let rotation = 90; rotation < 360; rotation += 90) {
        crop = rotateImageCrop(crop, rotatedImageSize(landscape, rotation));
    }
    expect(crop).toEqual(original);
});
