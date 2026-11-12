import type { Session } from "ente-locker-wasm";
import { beforeEach, expect, test, vi } from "vitest";

const {
    apiOrigin,
    savedAuthToken,
    masterKeyFromSession,
    keyAttributes,
    user,
    generateKey,
    openLocker,
} = vi.hoisted(() => ({
    apiOrigin: vi.fn<() => Promise<string>>(),
    savedAuthToken: vi.fn<() => Promise<string>>(),
    masterKeyFromSession: vi.fn<() => Promise<string>>(),
    keyAttributes: {
        publicKey: "public-key",
        encryptedSecretKey: "encrypted-secret-key",
        secretKeyDecryptionNonce: "secret-key-nonce",
        recoveryKeyEncryptedWithMasterKey: "encrypted-recovery-key",
        recoveryKeyDecryptionNonce: "recovery-key-nonce",
    },
    user: { id: 1 },
    generateKey: vi.fn<typeof import("ente-locker-wasm").generateKey>(),
    openLocker: vi.fn<typeof import("ente-locker-wasm").openSession>(),
}));

vi.mock("ente-base/app", () => ({
    clientPackageName: "io.ente.locker.web",
    desktopAppVersion: undefined,
    isDesktop: false,
}));
vi.mock("ente-base/origins", () => ({ apiOrigin }));
vi.mock("ente-base/token", () => ({ savedAuthToken }));
vi.mock("../src/services/account-keys", () => ({ masterKeyFromSession }));
vi.mock("ente-accounts/services/user", () => ({
    ensureLocalUser: () => user,
    ensureSavedKeyAttributes: () => keyAttributes,
}));
vi.mock("ente-locker-wasm", () => ({ generateKey, openSession: openLocker }));

let sessions: typeof import("../src/services/authenticated-session");

beforeEach(async () => {
    vi.resetModules();
    vi.resetAllMocks();
    user.id = 1;
    apiOrigin.mockResolvedValue("http://localhost:8080");
    savedAuthToken.mockResolvedValue("token");
    masterKeyFromSession.mockResolvedValue("key");
    sessions = await import("../src/services/authenticated-session");
});

test("reuses the session without decrypting the master key and refreshes its token", async () => {
    const locker = mockSession();
    openLocker.mockResolvedValue(locker);

    expect(await sessions.openAuthenticatedSession(1, "token", "key")).toBe(
        locker,
    );
    expect(await sessions.ensureAuthenticatedSession()).toBe(locker);
    expect(masterKeyFromSession).not.toHaveBeenCalled();
    savedAuthToken.mockResolvedValue("rotated-token");
    expect(await sessions.ensureAuthenticatedSession()).toBe(locker);
    expect(locker.updateAuthToken).toHaveBeenLastCalledWith("rotated-token");
    expect(openLocker).toHaveBeenCalledOnce();

    sessions.clearAuthenticatedSession();
    expect(locker.free).not.toHaveBeenCalled();
    await sessions.ensureAuthenticatedSession();
    expect(openLocker).toHaveBeenCalledTimes(2);
});

test("retries a failed Locker session", async () => {
    const locker = mockSession();
    openLocker
        .mockRejectedValueOnce(new Error("Download failed"))
        .mockResolvedValueOnce(locker);

    await expect(sessions.ensureAuthenticatedSession()).rejects.toThrow(
        "Download failed",
    );
    expect(await sessions.ensureAuthenticatedSession()).toBe(locker);
    expect(openLocker).toHaveBeenCalledTimes(2);
});

test("logout during credential lookup cannot reopen a session", async () => {
    const key = Promise.withResolvers<string>();
    const started = Promise.withResolvers<undefined>();
    masterKeyFromSession.mockImplementation(() => {
        started.resolve(undefined);
        return key.promise;
    });
    const opening = sessions.ensureAuthenticatedSession();
    await started.promise;
    sessions.clearAuthenticatedSession();
    key.resolve("key");

    await expect(opening).rejects.toThrow("Authenticated session was cleared");
    expect(openLocker).not.toHaveBeenCalled();
});

test("concurrent access decrypts the master key once", async () => {
    const locker = mockSession();
    openLocker.mockResolvedValue(locker);
    expect(
        await Promise.all([
            sessions.ensureAuthenticatedSession(),
            sessions.ensureAuthenticatedSession(),
        ]),
    ).toEqual([locker, locker]);
    expect(await sessions.ensureAuthenticatedSession()).toBe(locker);
    expect(masterKeyFromSession).toHaveBeenCalledOnce();
    expect(openLocker).toHaveBeenCalledOnce();
});

test("logout during WASM initialization frees the unused handle and permits a new session", async () => {
    const ready = Promise.withResolvers<Session>();
    const started = Promise.withResolvers<undefined>();
    const previous = mockSession();
    const next = mockSession();
    openLocker
        .mockImplementationOnce(() => {
            started.resolve(undefined);
            return ready.promise;
        })
        .mockResolvedValueOnce(next);
    const opening = sessions.ensureAuthenticatedSession();
    await started.promise;
    sessions.clearAuthenticatedSession();
    expect(await sessions.ensureAuthenticatedSession()).toBe(next);
    ready.resolve(previous);

    await expect(opening).rejects.toThrow("Authenticated session was cleared");
    expect(previous.free).toHaveBeenCalledOnce();
    expect(await sessions.ensureAuthenticatedSession()).toBe(next);
    expect(next.free).not.toHaveBeenCalled();
    expect(openLocker).toHaveBeenCalledTimes(2);
});

test("failed opens can be retried and account changes replace the cached session", async () => {
    const previous = mockSession();
    const next = mockSession();
    openLocker
        .mockRejectedValueOnce(new Error("Download failed"))
        .mockResolvedValueOnce(previous)
        .mockResolvedValueOnce(next);
    await expect(sessions.ensureAuthenticatedSession()).rejects.toThrow(
        "Download failed",
    );
    expect(await sessions.ensureAuthenticatedSession()).toBe(previous);

    user.id = 2;
    savedAuthToken.mockResolvedValue("other-token");
    masterKeyFromSession.mockResolvedValue("other-key");
    expect(await sessions.ensureAuthenticatedSession()).toBe(next);
    expect(openLocker).toHaveBeenLastCalledWith({
        baseUrl: "http://localhost:8080",
        authToken: "other-token",
        userID: 2,
        masterKeyB64: "other-key",
        keyAttributes,
        clientPackage: "io.ente.locker.web",
        clientVersion: undefined,
    });
    expect(previous.free).not.toHaveBeenCalled();
});

const mockSession = () =>
    ({
        free: vi.fn(),
        updateAuthToken: vi.fn(),
        [Symbol.dispose]: vi.fn(),
    }) satisfies Session;
