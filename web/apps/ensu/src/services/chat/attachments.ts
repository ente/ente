import { base64ToBytes, bytesToBase64 } from "../base64";
import { ensureCryptoInit, enteWasm } from "../wasm";

const ATTACHMENT_KEY_INFO = "llmchat_attachment_v1";
const BLOB_HEADER_BYTES = 24;

const ensureCryptoSubtle = () => {
    if (typeof crypto === "undefined" || !crypto.subtle) {
        throw new Error("WebCrypto not available for attachment encryption");
    }
    return crypto.subtle;
};

export const deriveAttachmentKeyB64 = async (
    chatKeyB64: string,
    sessionUuid: string,
): Promise<string> => {
    const subtle = ensureCryptoSubtle();
    const keyBytes = base64ToBytes(chatKeyB64);
    const salt = new TextEncoder().encode(sessionUuid);
    const info = new TextEncoder().encode(ATTACHMENT_KEY_INFO);

    const key = await subtle.importKey("raw", keyBytes, "HKDF", false, [
        "deriveBits",
    ]);
    const bits = await subtle.deriveBits(
        { name: "HKDF", hash: "SHA-256", salt, info },
        key,
        256,
    );

    return bytesToBase64(new Uint8Array(bits));
};

export const encryptAttachmentBytes = async (
    bytes: Uint8Array,
    chatKeyB64: string,
    sessionUuid: string,
): Promise<Uint8Array<ArrayBuffer>> => {
    await ensureCryptoInit();
    const wasm = await enteWasm();
    const derivedKeyB64 = await deriveAttachmentKeyB64(chatKeyB64, sessionUuid);
    const plaintextB64 = bytesToBase64(bytes);
    const encrypted = await wasm.crypto_encrypt_blob(
        plaintextB64,
        derivedKeyB64,
    );

    const headerBytes = base64ToBytes(encrypted.decryption_header);
    const cipherBytes = base64ToBytes(encrypted.encrypted_data);
    const combined = new Uint8Array(headerBytes.length + cipherBytes.length);
    combined.set(headerBytes, 0);
    combined.set(cipherBytes, headerBytes.length);
    return combined;
};

export const decryptAttachmentBytes = async (
    encrypted: Uint8Array,
    chatKeyB64: string,
    sessionUuid: string,
): Promise<Uint8Array<ArrayBuffer>> => {
    if (encrypted.length < BLOB_HEADER_BYTES) {
        throw new Error("Invalid attachment blob length");
    }

    await ensureCryptoInit();
    const wasm = await enteWasm();
    const derivedKeyB64 = await deriveAttachmentKeyB64(chatKeyB64, sessionUuid);

    const headerBytes = encrypted.slice(0, BLOB_HEADER_BYTES);
    const cipherBytes = encrypted.slice(BLOB_HEADER_BYTES);

    const plaintextB64 = await wasm.crypto_decrypt_blob(
        bytesToBase64(cipherBytes),
        bytesToBase64(headerBytes),
        derivedKeyB64,
    );
    return base64ToBytes(plaintextB64);
};
