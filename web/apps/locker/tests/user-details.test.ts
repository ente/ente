import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    LOCKER_FILE_LIMIT_FREE,
    LOCKER_FILE_LIMIT_PAID,
} from "../src/services/locker-limits";
import { loadLockerUsage, loadUserEmail } from "../src/services/user-details";

const { authenticatedRequestHeaders, savedLocalUser } = vi.hoisted(() => ({
    authenticatedRequestHeaders: vi.fn(),
    savedLocalUser: vi.fn(),
}));
vi.mock("ente-accounts/services/accounts-db", () => ({ savedLocalUser }));
vi.mock("ente-base/http", () => ({
    authenticatedRequestHeaders,
    ensureOk: (response: Response) => {
        if (!response.ok) throw new Error("Request failed");
    },
}));
vi.mock("ente-base/origins", () => ({
    apiURL: (path: string, params?: { memoryCount: boolean }) =>
        params ? `${path}?memoryCount=${params.memoryCount}` : path,
}));
const fetchMock = vi.fn<typeof fetch>();
beforeEach(() => {
    vi.resetAllMocks();
    vi.stubGlobal("fetch", fetchMock);
    authenticatedRequestHeaders.mockResolvedValue({ "X-Auth-Token": "token" });
    savedLocalUser.mockReturnValue({ email: "cached@example.org" });
});
afterEach(() => vi.unstubAllGlobals());

test.each([false, true])("usage defaults for paid=%s", async (isPaid) => {
    fetchMock.mockResolvedValue(Response.json({ isPaid }));
    expect(await loadLockerUsage()).toEqual({
        userDetails: {
            usage: 0,
            storageLimit: 0,
            fileCount: 0,
            lockerFileLimit: isPaid
                ? LOCKER_FILE_LIMIT_PAID
                : LOCKER_FILE_LIMIT_FREE,
            isPartOfFamily: false,
            lockerFamilyFileCount: undefined,
        },
    });
    expect(fetchMock).toHaveBeenCalledWith("/users/locker-usage", {
        headers: { "X-Auth-Token": "token" },
    });
});

test.each([false, true])("usage counts for family=%s", async (isFamily) => {
    fetchMock.mockResolvedValue(
        Response.json({
            isFamily,
            usedFileCount: 30,
            userFileCount: 7,
            usedStorage: 800,
            userStorage: 100,
            storageLimit: 1000,
            fileLimit: 0,
        }),
    );
    const headers = {
        "X-Auth-Token": "shared-token",
        "X-Client-Package": "locker",
    };
    expect(await loadLockerUsage(headers)).toEqual({
        userDetails: {
            usage: 800,
            storageLimit: 1000,
            fileCount: isFamily ? 7 : 30,
            lockerFileLimit: 0,
            isPartOfFamily: isFamily,
            lockerFamilyFileCount: isFamily ? 30 : undefined,
        },
    });
    expect(authenticatedRequestHeaders).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledWith("/users/locker-usage", { headers });
});

test.each([
    [{ email: "server@example.org" }, "server@example.org"],
    [{ email: "" }, ""],
    [{}, "cached@example.org"],
])("profile email fallback for %j", async (profile, expected) => {
    fetchMock.mockResolvedValue(Response.json(profile));
    const headers = {
        "X-Auth-Token": "shared-token",
        "X-Client-Package": "locker",
    };
    expect(await loadUserEmail(headers)).toBe(expected);
    expect(fetchMock).toHaveBeenCalledWith(
        "/users/details/v2?memoryCount=false",
        { headers },
    );
    expect(authenticatedRequestHeaders).not.toHaveBeenCalled();
});

test("missing profile and cached email yields an empty string", async () => {
    savedLocalUser.mockReturnValue(undefined);
    fetchMock.mockResolvedValue(Response.json({}));
    expect(await loadUserEmail()).toBe("");
    expect(authenticatedRequestHeaders).toHaveBeenCalledOnce();
});

test.each([loadLockerUsage, loadUserEmail])(
    "request failures propagate to the caller",
    async (load) => {
        fetchMock.mockResolvedValue(new Response(null, { status: 401 }));
        await expect(load()).rejects.toThrow("Request failed");
        fetchMock.mockRejectedValue(new Error("offline"));
        await expect(load()).rejects.toThrow("offline");
    },
);
