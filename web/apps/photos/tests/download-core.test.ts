import {
    decryptStreamBytes,
    decryptStreamChunk,
    initChunkDecryption,
} from "ente-base/crypto";
import type { SodiumStateAddress } from "ente-base/crypto/types";
import {
    createDownloadManager,
    NetworkDownloadError,
    type FileDownloadProgress,
} from "ente-gallery/services/download-core";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { describe, expect, test, vi } from "vitest";

vi.mock("ente-base/crypto", () => ({
    decryptStreamBytes: vi.fn(),
    initChunkDecryption: vi
        .fn()
        .mockResolvedValue({
            pullState: { name: "test-state" },
            decryptionChunkSize: 2,
        }),
    decryptStreamChunk: vi.fn((data: Uint8Array<ArrayBuffer>) =>
        Promise.resolve(data),
    ),
}));
vi.mock("ente-base/blob-cache", () => ({ blobCache: vi.fn() }));
vi.mock("ente-base/log", () => ({
    default: { info: vi.fn(), error: vi.fn() },
}));

const file = {
    id: 42,
    metadata: { fileType: FileType.image },
    file: { decryptionHeader: "header" },
    key: "key",
    info: { fileSize: 5 },
} as EnteFile;

const managerFor = (response: Response) =>
    createDownloadManager({
        downloadFile: () => Promise.resolve(response),
        downloadThumbnail: vi.fn(),
        renderableImageBlob: vi.fn(),
        playableVideoURL: vi.fn(),
    });

