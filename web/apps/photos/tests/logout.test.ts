import { afterEach, expect, test, vi } from "vitest";
import { openAuthenticatedSession } from "../src/services/authenticated-session";
import { photosLogout } from "../src/services/logout";

const {
    apiOrigin,
    encryptBoxWithRecoveryKey,
    generateKey,
    openSession,
    terminateMLWorker,
} = vi.hoisted(() => ({
    apiOrigin: vi.fn<() => Promise<string>>(),
    encryptBoxWithRecoveryKey: vi.fn(),
    generateKey: vi.fn(),
    openSession: vi.fn(() =>
        Promise.resolve({ free: vi.fn(), updateAuthToken: vi.fn() }),
    ),
    terminateMLWorker: vi.fn<() => Promise<void>>(),
}));

vi.mock("ente-base/app", () => ({
    clientPackageName: "io.ente.photos.web",
    desktopAppVersion: undefined,
    isDesktop: false,
}));
vi.mock("ente-base/origins", () => ({ apiOrigin }));
vi.mock("ente-base/session", () => ({ masterKeyFromSession: vi.fn() }));
vi.mock("ente-base/token", () => ({ savedAuthToken: vi.fn() }));
vi.mock("ente-base/log", () => ({
    default: { info: vi.fn(), error: vi.fn() },
}));
vi.mock("ente-photos-wasm", () => ({
    encryptBoxWithRecoveryKey,
    generateKey,
    openSession,
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
vi.mock("ente-accounts/services/logout", () => ({
    accountLogout: vi.fn(),
    logoutClearStateAgain: vi.fn(),
}));
vi.mock("@/services/export", () => ({
    default: { disableContinuousExport: vi.fn() },
}));
vi.mock("ente-gallery/components/utils/save-groups", () => ({
    resetSaveGroups: vi.fn(),
}));
vi.mock("ente-gallery/components/viewer/data-source", () => ({
    logoutFileViewerDataSource: vi.fn(),
}));
vi.mock("ente-gallery/services/download", () => ({
    downloadManager: { logout: vi.fn() },
}));
vi.mock("ente-gallery/services/files-db", () => ({ clearFilesDB: vi.fn() }));
vi.mock("ente-gallery/services/upload", () => ({ resetUploadState: vi.fn() }));
vi.mock("ente-gallery/services/video", () => ({ resetVideoState: vi.fn() }));
vi.mock("ente-new/photos/services/app-lock", () => ({
    logoutAppLock: vi.fn(),
}));
vi.mock("ente-new/photos/services/ml", () => ({
    terminateMLWorker,
    logoutML: vi.fn(),
}));
vi.mock("ente-new/photos/services/collection", () => ({
    bindCollectionKeyOpener: vi.fn(),
    unbindCollectionKeyOpener: vi.fn(),
}));
vi.mock("ente-new/photos/services/search", () => ({ logoutSearch: vi.fn() }));
vi.mock("ente-new/photos/services/settings", () => ({
    logoutSettings: vi.fn(),
}));
vi.mock("ente-new/photos/services/user-details", () => ({
    logoutUserDetails: vi.fn(),
}));
vi.mock("../src/services/upload-manager", () => ({
    uploadManager: { logout: vi.fn() },
}));

afterEach(() => vi.unstubAllGlobals());

test("logout rejects pending sessions while worker shutdown is pending", async () => {
    const origin = Promise.withResolvers<string>();
    const workerShutdown = Promise.withResolvers<undefined>();
    apiOrigin.mockReturnValue(origin.promise);
    terminateMLWorker.mockReturnValue(workerShutdown.promise);
    vi.stubGlobal("window", { location: { replace: vi.fn() } });

    const opening = openAuthenticatedSession(1, "token", "key");
    const loggingOut = photosLogout();
    origin.resolve("http://localhost:8080");

    try {
        await expect(opening).rejects.toThrow(
            "Authenticated session was cleared",
        );
        expect(openSession).not.toHaveBeenCalled();
    } finally {
        workerShutdown.resolve(undefined);
        await loggingOut;
    }
});
