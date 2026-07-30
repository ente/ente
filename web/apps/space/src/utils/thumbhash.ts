/*
 * ThumbHash
 *
 * Copyright (c) 2023 Evan Wallace
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * Source: https://github.com/evanw/thumbhash/blob/main/js/thumbhash.js
 */

type RGBABytes = Uint8Array | Uint8ClampedArray;

type ByteSequence = Uint8Array | readonly number[];

const byteStringFromBytes = (bytes: ByteSequence) => {
    let value = "";
    for (const byte of bytes) {
        value += String.fromCharCode(byte);
    }
    return value;
};

const bytesFromByteString = (value: string) => {
    const bytes = new Uint8Array(value.length);
    for (let i = 0; i < value.length; i++) {
        bytes[i] = value.charCodeAt(i);
    }
    return bytes;
};

const bytesToBase64 = (bytes: ByteSequence) => btoa(byteStringFromBytes(bytes));

const base64ToBytes = (value: string) => bytesFromByteString(atob(value));

/**
 * Encodes an RGBA image to a ThumbHash. RGB should not be premultiplied by A.
 *
 * @param w The width of the input image. Must be <=100px.
 * @param h The height of the input image. Must be <=100px.
 * @param rgba The pixels in the input image, row-by-row. Must have w*h*4 elements.
 * @returns The ThumbHash as a Uint8Array.
 */
export function rgbaToThumbHash(w: number, h: number, rgba: RGBABytes) {
    if (w > 100 || h > 100) throw new Error(`${w}x${h} doesn't fit in 100x100`);
    const { PI, abs, cos, max, round } = Math;

    let avgR = 0;
    let avgG = 0;
    let avgB = 0;
    let avgA = 0;
    for (let i = 0, j = 0; i < w * h; i++, j += 4) {
        const alpha = rgba[j + 3]! / 255;
        avgR += (alpha / 255) * rgba[j]!;
        avgG += (alpha / 255) * rgba[j + 1]!;
        avgB += (alpha / 255) * rgba[j + 2]!;
        avgA += alpha;
    }
    if (avgA) {
        avgR /= avgA;
        avgG /= avgA;
        avgB /= avgA;
    }

    const hasAlpha = avgA < w * h;
    const lLimit = hasAlpha ? 5 : 7;
    const lx = max(1, round((lLimit * w) / max(w, h)));
    const ly = max(1, round((lLimit * h) / max(w, h)));
    const l: number[] = [];
    const p: number[] = [];
    const q: number[] = [];
    const a: number[] = [];

    for (let i = 0, j = 0; i < w * h; i++, j += 4) {
        const alpha = rgba[j + 3]! / 255;
        const r = avgR * (1 - alpha) + (alpha / 255) * rgba[j]!;
        const g = avgG * (1 - alpha) + (alpha / 255) * rgba[j + 1]!;
        const b = avgB * (1 - alpha) + (alpha / 255) * rgba[j + 2]!;
        l[i] = (r + g + b) / 3;
        p[i] = (r + g) / 2 - b;
        q[i] = r - g;
        a[i] = alpha;
    }

    const encodeChannel = (
        channel: number[],
        nx: number,
        ny: number,
    ): [number, number[], number] => {
        let dc = 0;
        const ac: number[] = [];
        let scale = 0;
        const fx: number[] = [];
        for (let cy = 0; cy < ny; cy++) {
            for (let cx = 0; cx * ny < nx * (ny - cy); cx++) {
                let f = 0;
                for (let x = 0; x < w; x++) {
                    fx[x] = cos((PI / w) * cx * (x + 0.5));
                }
                for (let y = 0; y < h; y++) {
                    const fy = cos((PI / h) * cy * (y + 0.5));
                    for (let x = 0; x < w; x++) {
                        f += channel[x + y * w]! * fx[x]! * fy;
                    }
                }
                f /= w * h;
                if (cx || cy) {
                    ac.push(f);
                    scale = max(scale, abs(f));
                } else {
                    dc = f;
                }
            }
        }
        if (scale) {
            for (let i = 0; i < ac.length; i++) {
                ac[i] = 0.5 + (0.5 / scale) * ac[i]!;
            }
        }
        return [dc, ac, scale];
    };

    const [lDC, lAC, lScale] = encodeChannel(l, max(3, lx), max(3, ly));
    const [pDC, pAC, pScale] = encodeChannel(p, 3, 3);
    const [qDC, qAC, qScale] = encodeChannel(q, 3, 3);
    const [aDC, aAC, aScale] = hasAlpha ? encodeChannel(a, 5, 5) : [0, [], 0];

    const isLandscape = w > h;
    const header24 =
        round(63 * lDC) |
        (round(31.5 + 31.5 * pDC) << 6) |
        (round(31.5 + 31.5 * qDC) << 12) |
        (round(31 * lScale) << 18) |
        (Number(hasAlpha) << 23);
    const header16 =
        (isLandscape ? ly : lx) |
        (round(63 * pScale) << 3) |
        (round(63 * qScale) << 9) |
        (Number(isLandscape) << 15);
    const hash = [
        header24 & 255,
        (header24 >> 8) & 255,
        header24 >> 16,
        header16 & 255,
        header16 >> 8,
    ];
    const acStart = hasAlpha ? 6 : 5;
    let acIndex = 0;
    if (hasAlpha) hash.push(round(15 * aDC) | (round(15 * aScale) << 4));

    for (const ac of hasAlpha ? [lAC, pAC, qAC, aAC] : [lAC, pAC, qAC]) {
        for (const f of ac) {
            hash[acStart + (acIndex >> 1)]! |=
                round(15 * f) << ((acIndex++ & 1) << 2);
        }
    }
    return new Uint8Array(hash);
}

