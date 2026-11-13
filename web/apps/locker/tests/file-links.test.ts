import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    deleteLockerFileShareLink,
    getOrCreateLockerFileShareLink,
} from "../src/services/file-links";

const { getRecord, decryptKey, session, prepare, openSecret } = vi.hoisted(
    () => ({
        getRecord: vi.fn(),
        decryptKey: vi.fn(),
        session: vi.fn(),
        prepare: vi.fn(),
        openSecret: vi.fn(),
    }),
);
vi.mock("../src/services/locker-cache", () => ({
    getEncryptedFileRecord: getRecord,
}));
vi.mock("../src/services/sync/decrypt", () => ({
    decryptFileKeyForRecord: decryptKey,
}));
vi.mock("../src/services/authenticated-session", () => ({
    ensureAuthenticatedSession: session,
}));
vi.mock("ente-locker-wasm", () => ({
    prepareFileLink: prepare,
    openFileLinkSecret: openSecret,
}));
vi.mock("ente-base/http", () => ({
    authenticatedRequestHeaders: () =>
        Promise.resolve({ Authorization: "test-token" }),
    ensureOk: (res: Response) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
    },
}));
vi.mock("ente-base/origins", () => ({
    apiURL: (path: string) => `https://api.test${path}`,
}));

const fetchMock = vi.fn<typeof fetch>();
const record = { id: 42 };
const authSession = { id: "session" };
const responseLink = {
    linkID: 7,
    url: "https://share.test/link",
    ownerID: 1,
    fileID: 42,
    passwordEnabled: false,
    enableDownload: true,
    createdAt: 1,
    validTill: null,
};
beforeEach(() => {
    vi.resetAllMocks();
    vi.stubGlobal("fetch", fetchMock);
    getRecord.mockReturnValue(record);
    decryptKey.mockResolvedValue("file-key");
    session.mockResolvedValue(authSession);
    prepare.mockResolvedValue({
        secret: "new-secret",
        metadata: { encryptedFileKey: "encrypted", nonce: "nonce" },
    });
    openSecret.mockResolvedValue("existing-secret");
    fetchMock.mockResolvedValue(Response.json(responseLink));
});
afterEach(() => vi.unstubAllGlobals());

test("creates a link with encrypted metadata and keeps the secret in the URL fragment", async () => {
    expect(await getOrCreateLockerFileShareLink(42)).toEqual({
        linkID: "7",
        url: "https://share.test/link#new-secret",
        fileID: 42,
        validTill: null,
        enableDownload: true,
        passwordEnabled: false,
    });
    expect(decryptKey).toHaveBeenCalledWith(record);
    expect(prepare).toHaveBeenCalledWith(authSession, "file-key");
    expect(fetchMock).toHaveBeenCalledWith("https://api.test/files/share-url", {
        method: "POST",
        headers: {
            Authorization: "test-token",
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            fileID: 42,
            app: "locker",
            encryptedFileKey: "encrypted",
            nonce: "nonce",
        }),
    });
    expect(openSecret).not.toHaveBeenCalled();
});
test("uses the existing encrypted share secret when returned by the server", async () => {
    fetchMock.mockResolvedValue(
        Response.json({ ...responseLink, encryptedShareKey: "wrapped-secret" }),
    );
    expect((await getOrCreateLockerFileShareLink(42)).url).toBe(
        "https://share.test/link#existing-secret",
    );
    expect(openSecret).toHaveBeenCalledWith(authSession, "wrapped-secret");
});
test("missing cached files fail before crypto or network calls", async () => {
    getRecord.mockReturnValue(undefined);
    await expect(getOrCreateLockerFileShareLink(42)).rejects.toThrow(
        "File 42 not found in cache",
    );
    expect(prepare).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
});
test("rejects unsuccessful or malformed responses", async () => {
    fetchMock
        .mockResolvedValueOnce(new Response(null, { status: 403 }))
        .mockResolvedValueOnce(Response.json({ linkID: 7 }));
    await expect(getOrCreateLockerFileShareLink(42)).rejects.toThrow(
        "HTTP 403",
    );
    await expect(getOrCreateLockerFileShareLink(42)).rejects.toThrow();
    expect(openSecret).not.toHaveBeenCalled();
});
test("successful deletion stops after the supplied link ID", async () => {
    await deleteLockerFileShareLink(42, "link-id");
    expect(fetchMock).toHaveBeenCalledExactlyOnceWith(
        "https://api.test/files/share-url/link-id",
        { method: "DELETE", headers: { Authorization: "test-token" } },
    );
});
test("deletion retries with the file ID after a non-success response", async () => {
    fetchMock
        .mockResolvedValueOnce(new Response(null, { status: 404 }))
        .mockResolvedValueOnce(new Response(null, { status: 204 }));
    await deleteLockerFileShareLink(42, "link-id");
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
        "https://api.test/files/share-url/link-id",
        "https://api.test/files/share-url/42",
    ]);
});
test.each([undefined, "42"])(
    "uses the file ID only once when linkID is %s",
    async (linkID) => {
        await deleteLockerFileShareLink(42, linkID);
        expect(fetchMock).toHaveBeenCalledTimes(1);
        expect(fetchMock.mock.calls[0]![0]).toBe(
            "https://api.test/files/share-url/42",
        );
    },
);
test("reports the final deletion failure", async () => {
    fetchMock.mockResolvedValue(
        new Response(null, { status: 404, statusText: "Not Found" }),
    );
    await expect(deleteLockerFileShareLink(42, "link-id")).rejects.toThrow(
        "Failed to delete link 42: 404 Not Found",
    );
});
