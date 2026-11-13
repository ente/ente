import { rgbaToThumbHash, thumbHashToDataURL } from "thumbhash";

const minThumbHashBytes = 5;
const maxThumbHashBytes = 25;
const maxThumbHashBase64Length = 36;

const bytesFromBase64 = (value: string) =>
    Uint8Array.from(atob(value), (character) => character.charCodeAt(0));

const bytesToBase64 = (value: Uint8Array) =>
    btoa(String.fromCharCode(...value));

export const thumbHashDataURLFromBase64 = (hash: string | undefined) => {
    if (
        !hash ||
        hash.length > maxThumbHashBase64Length ||
        typeof atob != "function" ||
        typeof btoa != "function"
    ) {
        return undefined;
    }

    try {
        const bytes = bytesFromBase64(hash);
        if (
            bytes.length < minThumbHashBytes ||
            bytes.length > maxThumbHashBytes
        ) {
            return undefined;
        }
        return thumbHashToDataURL(bytes);
    } catch {
        return undefined;
    }
};

export const thumbHashBase64FromCanvas = (canvas: HTMLCanvasElement) => {
    const scale = Math.min(100 / canvas.width, 100 / canvas.height, 1);
    const width = Math.max(1, Math.round(canvas.width * scale));
    const height = Math.max(1, Math.round(canvas.height * scale));
    const thumbCanvas = document.createElement("canvas");
    thumbCanvas.width = width;
    thumbCanvas.height = height;

    const context = thumbCanvas.getContext("2d");
    if (!context) throw new Error("Could not create ThumbHash canvas");

    context.drawImage(canvas, 0, 0, width, height);
    const rgba = context.getImageData(0, 0, width, height).data;
    return bytesToBase64(rgbaToThumbHash(width, height, rgba));
};
