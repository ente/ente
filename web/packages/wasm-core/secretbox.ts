/**
 * @file Authenticated encryption with XSalsa20-Poly1305.
 */
import { loadWasmCore } from "./load";
import { Key, Nonce } from "./types";

/**
 * A secretbox ciphertext together with the nonce needed to open it, as returned
 * by {@link secretboxEncrypt}.
 */
export interface EncryptedBox {
    /** The secretbox ciphertext. */
    encryptedData: Uint8Array;
    /** The nonce needed to decrypt it. Not secret. */
    nonce: Nonce;
}

/** Encrypt `data` with `key` and a freshly generated random nonce. */
export const secretboxEncrypt = async (
    data: Uint8Array,
    key: Key,
): Promise<EncryptedBox> => {
    const wasm = await loadWasmCore();
    const box = wasm.secretboxEncrypt(data, key.bytes);
    try {
        return {
            encryptedData: box.encryptedData,
            nonce: Nonce.fromBytes(box.nonce),
        };
    } finally {
        box.free();
    }
};

/** Decrypt a ciphertext produced by {@link secretboxEncrypt}. */
export const secretboxDecrypt = async (
    data: Uint8Array,
    nonce: Nonce,
    key: Key,
): Promise<Uint8Array> => {
    const wasm = await loadWasmCore();
    return wasm.secretboxDecrypt(data, nonce.bytes, key.bytes);
};

/** Encrypt `data` with `key` into one self-contained buffer. */
export const secretboxEncryptCombined = async (
    data: Uint8Array,
    key: Key,
): Promise<Uint8Array> => {
    const wasm = await loadWasmCore();
    return wasm.secretboxEncryptCombined(data, key.bytes);
};

/** Decrypt a combined buffer produced by {@link secretboxEncryptCombined}. */
export const secretboxDecryptCombined = async (
    data: Uint8Array,
    key: Key,
): Promise<Uint8Array> => {
    const wasm = await loadWasmCore();
    return wasm.secretboxDecryptCombined(data, key.bytes);
};
