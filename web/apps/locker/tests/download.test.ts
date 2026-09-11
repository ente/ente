import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { downloadLockerFile } from "../src/services/download";

const {
    getRecord,
    getSnapshot,
    decryptCollectionKey,
    decryptBox,
    createDecryptor,
    customOrigin,
    fetchFile,
} = vi.hoisted(() => ({
    getRecord: vi.fn(),
    getSnapshot: vi.fn(),
    decryptCollectionKey: vi.fn(),
    decryptBox: vi.fn(),
    createDecryptor: vi.fn(),
    customOrigin: vi.fn(),
    fetchFile: vi.fn(),
}));
vi.mock("../src/services/locker-cache", () => ({
    getEncryptedFileRecord: getRecord,
    getLockerCacheSnapshot: getSnapshot,
}));
vi.mock("../src/services/sync/decrypt", () => ({ decryptCollectionKey }));
vi.mock("ente-locker-wasm", () => ({
    decryptBox,
    createStreamDecryptor: createDecryptor,
}));
vi.mock("ente-base/file-download", () => ({ fetchFile }));
vi.mock("ente-base/origins", () => ({ customAPIOrigin: customOrigin }));
vi.mock("ente-base/log", () => ({
    default: { info: vi.fn(), error: vi.fn(), warn: vi.fn() },
}));
vi.mock("ente-base/http", () => ({
    authenticatedRequestHeaders: () =>
        Promise.resolve({ Authorization: "test-token" }),
    ensureOk: (res: Response) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
    },
}));
const fetchMock = vi.fn<typeof fetch>();
const createObjectURL = vi.fn<(object: Blob | MediaSource) => string>();
const revokeObjectURL = vi.fn<(url: string) => void>();
const anchor = {
    style: { display: "" },
    href: "",
    download: "",
    click: vi.fn(),
    remove: vi.fn(),
};
const appendChild = vi.fn();
const decryptChunk = vi.fn((chunk: Uint8Array) => chunk);
const free = vi.fn();
const isFinalized = vi.fn(() => true);
const collection = { id: 2 };
const streamedResponse = (knownLength = true) =>
    new Response(
        new ReadableStream<Uint8Array>({
            start(controller) {
                for (const chunk of [[1], [2, 3], [4, 5]])
                    controller.enqueue(new Uint8Array(chunk));
                controller.close();
            },
        }),
        { headers: knownLength ? { "Content-Length": "5" } : {} },
    );

beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.stubGlobal("fetch", fetchMock);
    vi.stubGlobal("document", {
        createElement: () => anchor,
        body: { appendChild },
    });
    createObjectURL.mockReturnValue("blob:test");
    vi.spyOn(URL, "createObjectURL").mockImplementation(createObjectURL);
    vi.spyOn(URL, "revokeObjectURL").mockImplementation(revokeObjectURL);
    getRecord.mockReturnValue({
        id: 42,
        collectionID: 2,
        encryptedKey: "wrapped-key",
        keyDecryptionNonce: "nonce",
        fileDecryptionHeader: "header",
        hasObject: true,
    });
    getSnapshot.mockReturnValue({ collections: new Map([[2, collection]]) });
    decryptCollectionKey.mockResolvedValue("collection-key");
    decryptBox.mockResolvedValue("file-key");
    decryptChunk.mockImplementation((chunk: Uint8Array) => chunk);
    isFinalized.mockReturnValue(true);
    createDecryptor.mockResolvedValue({
        decryptionChunkSize: 2,
        decryptChunk,
        isFinalized,
        free,
    });
    customOrigin.mockResolvedValue(undefined);
    fetchMock.mockResolvedValue(streamedResponse());
    fetchFile.mockResolvedValue(streamedResponse());
});
afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
});

