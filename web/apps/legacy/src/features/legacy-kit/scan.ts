import type { PDFDocumentProxy, PDFPageProxy } from "pdfjs-dist";

type DecodeQR = (typeof import("qr/decode.js"))["default"];

const legacyKitShareMetadataPrefix = "ente-legacy-kit-share-v1:";
const legacyKitBundleMetadataPrefix = "ente-legacy-kit-shares-v1:";
const maxTextFileBytes = 64 * 1024;
const maxPDFFileBytes = 32 * 1024 * 1024;
const maxImageFileBytes = 32 * 1024 * 1024;
const maxInputImagePixels = 64 * 1024 * 1024;
const maxInputImageSide = 16_000;
const maxCanvasPixels = 6 * 1024 * 1024;
const maxCanvasSide = 2_400;
const maxPDFPagesToScan = 5;
const maxPDFTextChars = 128 * 1024;
const pdfFallbackTimeoutMS = 15_000;
const pdfPageTimeoutMS = 5_000;

const tooLargeMessage =
    "This recovery sheet is too large to scan safely. Try the original PDF or a smaller, clearer photo.";

interface DecodableImage {
    data: Uint8ClampedArray | number[];
    height: number;
    width: number;
}

interface ImageDimensions {
    height: number;
    width: number;
}

interface DrawableImage {
    dispose: () => void;
    height: number;
    source: CanvasImageSource;
    width: number;
}

let decodeQrPromise: Promise<DecodeQR> | undefined;

const loadDecodeQr = () =>
    (decodeQrPromise ??= import("qr/decode.js")
        .then(({ default: decodeQR }) => decodeQR)
        .catch((error: unknown) => {
            decodeQrPromise = undefined;
            throw error;
        }));

const isPDF = (file: File) =>
    file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf");

const isPlainText = (file: File) =>
    file.type.startsWith("text/") || file.name.toLowerCase().endsWith(".txt");

const withTimeout = async <T>(
    promise: Promise<T>,
    timeoutMS: number,
    message: string,
) => {
    let timeout: ReturnType<typeof setTimeout> | undefined;
    try {
        return await Promise.race([
            promise,
            new Promise<never>((_, reject) => {
                timeout = setTimeout(
                    () => reject(new Error(message)),
                    timeoutMS,
                );
            }),
        ]);
    } finally {
        if (timeout) clearTimeout(timeout);
    }
};

const assertFileSize = (file: File, maxBytes: number) => {
    if (file.size > maxBytes) {
        throw new Error(tooLargeMessage);
    }
};

const assertImageDimensions = ({ height, width }: ImageDimensions) => {
    if (
        width <= 0 ||
        height <= 0 ||
        width > maxInputImageSide ||
        height > maxInputImageSide ||
        width * height > maxInputImagePixels
    ) {
        throw new Error(tooLargeMessage);
    }
};

const imageOutputDimensions = ({ height, width }: ImageDimensions) => {
    const scale = Math.min(
        1,
        maxCanvasSide / Math.max(width, height),
        Math.sqrt(maxCanvasPixels / (width * height)),
    );
    return {
        height: Math.max(1, Math.floor(height * scale)),
        width: Math.max(1, Math.floor(width * scale)),
    };
};

const imageBitmapOptions = (
    dimensions: ImageDimensions,
): ImageBitmapOptions => {
    const { height, width } = imageOutputDimensions(dimensions);
    return dimensions.width >= dimensions.height
        ? { resizeQuality: "high", resizeWidth: width }
        : { resizeHeight: height, resizeQuality: "high" };
};

const byteAt = (bytes: Uint8Array, offset: number) => bytes[offset] ?? 0;

const hasBytes = (bytes: Uint8Array, offset: number, values: number[]) =>
    values.every((value, index) => byteAt(bytes, offset + index) === value);

const hasASCII = (bytes: Uint8Array, offset: number, value: string) => {
    for (let index = 0; index < value.length; index++) {
        if (byteAt(bytes, offset + index) !== value.charCodeAt(index)) {
            return false;
        }
    }
    return true;
};

const readUInt24LE = (bytes: Uint8Array, offset: number) =>
    byteAt(bytes, offset) |
    (byteAt(bytes, offset + 1) << 8) |
    (byteAt(bytes, offset + 2) << 16);

const jpegStartOfFrameMarkers = new Set([
    0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce,
    0xcf,
]);

