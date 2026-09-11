import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { updateFileItem, updateInfoItem } from "../src/services/items";
import {
    getEncryptedFileRecord,
    replaceLockerCache,
    type EncryptedFileRecord,
} from "../src/services/locker-cache";

const { encryptBlob, decryptMetadataJSON } = vi.hoisted(() => ({
    encryptBlob: vi.fn(),
    decryptMetadataJSON: vi.fn(),
}));
vi.mock("ente-accounts/services/user", () => ({}));
vi.mock("ente-base/http", () => ({
    authenticatedRequestHeaders: () => ({}),
    ensureOk: (response: Response) => {
        if (!response.ok) throw new Error("Request failed");
    },
}));
vi.mock("ente-base/origins", () => ({ apiURL: (path: string) => path }));
vi.mock("ente-base/log", () => ({ default: {} }));
vi.mock("ente-locker-wasm", () => ({
    decryptBox: () => "file-key",
    decryptMetadataJSON,
    encryptBlob,
}));
vi.mock("../src/services/authenticated-session", () => ({}));
vi.mock("../src/services/sync/decrypt", () => ({
    decryptCollectionKey: () => "collection-key",
}));

const fetchMock = vi.fn<typeof fetch>();
const originalMetadata = { version: 4, data: "original", header: "header" };

beforeEach(() => {
    vi.clearAllMocks();
    vi.stubGlobal("fetch", fetchMock);
    fetchMock.mockResolvedValue(new Response(null, { status: 200 }));
    encryptBlob.mockResolvedValue({
        encryptedData: "updated",
        decryptionHeader: "updated-header",
    });
    decryptMetadataJSON.mockResolvedValue({
        retained: "custom metadata",
        info: { type: "note", data: { title: "Original" } },
    });
    const file: EncryptedFileRecord = {
        id: 1,
        collectionID: 2,
        encryptedKey: "encrypted-key",
        keyDecryptionNonce: "nonce",
        fileDecryptionHeader: "header",
        hasObject: true,
        metadata: { encryptedData: "data", decryptionHeader: "header" },
        pubMagicMetadata: originalMetadata,
        updationTime: 0,
    };
    replaceLockerCache({
        collections: new Map([
            [
                2,
                {
                    id: 2,
                    ownerID: 1,
                    encryptedKey: "key",
                    keyDecryptionNonce: "nonce",
                    encryptedName: undefined,
                    nameDecryptionNonce: undefined,
                    type: "folder",
                    isDeleted: false,
                    updationTime: 0,
                },
            ],
        ]),
        files: new Map([[1, new Map([[2, file]])]]),
    });
});
afterEach(() => vi.unstubAllGlobals());

test.each(["file", "note"] as const)(
    "editing a %s preserves unrelated metadata and advances the cached version",
    async (type) => {
        if (type === "file") await updateFileItem(1, "  Renamed  ");
        else
            await updateInfoItem(1, "note", {
                title: "  Renamed  ",
                content: "Body",
            });

        expect(encryptBlob).toHaveBeenCalledWith(
            expect.any(Uint8Array),
            "file-key",
        );
        const metadata = JSON.parse(
            new TextDecoder().decode(
                encryptBlob.mock.calls[0]![0] as Uint8Array,
            ),
        ) as Record<string, unknown>;
        expect(typeof metadata.editedTime).toBe("number");
        expect(metadata).toEqual({
            retained: "custom metadata",
            noThumb: true,
            editedName: "Renamed",
            editedTime: metadata.editedTime,
            info: {
                type: "note",
                data:
                    type === "file"
                        ? { title: "Original" }
                        : { title: "  Renamed  ", content: "Body" },
            },
        });
        expect(fetchMock).toHaveBeenCalledWith(
            "/files/public-magic-metadata",
            expect.objectContaining({
                method: "PUT",
                body: JSON.stringify({
                    metadataList: [
                        {
                            id: 1,
                            magicMetadata: {
                                version: 4,
                                count: 5,
                                data: "updated",
                                header: "updated-header",
                            },
                        },
                    ],
                }),
            }),
        );
        expect(getEncryptedFileRecord(1)?.pubMagicMetadata).toEqual({
            version: 5,
            data: "updated",
            header: "updated-header",
        });
    },
);

test("a rejected metadata update leaves the cache unchanged", async () => {
    fetchMock.mockResolvedValue(new Response(null, { status: 500 }));
    await expect(updateFileItem(1, "Renamed")).rejects.toThrow(
        "Request failed",
    );
    expect(getEncryptedFileRecord(1)?.pubMagicMetadata).toEqual(
        originalMetadata,
    );
});
