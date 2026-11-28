import { HTTPError } from "ente-base/http";
import { getKVS, setKV } from "ente-base/kv";
import {
    downloadPublicCollectionFile,
    getPublicCollectionDiff,
    getPublicCollectionInfo,
    verifyPublicCollectionPassword,
} from "ente-media/public-albums";
import { beforeEach, describe, expect, test, vi } from "vitest";
import { fetchAndDecryptOriginal, prepareEnteAlbum } from "./import";
import { albumImportIssue } from "./import-error";

vi.mock("ente-base/crypto", () => ({
    decryptBlobBytes: vi.fn(),
    decryptStreamBytes: vi.fn().mockResolvedValue(new Uint8Array()),
}));
vi.mock("ente-base/kv", () => ({ getKVS: vi.fn(), setKV: vi.fn() }));
vi.mock("ente-base/origins", () => ({
    apiOrigin: () => Promise.resolve("https://api.ente.com"),
    customAPIOrigin: () => Promise.resolve(undefined),
}));
vi.mock("ente-media/file", () => ({ decryptRemoteFile: vi.fn() }));
vi.mock("ente-media/live-photo", () => ({ decodeLivePhoto: vi.fn() }));
vi.mock("ente-media/public-albums", () => ({
    getPublicCollectionInfo: vi.fn(),
    getPublicCollectionDiff: vi.fn(),
    verifyPublicCollectionPassword: vi.fn(),
    downloadPublicCollectionFile: vi.fn(),
}));

const albumUrl = `https://albums.ente.com/album#${"00".repeat(32)}`;
const httpError = (status: number) => {
    const res = new Response(null, { status });
    Object.defineProperty(res, "url", {
        value: "https://api.ente.com/public-collection/verify-password",
    });
    return new HTTPError(res);
};
const info = (download: boolean, password = false) =>
    ({
        collection: {
            publicURLs: [
                { enableDownload: download, passwordEnabled: password },
            ],
        },
        referralCode: "",
    }) as Awaited<ReturnType<typeof getPublicCollectionInfo>>;

beforeEach(() => {
    vi.resetAllMocks();
    vi.mocked(getPublicCollectionInfo).mockResolvedValue(info(true));
    vi.mocked(getPublicCollectionDiff).mockResolvedValue({
        diff: [],
        hasMore: false,
    });
});

