import {
    encryptStreamBytes,
    generateBlobOrStreamKey,
} from "ente-base/crypto/libsodium";
import { streamEncryptionChunkSize } from "ente-base/crypto/types";
import { createDownloadManager } from "ente-gallery/services/download-core";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { createHash } from "node:crypto";
import { expect, test, vi } from "vitest";

vi.mock("ente-base/crypto", () => import("ente-base/crypto/libsodium"));
vi.mock("ente-base/log", () => ({
    default: { info: vi.fn(), error: vi.fn(), warn: vi.fn() },
}));
const hash = (data: ArrayBuffer | Uint8Array) =>
    createHash("sha256").update(new Uint8Array(data)).digest("hex");
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

test.each([FileType.image, FileType.video])(
    "viewer first and different-file overlap: type %i",
    async (fileType) => {
        const fixtures = await Promise.all(
            [42, 43].map(async (id) => {
                const original = Uint8Array.from(
                    { length: streamEncryptionChunkSize * 2 + 123 },
                    (_, i) => (i + id) % 256,
                );
                const key = await generateBlobOrStreamKey();
                const encrypted = await encryptStreamBytes(original, key);
                const file = {
                    id,
                    key,
                    metadata: {
                        fileType,
                        title:
                            fileType === FileType.image
                                ? "test.jpg"
                                : "test.mp4",
                    },
                    file: { decryptionHeader: encrypted.decryptionHeader },
                } as EnteFile;
                return { file, original, encrypted };
            }),
        );
        const transport = vi.fn((file: EnteFile) => {
            const data = fixtures.find((f) => f.file.id === file.id)!.encrypted
                .encryptedData;
            let offset = 0;
            return Promise.resolve(
                new Response(
                    new ReadableStream<Uint8Array>({
                        async pull(c) {
                            await tick();
                            if (offset === data.length) c.close();
                            else {
                                const next = Math.min(
                                    offset + 128 * 1024,
                                    data.length,
                                );
                                c.enqueue(data.slice(offset, next));
                                offset = next;
                            }
                        },
                    }),
                ),
            );
        });
        const manager = createDownloadManager({
            downloadFile: transport,
            downloadThumbnail: vi.fn(),
            renderableImageBlob: (b) => Promise.resolve(b),
            playableVideoURL: (_f, _n, b) =>
                Promise.resolve(URL.createObjectURL(b)),
        });
        const first = fixtures[0]!;
        const second = fixtures[1]!;
        const viewed = manager.renderableSourceURLs(first.file);
        const saved = manager.fileBlob(first.file);
        const other = manager.fileBlob(second.file);
        const [source, blob, otherBlob] = await Promise.all([
            viewed,
            saved,
            other,
        ]);
        const url =
            source.type === "image"
                ? source.imageURL
                : source.type === "video"
                  ? source.videoURL
                  : "";
        expect(hash(await fetch(url).then((r) => r.arrayBuffer()))).toBe(
            hash(first.original),
        );
        expect(hash(await blob.arrayBuffer())).toBe(hash(first.original));
        expect(hash(await otherBlob.arrayBuffer())).toBe(hash(second.original));
        expect(transport).toHaveBeenCalledTimes(2);
        URL.revokeObjectURL(url);
    },
    10000,
);

