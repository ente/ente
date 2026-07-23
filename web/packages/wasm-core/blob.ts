/**
 * @file Authenticated encryption of a single value with XChaCha20-Poly1305.
 */
import { loadWasmCore } from "./load";
import { Header, Key } from "./types";

/**
 * A blob ciphertext together with the header needed to open it, as returned by
 * {@link blobEncrypt}.
 */
export interface EncryptedBlob {
    /** The blob ciphertext. */
    encryptedData: Uint8Array;
    /** The decryption header needed to decrypt it. Not secret. */
    decryptionHeader: Header;
}

/** Encrypt `data` with `key` as a single secretstream message. */
export const blobEncrypt = async (
    data: Uint8Array,
    key: Key,
): Promise<EncryptedBlob> => {
    const wasm = await loadWasmCore();
    const blob = wasm.blobEncrypt(data, key.bytes);
    try {
        return {
            encryptedData: blob.encryptedData,
            decryptionHeader: Header.fromBytes(blob.decryptionHeader),
        };
    } finally {
        blob.free();
    }
};

/**
 * Decrypt a blob produced by {@link blobEncrypt}, using its `header` and `key`.
 */
export const blobDecrypt = async (
    data: Uint8Array,
    header: Header,
    key: Key,
): Promise<Uint8Array> => {
    const wasm = await loadWasmCore();
    return wasm.blobDecrypt(data, header.bytes, key.bytes);
};

/** Encrypt `data` with `key` into one self-contained buffer. */
export const blobEncryptCombined = async (
    data: Uint8Array,
    key: Key,
): Promise<Uint8Array> => {
    const wasm = await loadWasmCore();
    return wasm.blobEncryptCombined(data, key.bytes);
};

/** Decrypt a combined buffer produced by {@link blobEncryptCombined}. */
export const blobDecryptCombined = async (
    data: Uint8Array,
    key: Key,
): Promise<Uint8Array> => {
    const wasm = await loadWasmCore();
    return wasm.blobDecryptCombined(data, key.bytes);
};
