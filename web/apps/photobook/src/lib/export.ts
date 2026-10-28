import JSZip from "jszip";
import { BOOK_SIZE_MM } from "./bookFormats";
import { getPhotoBlob } from "./db";
import { createPdfX4, renderCanvasToFogra39Jpeg } from "./pdfx";
import {
    CAPTION_FONT_WEIGHT,
    CENTER_TEXT_FONT_WEIGHT,
    getBrandingLayout,
    getCaptionLayout,
    getCenterTextLayout,
    getInterFont,
    getOutfitFont,
    getTextBlockLayout,
    SAFE_AREA,
    TEXT_LINE_HEIGHT,
} from "./printLayout";
import { preparePrintExport, type PrintSelection } from "./printProducts";
import type { BookPage } from "./types";

const DPI = 300;
const MM_PER_INCH = 25.4;

interface RenderSize {
    widthMm: number;
    heightMm: number;
    widthPx: number;
    heightPx: number;
}

function mmToPx(mm: number): number {
    return Math.round((mm / MM_PER_INCH) * DPI);
}

function getPageRenderSize(): RenderSize {
    const sizePx = mmToPx(BOOK_SIZE_MM);
    return {
        widthMm: BOOK_SIZE_MM,
        heightMm: BOOK_SIZE_MM,
        widthPx: sizePx,
        heightPx: sizePx,
    };
}

async function loadImage(src: string): Promise<HTMLImageElement> {
    return new Promise((resolve, reject) => {
        const img = new Image();
        img.crossOrigin = "anonymous";
        img.onload = () => resolve(img);
        img.onerror = reject;
        img.src = src;
    });
}

function createPhotoUrlResolver() {
    const cache = new Map<string, string>();

    return {
        resolve: async (photoId: string): Promise<string | null> => {
            if (cache.has(photoId)) return cache.get(photoId)!;
            const blob = await getPhotoBlob(photoId);
            if (!blob) return null;
            const url = URL.createObjectURL(blob);
            cache.set(photoId, url);
            return url;
        },
        revokeAll() {
            cache.forEach((url) => URL.revokeObjectURL(url));
            cache.clear();
        },
    };
}

