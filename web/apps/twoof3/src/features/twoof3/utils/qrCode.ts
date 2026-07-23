import encodeQR from "qr";

export interface QrModule {
    finder: boolean;
    x: number;
    y: number;
}

export interface QrSvgData {
    modules: QrModule[];
    viewBoxSize: number;
}

const QR_BORDER_MODULES = 4;

let decodeQrPromise: Promise<
    (typeof import("qr/decode.js"))["default"]
> | null = null;

const loadDecodeQr = () => {
    decodeQrPromise ??= import("qr/decode.js")
        .then(({ default: decodeQR }) => decodeQR)
        .catch((error: unknown) => {
            decodeQrPromise = null;
            throw error;
        });

    return decodeQrPromise;
};

interface DecodableImage {
    data: Uint8ClampedArray | number[];
    height: number;
    width: number;
}

const isFinderModule = (x: number, y: number, size: number) => {
    const inTopBand = y < 7;
    const inBottomBand = y >= size - 7;
    const inLeftBand = x < 7;
    const inRightBand = x >= size - 7;

    return (
        (inTopBand && inLeftBand) ||
        (inTopBand && inRightBand) ||
        (inBottomBand && inLeftBand)
    );
};

export const createQrSvgData = (value: string): QrSvgData | null => {
    try {
        const qr = encodeQR(value, "raw", { border: 1, ecc: "medium" });
        const modules: QrModule[] = [];

        for (let y = 0; y < qr.length; y++) {
            for (let x = 0; x < qr[y]!.length; x++) {
                if (!qr[y]![x]) continue;
                modules.push({
                    finder: isFinderModule(x, y, qr.length),
                    x: x + QR_BORDER_MODULES,
                    y: y + QR_BORDER_MODULES,
                });
            }
        }

        return { modules, viewBoxSize: qr.length + QR_BORDER_MODULES * 2 };
    } catch {
        return null;
    }
};

interface DrawableImage {
    dispose: () => void;
    height: number;
    source: CanvasImageSource;
    width: number;
}

const loadImageFromFile = (file: File) =>
    new Promise<DrawableImage>((resolve, reject) => {
        const objectUrl = URL.createObjectURL(file);
        const image = new Image();

        image.onload = () => {
            resolve({
                dispose: () => URL.revokeObjectURL(objectUrl),
                height: image.naturalHeight,
                source: image,
                width: image.naturalWidth,
            });
        };
        image.onerror = () => {
            URL.revokeObjectURL(objectUrl);
            reject(new Error("Could not read that image."));
        };
        image.src = objectUrl;
    });

const loadDrawableFromFile = async (file: File): Promise<DrawableImage> => {
    if (typeof createImageBitmap === "function") {
        try {
            const bitmap = await createImageBitmap(file);
            return {
                dispose: () => bitmap.close(),
                height: bitmap.height,
                source: bitmap,
                width: bitmap.width,
            };
        } catch {
            // Fall through to HTMLImageElement decoding when bitmap decode fails.
        }
    }

    return loadImageFromFile(file);
};

const imageDataFromFile = async (file: File) => {
    const drawable = await loadDrawableFromFile(file);
    const canvas = document.createElement("canvas");
    canvas.width = drawable.width;
    canvas.height = drawable.height;

    const context = canvas.getContext("2d");
    if (!context) {
        drawable.dispose();
        throw new Error("Could not read that image.");
    }

    try {
        context.drawImage(drawable.source, 0, 0, canvas.width, canvas.height);
        return context.getImageData(0, 0, canvas.width, canvas.height);
    } finally {
        drawable.dispose();
    }
};

const cropImage = (
    image: DecodableImage,
    leftRatio: number,
    topRatio: number,
    widthRatio: number,
    heightRatio: number,
): DecodableImage | null => {
    const left = Math.max(0, Math.floor(image.width * leftRatio));
    const top = Math.max(0, Math.floor(image.height * topRatio));
    const width = Math.min(
        image.width - left,
        Math.floor(image.width * widthRatio),
    );
    const height = Math.min(
        image.height - top,
        Math.floor(image.height * heightRatio),
    );

    if (width < 64 || height < 64) return null;

    const data = new Uint8ClampedArray(width * height * 4);
    for (let row = 0; row < height; row++) {
        const sourceOffset = ((top + row) * image.width + left) * 4;
        const targetOffset = row * width * 4;
        data.set(
            image.data.slice(sourceOffset, sourceOffset + width * 4),
            targetOffset,
        );
    }

    return { data, height, width };
};

const decodeQrImage = async (image: DecodableImage) => {
    const decodeQR = await loadDecodeQr();
    const attempts: {
        image: DecodableImage;
        options?: { cropToSquare?: boolean };
    }[] = [{ image, options: { cropToSquare: false } }, { image }];
    const cardLikeCrops = [
        [0.086, 0.213, 0.829, 0.591],
        [0.135, 0.238, 0.73, 0.49],
        [0.16, 0.255, 0.68, 0.52],
    ] as const;
    for (const crop of cardLikeCrops) {
        const [leftRatio, topRatio, widthRatio, heightRatio] = crop;
        const cropped = cropImage(
            image,
            leftRatio,
            topRatio,
            widthRatio,
            heightRatio,
        );
        if (!cropped) continue;
        attempts.push(
            { image: cropped, options: { cropToSquare: false } },
            { image: cropped },
        );
    }

    let lastError: unknown = null;
    for (const attempt of attempts) {
        try {
            return decodeQR(attempt.image, attempt.options).trim();
        } catch (error) {
            lastError = error;
        }
    }

    throw lastError instanceof Error
        ? lastError
        : new Error("Could not read that QR code.");
};

export const decodeQrFromFile = async (file: File) => {
    const imageData = await imageDataFromFile(file);
    return decodeQrImage(imageData);
};