test.each([FileType.image, FileType.video])(
    "download first, same-file viewer second: type %i",
    async (fileType) => {
        const original = Uint8Array.from(
            { length: streamEncryptionChunkSize * 2 + 123 },
            (_, i) => (i * 31 + (i >> 12)) % 256,
        );
        const key = await generateBlobOrStreamKey();
        const encrypted = await encryptStreamBytes(original, key);
        const file = {
            id: 42,
            key,
            metadata: {
                fileType,
                title: fileType === FileType.image ? "test.jpg" : "test.mp4",
            },
            file: { decryptionHeader: encrypted.decryptionHeader },
        } as EnteFile;
        const bodies: ReadableStreamDefaultController<Uint8Array>[] = [];
        const transport = vi.fn(() =>
            Promise.resolve(
                new Response(
                    new ReadableStream<Uint8Array>({
                        start(c) {
                            bodies.push(c);
                        },
                    }),
                    {
                        headers: {
                            "Content-Length": String(
                                encrypted.encryptedData.length,
                            ),
                        },
                    },
                ),
            ),
        );
        const manager = createDownloadManager({
            downloadFile: transport,
            downloadThumbnail: vi.fn(),
            renderableImageBlob: (b) => Promise.resolve(b),
            playableVideoURL: (_f, _n, b) =>
                Promise.resolve(URL.createObjectURL(b)),
        });
        const states: (number | undefined)[] = [];
        manager.fileDownloadProgressSubscribe(() =>
            states.push(
                manager.fileDownloadProgressSnapshot().get(file.id)?.loaded,
            ),
        );
        const saved = manager.fileBlob(file);
        while (bodies.length < 1) await tick();
        bodies[0]!.enqueue(encrypted.encryptedData.slice(0, 1024 * 1024));
        await tick();
        const viewed = manager.renderableSourceURLs(file);
        const repeatedSave = manager.fileBlob(file);
        await tick();
        expect(transport).toHaveBeenCalledTimes(1);
        expect(states.at(-1)).toBe(1024 * 1024);
        bodies[0]!.enqueue(encrypted.encryptedData.slice(1024 * 1024));
        bodies[0]!.close();
        const [downloadBlob, repeatedBlob] = await Promise.all([
            saved,
            repeatedSave,
        ]);
        expect(hash(await repeatedBlob.arrayBuffer())).toBe(hash(original));
        expect(manager.fileDownloadProgressSnapshot().has(file.id)).toBe(false);
        const source = await viewed;
        const url =
            source.type === "image"
                ? source.imageURL
                : source.type === "video"
                  ? source.videoURL
                  : "";
        const viewBytes = await fetch(url).then((r) => r.arrayBuffer());
        expect(hash(await downloadBlob.arrayBuffer())).toBe(hash(original));
        expect(hash(viewBytes)).toBe(hash(original));
        const loaded = states.filter((n): n is number => n !== undefined);
        expect(loaded).toEqual([...loaded].sort((a, b) => a - b));
        expect(states.filter((n) => n === undefined)).toHaveLength(1);
        URL.revokeObjectURL(url);
    },
    10000,
);

const fixture = async (fileType: FileType = FileType.image) => {
    const original = new Uint8Array(8192).fill(37);
    const key = await generateBlobOrStreamKey();
    const encrypted = await encryptStreamBytes(original, key);
    const file = {
        id: 42,
        key,
        metadata: { fileType, title: "test.jpg" },
        file: { decryptionHeader: encrypted.decryptionHeader },
    } as EnteFile;
    return { file, original, encrypted };
};
const managerWith = (downloadFile: (file: EnteFile) => Promise<Response>) =>
    createDownloadManager({
        downloadFile,
        downloadThumbnail: vi.fn(),
        renderableImageBlob: (b) => Promise.resolve(b),
        playableVideoURL: (_f, _n, b) =>
            Promise.resolve(URL.createObjectURL(b)),
    });

