import {
    replaceSavedLocalUser,
    savedKeyAttributes,
    savedOriginalKeyAttributes,
    savedSRPAttributes,
    saveKeyAttributes,
    saveOriginalKeyAttributes,
    saveSRPAttributes,
} from "ente-accounts/services/accounts-db";
import { changePassword } from "ente-accounts/services/password";
import { PasswordWorker } from "ente-accounts/services/password.worker";
import { checkSessionValidity } from "ente-accounts/services/session";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

const {
    generateInteractiveKeyAttributes,
    rustChangePassword,
    rustCheckSessionValidity,
} = vi.hoisted(() => ({
    generateInteractiveKeyAttributes: vi.fn(),
    rustChangePassword: vi.fn(),
    rustCheckSessionValidity: vi.fn(),
}));

vi.mock("comlink", () => ({ expose: vi.fn() }));
vi.mock("ente-base/log-web", () => ({
    logUnhandledErrorsAndRejectionsInWorker: vi.fn(),
}));
vi.mock("ente-base/token", () => ({
    ensureAuthToken: () => Promise.resolve("token"),
}));
vi.mock("ente-base/session-storage", () => ({
    readMasterKeyFromSession: () => Promise.resolve("master-key"),
}));
vi.mock("ente-base/worker/comlink-worker", () => ({
    ComlinkWorker: class {
        remote = Promise.resolve(new PasswordWorker());
        terminate = vi.fn();
    },
}));
vi.mock("ente-accounts/services/accounts-client", () => ({
    withAccountsClient: (operation: (client: unknown) => Promise<unknown>) =>
        operation({}),
}));
vi.mock("ente-accounts/services/key-attributes", () => ({
    generateInteractiveKeyAttributes,
}));
vi.mock("ente-prelogin-wasm", () => ({
    changePassword: rustChangePassword,
    checkSessionValidity: rustCheckSessionValidity,
}));

const original = {
    kekSalt: "old-salt",
    encryptedKey: "encrypted-key",
    keyDecryptionNonce: "key-nonce",
    publicKey: "public-key",
    encryptedSecretKey: "encrypted-secret-key",
    secretKeyDecryptionNonce: "secret-key-nonce",
    memLimit: 65536,
    opsLimit: 2,
};
const updated = { ...original, kekSalt: "new-local-salt" };
const remote = { ...original, kekSalt: "new-remote-salt" };
const updatedSRPAttributes = {
    kekSalt: remote.kekSalt,
    memLimit: remote.memLimit,
    opsLimit: remote.opsLimit,
    srpUserID: "srp-user-id",
    srpSalt: "srp-salt",
    isEmailMFAEnabled: true,
};
const originalSRPAttributes = {
    ...updatedSRPAttributes,
    kekSalt: original.kekSalt,
};
const change = () => changePassword("new-password", vi.fn());

afterEach(() => vi.unstubAllGlobals());

beforeEach(() => {
    vi.resetAllMocks();
    vi.stubGlobal("Worker", vi.fn());
    const storage = new Map<string, string>();
    vi.stubGlobal("localStorage", {
        getItem: (key: string) => storage.get(key) ?? null,
        setItem: (key: string, value: string) => storage.set(key, value),
        removeItem: (key: string) => storage.delete(key),
    });
    replaceSavedLocalUser({ id: 1, email: "user@example.org", token: "token" });
    saveKeyAttributes(original);
    saveOriginalKeyAttributes(original);
    saveSRPAttributes(originalSRPAttributes);
    generateInteractiveKeyAttributes.mockResolvedValue(updated);
    rustChangePassword.mockResolvedValue(remote);
    rustCheckSessionValidity.mockResolvedValue({
        status: "validButPasswordChanged",
        updatedKeyAttributes: remote,
        updatedSRPAttributes,
    });
});

test.each([true, false])(
    "password change reconciles SRP (cached: %s)",
    async (cached) => {
        if (!cached) localStorage.removeItem("srpAttributes");
        await expect(change()).resolves.toBeUndefined();

        expect(generateInteractiveKeyAttributes).toHaveBeenCalledBefore(
            rustChangePassword,
        );
        expect(savedKeyAttributes()).toEqual(updated);
        expect(savedOriginalKeyAttributes()).toEqual(remote);
        expect(savedSRPAttributes()).toEqual(
            cached ? originalSRPAttributes : undefined,
        );

        await expect(checkSessionValidity()).resolves.toEqual({
            status: "valid",
        });
        expect(rustCheckSessionValidity).toHaveBeenCalledWith(
            expect.anything(),
            "token",
            "user@example.org",
            cached ? originalSRPAttributes : undefined,
        );
        expect(savedSRPAttributes()).toEqual(updatedSRPAttributes);
    },
);

test.each([
    [true, true],
    [false, true],
    [true, false],
    [false, false],
])(
    "password change elsewhere is detected with SRP cache %s and original keys %s",
    async (hasSRP, hasOriginal) => {
        if (!hasSRP) localStorage.removeItem("srpAttributes");
        if (!hasOriginal) localStorage.removeItem("originalKeyAttributes");
        const result = {
            status: "validButPasswordChanged",
            updatedKeyAttributes: { ...remote, kekSalt: "another-salt" },
            updatedSRPAttributes: {
                ...updatedSRPAttributes,
                kekSalt: "another-salt",
            },
        };
        rustCheckSessionValidity.mockResolvedValue(result);

        await expect(checkSessionValidity()).resolves.toEqual(result);
        expect(savedSRPAttributes()).toEqual(
            hasSRP ? originalSRPAttributes : undefined,
        );
    },
);

test("local key preparation failure does not change the password", async () => {
    const error = new Error("key preparation failed");
    generateInteractiveKeyAttributes.mockRejectedValue(error);

    await expect(change()).rejects.toBe(error);

    expect(rustChangePassword).not.toHaveBeenCalled();
    expect(savedKeyAttributes()).toEqual(original);
    expect(savedOriginalKeyAttributes()).toEqual(original);
});

test("failed password update preserves the existing local keys", async () => {
    const error = new Error("update rejected");
    rustChangePassword.mockRejectedValue(error);

    await expect(change()).rejects.toBe(error);

    expect(savedKeyAttributes()).toEqual(original);
    expect(savedOriginalKeyAttributes()).toEqual(original);
    expect(savedSRPAttributes()).toEqual(originalSRPAttributes);
});
