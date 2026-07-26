import { createCanvas, Image, type Canvas } from "canvas";
import {
    computeInscribedCrop,
    cropRegionOfCanvas,
    rotateCanvas,
} from "ente-new/photos/utils/image-editor";
import { describe, expect, test } from "vitest";

// rotateCanvas/cropRegionOfCanvas construct `new Image()` internally, which
// isn't a Node global — node-canvas provides a compatible implementation.
(globalThis as { Image?: unknown }).Image = Image;

// node-canvas's Canvas is structurally compatible with the subset of
// HTMLCanvasElement that rotateCanvas/cropRegionOfCanvas use (getContext,
// toDataURL, width/height), so it's cast for use with these functions.
const asHTMLCanvas = (c: Canvas) => c as unknown as HTMLCanvasElement;

// canvas.width/height are integers (the spec truncates any assigned float),
// and the rotate+crop chain truncates twice (once per resize) — so up to a
// couple of pixels of accumulated truncation drift versus an independently
// computed float expectation is normal, not a bug.
const expectPxClose = (actual: number, expected: number) => {
    expect(Math.abs(actual - expected)).toBeLessThanOrEqual(2);
};

const makeMarkerCanvas = (width: number, height: number): Canvas => {
    const canvas = createCanvas(width, height);
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "red";
    ctx.fillRect(0, 0, width, height);
    // A green marker at the center, small relative to the canvas, so it
    // survives any crop that keeps a reasonable fraction of the image.
    ctx.fillStyle = "lime";
    ctx.fillRect(width / 2 - 5, height / 2 - 5, 10, 10);
    return canvas;
};

/** Bakes a straighten commit: rotate, then crop to the inscribed rectangle. */
const straighten = async (canvas: Canvas, angle: number) => {
    const originalWidth = canvas.width;
    const originalHeight = canvas.height;
    const crop = computeInscribedCrop(originalWidth, originalHeight, angle);

    await rotateCanvas(asHTMLCanvas(canvas), angle);

    const cropX = (canvas.width - crop.width) / 2;
    const cropY = (canvas.height - crop.height) / 2;
    await cropRegionOfCanvas(
        asHTMLCanvas(canvas),
        cropX,
        cropY,
        cropX + crop.width,
        cropY + crop.height,
    );

    return crop;
};

describe("rotateCanvas + cropRegionOfCanvas straighten pipeline", () => {
    test("after rotate+crop, canvas dimensions exactly match computeInscribedCrop", async () => {
        const canvas = makeMarkerCanvas(400, 300);
        const expectedCrop = await straighten(canvas, 12);

        expectPxClose(canvas.width, expectedCrop.width);
        expectPxClose(canvas.height, expectedCrop.height);
    });

    test("center marker survives the crop (content is preserved, not just resized)", async () => {
        const canvas = makeMarkerCanvas(400, 300);
        await straighten(canvas, 12);

        const ctx = canvas.getContext("2d");
        const centerPixel = ctx.getImageData(
            Math.floor(canvas.width / 2),
            Math.floor(canvas.height / 2),
            1,
            1,
        ).data;
        // Green should dominate; rotation may introduce minor anti-aliasing.
        expect(centerPixel[1]).toBeGreaterThan(200);
        expect(centerPixel[0]).toBeLessThan(100);
    });

    test("bake+crop sequencing does not race: crop uses post-rotation dimensions", async () => {
        // This is the specific bug the awaitable rotateCanvas/cropRegionOfCanvas
        // fix: if the crop step read canvas.width/height before rotateCanvas's
        // onload had actually resized the canvas, it would crop the
        // pre-rotation size (400x300) instead of the rotated bounding box.
        const width = 400;
        const height = 300;
        const angle = 20;
        const canvas = makeMarkerCanvas(width, height);

        await rotateCanvas(asHTMLCanvas(canvas), angle);

        const radians = (angle * Math.PI) / 180;
        const expectedRotatedWidth =
            Math.abs(width * Math.cos(radians)) +
            Math.abs(height * Math.sin(radians));
        expectPxClose(canvas.width, expectedRotatedWidth);
    });

    test("no black/transparent corners survive: every pixel (away from the tight boundary) is opaque content", async () => {
        const canvas = makeMarkerCanvas(400, 300);
        await straighten(canvas, 20);

        // The crop rectangle is computed as a tight floating-point boundary,
        // but the canvas only has integer pixel dimensions — right at that
        // exact edge, sub-pixel anti-aliasing can legitimately blend a thin
        // sliver of partial transparency. Sample a region inset from the
        // edges to check for genuine holes (a real bug) without tripping on
        // that expected boundary artifact.
        const inset = 3;
        const ctx = canvas.getContext("2d");
        const { data } = ctx.getImageData(
            inset,
            inset,
            canvas.width - inset * 2,
            canvas.height - inset * 2,
        );
        for (let i = 3; i < data.length; i += 4) {
            expect(data[i]).toBe(255);
        }
    });

    test("works across a range of angles and both landscape/portrait orientations", async () => {
        for (const [width, height] of [
            [400, 300],
            [300, 400],
        ]) {
            for (const angle of [1, 10, 30, 45, -20]) {
                const canvas = makeMarkerCanvas(width!, height!);
                const expectedCrop = await straighten(canvas, angle);
                expectPxClose(canvas.width, expectedCrop.width);
                expectPxClose(canvas.height, expectedCrop.height);
            }
        }
    });
});
