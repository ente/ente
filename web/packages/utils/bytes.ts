export const isArrayBufferBacked = (
    bytes: Uint8Array,
): bytes is Uint8Array<ArrayBuffer> => bytes.buffer instanceof ArrayBuffer;

export const ensureArrayBufferBacked = (
    bytes: Uint8Array,
): Uint8Array<ArrayBuffer> =>
    isArrayBufferBacked(bytes) ? bytes : new Uint8Array(bytes);