/**
 * Decodes a ThumbHash to an RGBA image. RGB is not premultiplied by A.
 *
 * @param hash The bytes of the ThumbHash.
 * @returns The width, height, and pixels of the rendered placeholder image.
 */
export function thumbHashToRGBA(hash: Uint8Array) {
    const { PI, cos, max, min, round } = Math;

    const header24 = hash[0]! | (hash[1]! << 8) | (hash[2]! << 16);
    const header16 = hash[3]! | (hash[4]! << 8);
    const lDC = (header24 & 63) / 63;
    const pDC = ((header24 >> 6) & 63) / 31.5 - 1;
    const qDC = ((header24 >> 12) & 63) / 31.5 - 1;
    const lScale = ((header24 >> 18) & 31) / 31;
    const hasAlpha = header24 >> 23;
    const pScale = ((header16 >> 3) & 63) / 63;
    const qScale = ((header16 >> 9) & 63) / 63;
    const isLandscape = header16 >> 15;
    const lx = max(3, isLandscape ? (hasAlpha ? 5 : 7) : header16 & 7);
    const ly = max(3, isLandscape ? header16 & 7 : hasAlpha ? 5 : 7);
    const aDC = hasAlpha ? (hash[5]! & 15) / 15 : 1;
    const aScale = (hash[5]! >> 4) / 15;

    let acIndex = 0;
    const acStart = hasAlpha ? 6 : 5;
    const decodeChannel = (nx: number, ny: number, scale: number) => {
        const ac: number[] = [];
        for (let cy = 0; cy < ny; cy++) {
            for (let cx = cy ? 0 : 1; cx * ny < nx * (ny - cy); cx++) {
                ac.push(
                    (((hash[acStart + (acIndex >> 1)]! >>
                        ((acIndex++ & 1) << 2)) &
                        15) /
                        7.5 -
                        1) *
                        scale,
                );
            }
        }
        return ac;
    };
    const lAC = decodeChannel(lx, ly, lScale);
    const pAC = decodeChannel(3, 3, pScale * 1.25);
    const qAC = decodeChannel(3, 3, qScale * 1.25);
    const aAC = hasAlpha ? decodeChannel(5, 5, aScale) : [];

    const ratio = thumbHashToApproximateAspectRatio(hash);
    const w = round(ratio > 1 ? 32 : 32 * ratio);
    const h = round(ratio > 1 ? 32 / ratio : 32);
    const rgba = new Uint8Array(w * h * 4);
    const fx: number[] = [];
    const fy: number[] = [];
    for (let y = 0, i = 0; y < h; y++) {
        for (let x = 0; x < w; x++, i += 4) {
            let l = lDC;
            let p = pDC;
            let q = qDC;
            let a = aDC;

            for (let cx = 0, n = max(lx, hasAlpha ? 5 : 3); cx < n; cx++) {
                fx[cx] = cos((PI / w) * (x + 0.5) * cx);
            }
            for (let cy = 0, n = max(ly, hasAlpha ? 5 : 3); cy < n; cy++) {
                fy[cy] = cos((PI / h) * (y + 0.5) * cy);
            }

            for (let cy = 0, j = 0; cy < ly; cy++) {
                const fy2 = fy[cy]! * 2;
                for (let cx = cy ? 0 : 1; cx * ly < lx * (ly - cy); cx++, j++) {
                    l += lAC[j]! * fx[cx]! * fy2;
                }
            }

            for (let cy = 0, j = 0; cy < 3; cy++) {
                const fy2 = fy[cy]! * 2;
                for (let cx = cy ? 0 : 1; cx < 3 - cy; cx++, j++) {
                    const f = fx[cx]! * fy2;
                    p += pAC[j]! * f;
                    q += qAC[j]! * f;
                }
            }

            if (hasAlpha) {
                for (let cy = 0, j = 0; cy < 5; cy++) {
                    const fy2 = fy[cy]! * 2;
                    for (let cx = cy ? 0 : 1; cx < 5 - cy; cx++, j++) {
                        a += aAC[j]! * fx[cx]! * fy2;
                    }
                }
            }

            const b = l - (2 / 3) * p;
            const r = (3 * l - b + q) / 2;
            const g = r - q;
            rgba[i] = max(0, 255 * min(1, r));
            rgba[i + 1] = max(0, 255 * min(1, g));
            rgba[i + 2] = max(0, 255 * min(1, b));
            rgba[i + 3] = max(0, 255 * min(1, a));
        }
    }
    return { w, h, rgba };
}

