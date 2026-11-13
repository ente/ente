import { applyEditorFilter, editorFilterPresets } from "./ImageEditor.filters";

export interface EditorAdjustments {
    preset: string;
    brightness: number;
    contrast: number;
    saturation: number;
    blur: number;
    invert: boolean;
}

export type EditorTransform =
    | { type: "aspect-ratio"; width: number; height: number }
    | { type: "crop"; left: number; top: number; right: number; bottom: number }
    | { type: "rotate"; direction: "left" | "right" }
    | { type: "flip"; direction: "horizontal" | "vertical" };

export const editorPreviewSize = (width: number, height: number) => {
    const scale = Math.min(1, 1600 / Math.max(width, height));
    return {
        width: Math.max(1, Math.round(width * scale)),
        height: Math.max(1, Math.round(height * scale)),
    };
};

const yieldToBrowser = () =>
    new Promise<void>((resolve) => setTimeout(resolve, 0));

export const awaitLatestEditorRender = async (current: () => Promise<void>) => {
    let rendering: Promise<void>;
    do {
        rendering = current();
        await rendering;
    } while (rendering !== current());
};

export const renderEditorCanvas = async (
    canvas: HTMLCanvasElement,
    image: HTMLImageElement,
    adjustments: EditorAdjustments,
    options: {
        blurScale: number;
        sourceRect?: { x: number; y: number; width: number; height: number };
        tiled?: boolean;
        isCurrent: () => boolean;
        yieldTask?: () => Promise<void>;
    },
) => {
    const assertCurrent = () => {
        if (!options.isCurrent())
            throw new DOMException("Render cancelled", "AbortError");
    };
    assertCurrent();
    const context = canvas.getContext("2d")!;
    const { preset, brightness, contrast, saturation, blur, invert } =
        adjustments;
    const filter = `brightness(${brightness}%) contrast(${contrast}%) blur(${blur * options.blurScale}px) saturate(${saturation}%) invert(${invert ? 1 : 0})`;
    const hasAdjustments =
        brightness !== 100 ||
        contrast !== 100 ||
        saturation !== 100 ||
        blur !== 0 ||
        invert;
    context.save();
    try {
        context.filter = preset === "None" ? filter : "none";
        context.clearRect(0, 0, canvas.width, canvas.height);
        context.imageSmoothingEnabled =
            canvas.width !== image.width || canvas.height !== image.height;
        if (options.sourceRect) {
            const { x, y, width, height } = options.sourceRect;
            context.drawImage(
                image,
                x,
                y,
                width,
                height,
                0,
                0,
                canvas.width,
                canvas.height,
            );
        } else {
            context.drawImage(image, 0, 0, canvas.width, canvas.height);
        }
        if (preset === "None") return;

        const matrix = editorFilterPresets.find(
            ({ name }) => name === preset,
        )!.matrix;
        const size = options.tiled
            ? 512
            : Math.max(canvas.width, canvas.height);
        for (let y = 0; y < canvas.height; y += size) {
            for (let x = 0; x < canvas.width; x += size) {
                assertCurrent();
                const pixels = context.getImageData(
                    x,
                    y,
                    Math.min(size, canvas.width - x),
                    Math.min(size, canvas.height - y),
                );
                applyEditorFilter(pixels.data, matrix);
                context.putImageData(pixels, x, y);
                if (options.tiled)
                    await (options.yieldTask ?? yieldToBrowser)();
            }
        }
        assertCurrent();
        if (hasAdjustments) {
            context.filter = filter;
            context.globalCompositeOperation = "copy";
            context.drawImage(canvas, 0, 0);
        }
    } finally {
        context.restore();
    }
};

export const transformEditorCanvas = (
    canvas: HTMLCanvasElement,
    transform: EditorTransform,
) => {
    const output = document.createElement("canvas");
    const width = canvas.width;
    const height = canvas.height;
    let left = 0;
    let top = 0;
    let cropWidth = width;
    let cropHeight = height;
    if (transform.type === "aspect-ratio") {
        const ratio = transform.width / transform.height;
        if (width / height > ratio) left = (width - height * ratio) / 2;
        else top = (height - width / ratio) / 2;
        cropWidth = width - 2 * left;
        cropHeight = height - 2 * top;
    } else if (transform.type === "crop") {
        left = transform.left * width;
        top = transform.top * height;
        cropWidth = (transform.right - transform.left) * width;
        cropHeight = (transform.bottom - transform.top) * height;
    }
    output.width = Math.max(
        1,
        transform.type === "rotate" ? height : Math.floor(cropWidth),
    );
    output.height = Math.max(
        1,
        transform.type === "rotate" ? width : Math.floor(cropHeight),
    );
    try {
        const context = output.getContext("2d")!;
        context.imageSmoothingEnabled = false;
        if (transform.type === "rotate") {
            context.translate(output.width / 2, output.height / 2);
            context.rotate(
                transform.direction === "left" ? -Math.PI / 2 : Math.PI / 2,
            );
            context.drawImage(canvas, -width / 2, -height / 2);
        } else if (transform.type === "flip") {
            context.translate(
                transform.direction === "horizontal" ? width : 0,
                transform.direction === "vertical" ? height : 0,
            );
            context.scale(
                transform.direction === "horizontal" ? -1 : 1,
                transform.direction === "vertical" ? -1 : 1,
            );
            context.drawImage(canvas, 0, 0);
        } else {
            context.drawImage(
                canvas,
                left,
                top,
                cropWidth,
                cropHeight,
                0,
                0,
                cropWidth,
                cropHeight,
            );
        }
        canvas.width = output.width;
        canvas.height = output.height;
        canvas.getContext("2d")!.drawImage(output, 0, 0);
    } finally {
        output.width = output.height = 1;
    }
};