export async function renderPageToCanvas(
    page: BookPage,
    resolvePhotoUrl: (photoId: string) => Promise<string | null>,
    width: number,
    height: number,
    isBackCover = false,
    isFrontCover = false,
): Promise<HTMLCanvasElement> {
    await document.fonts.ready;
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d")!;

    // White background
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, width, height);

    // Draw photo slots
    for (const slot of page.slots) {
        if (!slot.photoId) continue;
        const url = await resolvePhotoUrl(slot.photoId);
        if (!url)
            throw new Error(
                "A photo is missing. Re-import your photos before downloading.",
            );

        try {
            const img = await loadImage(url);

            const sx = (slot.x / 100) * width;
            const sy = (slot.y / 100) * height;
            const sw = (slot.width / 100) * width;
            const sh = (slot.height / 100) * height;

            ctx.save();
            ctx.beginPath();
            ctx.rect(sx, sy, sw, sh);
            ctx.clip();

            // Calculate crop/fit
            const imgAspect = img.naturalWidth / img.naturalHeight;
            const slotAspect = sw / sh;

            let drawW: number, drawH: number;
            if (imgAspect > slotAspect) {
                // Image wider than slot - fit height, crop width
                drawH = sh * slot.cropZoom;
                drawW = drawH * imgAspect;
            } else {
                // Image taller than slot - fit width, crop height
                drawW = sw * slot.cropZoom;
                drawH = drawW / imgAspect;
            }

            const drawX = sx + (sw - drawW) * slot.cropX;
            const drawY = sy + (sh - drawH) * slot.cropY;

            ctx.drawImage(img, drawX, drawY, drawW, drawH);
            ctx.restore();
        } catch {
            throw new Error(
                "A photo could not be rendered. Re-import your photos before downloading.",
            );
        }
    }

    // Fit page text and captions to the same rectangles used by the editor.
    const centerText = getCenterTextLayout(page);
    for (const position of ["center", "top", "bottom"] as const) {
        if (position === "bottom" && isBackCover) continue;
        const text =
            position === "center"
                ? page.centerText
                : position === "top"
                  ? page.topCaption
                  : page.bottomCaption;
        const layout =
            position === "center"
                ? centerText
                : getCaptionLayout(page, position, isFrontCover);
        if (!text || !layout) continue;
        ctx.save();
        ctx.beginPath();
        ctx.rect(
            (layout.x / 100) * width,
            (layout.y / 100) * height,
            (layout.width / 100) * width,
            (layout.height / 100) * height,
        );
        ctx.clip();
        ctx.fillStyle = "#2a2a2a";
        const isTitle = position === "center" || isFrontCover;
        const fontFamily = isTitle ? getOutfitFont() : getInterFont();
        const fontWeight = isTitle
            ? CENTER_TEXT_FONT_WEIGHT
            : CAPTION_FONT_WEIGHT;
        ctx.font = `${fontWeight} ${(layout.fontSize / 100) * height}px ${fontFamily}, sans-serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        const lines = position === "center" ? centerText!.lines : [text];
        const lineHeight =
            layout.fontSize *
            (position === "center" ? centerText!.lineHeight : TEXT_LINE_HEIGHT);
        const startY =
            layout.y + (layout.height - lines.length * lineHeight) / 2;
        lines.forEach((line, index) => {
            ctx.fillText(
                line,
                width / 2,
                ((startY + (index + 0.5) * lineHeight) / 100) * height,
            );
        });
        ctx.restore();
    }

    if (isBackCover) {
        // Draw centered Ente logo on back cover
        try {
            const logo = await loadImage("/ente-branding.svg");
            const layout = getBrandingLayout(
                logo.naturalWidth / logo.naturalHeight,
            );

            ctx.imageSmoothingEnabled = true;
            ctx.imageSmoothingQuality = "high";
            ctx.drawImage(
                logo,
                (layout.x / 100) * width,
                (layout.y / 100) * height,
                (layout.width / 100) * width,
                (layout.height / 100) * height,
            );
        } catch {
            throw new Error(
                "The back-cover logo could not be loaded. Please try downloading again.",
            );
        }
    }

    // Draw text blocks
    for (const block of page.textBlocks) {
        if (!block.text) continue;
        const layout = getTextBlockLayout(block);
        const bx = (layout.x / 100) * width;
        const by = (layout.y / 100) * height;
        const fontSize = height * (layout.fontSize / 100);
        const color = block.color ?? "#555555";
        const rotation = layout.rotation;

        ctx.save();
        ctx.beginPath();
        ctx.rect(
            (SAFE_AREA.x / 100) * width,
            (SAFE_AREA.y / 100) * height,
            (SAFE_AREA.width / 100) * width,
            (SAFE_AREA.height / 100) * height,
        );
        ctx.clip();
        if (rotation) {
            ctx.translate(bx, by);
            ctx.rotate((rotation * Math.PI) / 180);
            ctx.translate(-bx, -by);
        }

        ctx.fillStyle = color;
        ctx.font = `bold ${fontSize}px ${getInterFont()}, sans-serif`;
        ctx.textAlign = "left";
        ctx.textBaseline = "middle";

        const lines = layout.lines;
        const lineHeight = fontSize * TEXT_LINE_HEIGHT;
        for (let li = 0; li < lines.length; li++) {
            ctx.fillText(
                lines[li]!,
                bx + (layout.padding / 100) * width,
                by + (li + 0.5) * lineHeight,
            );
        }

        ctx.textBaseline = "alphabetic";
        ctx.restore();
    }

    return canvas;
}

function pdfBytesToBlob(pdfBytes: Uint8Array): Blob {
    const pdfArrayBuffer = new ArrayBuffer(pdfBytes.byteLength);
    new Uint8Array(pdfArrayBuffer).set(pdfBytes);
    return new Blob([pdfArrayBuffer], { type: "application/pdf" });
}

export async function exportPdfX4Pages(
    inputPages: BookPage[],
    selection: PrintSelection,
    onProgress?: (pct: number) => void,
): Promise<Blob> {
    const pages = preparePrintExport(inputPages, selection);
    const pageSize = getPageRenderSize();
    const resolver = createPhotoUrlResolver();
    try {
        const pageJpegs: Uint8Array[] = [];

        for (const [i, page] of pages.entries()) {
            const canvas = await renderPageToCanvas(
                page,
                resolver.resolve,
                pageSize.widthPx,
                pageSize.heightPx,
                i === pages.length - 1,
                i === 0,
            );

            pageJpegs.push(await renderCanvasToFogra39Jpeg(canvas));
            onProgress?.(Math.round(((i + 1) / pages.length) * 95));
            // Give React and the browser a turn to paint progress between expensive pages.
            await new Promise<void>((resolve) => setTimeout(resolve, 0));
        }

        const pdfBytes = await createPdfX4(pageJpegs, {
            widthMm: pageSize.widthMm,
            heightMm: pageSize.heightMm,
            widthPx: pageSize.widthPx,
            heightPx: pageSize.heightPx,
        });
        onProgress?.(100);
        return pdfBytesToBlob(pdfBytes);
    } finally {
        resolver.revokeAll();
    }
}

export async function exportPngPagesZip(
    inputPages: BookPage[],
    selection: PrintSelection,
    onProgress?: (pct: number) => void,
): Promise<Blob> {
    const pages = preparePrintExport(inputPages, selection);
    const pageSize = getPageRenderSize();
    const resolver = createPhotoUrlResolver();
    try {
        const zip = new JSZip();

        for (const [i, page] of pages.entries()) {
            const canvas = await renderPageToCanvas(
                page,
                resolver.resolve,
                pageSize.widthPx,
                pageSize.heightPx,
                i === pages.length - 1,
                i === 0,
            );

            const blob = await new Promise<Blob>((resolve) =>
                canvas.toBlob((b) => resolve(b!), "image/png"),
            );

            const pageNum = String(i + 1).padStart(3, "0");
            zip.file(`page_${pageNum}.png`, blob);

            onProgress?.(Math.round(((i + 1) / pages.length) * 100));
        }

        return await zip.generateAsync({ type: "blob" });
    } finally {
        resolver.revokeAll();
    }
}

export function downloadBlob(blob: Blob, filename: string) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}
