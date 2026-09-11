import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    emptyTrash,
    permanentlyDeleteFromTrash,
    restoreFromTrash,
    trashFiles,
} from "../src/services/trash";

const {
    getCollectionRecord,
    getEncryptedFileRecord,
    fetchLockerTrash,
    encryptBox,
    warn,
} = vi.hoisted(() => ({
    getCollectionRecord: vi.fn(),
    getEncryptedFileRecord: vi.fn(),
    fetchLockerTrash: vi.fn(),
    encryptBox: vi.fn(),
    warn: vi.fn(),
}));
vi.mock("../src/services/locker-cache", () => ({
    getCollectionRecord,
    getEncryptedFileRecord,
}));
vi.mock("../src/services/sync/decrypt", () => ({
    decryptCollectionKey: (record: { id: number }) => `collection-${record.id}`,
}));
vi.mock("../src/services/sync/sync", () => ({ fetchLockerTrash }));
vi.mock("ente-locker-wasm", () => ({
    decryptBox: () => "file-key",
    encryptBox,
}));
vi.mock("ente-base/http", () => ({
    authenticatedRequestHeaders: () => ({}),
    ensureOk: (res: Response) => {
        if (!res.ok) throw new Error("Request failed");
    },
}));
vi.mock("ente-base/origins", () => ({ apiURL: (path: string) => path }));
vi.mock("ente-base/log", () => ({ default: { warn } }));
vi.mock("ente-accounts/services/user", () => ({}));
vi.mock("../src/services/authenticated-session", () => ({}));
const fetchMock = vi.fn<typeof fetch>();
const items = [{ id: 1, collectionID: 2 }];
beforeEach(() => {
    vi.resetAllMocks();
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockResolvedValue(new Response(null, { status: 200 }));
    getCollectionRecord.mockImplementation((id: number) => ({ id }));
    getEncryptedFileRecord.mockReturnValue({
        collectionID: 2,
        encryptedKey: "key",
        keyDecryptionNonce: "nonce",
    });
    encryptBox.mockResolvedValue({
        encryptedData: "rewrapped",
        nonce: "new-nonce",
    });
});
afterEach(() => vi.unstubAllGlobals());

test("trash mutations preserve endpoints and payloads", async () => {
    await trashFiles([1, 3], 2);
    await permanentlyDeleteFromTrash([1, 3]);
    await emptyTrash(123);
    expect(
        fetchMock.mock.calls.map(([url, init]) => [
            url,
            init?.method,
            JSON.parse(init?.body as string) as unknown,
        ]),
    ).toEqual([
        [
            "/files/trash",
            "POST",
            {
                items: [
                    { fileID: 1, collectionID: 2 },
                    { fileID: 3, collectionID: 2 },
                ],
            },
        ],
        ["/trash/delete", "POST", { fileIDs: [1, 3] }],
        ["/trash/empty", "POST", { lastUpdatedAt: 123 }],
    ]);
});
test("restore rewraps the original file key for the chosen destination", async () => {
    await restoreFromTrash(items, 9);
    expect(getEncryptedFileRecord).toHaveBeenCalledWith(1, 2);
    expect(encryptBox).toHaveBeenCalledWith("file-key", "collection-9");
    expect(fetchMock).toHaveBeenCalledWith(
        "/collections/restore-files",
        expect.objectContaining({
            body: JSON.stringify({
                collectionID: 9,
                files: [
                    {
                        id: 1,
                        encryptedKey: "rewrapped",
                        keyDecryptionNonce: "new-nonce",
                    },
                ],
            }),
        }),
    );
});
test("restore refreshes missing cache records once before retrying", async () => {
    getEncryptedFileRecord.mockReturnValueOnce(undefined);
    await restoreFromTrash(items, 9);
    expect(fetchLockerTrash).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledTimes(1);
});
test("restore rejects when cache records remain missing", async () => {
    getEncryptedFileRecord.mockReturnValue(undefined);
    await expect(restoreFromTrash(items, 9)).rejects.toThrow(
        "missing encrypted metadata",
    );
    expect(fetchLockerTrash).toHaveBeenCalledTimes(1);
    expect(fetchMock).not.toHaveBeenCalled();
});
test("partial restore submits available files without retrying missing ones", async () => {
    getEncryptedFileRecord.mockReturnValueOnce(undefined);
    await restoreFromTrash([{ id: 3, collectionID: 2 }, ...items], 9);
    expect(fetchLockerTrash).not.toHaveBeenCalled();
    expect(warn).toHaveBeenCalledWith(expect.any(String), [3]);
    expect(
        (
            JSON.parse(fetchMock.mock.calls[0]![1]!.body as string) as {
                files: unknown[];
            }
        ).files,
    ).toHaveLength(1);
});
test("restore rejects a missing destination before sending a request", async () => {
    getCollectionRecord.mockReturnValue(undefined);
    await expect(restoreFromTrash(items, 9)).rejects.toThrow(
        "Collection 9 not in cache",
    );
    expect(fetchMock).not.toHaveBeenCalled();
});
test("mutation failures propagate", async () => {
    fetchMock.mockImplementation(() =>
        Promise.resolve(new Response(null, { status: 500 })),
    );
    await expect(trashFiles([1], 2)).rejects.toThrow("Request failed");
    await expect(permanentlyDeleteFromTrash([1])).rejects.toThrow(
        "Request failed",
    );
    await expect(emptyTrash(123)).rejects.toThrow("Request failed");
    await expect(restoreFromTrash(items, 9)).rejects.toThrow("Request failed");
});