const jpegDimensions = (
    bytes: Uint8Array,
    view: DataView,
): ImageDimensions | undefined => {
    if (!hasBytes(bytes, 0, [0xff, 0xd8])) return undefined;

    let offset = 2;
    while (offset + 3 < bytes.length) {
        while (byteAt(bytes, offset) === 0xff) offset += 1;
        const marker = byteAt(bytes, offset);
        offset += 1;

        if (marker === 0xda || marker === 0xd9) break;
        if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
        if (offset + 2 > bytes.length) break;

        const segmentLength = view.getUint16(offset, false);
        if (segmentLength < 2) break;
        if (jpegStartOfFrameMarkers.has(marker)) {
            if (offset + 7 > bytes.length) break;
            return {
                height: view.getUint16(offset + 3, false),
                width: view.getUint16(offset + 5, false),
            };
        }
        offset += segmentLength;
    }

    throw new Error("Could not read that image.");
};

const webPDimensions = (
    bytes: Uint8Array,
    view: DataView,
): ImageDimensions | undefined => {
    if (
        bytes.length < 20 ||
        !hasASCII(bytes, 0, "RIFF") ||
        !hasASCII(bytes, 8, "WEBP")
    ) {
        return undefined;
    }

    if (bytes.length >= 30 && hasASCII(bytes, 12, "VP8X")) {
        return {
            height: 1 + readUInt24LE(bytes, 27),
            width: 1 + readUInt24LE(bytes, 24),
        };
    }
    if (
        bytes.length >= 30 &&
        hasASCII(bytes, 12, "VP8 ") &&
        hasBytes(bytes, 23, [0x9d, 0x01, 0x2a])
    ) {
        return {
            height: view.getUint16(28, true) & 0x3fff,
            width: view.getUint16(26, true) & 0x3fff,
        };
    }
    if (
        bytes.length >= 25 &&
        hasASCII(bytes, 12, "VP8L") &&
        byteAt(bytes, 20) === 0x2f
    ) {
        return {
            height:
                1 +
                (((byteAt(bytes, 24) & 0x0f) << 10) |
                    (byteAt(bytes, 23) << 2) |
                    ((byteAt(bytes, 22) & 0xc0) >> 6)),
            width: 1 + (((byteAt(bytes, 22) & 0x3f) << 8) | byteAt(bytes, 21)),
        };
    }

    throw new Error("Could not read that image.");
};

const isoBMFFContainerBoxes = new Set([
    "meta",
    "iprp",
    "ipco",
    "moov",
    "trak",
    "mdia",
    "minf",
    "stbl",
]);

const isoBMFFDimensions = (
    bytes: Uint8Array,
    view: DataView,
): ImageDimensions | undefined => {
    if (bytes.length < 16 || !hasASCII(bytes, 4, "ftyp")) return undefined;

    const scanBoxes = (
        start: number,
        end: number,
        depth: number,
    ): ImageDimensions | undefined => {
        if (depth > 8) return undefined;
        let offset = start;
        while (offset + 8 <= end) {
            let boxSize = view.getUint32(offset, false);
            const boxTypeOffset = offset + 4;
            let contentOffset = offset + 8;
            if (boxSize === 1) {
                if (
                    offset + 16 > end ||
                    view.getUint32(offset + 8, false) > 0
                ) {
                    return undefined;
                }
                boxSize = view.getUint32(offset + 12, false);
                contentOffset = offset + 16;
            } else if (boxSize === 0) {
                boxSize = end - offset;
            }

            if (boxSize < contentOffset - offset || offset + boxSize > end) {
                return undefined;
            }

            const boxType = String.fromCharCode(
                byteAt(bytes, boxTypeOffset),
                byteAt(bytes, boxTypeOffset + 1),
                byteAt(bytes, boxTypeOffset + 2),
                byteAt(bytes, boxTypeOffset + 3),
            );
            const boxEnd = offset + boxSize;
            if (boxType === "ispe" && contentOffset + 12 <= boxEnd) {
                return {
                    height: view.getUint32(contentOffset + 8, false),
                    width: view.getUint32(contentOffset + 4, false),
                };
            }

            const childOffset =
                boxType === "meta" ? contentOffset + 4 : contentOffset;
            if (isoBMFFContainerBoxes.has(boxType) && childOffset < boxEnd) {
                const dimensions = scanBoxes(childOffset, boxEnd, depth + 1);
                if (dimensions) return dimensions;
            }
            offset = boxEnd;
        }
        return undefined;
    };

    return scanBoxes(0, bytes.length, 0);
};

