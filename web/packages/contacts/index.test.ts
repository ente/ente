import { beforeEach, describe, expect, test, vi } from "vitest";
import { resolveContactDisplayFromSnapshot } from "./resolver";
import type { ContactsDisplaySnapshot } from "./types";

const makeSnapshot = (): ContactsDisplaySnapshot => ({
    isHydrated: true,
    recordsByUserID: new Map([
        [
            101,
            {
                contactId: "c_1",
                contactUserId: 101,
                resolvedEmail: "set@test.test",
                displayName: "Set",
                profilePictureAttachmentID: "a_1",
                updatedAt: 1,
            },
        ],
    ]),
    recordsByEmail: new Map([
        [
            "set@test.test",
            {
                contactId: "c_1",
                contactUserId: 101,
                resolvedEmail: "set@test.test",
                displayName: "Set",
                profilePictureAttachmentID: "a_1",
                updatedAt: 1,
            },
        ],
    ]),
    avatarURLsByContactID: new Map(),
});

describe("resolveContactDisplayFromSnapshot", () => {
    test("prefers contact name by user id", () => {
        const resolved = resolveContactDisplayFromSnapshot(makeSnapshot(), {
            userID: 101,
            email: "set@test.test",
        });

        expect(resolved.primaryLabel).toBe("Set");
        expect(resolved.actualEmail).toBe("set@test.test");
        expect(resolved.source).toBe("contact");
    });

    test("falls back to email when no contact exists", () => {
        const resolved = resolveContactDisplayFromSnapshot(makeSnapshot(), {
            email: "other@test.test",
        });

        expect(resolved.primaryLabel).toBe("other@test.test");
        expect(resolved.actualEmail).toBe("other@test.test");
        expect(resolved.source).toBe("fallback");
    });

    test("returns an empty label when no user or email exists", () => {
        const resolved = resolveContactDisplayFromSnapshot(makeSnapshot(), {});

        expect(resolved.primaryLabel).toBe("");
        expect(resolved.initial).toBe("?");
        expect(resolved.source).toBe("fallback");
    });
});

beforeEach(() => {
    vi.resetModules();
    vi.restoreAllMocks();
    vi.clearAllMocks();
    vi.useRealTimers();
});

interface SetupOptions {
    diff?: object[];
    legacyInfo?: object;
    getProfilePictureError?: Error;
    getProfilePictureBytes?: Uint8Array;
    rootKeySource?: "cache" | "unresolved";
    wrappedRootContactKey?: { encryptedKey: string; header: string };
    currentWrappedRootContactKey?: { encryptedKey: string; header: string };
}

const setupContactsModule = async (options: SetupOptions = {}) => {
    const kv = new Map<string, unknown>();
    const setKV = vi.fn((key: string, value: unknown) => {
        kv.set(key, JSON.parse(JSON.stringify(value)));
    });
    const getKV = vi.fn((key: string) => kv.get(key));
    const getKVN = vi.fn((key: string) => {
        const value = kv.get(key);
        return typeof value === "number" ? value : undefined;
    });

    const savedAuthToken = vi.fn((): string | undefined => "auth-token-secret");
    const apiOrigin = vi.fn(() => "https://api.example");
    const info = vi.fn();
    const warn = vi.fn();
    const error = vi.fn();
    const update_auth_token = vi.fn();
    const current_wrapped_root_contact_key = vi.fn(
        () =>
            options.currentWrappedRootContactKey ??
            options.wrappedRootContactKey ??
            (options.rootKeySource === "unresolved"
                ? { encryptedKey: "wrapped-root-key", header: "wrapped-header" }
                : {
                      encryptedKey: "wrapped-root-key",
                      header: "wrapped-header",
                  }),
    );
    const diff = options.diff ?? [
        {
            id: "ct_1",
            contactUserId: 101,
            email: "set@test.test",
            name: "Set",
            profilePictureAttachmentID: "ua_1",
            isDeleted: false,
            updatedAt: 1,
        },
    ];

    const get_diff = vi
        .fn()
        .mockResolvedValueOnce(diff)
        .mockResolvedValueOnce([]);
    const get_profile_picture = vi.fn(() => {
        if (options.getProfilePictureBytes) {
            return Promise.resolve(options.getProfilePictureBytes);
        }
        return Promise.reject(
            options.getProfilePictureError ?? new Error("boom"),
        );
    });
    const legacy_get_info = vi.fn(() =>
        Promise.resolve(
            options.legacyInfo ?? {
                contacts: [],
                recoverSessions: [],
                othersEmergencyContact: [],
                othersRecoverySession: [],
            },
        ),
    );

    vi.doMock("ente-base/kv", () => ({ getKV, getKVN, setKV }));
    vi.doMock("ente-base/token", () => ({ savedAuthToken }));
    vi.doMock("ente-base/origins", () => ({ apiOrigin }));
    vi.doMock("ente-base/log", () => ({ default: { info, warn, error } }));
    vi.doMock("ente-accounts-rs/services/session-storage", () => ({
        masterKeyFromSession: vi.fn(() => "MASTER_KEY"),
    }));
    vi.doMock("ente-accounts-rs/services/user", () => ({
        ensureLocalUser: vi.fn(() => ({ id: 101 })),
    }));
    vi.doMock("ente-base/app", () => ({
        appName: "photos",
        clientPackageName: "io.ente.photos.web",
        desktopAppVersion: undefined,
        isDesktop: false,
    }));
    vi.doMock("ente-wasm", () => ({
        contacts_open_ctx: vi.fn(() => ({
            ctx: {
                update_auth_token,
                current_wrapped_root_contact_key,
                get_diff,
                get_profile_picture,
                legacy_get_info,
            },
            wrappedRootContactKey:
                options.wrappedRootContactKey ??
                (options.rootKeySource === "unresolved"
                    ? undefined
                    : {
                          encryptedKey: "wrapped-root-key",
                          header: "wrapped-header",
                      }),
            rootKeySource: options.rootKeySource ?? "cache",
        })),
    }));

    const contacts = await import("./index");

    return {
        contacts,
        setKV,
        savedAuthToken,
        update_auth_token,
        get_diff,
        get_profile_picture,
        legacy_get_info,
        info,
    };
};