test.each([true, false])(
    "streams partial chunks, reports progress and saves the blob (known length: %s)",
    async (knownLength) => {
        fetchMock.mockResolvedValue(streamedResponse(knownLength));
        const progress =
            vi.fn<(progress: { loaded: number; total?: number }) => void>();
        await downloadLockerFile(42, "download.bin", progress);
        expect(fetchMock).toHaveBeenCalledWith(
            "https://files.ente.com/?fileID=42",
            { headers: { Authorization: "test-token" } },
        );
        expect(fetchFile).not.toHaveBeenCalled();
        expect(decryptCollectionKey).toHaveBeenCalledWith(collection);
        expect(decryptBox).toHaveBeenCalledWith(
            { encryptedData: "wrapped-key", nonce: "nonce" },
            "collection-key",
        );
        expect(createDecryptor).toHaveBeenCalledWith("header", "file-key");
        expect(
            decryptChunk.mock.calls.map(([chunk]) => Array.from(chunk)),
        ).toEqual([[1, 2], [3, 4], [5]]);
        expect(progress.mock.calls.map(([value]) => value)).toEqual(
            [0, 1, 3, 5, 5].map((loaded) => ({
                loaded,
                total: knownLength ? 5 : undefined,
            })),
        );
        const blob = createObjectURL.mock.calls[0]![0] as Blob;
        expect(Array.from(new Uint8Array(await blob.arrayBuffer()))).toEqual([
            1, 2, 3, 4, 5,
        ]);
        expect(anchor.download).toBe("download.bin");
        expect(anchor.href).toBe("blob:test");
        expect(appendChild).toHaveBeenCalledWith(anchor);
        expect(anchor.click).toHaveBeenCalledOnce();
        expect(anchor.remove).toHaveBeenCalledOnce();
        expect(free).toHaveBeenCalledOnce();
        expect(revokeObjectURL).not.toHaveBeenCalled();
        vi.advanceTimersByTime(30_000);
        expect(revokeObjectURL).toHaveBeenCalledWith("blob:test");
    },
);
test("uses the configured API download route for custom origins", async () => {
    customOrigin.mockResolvedValue("https://custom.test");
    await downloadLockerFile(42, "download.bin");
    expect(fetchFile).toHaveBeenCalledExactlyOnceWith(42, "file");
    expect(fetchMock).not.toHaveBeenCalled();
});
test.each(["file", "collection"])(
    "rejects a missing cached %s before downloading",
    async (missing) => {
        if (missing === "file") getRecord.mockReturnValue(undefined);
        else getSnapshot.mockReturnValue({ collections: new Map() });
        await expect(downloadLockerFile(42, "file")).rejects.toThrow(
            "not found in cache",
        );
        expect(fetchMock).not.toHaveBeenCalled();
        expect(anchor.click).not.toHaveBeenCalled();
    },
);
test("propagates key decryption failure before starting a request", async () => {
    decryptBox.mockRejectedValue(new Error("bad key"));
    await expect(downloadLockerFile(42, "file")).rejects.toThrow("bad key");
    expect(fetchMock).not.toHaveBeenCalled();
});
test.each(["http", "body"])(
    "rejects invalid download responses: %s",
    async (reason) => {
        fetchMock.mockResolvedValue(
            new Response(null, { status: reason === "http" ? 403 : 200 }),
        );
        await expect(downloadLockerFile(42, "file")).rejects.toThrow(
            reason === "http" ? "HTTP 403" : "Download response body is empty",
        );
        expect(createDecryptor).not.toHaveBeenCalled();
        expect(anchor.click).not.toHaveBeenCalled();
    },
);
test("rejects truncated ciphertext and releases the decryptor without saving", async () => {
    isFinalized.mockReturnValue(false);
    await expect(downloadLockerFile(42, "file")).rejects.toThrow(
        "Download stream truncated before final chunk",
    );
    expect(free).toHaveBeenCalledOnce();
    expect(createObjectURL).not.toHaveBeenCalled();
    expect(anchor.click).not.toHaveBeenCalled();
});
test("propagates chunk decryption errors and releases the decryptor", async () => {
    decryptChunk.mockImplementation(() => {
        throw new Error("corrupt chunk");
    });
    await expect(downloadLockerFile(42, "file")).rejects.toThrow(
        "corrupt chunk",
    );
    expect(free).toHaveBeenCalledOnce();
    expect(anchor.click).not.toHaveBeenCalled();
});