const imageDimensionsFromBytes = (bytes: Uint8Array) => {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

    if (
        bytes.length >= 24 &&
        hasBytes(bytes, 0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    ) {
        return {
            height: view.getUint32(20, false),
            width: view.getUint32(16, false),
        };
    }
    if (
        bytes.length >= 10 &&
        (hasASCII(bytes, 0, "GIF87a") || hasASCII(bytes, 0, "GIF89a"))
    ) {
        return {
            height: view.getUint16(8, true),
            width: view.getUint16(6, true),
        };
    }
    if (bytes.length >= 26 && hasASCII(bytes, 0, "BM")) {
        return {
            height: Math.abs(view.getInt32(22, true)),
            width: view.getInt32(18, true),
        };
    }

    return (
        jpegDimensions(bytes, view) ??
        webPDimensions(bytes, view) ??
        isoBMFFDimensions(bytes, view)
    );
};

// Keep this before browser image decode; compressed images can expand to huge bitmaps.
const imageDimensionsFromFile = async (file: File) => {
    const bytes = new Uint8Array(await file.arrayBuffer());
    const dimensions = imageDimensionsFromBytes(bytes);
    if (!dimensions) throw new Error("Could not read that image.");
    assertImageDimensions(dimensions);
    return dimensions;
};

const findJsonObject = (value: string) => {
    const start = value.indexOf('{"pv"');
    if (start < 0) return undefined;

    let depth = 0;
    let inString = false;
    let escaped = false;

    for (let index = start; index < value.length; index++) {
        const char = value[index];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (char === "\\") {
            escaped = true;
            continue;
        }
        if (char === '"') {
            inString = !inString;
            continue;
        }
        if (inString) {
            continue;
        }
        if (char === "{") {
            depth += 1;
        } else if (char === "}") {
            depth -= 1;
            if (depth === 0) {
                return value.slice(start, index + 1);
            }
        }
    }

    return undefined;
};

const markerPayload = (value: string, marker: string) => {
    const markerStart = value.indexOf(marker);
    if (markerStart < 0) return undefined;

    const payloadStart = markerStart + marker.length;
    const payload = /^[A-Za-z0-9_-]+/.exec(value.slice(payloadStart))?.[0];
    return payload || undefined;
};

const decodeBase64URLUTF8 = (value: string) => {
    const base64 = value
        .replaceAll("-", "+")
        .replaceAll("_", "/")
        .padEnd(Math.ceil(value.length / 4) * 4, "=");
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index++) {
        bytes[index] = binary.charCodeAt(index);
    }
    return new TextDecoder().decode(bytes);
};

const codeFromPDFMetadata = (bytes: Uint8Array) => {
    const pdfText = new TextDecoder("latin1").decode(bytes);
    const sharePayload = markerPayload(pdfText, legacyKitShareMetadataPrefix);
    if (sharePayload) {
        return decodeBase64URLUTF8(sharePayload);
    }

    const bundlePayload = markerPayload(pdfText, legacyKitBundleMetadataPrefix);
    if (!bundlePayload) return undefined;

    const payloads: unknown = JSON.parse(decodeBase64URLUTF8(bundlePayload));
    if (!Array.isArray(payloads)) {
        throw new Error("Legacy Kit PDF metadata is invalid.");
    }
    if (payloads.length === 1 && typeof payloads[0] === "string") {
        return payloads[0];
    }
    throw new Error("Choose individual Legacy Kit sheet PDFs.");
};

const loadImageFromFile = (file: File) =>
    new Promise<DrawableImage>((resolve, reject) => {
        const objectURL = URL.createObjectURL(file);
        const image = new Image();
        image.onload = () => {
            resolve({
                dispose: () => URL.revokeObjectURL(objectURL),
                height: image.naturalHeight,
                source: image,
                width: image.naturalWidth,
            });
        };
        image.onerror = () => {
            URL.revokeObjectURL(objectURL);
            reject(new Error("Could not read that image."));
        };
        image.src = objectURL;
    });

const loadDrawableFromFile = async (
    file: File,
    dimensions: ImageDimensions,
): Promise<DrawableImage> => {
    if (typeof createImageBitmap === "function") {
        try {
            const bitmap = await createImageBitmap(
                file,
                imageBitmapOptions(dimensions),
            );
            return {
                dispose: () => bitmap.close(),
                height: bitmap.height,
                source: bitmap,
                width: bitmap.width,
            };
        } catch {
            // Fall through to HTMLImageElement decoding.
        }
    }

    return loadImageFromFile(file);
};

const imageDataFromDrawable = (drawable: DrawableImage) => {
    assertImageDimensions(drawable);

    const { height, width } = imageOutputDimensions(drawable);
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    if (!context) {
        throw new Error("Could not read that image.");
    }
    context.drawImage(drawable.source, 0, 0, canvas.width, canvas.height);
    return context.getImageData(0, 0, canvas.width, canvas.height);
};

