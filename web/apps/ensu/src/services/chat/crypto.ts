import { base64ToUtf8, utf8ToBase64 } from "../base64";
import { ensureCryptoInit, enteWasm } from "../wasm";

export interface EncryptedChatPayload {
    encryptedData: string;
    header: string;
}

const CHAT_FIELD_PREFIX = "enc:v1";

/** Encrypt a JSON payload for storage using the chat key (base64). */
export const encryptChatPayload = async (
    payload: unknown,
    chatKeyB64: string,
): Promise<EncryptedChatPayload> => {
    await ensureCryptoInit();
    const wasm = await enteWasm();

    const plaintextB64 = utf8ToBase64(JSON.stringify(payload));
    const encrypted = await wasm.crypto_encrypt_blob(plaintextB64, chatKeyB64);

    return {
        encryptedData: encrypted.encrypted_data,
        header: encrypted.decryption_header,
    };
};

/** Decrypt a JSON payload using the chat key (base64). */
export const decryptChatPayload = async (
    { encryptedData, header }: EncryptedChatPayload,
    chatKeyB64: string,
): Promise<unknown> => {
    await ensureCryptoInit();
    const wasm = await enteWasm();

    const plaintextB64 = await wasm.crypto_decrypt_blob(
        encryptedData,
        header,
        chatKeyB64,
    );
    return JSON.parse(base64ToUtf8(plaintextB64));
};

/** Encrypt a string for inclusion in plaintext JSON (enc:v1:..:..). */
export const encryptChatField = async (
    value: string,
    chatKeyB64: string,
): Promise<string> => {
    await ensureCryptoInit();
    const wasm = await enteWasm();

    const plaintextB64 = utf8ToBase64(value);
    const encrypted = await wasm.crypto_encrypt_blob(plaintextB64, chatKeyB64);
    return `${CHAT_FIELD_PREFIX}:${encrypted.encrypted_data}:${encrypted.decryption_header}`;
};

/** Decrypt a string field stored as enc:v1:... */
export const decryptChatField = async (
    value: string,
    chatKeyB64: string,
): Promise<string> => {
    const [prefix, version, ciphertext, header] = value.split(":");
    if (
        `${prefix}:${version}` !== CHAT_FIELD_PREFIX ||
        !ciphertext ||
        !header
    ) {
        throw new Error("Invalid encrypted field format");
    }

    await ensureCryptoInit();
    const wasm = await enteWasm();
    const plaintextB64 = await wasm.crypto_decrypt_blob(
        ciphertext,
        header,
        chatKeyB64,
    );
    return base64ToUtf8(plaintextB64);
};
