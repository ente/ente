import { createHash } from "node:crypto";
import { expect, test } from "vitest";
import {
    createStreamDecryptor,
    createStreamEncryptor,
    decryptBox,
    decryptBoxBytes,
    decryptMetadataJSON,
    encryptBlob,
    encryptBox,
    encryptBoxBytes,
    encryptFileStreamWithKey,
    generateKey,
} from "../index";
import { cryptoDecryptBlob } from "../pkg/ente_locker_wasm.js";

test.each([
    new Uint8Array(),
    Uint8Array.from({ length: 256 }, (_, i) => i).subarray(1, 255),
])("byte boxes interoperate with base64 boxes (case %#)", async (plaintext) => {
    const key = await generateKey();
    const plaintextB64 = Buffer.from(plaintext).toString("base64");
    const box = await encryptBoxBytes(plaintext, key);
    expect(await decryptBox(box, key)).toBe(plaintextB64);
    expect(
        await decryptBoxBytes(await encryptBox(plaintextB64, key), key),
    ).toStrictEqual(plaintext);
});

test("metadata stays base64 on the wire and decodes to Unicode JSON", async () => {
    const metadata = { title: "Zoë 🦋", note: "\u0000\n" };
    const plaintext = new TextEncoder().encode(JSON.stringify(metadata));
    const key = await generateKey();
    const blob = await encryptBlob(plaintext, key);
    const decryptor = await createStreamDecryptor(blob.decryptionHeader, key);
    try {
        expect(
            decryptor.decryptChunk(Buffer.from(blob.encryptedData, "base64")),
        ).toStrictEqual(plaintext);
        expect(decryptor.isFinalized()).toBe(true);
        expect(await decryptMetadataJSON(blob, key)).toStrictEqual(metadata);
        await expect(
            decryptMetadataJSON(blob, await generateKey()),
        ).rejects.toBeInstanceOf(Error);
    } finally {
        decryptor.free();
    }
});

test("encrypted file bytes are uploadable with their MD5 and header", async () => {
    const plaintext = Uint8Array.from({ length: 256 }, (_, i) => i);
    const key = await generateKey();
    const encrypted = await encryptFileStreamWithKey(
        Buffer.from(plaintext).toString("base64"),
        key,
    );
    expect(encrypted.encryptedData).toBeInstanceOf(Uint8Array);
    expect(encrypted.md5Hash).toBe(
        createHash("md5").update(encrypted.encryptedData).digest("base64"),
    );
    const decryptor = await createStreamDecryptor(
        encrypted.decryptionHeader,
        key,
    );
    try {
        expect(decryptor.decryptChunk(encrypted.encryptedData)).toStrictEqual(
            plaintext,
        );
        expect(decryptor.isFinalized()).toBe(true);
    } finally {
        decryptor.free();
    }
});

test("metadata wrapper reads legacy JSON after a stream_truncated error", async () => {
    const metadata = { title: "Zoë 🦋" };
    const encryptor = await createStreamEncryptor();

    try {
        const encryptedData = encryptor.encryptChunk(
            new TextEncoder().encode(JSON.stringify(metadata)),
            false,
        );
        const { key, decryptionHeader } = encryptor;

        expect(() =>
            cryptoDecryptBlob(
                Buffer.from(encryptedData).toString("base64"),
                decryptionHeader,
                key,
            ),
        ).toThrow(expect.objectContaining({ name: "stream_truncated" }));

        expect(
            await decryptMetadataJSON(
                { encryptedData, decryptionHeader },
                Buffer.from(key, "base64"),
            ),
        ).toStrictEqual(metadata);
    } finally {
        encryptor.free();
    }
});