test.each(["network", "decryption"])(
    "shared %s failure reaches every consumer and permits retry",
    async (failure) => {
        const { file, encrypted, original } = await fixture();
        const transport = vi.fn(() =>
            Promise.resolve(new Response(encrypted.encryptedData)),
        );
        if (failure === "network")
            transport.mockRejectedValueOnce(new Error("offline"));
        else
            transport.mockResolvedValueOnce(
                new Response(new Uint8Array([1, 2, 3])),
            );
        const manager = managerWith(transport);
        const results = await Promise.allSettled([
            manager.fileBlob(file),
            manager.fileBlob(file),
            manager.renderableSourceURLs(file),
        ]);
        expect(transport).toHaveBeenCalledTimes(1);
        expect(results.every((r) => r.status === "rejected")).toBe(true);
        const errors = results.map((r) =>
            r.status === "rejected" ? (r.reason as unknown) : undefined,
        );
        expect(errors[0]).toBe(errors[1]);
        expect(errors[0]).toBe(errors[2]);
        expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
        const [retried, source] = await Promise.all([
            manager.fileBlob(file),
            manager.renderableSourceURLs(file),
        ]);
        expect(hash(await retried.arrayBuffer())).toBe(hash(original));
        expect(transport).toHaveBeenCalledTimes(2);
        if (source.type === "image") URL.revokeObjectURL(source.imageURL);
    },
);

test.each([
    [false, "network"],
    [true, "network"],
    [false, "decryption"],
    [true, "decryption"],
] as const)(
    "waiting saves automatically retry a failed viewer: background %s, %s failure",
    async (background, failure) => {
        const { file, encrypted, original } = await fixture();
        const transport = vi.fn(() =>
            Promise.resolve(new Response(encrypted.encryptedData)),
        );
        if (failure === "network")
            transport.mockRejectedValueOnce(new Error("offline"));
        else
            transport.mockResolvedValueOnce(
                new Response(new Uint8Array([1, 2, 3])),
            );
        const manager = managerWith(transport);
        const viewer = manager.renderableSourceURLs(file);
        const viewerFailure = expect(viewer).rejects.toBeInstanceOf(Error);
        const saves = [manager.fileBlob(file, { background })];
        // Foreground saves share the fallback job; background jobs stay separate.
        if (!background) saves.push(manager.fileBlob(file));
        const blobs = await Promise.all(saves);
        await viewerFailure;
        for (const blob of blobs)
            expect(hash(await blob.arrayBuffer())).toBe(hash(original));
        expect(transport).toHaveBeenCalledTimes(2);
        expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
    },
);

test.each([false, true])(
    "a waiting save surfaces a failed fallback without retrying indefinitely: background %s",
    async (background) => {
        const { file } = await fixture();
        const transport = vi.fn<() => Promise<Response>>();
        transport.mockRejectedValue(new Error("offline"));
        const manager = managerWith(transport);
        const viewerFailure = expect(
            manager.renderableSourceURLs(file),
        ).rejects.toThrow("offline");
        await expect(manager.fileBlob(file, { background })).rejects.toThrow(
            "offline",
        );
        await viewerFailure;
        expect(transport).toHaveBeenCalledTimes(3);
        expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
    },
);

test.each([false, true])(
    "waiting saves recover after the viewer and first fallback both fail: background %s",
    async (background) => {
        const { file, encrypted, original } = await fixture();
        const transport = vi.fn(() =>
            Promise.resolve(new Response(encrypted.encryptedData)),
        );
        transport.mockRejectedValueOnce(new Error("viewer failed"));
        transport.mockRejectedValueOnce(new Error("first fallback failed"));
        const manager = managerWith(transport);
        const viewerFailure = expect(
            manager.renderableSourceURLs(file),
        ).rejects.toThrow("viewer failed");
        const saves = [manager.fileBlob(file, { background })];
        if (!background) saves.push(manager.fileBlob(file));
        const blobs = await Promise.all(saves);
        await viewerFailure;
        for (const blob of blobs)
            expect(hash(await blob.arrayBuffer())).toBe(hash(original));
        expect(transport).toHaveBeenCalledTimes(3);
        expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
    },
);

