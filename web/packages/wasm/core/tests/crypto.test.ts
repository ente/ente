import { expect, test } from "vitest";
import {
    CryptoStreamEncryptor,
    crypto_decrypt_blob,
    crypto_decrypt_blob_legacy,
} from "../pkg/ente_core_wasm.js";

test("strict blob decrypt rejects non-final secretstream payloads", () => {
    const encryptor = new CryptoStreamEncryptor();
    const ciphertext = encryptor.encrypt_chunk(
        Uint8Array.from([1, 2, 3, 4]),
        false,
    );
    const encryptedData = Buffer.from(ciphertext).toString("base64");

    expect(() =>
        crypto_decrypt_blob(
            encryptedData,
            encryptor.decryption_header,
            encryptor.key,
        ),
    ).toThrow();
});

test("legacy blob decrypt accepts non-final secretstream payloads", () => {
    const encryptor = new CryptoStreamEncryptor();
    const ciphertext = encryptor.encrypt_chunk(
        Uint8Array.from([1, 2, 3, 4]),
        false,
    );
    const encryptedData = Buffer.from(ciphertext).toString("base64");

    const decrypted = crypto_decrypt_blob_legacy(
        encryptedData,
        encryptor.decryption_header,
        encryptor.key,
    );

    expect(decrypted).toBe("AQIDBA==");
});
