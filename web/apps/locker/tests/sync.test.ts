import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    getLockerCacheSnapshot,
    replaceLockerCache,
    type EncryptedCollectionRecord,
    type EncryptedFileRecord,
} from "../src/services/locker-cache";
import * as db from "../src/services/locker-db";
import {
    loadPersistedLockerState,
    syncLockerState,
} from "../src/services/sync/sync";

vi.mock("../src/services/locker-db", () => ({
    loadLockerSnapshotFromDB: vi.fn(),
    saveCollectionRecords: vi.fn(),
    saveCollectionsSinceTime: vi.fn(),
    saveCollectionSinceTime: vi.fn(),
    deleteCollectionSinceTime: vi.fn(),
    saveFileRecords: vi.fn(),
    deleteFileRecords: vi.fn(),
    deleteFileRecordsForCollection: vi.fn(),
    saveTrashFileRecords: vi.fn(),
    deleteTrashFileRecords: vi.fn(),
    saveTrashSinceTime: vi.fn(),
}));
const { ensureAuthenticatedSession, openCollectionKey, decryptMetadataJSON } =
    vi.hoisted(() => ({
        ensureAuthenticatedSession: vi.fn(),
        openCollectionKey: vi.fn(),
        decryptMetadataJSON: vi.fn(),
    }));
vi.mock("../src/services/authenticated-session", () => ({
    ensureAuthenticatedSession,
}));
vi.mock("ente-locker-wasm", () => ({
    openCollectionKey,
    decryptBox: () => "file-key",
    decryptMetadataJSON,
    decryptBoxBytes: () =>
        new TextEncoder().encode(
            JSON.stringify({ name: "Saved", owner: { id: 1 }, sharees: [] }),
        ),
    encryptBoxBytes: () => ({ encryptedData: "payload", nonce: "nonce" }),
}));
vi.mock("ente-base/http", () => ({
    authenticatedRequestHeaders: () => ({ "X-Auth-Token": "test" }),
    ensureOk: (response: Response) => {
        if (!response.ok) throw new Error("Request failed");
    },
}));
vi.mock("ente-base/origins", () => ({
    apiURL: (path: string, params: Record<string, number>) =>
        `${path}?${new URLSearchParams(Object.entries(params).map(([key, value]) => [key, String(value)]))}`,
}));
vi.mock("ente-base/log", () => ({
    default: { error: vi.fn(), warn: vi.fn() },
}));

const collection = (id: number): EncryptedCollectionRecord => ({
    id,
    ownerID: 1,
    encryptedKey: `key-${id}`,
    keyDecryptionNonce: "nonce",
    encryptedName: undefined,
    nameDecryptionNonce: undefined,
    payloadEncryptedData: "payload",
    payloadDecryptionNonce: "nonce",
    type: "folder",
    isDeleted: false,
    updationTime: 20,
});
const file = (id: number, collectionID: number): EncryptedFileRecord => ({
    id,
    collectionID,
    encryptedKey: "key",
    keyDecryptionNonce: "nonce",
    fileDecryptionHeader: "header",
    hasObject: true,
    metadata: { encryptedData: "metadata", decryptionHeader: "header" },
    pubMagicMetadata: { version: 1, data: "public", header: "header" },
    updationTime: 30,
});
const snapshot = () => ({
    collections: new Map([
        [1, collection(1)],
        [2, collection(2)],
    ]),
    files: [file(10, 1), file(10, 2)],
    trashFiles: [{ ...file(11, 1), updatedAt: 40, deleteBy: 100 }],
    collectionsSinceTime: 5,
    collectionSinceTimeByID: new Map([
        [1, 10],
        [2, 20],
    ]),
    trashSinceTime: 40,
    hasPersistedState: true,
});
const fetchMock = vi.fn<typeof fetch>();
const response = (body: unknown) =>
    new Response(JSON.stringify(body), { status: 200 });

beforeEach(() => {
    vi.resetAllMocks();
    vi.stubGlobal("fetch", fetchMock);
    replaceLockerCache({ collections: new Map(), files: new Map() });
    vi.mocked(db.loadLockerSnapshotFromDB).mockResolvedValue(snapshot());
    ensureAuthenticatedSession.mockResolvedValue("session");
    openCollectionKey.mockResolvedValue("collection-key");
    decryptMetadataJSON.mockImplementation(
        (value: { encryptedData: string }) =>
            value.encryptedData === "public"
                ? { editedName: "Renamed" }
                : { title: "Original", creationTime: 1_700_000_000_000 },
    );
});
afterEach(() => vi.unstubAllGlobals());

