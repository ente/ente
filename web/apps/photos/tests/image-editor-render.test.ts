import {
    awaitLatestEditorRender,
    editorPreviewSize,
    renderEditorCanvas,
    type EditorAdjustments,
} from "ente-new/photos/components/ImageEditor.render";
import { describe, expect, test, vi } from "vitest";

const adjustments: EditorAdjustments = {
    preset: "Carbon",
    brightness: 100,
    contrast: 100,
    saturation: 100,
    blur: 0,
    invert: false,
};

const canvasFixture = (width = 1300, height = 1100) => {
    const context = {
        filter: "none",
        save: vi.fn(),
        restore: vi.fn(),
        clearRect: vi.fn(),
        drawImage: vi.fn(),
        putImageData: vi.fn(),
        getImageData: vi.fn((_x: number, _y: number, w: number, h: number) => ({
            data: new Uint8ClampedArray(w * h * 4),
            width: w,
            height: h,
        })),
    };
    return {
        context,
        canvas: {
            width,
            height,
            getContext: () => context,
        } as unknown as HTMLCanvasElement,
        image: { width, height } as HTMLImageElement,
    };
};

describe("bounded editor rendering", () => {
    test("a 48 MP image uses a 1.92 MP preview", () => {
        expect(editorPreviewSize(8000, 6000)).toEqual({
            width: 1600,
            height: 1200,
        });
        expect(editorPreviewSize(6000, 8000)).toEqual({
            width: 1200,
            height: 1600,
        });
        expect(editorPreviewSize(640, 480)).toEqual({
            width: 640,
            height: 480,
        });
    });

    test("full-resolution preset work uses bounded tiles and yields between them", async () => {
        const { context, canvas, image } = canvasFixture();
        const yieldTask = vi.fn().mockResolvedValue(undefined);
        await renderEditorCanvas(canvas, image, adjustments, {
            blurScale: 1,
            tiled: true,
            isCurrent: () => true,
            yieldTask,
        });
        const reads = context.getImageData.mock.calls;
        expect(reads).toHaveLength(9);
        expect(reads.every(([, , w, h]) => w <= 512 && h <= 512)).toBe(true);
        expect(reads.reduce((area, [, , w, h]) => area + w * h, 0)).toBe(
            1300 * 1100,
        );
        expect(yieldTask).toHaveBeenCalledTimes(9);
        expect(context.restore).toHaveBeenCalledOnce();
    });

    test.each(["None", "Carbon"])(
        "%s thumbnails retain manual adjustments and scale blur to thumbnail size",
        async (preset) => {
            const { context, canvas, image } = canvasFixture(96, 96);
            const draws: string[] = [];
            context.drawImage.mockImplementation(() => {
                draws.push(context.filter);
            });
            const filter =
                "brightness(120%) contrast(80%) blur(0.5px) saturate(140%) invert(1)";
            await renderEditorCanvas(
                canvas,
                image,
                {
                    preset,
                    brightness: 120,
                    contrast: 80,
                    saturation: 140,
                    blur: 2,
                    invert: true,
                },
                {
                    blurScale: 96 / 384,
                    sourceRect: { x: 100, y: 0, width: 400, height: 400 },
                    isCurrent: () => true,
                },
            );
            expect(context.drawImage).toHaveBeenNthCalledWith(
                1,
                image,
                100,
                0,
                400,
                400,
                0,
                0,
                96,
                96,
            );
            if (preset === "None") {
                expect(draws).toEqual([filter]);
                expect(context.getImageData).not.toHaveBeenCalled();
            } else {
                expect(draws).toEqual(["none", filter]);
                expect(context.putImageData).toHaveBeenCalledOnce();
                expect(context.drawImage).toHaveBeenNthCalledWith(
                    2,
                    canvas,
                    0,
                    0,
                );
                expect(
                    context.putImageData.mock.invocationCallOrder[0],
                ).toBeLessThan(context.drawImage.mock.invocationCallOrder[1]!);
            }
        },
    );

    test("a cancelled render stops before reading or drawing another tile", async () => {
        const { context, canvas, image } = canvasFixture();
        let current = true;
        await expect(
            renderEditorCanvas(
                canvas,
                image,
                { ...adjustments, brightness: 120 },
                {
                    blurScale: 1,
                    tiled: true,
                    isCurrent: () => current,
                    yieldTask: () => {
                        current = false;
                        return Promise.resolve();
                    },
                },
            ),
        ).rejects.toMatchObject({ name: "AbortError" });
        expect(context.getImageData).toHaveBeenCalledOnce();
        expect(context.drawImage).toHaveBeenCalledOnce();
        expect(context.restore).toHaveBeenCalledOnce();
    });

    test("ordinary color adjustments do not read pixels back from the canvas", async () => {
        const { context, canvas, image } = canvasFixture();
        await renderEditorCanvas(
            canvas,
            image,
            { ...adjustments, preset: "None", brightness: 120 },
            { blurScale: 1, tiled: true, isCurrent: () => true },
        );
        expect(context.getImageData).not.toHaveBeenCalled();
    });

    test("a transform waits for the latest render even if it replaces a pending one", async () => {
        let finishFirst!: () => void;
        let finishLatest!: () => void;
        let current = new Promise<void>((resolve) => {
            finishFirst = resolve;
        });
        let transformed = false;
        const waiting = awaitLatestEditorRender(() => current).then(() => {
            transformed = true;
        });
        current = new Promise<void>((resolve) => {
            finishLatest = resolve;
        });
        finishFirst();
        await Promise.resolve();
        expect(transformed).toBe(false);
        finishLatest();
        await waiting;
        expect(transformed).toBe(true);
    });
});
