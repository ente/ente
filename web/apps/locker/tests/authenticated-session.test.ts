import type { Session } from "ente-locker-wasm";
import { beforeEach, expect, test, vi } from "vitest";

const {
    apiOrigin,
    savedAuthToken,
    masterKeyFromSession,
    user,
    openLocker,
    openLegacy,
} = vi.hoisted(() => ({
    apiOrigin: vi.fn<() => Promise<string>>(),
    savedAuthToken: vi.fn<() => Promise<string>>(),
    masterKeyFromSession: vi.fn<() => Promise<string>>(),
    user: { id: 1 },
    openLocker: vi.fn<typeof import("ente-locker-wasm").openSession>(),
    openLegacy:
        vi.fn<typeof import("ente-legacy-wasm/authenticated").openSession>(),
}));

vi.mock("ente-base/app", () => ({
    clientPackageName: "io.ente.locker.web",
    desktopAppVersion: undefined,
    isDesktop: false,
}));
vi.mock("ente-base/origins", () => ({ apiOrigin }));
vi.mock("ente-base/token", () => ({ savedAuthToken }));
vi.mock("ente-accounts/services/session-storage", () => ({
    masterKeyFromSession,
}));
vi.mock("ente-accounts/services/user", () => ({ ensureLocalUser: () => user }));
vi.mock("ente-locker-wasm", () => ({ openSession: openLocker }));
vi.mock("ente-legacy-wasm/authenticated", () => ({ openSession: openLegacy }));

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

test("opens each artifact only when needed, reuses sessions, and clears both at logout", async () => {
    const locker = mockSession();
    const legacy = mockSession();
    openLocker.mockResolvedValue(locker);
    openLegacy.mockResolvedValue(legacy);

    expect(openLocker).not.toHaveBeenCalled();
    expect(openLegacy).not.toHaveBeenCalled();
    expect(await sessions.openAuthenticatedSession(1, "token", "key")).toBe(
        locker,
    );
    expect(openLegacy).not.toHaveBeenCalled();

    const first = sessions.authenticatedLegacySession();
    const second = sessions.authenticatedLegacySession();
    expect(await first).toBe(legacy);
    expect(await second).toBe(legacy);
    savedAuthToken.mockResolvedValue("rotated-token");
    expect(await sessions.authenticatedLegacySession()).toBe(legacy);
    expect(legacy.updateAuthToken).toHaveBeenLastCalledWith("rotated-token");
    expect(openLegacy).toHaveBeenCalledTimes(1);

    sessions.clearAuthenticatedSession();
    expect(locker.free).not.toHaveBeenCalled();
    expect(legacy.free).not.toHaveBeenCalled();
    await sessions.openAuthenticatedSession(1, "rotated-token", "key");
    expect(openLocker).toHaveBeenCalledTimes(2);
    expect(openLegacy).toHaveBeenCalledTimes(1);
    await sessions.authenticatedLegacySession();
    expect(openLegacy).toHaveBeenCalledTimes(2);
});

test("logout during credential lookup cannot reopen a Legacy session", async () => {
    const key = Promise.withResolvers<string>();
    masterKeyFromSession.mockReturnValue(key.promise);
    const opening = sessions.authenticatedLegacySession();
    sessions.clearAuthenticatedSession();
    key.resolve("key");

    await expect(opening).rejects.toThrow("Authenticated session was cleared");
    expect(openLegacy).not.toHaveBeenCalled();
});

test("logout during WASM initialization frees the unused handle and permits a new session", async () => {
    const ready = Promise.withResolvers<Session>();
    const started = Promise.withResolvers<undefined>();
    const previous = mockSession();
    const next = mockSession();
    openLegacy
        .mockImplementationOnce(() => {
            started.resolve(undefined);
            return ready.promise;
        })
        .mockResolvedValueOnce(next);
    const opening = sessions.authenticatedLegacySession();
    await started.promise;
    sessions.clearAuthenticatedSession();
    expect(await sessions.authenticatedLegacySession()).toBe(next);
    ready.resolve(previous);

    await expect(opening).rejects.toThrow("Authenticated session was cleared");
    expect(previous.free).toHaveBeenCalledOnce();
    expect(await sessions.authenticatedLegacySession()).toBe(next);
    expect(next.free).not.toHaveBeenCalled();
    expect(openLegacy).toHaveBeenCalledTimes(2);
});

test("failed opens can be retried and account changes replace the cached Legacy session", async () => {
    const previous = mockSession();
    const next = mockSession();
    openLegacy
        .mockRejectedValueOnce(new Error("Download failed"))
        .mockResolvedValueOnce(previous)
        .mockResolvedValueOnce(next);
    await expect(sessions.authenticatedLegacySession()).rejects.toThrow(
        "Download failed",
    );
    expect(await sessions.authenticatedLegacySession()).toBe(previous);

    user.id = 2;
    savedAuthToken.mockResolvedValue("other-token");
    masterKeyFromSession.mockResolvedValue("other-key");
    expect(await sessions.authenticatedLegacySession()).toBe(next);
    expect(openLegacy).toHaveBeenLastCalledWith({
        baseUrl: "http://localhost:8080",
        authToken: "other-token",
        masterKeyB64: "other-key",
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
