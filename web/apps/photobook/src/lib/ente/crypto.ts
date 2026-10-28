import { loadCryptoReady } from "@/vendor/ente-wasm";
import { base64ToBytes, bytesToBase64 } from "./base64";

export async function decryptFileKey(
    encryptedKey: string,
    nonce: string,
    collectionKey: string,
): Promise<string> {
    const wasm = await loadCryptoReady();
    return wasm.crypto_decrypt_box(encryptedKey, nonce, collectionKey);
}

export async function decryptBlobBytes(
    encryptedData: string | Uint8Array,
    decryptionHeader: string,
    key: string,
): Promise<Uint8Array> {
    const wasm = await loadCryptoReady();
    const encB64 =
        typeof encryptedData === "string"
            ? encryptedData
            : bytesToBase64(encryptedData);
    const plainB64 = wasm.crypto_decrypt_blob(encB64, decryptionHeader, key);
    return base64ToBytes(plainB64);
}

export async function decryptMetadataJson(
    encryptedData: string,
    decryptionHeader: string,
    key: string,
): Promise<unknown> {
    const bytes = await decryptBlobBytes(encryptedData, decryptionHeader, key);
    const text = new TextDecoder().decode(bytes);
    return JSON.parse(text);
}

export async function decryptFileBytes(
    encryptedData: Uint8Array,
    decryptionHeader: string,
    key: string,
): Promise<Uint8Array> {
    const wasm = await loadCryptoReady();
    const encB64 = bytesToBase64(encryptedData);
    const plainB64 = wasm.crypto_decrypt_stream(encB64, decryptionHeader, key);
    return base64ToBytes(plainB64);
}

export async function deriveArgonKey(
    password: string,
    saltB64: string,
    opsLimit: number,
    memLimit: number,
): Promise<string> {
    const wasm = await loadCryptoReady();
    return wasm.crypto_derive_key(password, saltB64, memLimit, opsLimit);
}
