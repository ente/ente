import { ensureArrayBufferBacked } from "ente-base/bytes";
import type {
    EncryptedBlob,
    EncryptedBox,
    EncryptedFile,
    KeyPair,
} from "ente-base/crypto/types";
import { loadCryptoReadyEnteWasm } from "ente-core-wasm/load";

const shouldFallbackToLegacyBlobDecrypt = (error: unknown): boolean => {
    if (!error || typeof error !== "object") {
        return false;
    }
    if ("code" in error && error.code === "stream_truncated") {
        return true;
    }
    if ("message" in error && typeof error.message === "string") {
        return (
            error.message.includes("stream_truncated") ||
            error.message.includes("StreamTruncated")
        );
    }
    return false;
};

const toB64String = (v: Uint8Array | string): string => {
    if (typeof v === "string") return v;
    let binary = "";
    for (const byte of v) {
        binary += String.fromCharCode(byte);
    }
    return btoa(binary);
};

const fromB64String = (b64: string): Uint8Array<ArrayBuffer> => {
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
};

export const decryptBox = async (
    box: EncryptedBox,
    key: Uint8Array | string,
): Promise<string> => {
    const wasm = await loadCryptoReadyEnteWasm();
    return wasm.crypto_decrypt_box(
        toB64String(box.encryptedData),
        toB64String(box.nonce),
        toB64String(key),
    );
};

export const decryptBoxBytes = async (
    box: EncryptedBox,
    key: Uint8Array | string,
): Promise<Uint8Array> => {
    const b64 = await decryptBox(box, key);
    return fromB64String(b64);
};

export const decryptMetadataJSON = async (
    blob: EncryptedBlob,
    key: Uint8Array | string,
): Promise<unknown> => {
    const wasm = await loadCryptoReadyEnteWasm();
    const encryptedData = toB64String(blob.encryptedData);
    const decryptionHeader = toB64String(blob.decryptionHeader);
    const keyB64 = toB64String(key);
    let plaintextB64: string;
    try {
        plaintextB64 = wasm.crypto_decrypt_blob(
            encryptedData,
            decryptionHeader,
            keyB64,
        );
    } catch (error) {
        if (!shouldFallbackToLegacyBlobDecrypt(error)) {
            throw error;
        }
        plaintextB64 = wasm.crypto_decrypt_blob_legacy(
            encryptedData,
            decryptionHeader,
            keyB64,
        );
    }
    return JSON.parse(new TextDecoder().decode(fromB64String(plaintextB64)));
};

export const boxSealOpen = async (
    encryptedData: string,
    keyPair: KeyPair,
): Promise<string> => {
    const wasm = await loadCryptoReadyEnteWasm();
    return wasm.crypto_box_seal_open(
        encryptedData,
        keyPair.publicKey,
        keyPair.privateKey,
    );
};

export const boxSeal = async (
    dataB64: string,
    publicKeyB64: string,
): Promise<string> => {
    const wasm = await loadCryptoReadyEnteWasm();
    return wasm.crypto_box_seal(dataB64, publicKeyB64);
};

export const generateKey = async (): Promise<string> => {
    const wasm = await loadCryptoReadyEnteWasm();
    return wasm.crypto_generate_key();
};

export const md5Base64 = async (data: Uint8Array): Promise<string> => {
    const wasm = await loadCryptoReadyEnteWasm();
    return wasm.crypto_md5_base64(data);
};

export const encryptBox = async (
    dataB64: string,
    keyB64: string,
): Promise<{ encryptedData: string; nonce: string }> => {
    const wasm = await loadCryptoReadyEnteWasm();
    const result = wasm.crypto_encrypt_box(dataB64, keyB64);
    return { encryptedData: result.encrypted_data, nonce: result.nonce };
};

export const encryptBlob = async (
    dataB64: string,
    keyB64: string,
): Promise<{ encryptedData: string; decryptionHeader: string }> => {
    const wasm = await loadCryptoReadyEnteWasm();
    const result = wasm.crypto_encrypt_blob(dataB64, keyB64);
    return {
        encryptedData: result.encrypted_data,
        decryptionHeader: result.decryption_header,
    };
};

export const stringToB64 = (s: string): string => {
    const encoder = new TextEncoder();
    const bytes = encoder.encode(s);
    return toB64String(bytes);
};

export { fromB64String, toB64String };

export interface StreamEncryptorHandle {
    key: string;
    decryptionHeader: string;
    encryptChunk: (
        data: Uint8Array,
        isFinal: boolean,
    ) => Promise<Uint8Array<ArrayBuffer>>;
    free: () => void;
}

export interface StreamDecryptorHandle {
    decryptionChunkSize: number;
    decryptChunk: (data: Uint8Array) => Promise<Uint8Array>;
    isFinalized: () => boolean;
    free: () => void;
}

export const createStreamEncryptor =
    async (): Promise<StreamEncryptorHandle> => {
        const wasm = await loadCryptoReadyEnteWasm();
        const encryptor = new wasm.CryptoStreamEncryptor();

        return {
            key: encryptor.key,
            decryptionHeader: encryptor.decryption_header,
            encryptChunk: (data: Uint8Array, isFinal: boolean) =>
                Promise.resolve(
                    ensureArrayBufferBacked(
                        encryptor.encrypt_chunk(data, isFinal),
                    ),
                ),
            free: () => encryptor.free(),
        };
    };

export const createStreamDecryptor = async (
    decryptionHeader: string,
    keyB64: string,
): Promise<StreamDecryptorHandle> => {
    const wasm = await loadCryptoReadyEnteWasm();
    const decryptor = new wasm.CryptoStreamDecryptor(decryptionHeader, keyB64);

    return {
        decryptionChunkSize: decryptor.decryption_chunk_size,
        decryptChunk: (data: Uint8Array) =>
            Promise.resolve(decryptor.decrypt_chunk(data)),
        isFinalized: () => decryptor.is_finalized,
        free: () => decryptor.free(),
    };
};

export interface EncryptedFileResult {
    encryptedData: string;
    decryptionHeader: string;
    md5Hash: string;
    key: string;
}

export const encryptFileStream = async (
    dataB64: string,
): Promise<EncryptedFileResult> => {
    const wasm = await loadCryptoReadyEnteWasm();
    const result = wasm.crypto_encrypt_stream(dataB64);
    return {
        encryptedData: result.encrypted_data,
        decryptionHeader: result.decryption_header,
        md5Hash: result.md5_hash,
        key: result.key,
    };
};

export const encryptFileStreamWithKey = async (
    dataB64: string,
    keyB64: string,
): Promise<EncryptedFileResult> => {
    const wasm = await loadCryptoReadyEnteWasm();
    const result = wasm.crypto_encrypt_stream_with_key(dataB64, keyB64);
    return {
        encryptedData: result.encrypted_data,
        decryptionHeader: result.decryption_header,
        md5Hash: result.md5_hash,
        key: result.key,
    };
};

export const bytesToB64 = (bytes: Uint8Array): string => toB64String(bytes);

export const b64ToBytes = (b64: string): Uint8Array<ArrayBuffer> =>
    fromB64String(b64);

export const decryptStreamBytes = async (
    file: EncryptedFile,
    key: Uint8Array | string,
): Promise<Uint8Array> => {
    const wasm = await loadCryptoReadyEnteWasm();
    const plaintextB64 = wasm.crypto_decrypt_stream(
        toB64String(file.encryptedData),
        toB64String(file.decryptionHeader),
        toB64String(key),
    );
    return fromB64String(plaintextB64);
};
