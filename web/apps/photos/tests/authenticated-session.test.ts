import type { Session } from "ente-photos-wasm";
import { beforeEach, expect, test, vi } from "vitest";

const {
    apiOrigin,
    bindCollectionKeyOpener,
    encryptBoxWithRecoveryKey,
    generateKey,
    keyAttributes,
    masterKeyFromSession,
    openCollectionKey,
    openSession,
    savedAuthToken,
    unbindCollectionKeyOpener,
} = vi.hoisted(() => ({
    apiOrigin: vi.fn<() => Promise<string>>(),
    bindCollectionKeyOpener:
        vi.fn<
            typeof import("ente-new/photos/services/collection").bindCollectionKeyOpener
        >(),
    encryptBoxWithRecoveryKey:
        vi.fn<typeof import("ente-photos-wasm").encryptBoxWithRecoveryKey>(),
    generateKey: vi.fn<typeof import("ente-photos-wasm").generateKey>(),
    keyAttributes: {
        publicKey: "public-key",
        encryptedSecretKey: "encrypted-secret-key",
        secretKeyDecryptionNonce: "secret-key-nonce",
        recoveryKeyEncryptedWithMasterKey: "encrypted-recovery-key",
        recoveryKeyDecryptionNonce: "recovery-key-nonce",
    },
    masterKeyFromSession: vi.fn<() => Promise<string | undefined>>(),
    openCollectionKey:
        vi.fn<typeof import("ente-photos-wasm").openCollectionKey>(),
    openSession: vi.fn<typeof import("ente-photos-wasm").openSession>(),
    savedAuthToken: vi.fn<() => Promise<string | undefined>>(),
    unbindCollectionKeyOpener: vi.fn(),
}));

vi.mock("ente-base/app", () => ({
    clientPackageName: "io.ente.photos.web",
    desktopAppVersion: undefined,
    isDesktop: false,
}));
vi.mock("ente-base/origins", () => ({ apiOrigin }));
vi.mock("ente-accounts/services/user", () => ({
    ensureLocalUser: () => ({ id: 1 }),
    ensureSavedKeyAttributes: () => keyAttributes,
}));
vi.mock("ente-base/session", () => ({ masterKeyFromSession }));
vi.mock("ente-base/token", () => ({ savedAuthToken }));
vi.mock("ente-new/photos/services/collection", () => ({
    bindCollectionKeyOpener,
    unbindCollectionKeyOpener,
}));
vi.mock("ente-photos-wasm", () => ({
    encryptBoxWithRecoveryKey,
    generateKey,
    openCollectionKey,
    openSession,
}));

let sessions: typeof import("../src/services/authenticated-session");

beforeEach(async () => {
    vi.resetModules();
    vi.resetAllMocks();
    apiOrigin.mockResolvedValue("http://localhost:8080");
    masterKeyFromSession.mockResolvedValue("key");
    savedAuthToken.mockResolvedValue("token");
    sessions = await import("../src/services/authenticated-session");
});

const mockSession = () =>
    ({
        encryptWithRecoveryKey: vi.fn(),
        free: vi.fn(),
        recoveryKeyMnemonic: vi.fn(),
        updateAuthToken: vi.fn(),
        [Symbol.dispose]: vi.fn(),
    }) satisfies Session;

test("concurrent opens share a session and retain the latest token", async () => {
    const ready = Promise.withResolvers<Session>();
    const session = mockSession();
    openSession.mockReturnValue(ready.promise);

    const first = sessions.openAuthenticatedSession(1, "old-token", "key");
    const second = sessions.openAuthenticatedSession(1, "new-token", "key");
    await Promise.resolve();
    expect(openSession).toHaveBeenCalledTimes(1);

    ready.resolve(session);
    expect(await first).toBe(session);
    expect(await second).toBe(session);
    expect(session.updateAuthToken).toHaveBeenLastCalledWith("new-token");
    expect(await sessions.openAuthenticatedSession(1, "new-token", "key")).toBe(
        session,
    );
    expect(openSession).toHaveBeenCalledTimes(1);

    sessions.clearAuthenticatedSession();
    sessions.clearAuthenticatedSession();
    expect(session.free).not.toHaveBeenCalled();
    const next = mockSession();
    openSession.mockResolvedValueOnce(next);
    expect(await sessions.openAuthenticatedSession(1, "new-token", "key")).toBe(
        next,
    );
    expect(openSession).toHaveBeenCalledTimes(2);
});