test("persisted hydration preserves memberships, metadata, trash and cursors without fetching", async () => {
    const result = await loadPersistedLockerState();
    expect(result).toMatchObject({
        collectionsSinceTime: 5,
        trashSinceTime: 40,
        trashLastUpdatedAt: 40,
        hasPersistedState: true,
    });
    expect(result.collections).toHaveLength(2);
    expect(result.collections[0]?.items[0]).toMatchObject({
        id: 10,
        collectionIDs: [1, 2],
        data: { name: "Renamed" },
        createdAt: 1_700_000_000_000_000,
    });
    expect(result.trashItems[0]).toMatchObject({
        id: 11,
        updatedAt: 40,
        deleteBy: 100,
    });
    expect(getLockerCacheSnapshot().files.get(10)?.size).toBe(2);
    expect(getLockerCacheSnapshot().files.has(11)).toBe(true);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(ensureAuthenticatedSession).toHaveBeenCalledOnce();
});

const infoItemCases = [
    { type: "note", data: { title: "Note", content: "Body" } },
    {
        type: "accountCredential",
        data: {
            name: "Account",
            username: "user",
            password: " secret ",
            notes: "Notes",
        },
    },
    {
        type: "physicalRecord",
        data: { name: "Record", location: "Home", notes: "Notes" },
    },
    {
        type: "emergencyContact",
        data: { name: "Contact", contactDetails: "123", notes: "Notes" },
    },
];

test.each(
    infoItemCases.flatMap(({ type, data }) =>
        Object.keys(data).flatMap((field) =>
            [{ unexpected: "object" }, ["array"], 42, true].map((value) => ({
                type,
                field,
                data: { ...data, [field]: value },
            })),
        ),
    ),
)(
    "malformed $type $field is isolated during cached hydration and trash loading: $data",
    async ({ type, data }) => {
        const saved = snapshot();
        saved.files.push({
            ...file(12, 1),
            pubMagicMetadata: { version: 1, data: "bad", header: "header" },
        });
        saved.trashFiles.push({
            ...file(13, 1),
            pubMagicMetadata: { version: 1, data: "bad", header: "header" },
            updatedAt: 40,
            deleteBy: 100,
        });
        vi.mocked(db.loadLockerSnapshotFromDB).mockResolvedValue(saved);
        decryptMetadataJSON.mockImplementation(
            (value: { encryptedData: string }) =>
                value.encryptedData === "bad"
                    ? { info: { type, data } }
                    : { title: "Healthy file" },
        );

        for (let load = 0; load < 2; load++) {
            const result = await loadPersistedLockerState();
            expect(result.collections).toHaveLength(2);
            expect(
                result.collections.map((entry) =>
                    entry.items.map((item) => item.id),
                ),
            ).toEqual([[10], [10]]);
            expect(result.trashItems.map((item) => item.id)).toEqual([11]);
            expect(getLockerCacheSnapshot().files.has(12)).toBe(true);
        }
    },
);

test.each([null, undefined, [], "text", 42, true])(
    "invalid info data is skipped rather than admitted as an item: %j",
    async (data) => {
        decryptMetadataJSON.mockResolvedValue({ info: { type: "note", data } });
        const result = await loadPersistedLockerState();
        expect(
            result.collections.every((entry) => entry.items.length === 0),
        ).toBe(true);
        expect(result.trashItems).toEqual([]);
    },
);

test.each([
    ...infoItemCases,
    { type: "account-credential", data: { name: "Account" } },
    { type: "physical-record", data: { name: "Record" } },
    {
        type: "emergency-contact",
        data: { name: "Contact", contactDetails: "123" },
    },
])("valid $type metadata retains its fields", async ({ type, data }) => {
    decryptMetadataJSON.mockResolvedValue({ info: { type, data } });
    const result = await loadPersistedLockerState();
    const expectedType = type.replace(/-([a-z])/g, (_, letter: string) =>
        letter.toUpperCase(),
    );
    expect(result.collections[0]?.items[0]).toMatchObject({
        type: expectedType,
        data,
    });
    expect(result.trashItems[0]).toMatchObject({ type: expectedType, data });
});

test("empty mobile fields are normalized and unknown fields are excluded", async () => {
    decryptMetadataJSON.mockResolvedValue({
        info: { type: "note", data: { title: null, extra: { nested: true } } },
    });
    const result = await loadPersistedLockerState();
    expect(result.collections[0]?.items[0]?.data).toEqual({
        title: "",
        content: "",
    });
});

