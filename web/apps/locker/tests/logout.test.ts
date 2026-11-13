import { logoutClearStateAgain } from "ente-accounts/services/logout";
import { logoutContacts } from "ente-contacts";
import { afterEach, expect, test, vi } from "vitest";
import { openAuthenticatedSession } from "../src/services/authenticated-session";
import { lockerLogout } from "../src/services/logout";

const { apiOrigin, openSession, accountLogout } = vi.hoisted(() => ({
    apiOrigin: vi.fn<() => Promise<string>>(),
    openSession: vi.fn(() =>
        Promise.resolve({ free: vi.fn(), updateAuthToken: vi.fn() }),
    ),
    accountLogout: vi.fn<() => Promise<void>>(),
}));

vi.mock("ente-contacts", () => ({ logoutContacts: vi.fn() }));

vi.mock("ente-base/app", () => ({
    clientPackageName: "io.ente.locker.web",
    desktopAppVersion: undefined,
    isDesktop: false,
}));
vi.mock("ente-base/origins", () => ({ apiOrigin }));
vi.mock("ente-base/log", () => ({
    default: { info: vi.fn(), error: vi.fn() },
}));
vi.mock("ente-base/token", () => ({ savedAuthToken: vi.fn() }));
vi.mock("../src/services/account-keys", () => ({
    masterKeyFromSession: vi.fn(),
}));
vi.mock("ente-accounts/services/user", () => ({
    ensureLocalUser: () => ({ id: 1 }),
    ensureSavedKeyAttributes: () => ({
        publicKey: "public-key",
        encryptedSecretKey: "encrypted-secret-key",
        secretKeyDecryptionNonce: "secret-key-nonce",
        recoveryKeyEncryptedWithMasterKey: "encrypted-recovery-key",
        recoveryKeyDecryptionNonce: "recovery-key-nonce",
    }),
}));
vi.mock("ente-accounts/services/accounts-db", () => ({
    savedLocalUser: () => ({ id: 1 }),
}));
vi.mock("ente-accounts/services/logout", () => ({
    accountLogout,
    logoutClearStateAgain: vi.fn(),
}));
vi.mock("ente-locker-wasm", () => ({ openSession }));
vi.mock("../src/services/locker-db", () => ({ clearLockerDB: vi.fn() }));

afterEach(() => vi.unstubAllGlobals());

test("logout rejects pending sessions while account cleanup is pending", async () => {
    const origin = Promise.withResolvers<string>();
    const accountCleanup = Promise.withResolvers<undefined>();
    apiOrigin.mockReturnValue(origin.promise);
    accountLogout.mockReturnValue(accountCleanup.promise);
    const replace = vi.fn();
    vi.stubGlobal("window", { location: { replace } });

    const opening = openAuthenticatedSession(1, "token", "key");
    const loggingOut = lockerLogout();
    origin.resolve("http://localhost:8080");

    try {
        await expect(opening).rejects.toThrow(
            "Authenticated session was cleared",
        );
        expect(openSession).not.toHaveBeenCalled();
        expect(replace).not.toHaveBeenCalled();
    } finally {
        accountCleanup.resolve(undefined);
        await loggingOut;
    }
    expect(logoutContacts).toHaveBeenCalledOnce();
    expect(logoutClearStateAgain).toHaveBeenCalledOnce();
    expect(replace).toHaveBeenCalledExactlyOnceWith("/login");
});
