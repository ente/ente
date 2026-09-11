import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    deleteCollectionKeepingFiles,
    updateItemCollections,
} from "../src/services/collection-membership";
import {
    replaceLockerCache,
    type EncryptedCollectionRecord,
    type EncryptedFileRecord,
} from "../src/services/locker-cache";
import type { LockerCollection, LockerItem } from "../src/types";

vi.mock("ente-accounts/services/user", () => ({
    ensureLocalUser: () => ({ id: 1 }),
}));
vi.mock("ente-base/http", () => ({
    authenticatedRequestHeaders: () => ({ "X-Auth-Token": "test" }),
    ensureOk: (response: Response) => {
        if (!response.ok) throw new Error("Request failed");
    },
}));
vi.mock("ente-base/origins", () => ({
    apiURL: (path: string, params?: Record<string, unknown>) =>
        params
            ? `${path}?${new URLSearchParams(Object.entries(params).map(([key, value]) => [key, String(value)]))}`
            : path,
}));
vi.mock("ente-base/log", () => ({ default: {} }));
vi.mock("../src/services/authenticated-session", () => ({}));
vi.mock("ente-locker-wasm", () => ({
    decryptBox: () => "file-key",
    encryptBox: (_fileKey: string, collectionKey: string) => ({
        encryptedData: `encrypted-for-${collectionKey}`,
        nonce: "nonce",
    }),
}));
vi.mock("../src/services/sync/decrypt", () => ({
    decryptCollectionKey: (record: EncryptedCollectionRecord) =>
        `collection-${record.id}`,
}));
vi.mock("../src/services/sync/sync", () => ({}));

const fetchMock = vi.fn<typeof fetch>();
const collection = (
    id: number,
    ownerID = 1,
    type = "folder",
): EncryptedCollectionRecord => ({
    id,
    ownerID,
    type,
    encryptedKey: "key",
    keyDecryptionNonce: "nonce",
    encryptedName: undefined,
    nameDecryptionNonce: undefined,
    isDeleted: false,
    updationTime: 0,
});
const file = (id: number, collectionID: number): EncryptedFileRecord => ({
    id,
    collectionID,
    encryptedKey: "key",
    keyDecryptionNonce: "nonce",
    fileDecryptionHeader: "header",
    hasObject: true,
    metadata: { encryptedData: "data", decryptionHeader: "header" },
    updationTime: 0,
});
const item = (id: number, ownerID = 1): LockerItem => ({
    id,
    ownerID,
    type: "file",
    data: { name: "File" },
    collectionID: 1,
    collectionIDs: [1, 2],
});
const source = (items: LockerItem[]): LockerCollection => ({
    id: 1,
    name: "Source",
    owner: { id: 1 },
    sharees: [],
    items,
    type: "folder",
    isShared: false,
});
const seed = (ids = [10], sharedSource = false) =>
    replaceLockerCache({
        collections: new Map([
            [1, collection(1, sharedSource ? 2 : 1)],
            [2, collection(2)],
            [3, collection(3)],
            [9, collection(9, 1, "uncategorized")],
        ]),
        files: new Map(
            ids.map((id) => [
                id,
                new Map([
                    [1, file(id, 1)],
                    [2, file(id, 2)],
                ]),
            ]),
        ),
    });
const requests = () =>
    fetchMock.mock.calls.map(([url, options]) => ({
        url,
        method: options?.method,
        body:
            typeof options?.body === "string"
                ? (JSON.parse(options.body) as Record<string, unknown>)
                : undefined,
    }));
beforeEach(() => {
    vi.clearAllMocks();
    fetchMock
        .mockReset()
        .mockImplementation(() =>
            Promise.resolve(new Response(null, { status: 200 })),
        );
    vi.stubGlobal("fetch", fetchMock);
    seed();
});
afterEach(() => vi.unstubAllGlobals());

test("membership updates deduplicate targets and add before moving the removed owned membership", async () => {
    await updateItemCollections(10, [2, 3, 3], "master-key");
    expect(requests()).toEqual([
        {
            url: "/collections/add-files",
            method: "POST",
            body: {
                collectionID: 3,
                files: [
                    {
                        id: 10,
                        encryptedKey: "encrypted-for-collection-3",
                        keyDecryptionNonce: "nonce",
                    },
                ],
            },
        },
        {
            url: "/collections/move-files",
            method: "POST",
            body: {
                fromCollectionID: 1,
                toCollectionID: 2,
                files: [
                    {
                        id: 10,
                        encryptedKey: "encrypted-for-collection-2",
                        keyDecryptionNonce: "nonce",
                    },
                ],
            },
        },
    ]);
});

test("removing a shared membership detaches it without moving the file", async () => {
    seed([10], true);
    await updateItemCollections(10, [2], "master-key");
    expect(requests()).toEqual([
        {
            url: "/collections/v3/remove-files",
            method: "POST",
            body: { collectionID: 1, fileIDs: [10] },
        },
    ]);
});

test("a failed addition leaves existing memberships untouched", async () => {
    fetchMock.mockResolvedValueOnce(new Response(null, { status: 500 }));
    await expect(updateItemCollections(10, [3], "master-key")).rejects.toThrow(
        "Request failed",
    );
    expect(requests().map((request) => request.url)).toEqual([
        "/collections/add-files",
    ]);
});

test("an empty target selection falls back to Uncategorized before removing current memberships", async () => {
    await updateItemCollections(10, [], "master-key");
    expect(requests().map((request) => request.body)).toEqual([
        {
            collectionID: 9,
            files: [
                {
                    id: 10,
                    encryptedKey: "encrypted-for-collection-9",
                    keyDecryptionNonce: "nonce",
                },
            ],
        },
        {
            fromCollectionID: 1,
            toCollectionID: 9,
            files: [
                {
                    id: 10,
                    encryptedKey: "encrypted-for-collection-9",
                    keyDecryptionNonce: "nonce",
                },
            ],
        },
        {
            fromCollectionID: 2,
            toCollectionID: 9,
            files: [
                {
                    id: 10,
                    encryptedKey: "encrypted-for-collection-9",
                    keyDecryptionNonce: "nonce",
                },
            ],
        },
    ]);
});

test("keeping files batches owned moves, detaches other owners' files, then deletes the collection", async () => {
    const ids = Array.from({ length: 101 }, (_, i) => i + 10);
    seed(ids);
    await deleteCollectionKeepingFiles(
        source([...ids.map((id) => item(id)), item(200, 2)]),
        "master-key",
    );
    const calls = requests();
    expect(calls.map((call) => call.url)).toEqual([
        "/collections/move-files",
        "/collections/move-files",
        "/collections/v3/remove-files",
        "/collections/v3/1?collectionID=1&keepFiles=true",
    ]);
    expect(calls[0]?.body).toMatchObject({
        fromCollectionID: 1,
        toCollectionID: 2,
    });
    expect(calls[0]?.body?.files).toHaveLength(100);
    expect(calls[1]?.body?.files).toEqual([
        {
            id: 110,
            encryptedKey: "encrypted-for-collection-2",
            keyDecryptionNonce: "nonce",
        },
    ]);
    expect(calls[2]?.body).toEqual({ collectionID: 1, fileIDs: [200] });
    expect(calls[3]?.method).toBe("DELETE");
});

test("a failed move prevents the final collection deletion", async () => {
    fetchMock.mockResolvedValueOnce(new Response(null, { status: 500 }));
    await expect(
        deleteCollectionKeepingFiles(source([item(10)]), "master-key"),
    ).rejects.toThrow("Request failed");
    expect(requests().map((request) => request.url)).toEqual([
        "/collections/move-files",
    ]);
});
