import { lowercaseExtension } from "ente-base/file-name";
import { extractExif } from "ente-gallery/services/exif";
import { isHEICExtension } from "ente-media/formats";
import { heicToJPEG } from "ente-media/heic-convert";
import { scaledImageDimensions } from "ente-media/image";

const HEIC_MIME_TYPES = new Set(["image/heic", "image/heif"]);

export async function extractExifDate(file: File): Promise<number | null> {
    try {
        const { creationDate } = await extractExif(file);
        return creationDate ? Math.round(creationDate.timestamp / 1000) : null;
    } catch {
        return null;
    }
}

function isHeicLike(mimeType: string | undefined, fileName: string): boolean {
    return (
        HEIC_MIME_TYPES.has(mimeType ?? "") ||
        isHEICExtension(lowercaseExtension(fileName) ?? "")
    );
}

export async function normalizeImportedImageBlob(
    blob: Blob,
    fileName: string,
): Promise<Blob> {
    if (!isHeicLike(blob.type, fileName)) {
        return blob;
    }

    return heicToJPEG(blob);
}

export async function createThumbnail(
    img: HTMLImageElement,
    maxSize: number,
): Promise<Blob> {
    const canvas = document.createElement("canvas");
    const { width, height } = scaledImageDimensions(
        img.naturalWidth,
        img.naturalHeight,
        maxSize,
    );
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d")!;
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(img, 0, 0, width, height);

    return new Promise((resolve) => {
        canvas.toBlob((blob) => resolve(blob!), "image/jpeg", 0.85);
    });
}
