import log from "ente-base/log";
import * as ffmpeg from "ente-gallery/services/ffmpeg";
import { FileType, type FileTypeInfo } from "ente-media/file-type";
import { isHEICExtension } from "ente-media/formats";
import { heicToJPEG } from "ente-media/heic-convert";
import { scaledImageDimensions } from "ente-media/image";
import { withTimeout } from "ente-utils/promise";

const maxThumbnailDimension = 720;
const maxThumbnailSize = 100 * 1024;

// Unsupported image formats may never fire a load event.
const canvasThumbnailGenerationTimeout = 30 * 1000;

export const generateThumbnailWeb = async (
    blob: Blob,
    fileTypeInfo: FileTypeInfo,
): Promise<Uint8Array<ArrayBuffer>> =>
    fileTypeInfo.fileType == FileType.image
        ? await generateImageThumbnailWeb(blob, fileTypeInfo)
        : await generateVideoThumbnailWeb(blob);

const generateImageThumbnailWeb = async (
    blob: Blob,
    { extension }: FileTypeInfo,
) => {
    if (isHEICExtension(extension)) {
        log.debug(() => `Pre-converting HEIC to JPEG for thumbnail generation`);
        blob = await heicToJPEG(blob);
    }

    return generateImageThumbnailUsingCanvas(blob);
};

const generateImageThumbnailUsingCanvas = async (blob: Blob) => {
    const canvas = document.createElement("canvas");
    const canvasCtx = canvas.getContext("2d")!;

    const imageURL = URL.createObjectURL(blob);
    await withTimeout(
        new Promise((resolve, reject) => {
            const image = new Image();
            image.setAttribute("src", imageURL);
            image.onload = () => {
                try {
                    URL.revokeObjectURL(imageURL);
                    const { width, height } = scaledImageDimensions(
                        image.width,
                        image.height,
                        maxThumbnailDimension,
                    );
                    canvas.width = width;
                    canvas.height = height;
                    canvasCtx.drawImage(image, 0, 0, width, height);
                    resolve(undefined);
                } catch (e: unknown) {
                    // eslint-disable-next-line @typescript-eslint/prefer-promise-reject-errors
                    reject(e);
                }
            };
        }),
        canvasThumbnailGenerationTimeout,
    );

    return await compressedJPEGData(canvas);
};

const compressedJPEGData = async (
    canvas: HTMLCanvasElement,
): Promise<Uint8Array<ArrayBuffer>> => {
    let blob: Blob | undefined | null;
    let prevSize = Number.MAX_SAFE_INTEGER;
    let quality = 0.7;

    do {
        if (blob) prevSize = blob.size;
        blob = await new Promise((resolve) => {
            canvas.toBlob((blob) => resolve(blob), "image/jpeg", quality);
        });
        quality -= 0.1;
    } while (
        quality >= 0.5 &&
        blob &&
        blob.size > maxThumbnailSize &&
        percentageSizeDiff(blob.size, prevSize) >= 10
    );

    return new Uint8Array(await blob!.arrayBuffer());
};

const percentageSizeDiff = (
    newThumbnailSize: number,
    oldThumbnailSize: number,
) => ((oldThumbnailSize - newThumbnailSize) * 100) / oldThumbnailSize;

const generateVideoThumbnailWeb = async (blob: Blob) => {
    try {
        return await ffmpeg.generateVideoThumbnailWeb(blob);
    } catch (e) {
        log.error(
            `Failed to generate video thumbnail using the Wasm FFmpeg web worker, will fallback to canvas`,
            e,
        );
        return generateVideoThumbnailUsingCanvas(blob);
    }
};

const generateVideoThumbnailUsingCanvas = async (blob: Blob) => {
    const canvas = document.createElement("canvas");
    const canvasCtx = canvas.getContext("2d")!;

    const videoURL = URL.createObjectURL(blob);
    await withTimeout(
        new Promise((resolve, reject) => {
            const video = document.createElement("video");
            video.preload = "metadata";
            video.src = videoURL;
            video.addEventListener("loadeddata", () => {
                try {
                    URL.revokeObjectURL(videoURL);
                    const { width, height } = scaledImageDimensions(
                        video.videoWidth,
                        video.videoHeight,
                        maxThumbnailDimension,
                    );
                    canvas.width = width;
                    canvas.height = height;
                    canvasCtx.drawImage(video, 0, 0, width, height);
                    resolve(undefined);
                } catch (e) {
                    // eslint-disable-next-line @typescript-eslint/prefer-promise-reject-errors
                    reject(e);
                }
            });
        }),
        canvasThumbnailGenerationTimeout,
    );

    return await compressedJPEGData(canvas);
};

export const fallbackThumbnail = (): Uint8Array<ArrayBuffer> =>
    Uint8Array.from(atob(blackThumbnailB64), (c) => c.charCodeAt(0));

const blackThumbnailB64 =
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAEBAQEBAQEB" +
    "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQ" +
    "EBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARC" +
    "ACWASwDAREAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUF" +
    "BAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk" +
    "6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztL" +
    "W2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAA" +
    "AAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVY" +
    "nLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImK" +
    "kpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oAD" +
    "AMBAAIRAxEAPwD/AD/6ACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKA" +
    "CgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACg" +
    "AoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKAC" +
    "gAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAo" +
    "AKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACg" +
    "AoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACg" +
    "AoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKA" +
    "CgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKA" +
    "CgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoA" +
    "KACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACg" +
    "AoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAo" +
    "AKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKA" +
    "CgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAK" +
    "ACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoA" +
    "KACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAo" +
    "AKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAo" +
    "AKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgAoAKACgD/9k=";