describe("download byte progress", () => {
    test("a throwing observer cannot interrupt image bytes or other observers", async () => {
        const bytes = new Uint8Array([3, 1, 4, 1, 5]);
        const manager = managerFor(
            new Response(
                new ReadableStream({
                    start(controller) {
                        controller.enqueue(bytes.slice(0, 2));
                        controller.enqueue(bytes.slice(2));
                        controller.close();
                    },
                }),
            ),
        );
        manager.fileDownloadProgressSubscribe(() => {
            throw new Error("observer failed");
        });
        const updates: (FileDownloadProgress | undefined)[] = [];
        manager.fileDownloadProgressSubscribe(() => {
            updates.push(manager.fileDownloadProgressSnapshot().get(file.id));
        });
        vi.mocked(decryptStreamBytes).mockImplementationOnce(
            ({ encryptedData }) => {
                expect(encryptedData).toEqual(bytes);
                return Promise.resolve(encryptedData);
            },
        );
        const stream = await manager.fileStream({ ...file, info: undefined });
        expect(
            new Uint8Array(await new Response(stream).arrayBuffer()),
        ).toEqual(bytes);
        expect(updates).toEqual([
            { loaded: 2, total: undefined },
            { loaded: 5, total: undefined },
            { loaded: 5, total: 5 },
            undefined,
        ]);
    });

    test("cancelling a pending read does not recreate progress", async () => {
        const cancel = vi.fn();
        const manager = managerFor(
            new Response(new ReadableStream({ cancel })),
        );
        const onChange = vi.fn();
        manager.fileDownloadProgressSubscribe(onChange);
        const stream = await manager.fileStream({
            ...file,
            metadata: { ...file.metadata, fileType: FileType.video },
        });
        await stream!.cancel("viewer closed");
        await new Promise((resolve) => setTimeout(resolve, 0));
        expect(cancel).toHaveBeenCalledWith("viewer closed");
        expect(onChange).not.toHaveBeenCalled();
        expect(manager.fileDownloadProgressSnapshot().has(file.id)).toBe(false);
    });

    test("cancelling during decryption stops processing further chunks", async () => {
        const decrypting = Promise.withResolvers<undefined>();
        const decrypted = Promise.withResolvers<Uint8Array<ArrayBuffer>>();
        vi.mocked(decryptStreamChunk).mockClear();
        vi.mocked(decryptStreamChunk).mockImplementationOnce(() => {
            decrypting.resolve(undefined);
            return decrypted.promise;
        });
        const cancel = vi.fn();
        const manager = managerFor(
            new Response(
                new ReadableStream({
                    start(controller) {
                        controller.enqueue(new Uint8Array([1, 2, 3, 4]));
                    },
                    cancel,
                }),
            ),
        );
        const updates: (FileDownloadProgress | undefined)[] = [];
        manager.fileDownloadProgressSubscribe(() => {
            updates.push(manager.fileDownloadProgressSnapshot().get(file.id));
        });
        const stream = await manager.fileStream({
            ...file,
            metadata: { ...file.metadata, fileType: FileType.video },
        });
        await decrypting.promise;
        await stream!.cancel("viewer closed");
        decrypted.resolve(new Uint8Array([1, 2]));
        await new Promise((resolve) => setTimeout(resolve, 0));
        expect(cancel).toHaveBeenCalledWith("viewer closed");
        expect(decryptStreamChunk).toHaveBeenCalledTimes(1);
        expect(updates).toEqual([{ loaded: 4, total: 5 }, undefined]);
        expect(manager.fileDownloadProgressSnapshot().has(file.id)).toBe(false);
    });

    test("reports chunk progress and retains 100% until decryption settles", async () => {
        const body = new ReadableStream<Uint8Array>({
            start(controller) {
                controller.enqueue(new Uint8Array([1, 2]));
                controller.enqueue(new Uint8Array([3, 4]));
                controller.enqueue(new Uint8Array([5, 6]));
                controller.close();
            },
        });
        const manager = managerFor(
            new Response(body, { headers: { "Content-Length": "6" } }),
        );
        const snapshots = [manager.fileDownloadProgressSnapshot()];
        const updates: (FileDownloadProgress | undefined)[] = [];
        manager.fileDownloadProgressSubscribe(() => {
            const snapshot = manager.fileDownloadProgressSnapshot();
            snapshots.push(snapshot);
            updates.push(snapshot.get(file.id));
        });
        const decrypting = Promise.withResolvers<undefined>();
        const decrypted = Promise.withResolvers<Uint8Array<ArrayBuffer>>();
        vi.mocked(decryptStreamBytes).mockImplementationOnce(() => {
            decrypting.resolve(undefined);
            return decrypted.promise;
        });
        const download = manager.fileStream(file);
        await decrypting.promise;
        expect(updates).toEqual(
            expect.arrayContaining([
                { loaded: 2, total: 6 },
                { loaded: 4, total: 6 },
                { loaded: 6, total: 6 },
            ]),
        );
        expect(updates).not.toContain(undefined);
        expect(manager.fileDownloadProgressSnapshot().get(file.id)).toEqual({
            loaded: 6,
            total: 6,
        });
        decrypted.resolve(new Uint8Array([1, 2, 3]));
        await download;
        expect(updates.at(-1)).toBeUndefined();
        expect(manager.fileDownloadProgressSnapshot().has(file.id)).toBe(false);
        expect(new Set(snapshots).size).toBe(snapshots.length);
        expect(snapshots.map((snapshot) => snapshot.get(file.id))).toEqual([
            undefined,
            ...updates,
        ]);
    });

    test("a null body emits no synthetic progress or empty deletion", async () => {
        const manager = managerFor(new Response(null));
        const snapshot = manager.fileDownloadProgressSnapshot();
        const onChange = vi.fn();
        manager.fileDownloadProgressSubscribe(onChange);
        vi.mocked(decryptStreamBytes).mockResolvedValueOnce(new Uint8Array());
        await manager.fileStream(file);
        expect(onChange).not.toHaveBeenCalled();
        expect(manager.fileDownloadProgressSnapshot()).toBe(snapshot);
    });

    test("keeps video progress until EOF and closes the decrypted stream", async () => {
        const body = new ReadableStream<Uint8Array>({
            start(controller) {
                controller.enqueue(new Uint8Array([1, 2]));
                controller.enqueue(new Uint8Array([3, 4]));
                controller.enqueue(new Uint8Array([5, 6]));
                controller.close();
            },
        });
        const manager = managerFor(new Response(body));
        const updates: (FileDownloadProgress | undefined)[] = [];
        manager.fileDownloadProgressSubscribe(() => {
            updates.push(manager.fileDownloadProgressSnapshot().get(file.id));
        });
        const stream = await manager.fileStream({
            ...file,
            metadata: { ...file.metadata, fileType: FileType.video },
        });
        expect(
            new Uint8Array(await new Response(stream).arrayBuffer()),
        ).toEqual(new Uint8Array([1, 2, 3, 4, 5, 6]));
        expect(updates).toEqual([
            { loaded: 2, total: 5 },
            { loaded: 4, total: 5 },
            { loaded: 6, total: 5 },
            { loaded: 6, total: 6 },
            undefined,
        ]);
    });

    test.each([FileType.image, FileType.video])(
        "wraps a body read error and deletes progress for type %s",
        async (fileType) => {
            let reads = 0;
            const body = new ReadableStream<Uint8Array>({
                pull(controller) {
                    if (reads++ == 0)
                        controller.enqueue(new Uint8Array([1, 2]));
                    else controller.error(new Error("connection lost"));
                },
            });
            const manager = managerFor(new Response(body));
            const updates: (FileDownloadProgress | undefined)[] = [];
            manager.fileDownloadProgressSubscribe(() => {
                updates.push(
                    manager.fileDownloadProgressSnapshot().get(file.id),
                );
            });
            const download = manager
                .fileStream({
                    ...file,
                    metadata: { ...file.metadata, fileType },
                })
                .then((stream) => new Response(stream).arrayBuffer());
            await expect(download).rejects.toBeInstanceOf(NetworkDownloadError);
            expect(updates).toEqual([{ loaded: 2, total: 5 }, undefined]);
            expect(manager.fileDownloadProgressSnapshot().has(file.id)).toBe(
                false,
            );
        },
    );
});