const imageDataFromFile = async (file: File) => {
    const dimensions = await imageDimensionsFromFile(file);
    const drawable = await loadDrawableFromFile(file, dimensions);
    try {
        return imageDataFromDrawable(drawable);
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
): DecodableImage | undefined => {
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
    if (width < 64 || height < 64) return undefined;

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
    const crops = [
        [0.05, 0.4, 0.48, 0.42],
        [0.07, 0.44, 0.36, 0.3],
        [0.1, 0.46, 0.3, 0.25],
        [0.08, 0.2, 0.84, 0.64],
    ] as const;
    const attempts: {
        image: DecodableImage;
        options?: { cropToSquare?: boolean };
    }[] = [{ image, options: { cropToSquare: false } }, { image }];

    for (const crop of crops) {
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

    let lastError: unknown;
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

const textFromPDF = async (pdf: PDFDocumentProxy) => {
    const chunks: string[] = [];
    let charCount = 0;
    const pageCount = Math.min(pdf.numPages, maxPDFPagesToScan);
    for (let pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
        const page = await pdf.getPage(pageNumber);
        try {
            const textContent = await withTimeout(
                page.getTextContent(),
                pdfPageTimeoutMS,
                "Could not read that PDF page.",
            );
            const pageText = textContent.items
                .map((item) => ("str" in item ? item.str : ""))
                .join("")
                .slice(0, maxPDFTextChars - charCount);
            chunks.push(pageText);
            charCount += pageText.length;
        } finally {
            page.cleanup();
        }
        if (charCount >= maxPDFTextChars) {
            break;
        }
    }
    return chunks.join("\n");
};

const pdfRenderScale = (page: PDFPageProxy) => {
    const baseViewport = page.getViewport({ scale: 1 });
    if (
        !Number.isFinite(baseViewport.width) ||
        !Number.isFinite(baseViewport.height) ||
        baseViewport.width <= 0 ||
        baseViewport.height <= 0
    ) {
        throw new Error(tooLargeMessage);
    }
    const pixelScale = Math.sqrt(
        maxCanvasPixels / (baseViewport.width * baseViewport.height),
    );
    return Math.min(
        3,
        maxCanvasSide / Math.max(baseViewport.width, baseViewport.height),
        pixelScale,
    );
};

const renderPDFPage = async (page: PDFPageProxy) => {
    const viewport = page.getViewport({ scale: pdfRenderScale(page) });
    const width = Math.max(1, Math.ceil(viewport.width));
    const height = Math.max(1, Math.ceil(viewport.height));
    if (width * height > maxCanvasPixels) {
        throw new Error(tooLargeMessage);
    }

    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    if (!context) {
        throw new Error("Could not render that PDF.");
    }
    const renderTask = page.render({
        canvas,
        canvasContext: context,
        viewport,
    });
    try {
        await withTimeout(
            renderTask.promise,
            pdfPageTimeoutMS,
            "Could not render that PDF page.",
        );
    } catch (error) {
        renderTask.cancel();
        throw error;
    }
    return context.getImageData(0, 0, canvas.width, canvas.height);
};

const decodeQrFromPDFBytes = async (bytes: Uint8Array) => {
    const pdfjs =
        (await import("pdfjs-dist/legacy/webpack.mjs")) as unknown as typeof import("pdfjs-dist");
    const loadingTask = pdfjs.getDocument({
        data: bytes.slice(),
        disableFontFace: true,
    });
    let pdf: PDFDocumentProxy;
    try {
        pdf = await withTimeout(
            loadingTask.promise,
            pdfFallbackTimeoutMS,
            "Could not read that PDF. Download the sheet again and try the new PDF.",
        );
    } catch (error) {
        await loadingTask.destroy().catch(() => undefined);
        throw error;
    }

    try {
        let textCode: string | undefined;
        try {
            textCode = findJsonObject(await textFromPDF(pdf));
        } catch {
            // Text extraction is a fast path; scanned PDFs should still use QR rendering.
        }
        if (textCode) {
            return textCode;
        }

        const pageCount = Math.min(pdf.numPages, maxPDFPagesToScan);
        for (let pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
            const page = await pdf.getPage(pageNumber);
            try {
                return await decodeQrImage(await renderPDFPage(page));
            } catch {
                // Try the next page before surfacing a failure.
            } finally {
                page.cleanup();
            }
        }
    } finally {
        await pdf.destroy();
    }

    throw new Error("Could not find a Legacy Kit QR code in that PDF.");
};

const decodeQrFromPDF = async (file: File) => {
    assertFileSize(file, maxPDFFileBytes);
    const bytes = new Uint8Array(await file.arrayBuffer());
    const metadataCode = codeFromPDFMetadata(bytes);
    if (metadataCode) return metadataCode;
    return decodeQrFromPDFBytes(bytes);
};

export const readLegacyKitCodeFromFile = async (file: File) => {
    if (isPDF(file)) return decodeQrFromPDF(file);
    if (isPlainText(file)) {
        assertFileSize(file, maxTextFileBytes);
        const value = await file.text();
        return findJsonObject(value) ?? value.trim();
    }
    assertFileSize(file, maxImageFileBytes);
    return decodeQrImage(await imageDataFromFile(file));
};