describe("album import admission", () => {
    test("reuses and saves an admission handed off by the app even without a refreshed token", async () => {
        const result = await prepareEnteAlbum(
            albumUrl,
            vi.fn(),
            "existing-admission",
        );
        expect(getPublicCollectionInfo).toHaveBeenCalledWith(
            expect.objectContaining({ linkDeviceToken: "existing-admission" }),
        );
        expect(getPublicCollectionDiff).toHaveBeenCalledWith(
            expect.objectContaining({ linkDeviceToken: "existing-admission" }),
            0,
        );
        expect(setKV).toHaveBeenCalledWith(
            "public-collection-link-device-token:https://api.ente.com:album",
            "existing-admission",
        );
        expect(result.credentials.linkDeviceToken).toBe("existing-admission");
    });
    test("manual imports reuse the saved admission and retain a refreshed token", async () => {
        vi.mocked(getKVS).mockResolvedValue("saved-admission");
        vi.mocked(getPublicCollectionInfo).mockResolvedValue({
            ...info(true),
            linkDeviceToken: "refreshed-admission",
        });
        await prepareEnteAlbum(albumUrl, vi.fn());
        expect(getPublicCollectionDiff).toHaveBeenCalledWith(
            expect.objectContaining({ linkDeviceToken: "refreshed-admission" }),
            0,
        );
        expect(setKV).toHaveBeenCalledWith(
            expect.any(String),
            "refreshed-admission",
        );
    });
    test("stops disabled downloads and allows a retry after they are enabled", async () => {
        vi.mocked(getPublicCollectionInfo).mockResolvedValue(info(false));
        const error = await prepareEnteAlbum(albumUrl, vi.fn()).catch(
            (error: unknown) => error,
        );
        const issue = await albumImportIssue(error);
        expect(issue.message).toContain("Downloads are disabled");
        expect(issue.canRetry).toBe(true);
        expect(getPublicCollectionDiff).not.toHaveBeenCalled();
        expect(downloadPublicCollectionFile).not.toHaveBeenCalled();
        vi.mocked(getPublicCollectionInfo).mockResolvedValue(info(true));
        await prepareEnteAlbum(albumUrl, vi.fn());
        expect(getPublicCollectionDiff).toHaveBeenCalledOnce();
    });
    test("stops admission errors before fetching photos", async () => {
        const error = new Error("Device limit reached");
        vi.mocked(getPublicCollectionInfo).mockRejectedValue(error);
        await expect(prepareEnteAlbum(albumUrl, vi.fn())).rejects.toBe(error);
        expect(getPublicCollectionDiff).not.toHaveBeenCalled();
        expect(downloadPublicCollectionFile).not.toHaveBeenCalled();
    });
    test("unlocks a protected album before listing photos", async () => {
        vi.mocked(getPublicCollectionInfo).mockResolvedValue(info(true, true));
        vi.mocked(verifyPublicCollectionPassword).mockResolvedValue(
            "password-grant",
        );
        await prepareEnteAlbum(albumUrl, () => Promise.resolve("password"));
        expect(getPublicCollectionDiff).toHaveBeenCalledWith(
            expect.objectContaining({ accessTokenJWT: "password-grant" }),
            0,
        );
    });
    test("cancelling a password prompt does not fetch photos", async () => {
        vi.mocked(getPublicCollectionInfo).mockResolvedValue(info(true, true));
        await expect(
            prepareEnteAlbum(albumUrl, () => Promise.resolve(null)),
        ).rejects.toMatchObject({ cancelled: true });
        expect(getPublicCollectionDiff).not.toHaveBeenCalled();
    });
    test("an incorrect password can be corrected without restarting admission", async () => {
        vi.mocked(getPublicCollectionInfo).mockResolvedValue(info(true, true));
        vi.mocked(verifyPublicCollectionPassword)
            .mockRejectedValueOnce(httpError(401))
            .mockResolvedValueOnce("password-grant");
        const requestPassword = vi
            .fn()
            .mockResolvedValueOnce("wrong")
            .mockResolvedValueOnce("correct");
        await prepareEnteAlbum(albumUrl, requestPassword);
        expect(requestPassword).toHaveBeenNthCalledWith(
            2,
            "That password is incorrect.",
        );
        expect(getPublicCollectionInfo).toHaveBeenCalledOnce();
        expect(getPublicCollectionDiff).toHaveBeenCalledWith(
            expect.objectContaining({ accessTokenJWT: "password-grant" }),
            0,
        );
    });
    test("cancelling after an incorrect password stops the import", async () => {
        vi.mocked(getPublicCollectionInfo).mockResolvedValue(info(true, true));
        vi.mocked(verifyPublicCollectionPassword).mockRejectedValue(
            httpError(401),
        );
        const requestPassword = vi
            .fn()
            .mockResolvedValueOnce("wrong")
            .mockResolvedValueOnce(null);
        await expect(
            prepareEnteAlbum(albumUrl, requestPassword),
        ).rejects.toMatchObject({ cancelled: true });
        expect(verifyPublicCollectionPassword).toHaveBeenCalledOnce();
        expect(getPublicCollectionDiff).not.toHaveBeenCalled();
    });
    test("a password rate limit leaves the password loop", async () => {
        vi.mocked(getPublicCollectionInfo).mockResolvedValue(info(true, true));
        const error = httpError(429);
        vi.mocked(verifyPublicCollectionPassword).mockRejectedValue(error);
        const requestPassword = vi.fn().mockResolvedValue("password");
        await expect(prepareEnteAlbum(albumUrl, requestPassword)).rejects.toBe(
            error,
        );
        expect(requestPassword).toHaveBeenCalledOnce();
        expect(getPublicCollectionDiff).not.toHaveBeenCalled();
    });
    test("invalid links are not offered an unchanged retry", async () => {
        const error = await prepareEnteAlbum("not-a-url", vi.fn()).catch(
            (error: unknown) => error,
        );
        await expect(albumImportIssue(error)).resolves.toMatchObject({
            canRetry: false,
        });
        expect(getPublicCollectionInfo).not.toHaveBeenCalled();
    });
    test("original downloads do not request another device admission", async () => {
        vi.mocked(downloadPublicCollectionFile).mockResolvedValue(
            new Uint8Array(),
        );
        await fetchAndDecryptOriginal(
            {
                accessToken: "album",
                downloadOrigin: "https://public-albums.ente.com",
            },
            {
                enteFileId: 1,
                fileKey: "key",
                mediaKind: "image",
                thumbnailDecryptionHeader: "",
                fileDecryptionHeader: "header",
                fileName: "photo.jpg",
                dateTaken: 0,
                width: 1,
                height: 1,
            },
        );
        expect(getPublicCollectionInfo).not.toHaveBeenCalled();
        expect(getPublicCollectionDiff).not.toHaveBeenCalled();
        expect(downloadPublicCollectionFile).toHaveBeenCalledOnce();
    });
});
