import exifr from "exifr";

const HEIC_MIME_TYPES = new Set(["image/heic", "image/heif"]);

export async function extractExifDate(file: File): Promise<number | null> {
    try {
        const exif = (await exifr.parse(file, {
            pick: ["DateTimeOriginal", "CreateDate", "ModifyDate"],
        })) as
            | Partial<
                  Record<
                      "DateTimeOriginal" | "CreateDate" | "ModifyDate",
                      Date | string | number
                  >
              >
            | undefined;
        if (exif?.DateTimeOriginal) {
            return new Date(exif.DateTimeOriginal).getTime();
        }
        if (exif?.CreateDate) {
            return new Date(exif.CreateDate).getTime();
        }
        if (exif?.ModifyDate) {
            return new Date(exif.ModifyDate).getTime();
        }
    } catch {
        // EXIF extraction failed, that's fine
    }
    return null;
}

function isHeicLike(mimeType: string | undefined, fileName: string): boolean {
    const normalizedName = fileName.toLowerCase();
    return (
        HEIC_MIME_TYPES.has(mimeType ?? "") ||
        normalizedName.endsWith(".heic") ||
        normalizedName.endsWith(".heif")
    );
}

export async function normalizeImportedImageBlob(
    blob: Blob,
    fileName: string,
): Promise<Blob> {
    if (!isHeicLike(blob.type, fileName)) {
        return blob;
    }

    const heic2any = (await import("heic2any")).default;
    const converted = await heic2any({
        blob,
        toType: "image/jpeg",
        quality: 0.92,
    });
    const jpegBlob = Array.isArray(converted) ? converted[0]! : converted;

    if (jpegBlob.type === "image/jpeg") {
        return jpegBlob;
    }

    return new Blob([jpegBlob], { type: "image/jpeg" });
}

export async function createThumbnail(
    img: HTMLImageElement,
    maxSize: number,
): Promise<Blob> {
    const canvas = document.createElement("canvas");
    let w = img.naturalWidth;
    let h = img.naturalHeight;

    if (w > h) {
        if (w > maxSize) {
            h = Math.round((h * maxSize) / w);
            w = maxSize;
        }
    } else {
        if (h > maxSize) {
            w = Math.round((w * maxSize) / h);
            h = maxSize;
        }
    }

    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d")!;
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(img, 0, 0, w, h);

    return new Promise((resolve) => {
        canvas.toBlob((blob) => resolve(blob!), "image/jpeg", 0.85);
    });
}
