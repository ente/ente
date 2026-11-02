import {
    encryptStreamBytes,
    generateBlobOrStreamKey,
} from "ente-base/crypto/libsodium";
import {
    streamEncryptionChunkOverhead,
    streamEncryptionChunkSize,
    type EncryptedFile,
} from "ente-base/crypto/types";
import { createDownloadManager } from "ente-gallery/services/download-core";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { Buffer } from "node:buffer";
import { beforeAll, describe, expect, test, vi } from "vitest";

vi.mock("ente-base/crypto", () => import("ente-base/crypto/libsodium"));
vi.mock("ente-base/log", () => ({
    default: { info: vi.fn(), error: vi.fn() },
}));

let key: string;
let encrypted: EncryptedFile;
const original = new Uint8Array(streamEncryptionChunkSize * 2 + 123).fill(42);
const encryptedChunkSize =
    streamEncryptionChunkSize + streamEncryptionChunkOverhead;

beforeAll(async () => {
    key = await generateBlobOrStreamKey();
    encrypted = await encryptStreamBytes(original, key);
});

const download = (
    data: Uint8Array<ArrayBuffer> | null,
    decryptionHeader = encrypted.decryptionHeader,
) => {
    const manager = createDownloadManager({
        downloadFile: () => Promise.resolve(new Response(data)),
        downloadThumbnail: vi.fn(),
        renderableImageBlob: vi.fn(),
        playableVideoURL: vi.fn(),
    });
    const file = {
        id: 42,
        metadata: { fileType: FileType.video },
        file: { decryptionHeader },
        key,
    } as EnteFile;
    return {
        manager,
        bytes: manager
            .fileStream(file)
            .then((stream) => new Response(stream).arrayBuffer()),
    };
};

describe("streaming video download integrity", () => {
    test.each([0, 123, streamEncryptionChunkSize, original.length])(
        "accepts a complete file with %i plaintext bytes",
        async (size) => {
            const plaintext = original.slice(0, size);
            const file = await encryptStreamBytes(plaintext, key);
            const { bytes, manager } = download(
                file.encryptedData,
                file.decryptionHeader,
            );
            expect(
                Buffer.from(await bytes).equals(Buffer.from(plaintext)),
            ).toBe(true);
            expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
        },
    );

    test.each([0, encryptedChunkSize, encryptedChunkSize * 2])(
        "rejects EOF after %i encrypted bytes without a final tag",
        async (length) => {
            const { bytes, manager } = download(
                encrypted.encryptedData.slice(0, length),
            );
            await expect(bytes).rejects.toThrow(
                length === 0
                    ? "Missing final encrypted chunk"
                    : "Unexpected encrypted stream final tag",
            );
            expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
        },
    );

    test("rejects a missing response body", async () => {
        await expect(download(null).bytes).rejects.toThrow(
            "Missing final encrypted chunk",
        );
    });

    test("rejects truncation inside a chunk", async () => {
        await expect(
            download(encrypted.encryptedData.slice(0, encryptedChunkSize + 100))
                .bytes,
        ).rejects.toThrow("Invalid encrypted chunk");
    });

    test("rejects ciphertext appended after a full-size final chunk", async () => {
        const complete = await encryptStreamBytes(
            original.slice(0, streamEncryptionChunkSize),
            key,
        );
        const appended = new Uint8Array(complete.encryptedData.length + 1);
        appended.set(complete.encryptedData);
        await expect(
            download(appended, complete.decryptionHeader).bytes,
        ).rejects.toThrow("Unexpected encrypted stream final tag");
    });

    test("rejects a modified encrypted chunk", async () => {
        const modified = encrypted.encryptedData.slice();
        modified[0] = modified[0]! ^ 1;
        await expect(download(modified).bytes).rejects.toThrow(
            "Invalid encrypted chunk",
        );
    });
});