/**
 * Extracts the approximate aspect ratio of the original image.
 *
 * @param hash The bytes of the ThumbHash.
 * @returns The approximate aspect ratio, width / height.
 */
export function thumbHashToApproximateAspectRatio(hash: Uint8Array) {
    const header = hash[3]!;
    const hasAlpha = hash[2]! & 0x80;
    const isLandscape = hash[4]! & 0x80;
    const lx = isLandscape ? (hasAlpha ? 5 : 7) : header & 7;
    const ly = isLandscape ? header & 7 : hasAlpha ? 5 : 7;
    return lx / ly;
}

/**
 * Encodes an RGBA image to a PNG data URL. RGB should not be premultiplied by A.
 *
 * @param w The width of the input image. Must be <=100px.
 * @param h The height of the input image. Must be <=100px.
 * @param rgba The pixels in the input image, row-by-row. Must have w*h*4 elements.
 * @returns A data URL containing a PNG for the input image.
 */
export function rgbaToDataURL(w: number, h: number, rgba: RGBABytes) {
    const row = w * 4 + 1;
    const idat = 6 + h * (5 + row);
    const bytes = [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        13,
        73,
        72,
        68,
        82,
        0,
        0,
        w >> 8,
        w & 255,
        0,
        0,
        h >> 8,
        h & 255,
        8,
        6,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        idat >>> 24,
        (idat >> 16) & 255,
        (idat >> 8) & 255,
        idat & 255,
        73,
        68,
        65,
        84,
        120,
        1,
    ];
    const table = [
        0, 498536548, 997073096, 651767980, 1994146192, 1802195444, 1303535960,
        1342533948, -306674912, -267414716, -690576408, -882789492, -1687895376,
        -2032938284, -1609899400, -1111625188,
    ];
    let a = 1;
    let b = 0;
    for (let y = 0, i = 0, end = row - 1; y < h; y++, end += row - 1) {
        bytes.push(
            y + 1 < h ? 0 : 1,
            row & 255,
            row >> 8,
            ~row & 255,
            (row >> 8) ^ 255,
            0,
        );
        for (b = (b + a) % 65521; i < end; i++) {
            const u = rgba[i]! & 255;
            bytes.push(u);
            a = (a + u) % 65521;
            b = (b + a) % 65521;
        }
    }
    bytes.push(
        b >> 8,
        b & 255,
        a >> 8,
        a & 255,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        73,
        69,
        78,
        68,
        174,
        66,
        96,
        130,
    );
    const chunks: [number, number][] = [
        [12, 29],
        [37, 41 + idat],
    ];
    for (const [start, initialEnd] of chunks) {
        const end = initialEnd;
        let c = ~0;
        for (let i = start; i < end; i++) {
            c ^= bytes[i]!;
            c = (c >>> 4) ^ table[c & 15]!;
            c = (c >>> 4) ^ table[c & 15]!;
        }
        c = ~c;
        bytes[end] = c >>> 24;
        bytes[end + 1] = (c >> 16) & 255;
        bytes[end + 2] = (c >> 8) & 255;
        bytes[end + 3] = c & 255;
    }
    return `data:image/png;base64,${bytesToBase64(bytes)}`;
}

/**
 * Decodes a ThumbHash to a PNG data URL.
 *
 * @param hash The bytes of the ThumbHash.
 * @returns A data URL containing a PNG for the rendered ThumbHash.
 */
export function thumbHashToDataURL(hash: Uint8Array) {
    const image = thumbHashToRGBA(hash);
    return rgbaToDataURL(image.w, image.h, image.rgba);
}

export const thumbHashToBase64 = (hash: Uint8Array) => bytesToBase64(hash);

const minThumbHashBytes = 5;
const maxThumbHashBytes = 25;
const maxThumbHashBase64Length = 36;

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
        const bytes = base64ToBytes(hash);
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
    return thumbHashToBase64(rgbaToThumbHash(width, height, rgba));
};