describe("ensureContactsReady", () => {
    test("does not persist auth token or master key in contacts kv", async () => {
        const { contacts, setKV } = await setupContactsModule();

        await contacts.ensureContactsReady({
            userID: 101,
            masterKeyB64: "MASTER_KEY_SHOULD_NOT_PERSIST",
        });

        const persisted = setKV.mock.calls
            .map(([key, value]) => `${key}:${JSON.stringify(value)}`)
            .join("\n");

        expect(persisted).toContain("contacts/");
        expect(persisted).toContain("wrapped-root-key");
        expect(persisted).toContain("Set");
        expect(persisted).not.toContain("MASTER_KEY_SHOULD_NOT_PERSIST");
        expect(persisted).not.toContain("auth-token-secret");

        const resolved = contacts.resolveContactDisplay({ userID: 101 });
        expect(resolved.profilePictureAttachmentID).toBe("ua_1");
    });

    test("does not persist an unresolved wrapped root contact key", async () => {
        const { contacts, setKV } = await setupContactsModule({
            rootKeySource: "unresolved",
            diff: [],
        });

        await contacts.ensureContactsReady({
            userID: 101,
            masterKeyB64: "MASTER_KEY_SHOULD_NOT_PERSIST",
        });

        const persisted = setKV.mock.calls
            .map(([key, value]) => `${key}:${JSON.stringify(value)}`)
            .join("\n");

        expect(persisted).not.toContain("wrapped-root-key");
    });

    test("persists a resolved wrapped root contact key after non-empty diff", async () => {
        const { contacts, setKV } = await setupContactsModule({
            rootKeySource: "unresolved",
        });

        await contacts.ensureContactsReady({
            userID: 101,
            masterKeyB64: "MASTER_KEY_SHOULD_NOT_PERSIST",
        });

        const persisted = setKV.mock.calls
            .map(([key, value]) => `${key}:${JSON.stringify(value)}`)
            .join("\n");

        expect(persisted).toContain("wrapped-root-key");
    });
});

describe("profile picture loading", () => {
    test("negative-caches failed profile picture fetches and logs at info", async () => {
        const { contacts, get_profile_picture, info } =
            await setupContactsModule({
                getProfilePictureError: new Error("network failure"),
            });

        await contacts.ensureContactsReady({
            userID: 101,
            masterKeyB64: "ignored",
        });

        await contacts.__testing.preloadResolvedContactAvatar({
            userID: 101,
            email: "set@test.test",
        });
        await contacts.__testing.preloadResolvedContactAvatar({
            userID: 101,
            email: "set@test.test",
        });

        expect(get_profile_picture).toHaveBeenCalledTimes(1);
        expect(info).toHaveBeenCalledTimes(1);
        expect(info.mock.calls[0]?.[0]).toContain(
            "Failed to load contact profile picture for ct_1",
        );
    });

    test("uses the inferred image mime type for avatar blobs", async () => {
        const createObjectURL = vi
            .spyOn(URL, "createObjectURL")
            .mockReturnValue("blob:contact");
        const pngBytes = Uint8Array.from([
            0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00,
            0x0d,
        ]);
        const { contacts } = await setupContactsModule({
            getProfilePictureBytes: pngBytes,
        });

        await contacts.ensureContactsReady({
            userID: 101,
            masterKeyB64: "ignored",
        });
        await contacts.__testing.preloadResolvedContactAvatar({ userID: 101 });

        const blobArg = createObjectURL.mock.calls[0]?.[0] as Blob | undefined;
        expect(blobArg?.type).toBe("image/png");
    });
});