describe("download consumer compatibility", () => {
    test.each([
        ["fragmented chunks", [[1], [2], [3], [4], [5]]],
        [
            "full-size final chunk",
            [
                [1, 2],
                [3, 4],
            ],
        ],
        ["multiple chunks per read", [[1, 2, 3, 4, 5]]],
        ["empty network chunks", [[], [1, 2], [], [3, 4, 5]]],
    ] as const)("emits decrypted video bytes with %s", async (_, chunks) => {
        vi.mocked(decryptStreamChunk).mockClear();
        vi.mocked(initChunkDecryption).mockClear();
        const pullState: SodiumStateAddress = { name: "video-test-state" };
        vi.mocked(initChunkDecryption).mockResolvedValueOnce({
            pullState,
            decryptionChunkSize: 2,
        });
        const encryptedBytes = new Uint8Array(chunks.flat());
        const expectedChunks = [];
        for (let i = 0; i < encryptedBytes.length; i += 2) {
            const chunk = encryptedBytes.slice(i, i + 2);
            expectedChunks.push([
                chunk,
                pullState,
                i + 2 >= encryptedBytes.length,
            ]);
            vi.mocked(decryptStreamChunk).mockResolvedValueOnce(
                chunk.map((byte) => byte + 10),
            );
        }
        const manager = managerFor(
            new Response(
                new ReadableStream({
                    start(controller) {
                        for (const chunk of chunks)
                            controller.enqueue(new Uint8Array(chunk));
                        controller.close();
                    },
                }),
            ),
        );
        const stream = await manager.fileStream({
            ...file,
            metadata: { ...file.metadata, fileType: FileType.video },
        });
        const bytes = new Uint8Array(await new Response(stream).arrayBuffer());
        expect(bytes).toEqual(encryptedBytes.map((byte) => byte + 10));
        expect(initChunkDecryption).toHaveBeenCalledExactlyOnceWith(
            file.file.decryptionHeader,
            file.key,
        );
        expect(vi.mocked(decryptStreamChunk).mock.calls).toEqual(
            expectedChunks,
        );
        expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
    });

    test.each([FileType.image, FileType.video])(
        "preserves crypto errors and clears progress for type %s",
        async (fileType) => {
            const error = new Error("invalid ciphertext");
            if (fileType === FileType.video)
                vi.mocked(decryptStreamChunk).mockRejectedValueOnce(error);
            else vi.mocked(decryptStreamBytes).mockRejectedValueOnce(error);
            const manager = managerFor(new Response(new Uint8Array([1, 2, 3])));
            await expect(
                manager
                    .fileStream({
                        ...file,
                        metadata: { ...file.metadata, fileType },
                    })
                    .then((stream) => new Response(stream).arrayBuffer()),
            ).rejects.toBe(error);
            expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
        },
    );

    test("preserves initialization errors", async () => {
        const error = new Error("invalid header");
        vi.mocked(initChunkDecryption).mockRejectedValueOnce(error);
        const manager = managerFor(new Response(new Uint8Array([1, 2])));
        await expect(
            manager.fileStream({
                ...file,
                metadata: { ...file.metadata, fileType: FileType.video },
            }),
        ).rejects.toBe(error);
        expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
    });

    test("forwards background options and wraps transport failures", async () => {
        const error = new Error("offline");
        const downloadFile = vi.fn().mockRejectedValue(error);
        const manager = createDownloadManager({
            downloadFile,
            downloadThumbnail: vi.fn(),
            renderableImageBlob: vi.fn(),
            playableVideoURL: vi.fn(),
        });
        const opts = { background: true };
        await expect(manager.fileStream(file, opts)).rejects.toMatchObject({
            error,
        });
        expect(downloadFile).toHaveBeenCalledWith(file, opts);
        await expect(manager.fileStream(file)).rejects.toBeInstanceOf(
            NetworkDownloadError,
        );
        expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
    });
});