test("the bound collection opener retries a failed initialization", async () => {
    const error = new Error("WASM download failed");
    const session = mockSession();
    openSession.mockRejectedValueOnce(error).mockResolvedValueOnce(session);

    const opening = sessions.openAuthenticatedSession(1, "token", "key");
    await Promise.resolve();
    const opener = bindCollectionKeyOpener.mock.calls[0]![0];
    await expect(opening).rejects.toBe(error);

    openCollectionKey.mockResolvedValue("collection-key");
    await expect(
        opener({
            ownerID: 1,
            encryptedKey: "encrypted-key",
            keyDecryptionNonce: "nonce",
        }),
    ).resolves.toBe("collection-key");
    expect(openSession).toHaveBeenCalledTimes(2);
    expect(openCollectionKey).toHaveBeenCalledWith(
        session,
        1,
        "encrypted-key",
        "nonce",
    );
});

test.each(["account", "origin"])(
    "changing the %s replaces the cached session without freeing active callers' handles",
    async (change) => {
        const previous = mockSession();
        const next = mockSession();
        openSession.mockResolvedValueOnce(previous).mockResolvedValueOnce(next);
        await sessions.openAuthenticatedSession(1, "token", "key");

        if (change === "origin") {
            apiOrigin.mockResolvedValue("http://localhost:8081");
        }
        const userID = change === "account" ? 2 : 1;
        expect(
            await sessions.openAuthenticatedSession(userID, "token", "key"),
        ).toBe(next);
        expect(previous.free).not.toHaveBeenCalled();
        expect(next.free).not.toHaveBeenCalled();
    },
);

test("clearing during origin lookup prevents initialization", async () => {
    const origin = Promise.withResolvers<string>();
    apiOrigin.mockReturnValue(origin.promise);
    const opening = sessions.openAuthenticatedSession(1, "token", "key");
    sessions.clearAuthenticatedSession();
    origin.resolve("http://localhost:8080");

    await expect(opening).rejects.toThrow("Authenticated session was cleared");
    expect(openSession).not.toHaveBeenCalled();
});

test("clearing during initialization disposes its eventual handle", async () => {
    const ready = Promise.withResolvers<Session>();
    const session = mockSession();
    openSession.mockReturnValue(ready.promise);
    const opening = sessions.openAuthenticatedSession(1, "token", "key");
    await Promise.resolve();

    sessions.clearAuthenticatedSession();
    expect(unbindCollectionKeyOpener).toHaveBeenCalledOnce();
    ready.resolve(session);
    await expect(opening).rejects.toThrow("Authenticated session was cleared");
    expect(session.free).toHaveBeenCalledTimes(1);
});

test.each(["resolve", "reject"])(
    "a replaced initialization cannot affect the new session when it %ss",
    async (outcome) => {
        const ready = Promise.withResolvers<Session>();
        const previous = mockSession();
        const next = mockSession();
        openSession
            .mockReturnValueOnce(ready.promise)
            .mockResolvedValueOnce(next);
        const opening = sessions.openAuthenticatedSession(
            1,
            "old-token",
            "key",
        );
        await Promise.resolve();
        await sessions.openAuthenticatedSession(2, "new-token", "key");

        if (outcome === "resolve") {
            ready.resolve(previous);
        } else {
            ready.reject(new Error("WASM download failed"));
        }
        await expect(opening).rejects.toThrow();
        expect(previous.free).toHaveBeenCalledTimes(
            outcome === "resolve" ? 1 : 0,
        );
        expect(next.free).not.toHaveBeenCalled();
        expect(
            await sessions.openAuthenticatedSession(2, "new-token", "key"),
        ).toBe(next);
        expect(openSession).toHaveBeenCalledTimes(2);
    },
);