test("partial decryption failure excludes only the failed collection and its cache records", async () => {
    openCollectionKey.mockImplementation((_session, _owner, key) => {
        if (key === "key-2") throw new Error("Bad key");
        return "collection-key";
    });
    const result = await loadPersistedLockerState();
    expect(result.collections.map((entry) => entry.id)).toEqual([1]);
    expect([...getLockerCacheSnapshot().collections.keys()]).toEqual([1]);
    expect([...getLockerCacheSnapshot().files.get(10)!.keys()]).toEqual([1]);
});

test("total decryption failure leaves the existing cache intact", async () => {
    const existing = {
        collections: new Map([[9, collection(9)]]),
        files: new Map(),
    };
    replaceLockerCache(existing);
    openCollectionKey.mockRejectedValue(new Error("Bad key"));
    await expect(loadPersistedLockerState()).rejects.toThrow(
        "Failed to decrypt all 2 locker collections",
    );
    expect(getLockerCacheSnapshot()).toEqual(existing);
});

test("incremental sync paginates changed collections and trash, skipping up-to-date collections", async () => {
    const remoteFile = {
        id: 12,
        collectionID: 1,
        encryptedKey: "key",
        keyDecryptionNonce: "nonce",
        file: { decryptionHeader: "header" },
        metadata: { encryptedData: "metadata", decryptionHeader: "header" },
        updationTime: 30,
        isDeleted: false,
    };
    fetchMock
        .mockResolvedValueOnce(response({ collections: [] }))
        .mockResolvedValueOnce(response({ diff: [remoteFile], hasMore: true }))
        .mockResolvedValueOnce(
            response({
                diff: [
                    {
                        id: 13,
                        collectionID: 1,
                        encryptedKey: "",
                        keyDecryptionNonce: "",
                        file: { decryptionHeader: "" },
                        metadata: { decryptionHeader: "" },
                        updationTime: 35,
                        isDeleted: true,
                    },
                ],
                hasMore: false,
            }),
        )
        .mockResolvedValueOnce(
            response({
                diff: [
                    {
                        file: remoteFile,
                        isDeleted: false,
                        isRestored: false,
                        updatedAt: 45,
                        deleteBy: 100,
                    },
                ],
                hasMore: true,
            }),
        )
        .mockResolvedValueOnce(
            response({
                diff: [
                    {
                        file: { ...remoteFile, id: 11 },
                        isDeleted: false,
                        isRestored: true,
                        updatedAt: 50,
                        deleteBy: 100,
                    },
                ],
                hasMore: false,
            }),
        );
    await syncLockerState();
    expect(ensureAuthenticatedSession).toHaveBeenCalledOnce();
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
        "/collections/v2?sinceTime=5",
        "/collections/v2/diff?collectionID=1&sinceTime=10",
        "/collections/v2/diff?collectionID=1&sinceTime=30",
        "/trash/v2/diff?sinceTime=40",
        "/trash/v2/diff?sinceTime=45",
    ]);
    expect(db.saveFileRecords).toHaveBeenCalledWith([
        expect.objectContaining({ id: 12, collectionID: 1, hasObject: true }),
    ]);
    expect(db.deleteFileRecords).toHaveBeenCalledWith([[13, 1]]);
    expect(db.saveCollectionSinceTime).toHaveBeenCalledExactlyOnceWith(1, 35);
    expect(db.saveTrashFileRecords).toHaveBeenCalledWith([
        expect.objectContaining({ id: 12, updatedAt: 45, deleteBy: 100 }),
    ]);
    expect(db.deleteTrashFileRecords).toHaveBeenCalledWith([11]);
    expect(db.saveTrashSinceTime).toHaveBeenCalledExactlyOnceWith(50);
    expect(
        vi.mocked(db.saveFileRecords).mock.invocationCallOrder[0],
    ).toBeLessThan(
        vi.mocked(db.saveCollectionSinceTime).mock.invocationCallOrder[0]!,
    );
});

test("failed file pagination does not persist a partial diff or advance its cursor", async () => {
    fetchMock
        .mockResolvedValueOnce(response({ collections: [] }))
        .mockResolvedValueOnce(response({ diff: [], hasMore: true }))
        .mockResolvedValueOnce(new Response(null, { status: 500 }));
    const existing = getLockerCacheSnapshot();
    await expect(syncLockerState()).rejects.toThrow("Request failed");
    expect(db.saveFileRecords).not.toHaveBeenCalled();
    expect(db.saveCollectionSinceTime).not.toHaveBeenCalled();
    expect(db.saveTrashSinceTime).not.toHaveBeenCalled();
    expect(getLockerCacheSnapshot()).toEqual(existing);
});