test.each(["complete", "fail"])(
    "old jobs cannot change a new session when they %s",
    async (outcome) => {
        const { file, encrypted } = await fixture();
        const bodies: ReadableStreamDefaultController<Uint8Array>[] = [];
        const transport = vi.fn(() =>
            Promise.resolve(
                new Response(
                    new ReadableStream<Uint8Array>({
                        start(c) {
                            bodies.push(c);
                        },
                    }),
                ),
            ),
        );
        const manager = managerWith(transport);
        const old = Promise.allSettled([
            manager.fileBlob(file),
            manager.renderableSourceURLs(file),
        ]);
        while (!bodies.length) await tick();
        bodies[0]!.enqueue(encrypted.encryptedData.slice(0, 1024));
        await tick();
        const oldSnapshot = manager.fileDownloadProgressSnapshot();
        manager.logout();
        expect(oldSnapshot.get(file.id)?.loaded).toBe(1024);
        expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
        const observer = vi.fn();
        manager.fileDownloadProgressSubscribe(observer);
        const current = manager.renderableSourceURLs(file);
        while (bodies.length < 2) await tick();
        bodies[1]!.enqueue(encrypted.encryptedData.slice(0, 512));
        await tick();
        const snapshot = manager.fileDownloadProgressSnapshot();
        observer.mockClear();
        if (outcome === "fail")
            bodies[0]!.error(new Error("old connection failed"));
        else {
            bodies[0]!.enqueue(encrypted.encryptedData.slice(1024));
            bodies[0]!.close();
        }
        const oldResults = await old;
        expect(observer).not.toHaveBeenCalled();
        expect(manager.fileDownloadProgressSnapshot()).toBe(snapshot);
        const saved = manager.fileBlob(file);
        bodies[1]!.enqueue(encrypted.encryptedData.slice(512));
        bodies[1]!.close();
        const [source] = await Promise.all([current, saved]);
        expect(transport).toHaveBeenCalledTimes(2);
        expect(manager.fileDownloadProgressSnapshot().size).toBe(0);
        if (source.type === "image") URL.revokeObjectURL(source.imageURL);
        const oldSource = oldResults[1];
        if (
            oldSource.status === "fulfilled" &&
            !(oldSource.value instanceof Blob) &&
            oldSource.value.type === "image"
        )
            URL.revokeObjectURL(oldSource.value.imageURL);
    },
);

test("save-only blobs are shared while pending and released after completion", async () => {
    const { file, encrypted } = await fixture();
    const transport = vi.fn(() =>
        Promise.resolve(new Response(encrypted.encryptedData)),
    );
    const manager = managerWith(transport);
    await Promise.all([manager.fileBlob(file), manager.fileBlob(file)]);
    expect(transport).toHaveBeenCalledTimes(1);
    await manager.fileBlob(file);
    expect(transport).toHaveBeenCalledTimes(2);
});

test.each(["stream", "background"])(
    "a separate %s completes independently and both downloads preserve bytes",
    async (consumer) => {
        const { file, encrypted, original } = await fixture(FileType.video);
        const bodies: ReadableStreamDefaultController<Uint8Array>[] = [];
        const transport = vi.fn(() =>
            Promise.resolve(
                new Response(
                    new ReadableStream<Uint8Array>({
                        start(c) {
                            bodies.push(c);
                        },
                    }),
                ),
            ),
        );
        const manager = managerWith(transport);
        const shared = manager.fileBlob(file);
        while (!bodies.length) await tick();
        bodies[0]!.enqueue(encrypted.encryptedData.slice(0, 1024));
        const other =
            consumer === "stream"
                ? manager.fileStream(file).then((s) => new Response(s).blob())
                : manager.fileBlob(file, { background: true });
        while (bodies.length < 2) await tick();
        bodies[1]!.enqueue(encrypted.encryptedData);
        bodies[1]!.close();
        // The separate consumer must finish while the shared response is still open.
        const otherBlob = await other;
        expect(hash(await otherBlob.arrayBuffer())).toBe(hash(original));
        expect(transport).toHaveBeenCalledTimes(2);
        bodies[0]!.enqueue(encrypted.encryptedData.slice(1024));
        bodies[0]!.close();
        const sharedBlob = await shared;
        expect(hash(await sharedBlob.arrayBuffer())).toBe(hash(original));
    },
);
