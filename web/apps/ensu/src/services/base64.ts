/**
 * Tiny base64 helpers for browser-only code.
 *
 * These are used by the Ensu web app to move between UTF-8, bytes and base64
 * without pulling in libsodium just for encoding/decoding.
 */

/** Convert a Uint8Array to a standard base64 string. */
export const bytesToBase64 = (bytes: Uint8Array): string => {
    // Chunk to avoid call stack / perf issues for larger arrays.
    const chunkSize = 0x8000;
    let binary = "";
    for (let i = 0; i < bytes.length; i += chunkSize) {
        const chunk = bytes.subarray(i, i + chunkSize);
        for (const value of chunk) {
            binary += String.fromCharCode(value);
        }
    }
    return btoa(binary);
};

/** Convert a base64 string to bytes. */
export const base64ToBytes = (b64: string): Uint8Array<ArrayBuffer> => {
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
};

/** UTF-8 string to base64. */
export const utf8ToBase64 = (s: string): string =>
    bytesToBase64(new TextEncoder().encode(s));

/** Base64 to UTF-8 string. */
export const base64ToUtf8 = (b64: string): string =>
    new TextDecoder().decode(base64ToBytes(b64));