describe("retry after warm-up failure", () => {
    test("recovers from a transient failure with bounded background retry", async () => {
        vi.useFakeTimers();
        const { contacts, get_diff } = await setupContactsModule();
        get_diff.mockReset();
        get_diff
            .mockRejectedValueOnce(new Error("transient"))
            .mockResolvedValueOnce([
                {
                    id: "ct_1",
                    contactUserId: 101,
                    email: "set@test.test",
                    name: "Set",
                    profilePictureAttachmentID: "ua_1",
                    isDeleted: false,
                    updatedAt: 1,
                },
            ])
            .mockResolvedValueOnce([]);

        const ready = contacts.ensureContactsReady({
            userID: 101,
            masterKeyB64: "ignored",
        });
        await vi.advanceTimersByTimeAsync(10_001);
        await expect(ready).resolves.toBeUndefined();

        expect(get_diff).toHaveBeenCalledTimes(3);
    });

    test("stops after bounded background retries keep failing", async () => {
        vi.useFakeTimers();
        const { contacts, get_diff } = await setupContactsModule();
        get_diff.mockReset();
        get_diff.mockRejectedValue(new Error("down"));

        const ready = expect(
            contacts.ensureContactsReady({
                userID: 101,
                masterKeyB64: "ignored",
            }),
        ).rejects.toThrow("down");

        await vi.advanceTimersByTimeAsync(10_001);
        await vi.advanceTimersByTimeAsync(30_001);
        await vi.advanceTimersByTimeAsync(120_001);
        await ready;

        expect(get_diff).toHaveBeenCalledTimes(4);
        await vi.advanceTimersByTimeAsync(300_000);
        expect(get_diff).toHaveBeenCalledTimes(4);
    });

    test("stale retry does not update a newer generation context token", async () => {
        vi.useFakeTimers();
        const { contacts, savedAuthToken, update_auth_token, get_diff } =
            await setupContactsModule();
        savedAuthToken
            .mockReturnValueOnce("old-token")
            .mockReturnValueOnce(undefined)
            .mockReturnValue("new-token");
        get_diff.mockReset();
        get_diff
            .mockRejectedValueOnce(new Error("transient"))
            .mockResolvedValueOnce([])
            .mockResolvedValueOnce([]);

        const staleReady = contacts.ensureContactsReady({
            userID: 101,
            masterKeyB64: "old-master-key",
        });
        await vi.advanceTimersByTimeAsync(0);
        expect(get_diff).toHaveBeenCalledTimes(1);

        await contacts.ensureContactsReady({
            userID: 101,
            masterKeyB64: "clearing-master-key",
        });
        expect(get_diff).toHaveBeenCalledTimes(1);

        await contacts.ensureContactsReady({
            userID: 101,
            masterKeyB64: "new-master-key",
        });
        expect(get_diff).toHaveBeenCalledTimes(2);

        await vi.advanceTimersByTimeAsync(10_001);
        await expect(staleReady).resolves.toBeUndefined();
        expect(update_auth_token).not.toHaveBeenCalled();
        expect(get_diff).toHaveBeenCalledTimes(2);
    });
});

describe("legacyGetInfo", () => {
    test("normalizes bigint legacy numeric fields at the API boundary", async () => {
        const { contacts } = await setupContactsModule({
            legacyInfo: {
                contacts: [
                    {
                        user: { id: 101n, email: "owner@test.test" },
                        emergencyContact: {
                            id: 202n,
                            email: "trusted@test.test",
                        },
                        state: "ACCEPTED",
                        recoveryNoticeInDays: 14n,
                    },
                ],
                recoverSessions: [
                    {
                        id: "session_1",
                        user: { id: 101n, email: "owner@test.test" },
                        emergencyContact: {
                            id: 202n,
                            email: "trusted@test.test",
                        },
                        status: "WAITING",
                        waitTill: 3_600_000_000n,
                        createdAt: 1_700_000_000_000_000n,
                    },
                ],
                othersEmergencyContact: [],
                othersRecoverySession: [],
            },
        });

        const info = await contacts.legacyGetInfo();

        expect(info.contacts[0]?.user.id).toBe(101);
        expect(info.contacts[0]?.emergencyContact.id).toBe(202);
        expect(info.contacts[0]?.recoveryNoticeInDays).toBe(14);
        expect(typeof info.contacts[0]?.user.id).toBe("number");
        expect(typeof info.contacts[0]?.emergencyContact.id).toBe("number");
        expect(typeof info.contacts[0]?.recoveryNoticeInDays).toBe("number");
        expect(info.recoverSessions[0]?.waitTill).toBe(3_600_000_000);
        expect(info.recoverSessions[0]?.createdAt).toBe(1_700_000_000_000_000);
        expect(typeof info.recoverSessions[0]?.waitTill).toBe("number");
        expect(typeof info.recoverSessions[0]?.createdAt).toBe("number");
    });
});
