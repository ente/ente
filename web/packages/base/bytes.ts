export const isArrayBufferBacked = (
    bytes: Uint8Array,
): bytes is Uint8Array<ArrayBuffer> => bytes.buffer instanceof ArrayBuffer;

/**
 * Return {@link bytes} when it is backed by an {@link ArrayBuffer}; otherwise
 * copy it into a new {@link Uint8Array} with an {@link ArrayBuffer} backing.
 */
export const ensureArrayBufferBacked = (
    bytes: Uint8Array,
): Uint8Array<ArrayBuffer> =>
    isArrayBufferBacked(bytes) ? bytes : new Uint8Array(bytes);
