import { beforeEach, describe, expect, test, vi } from "vitest";

const getSession = vi.fn(() => Promise.resolve({}));

beforeEach(() => {
    vi.resetModules();
    vi.restoreAllMocks();
    vi.clearAllMocks();
    getSession.mockReset();
    vi.useRealTimers();
});

interface SetupOptions {
    diff?: object[];
    getProfilePictureError?: Error;
    getProfilePictureBytes?: Uint8Array;
    rootKeyResolved?: boolean;
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

    const apiOrigin = vi.fn(() => "https://api.example");
    const info = vi.fn();
    const warn = vi.fn();
    const error = vi.fn();
    let isRootKeyResolved = options.rootKeyResolved ?? true;
    const wrappedRootContactKey = {
        encryptedKey: "wrapped-root-key",
        header: "wrapped-header",
    };
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

    const getDiff = vi
        .fn()
        .mockImplementationOnce(() => {
            if (diff.length > 0) isRootKeyResolved = true;
            return Promise.resolve({
                records: diff,
                wrappedRootContactKey: isRootKeyResolved
                    ? wrappedRootContactKey
                    : undefined,
            });
        })
        .mockResolvedValueOnce({
            records: [],
            wrappedRootContactKey: isRootKeyResolved
                ? wrappedRootContactKey
                : undefined,
        });
    const getProfilePicture = vi.fn(() => {
        if (options.getProfilePictureBytes) {
            return Promise.resolve({
                bytes: options.getProfilePictureBytes,
                wrappedRootContactKey,
            });
        }
        return Promise.reject(
            options.getProfilePictureError ?? new Error("boom"),
        );
    });
    vi.doMock("ente-base/kv", () => ({ getKV, getKVN, setKV }));
    vi.doMock("ente-base/origins", () => ({ apiOrigin }));
    vi.doMock("ente-base/log", () => ({
        default: { info, warn, error },
        logToDisk: vi.fn(),
    }));
    const contacts = await import("./index");

    return { contacts, setKV, getDiff, getProfilePicture, info };
};

describe("contacts synchronization", () => {
    test("initializes locally before pulling and persisting contacts", async () => {
        const { contacts, getDiff, getProfilePicture, setKV } =
            await setupContactsModule();

        await contacts.initContacts(
            101,
            getSession,
            getDiff,
            getProfilePicture,
        );
        expect(getSession).not.toHaveBeenCalled();
        expect(getDiff).not.toHaveBeenCalled();
        expect(contacts.contactsDisplaySnapshot().isHydrated).toBe(true);
        await contacts.pullContacts();
        expect(getSession).toHaveBeenCalledOnce();

        const persisted = setKV.mock.calls
            .map(([key, value]) => `${key}:${JSON.stringify(value)}`)
            .join("\n");

        expect(persisted).toContain("contacts/");
        expect(persisted).toContain("wrapped-root-key");
        expect(persisted).toContain("Set");

        const resolved = contacts.resolveContactDisplay({ userID: 101 });
        expect(resolved.profilePictureAttachmentID).toBe("ua_1");
    });

    test("does not persist an unresolved wrapped root contact key", async () => {
        const { contacts, getDiff, getProfilePicture, setKV } =
            await setupContactsModule({ rootKeyResolved: false, diff: [] });

        await contacts.initContacts(
            101,
            getSession,
            getDiff,
            getProfilePicture,
        );
        await contacts.pullContacts();

        const persisted = setKV.mock.calls
            .map(([key, value]) => `${key}:${JSON.stringify(value)}`)
            .join("\n");

        expect(persisted).not.toContain("wrapped-root-key");
    });

    test("persists a resolved wrapped root contact key after non-empty diff", async () => {
        const { contacts, getDiff, getProfilePicture, setKV } =
            await setupContactsModule({ rootKeyResolved: false });

        await contacts.initContacts(
            101,
            getSession,
            getDiff,
            getProfilePicture,
        );
        await contacts.pullContacts();

        const persisted = setKV.mock.calls
            .map(([key, value]) => `${key}:${JSON.stringify(value)}`)
            .join("\n");

        expect(persisted).toContain("wrapped-root-key");
    });
});

test("each pull and avatar load acquires the current session", async () => {
    const first = { token: "first" };
    const second = { token: "second" };
    const third = { token: "third" };
    getSession
        .mockResolvedValueOnce(first)
        .mockResolvedValueOnce(second)
        .mockResolvedValueOnce(third);
    const { contacts, getDiff, getProfilePicture } =
        await setupContactsModule();

    await contacts.initContacts(101, getSession, getDiff, getProfilePicture);
    await contacts.pullContacts();
    expect(getDiff.mock.calls[0]?.[0]).toBe(first);
    expect(getDiff.mock.calls[1]?.[0]).toBe(first);

    getDiff.mockResolvedValue({ records: [] });
    await contacts.pullContacts();
    expect(getDiff.mock.lastCall?.[0]).toBe(second);

    await contacts.__testing.preloadResolvedContactAvatar({ userID: 101 });
    expect(getProfilePicture).toHaveBeenCalledWith(
        third,
        expect.anything(),
        "ct_1",
    );
    expect(getSession).toHaveBeenCalledTimes(3);
});

test("logout while acquiring a session prevents the pull", async () => {
    const pending = Promise.withResolvers<object>();
    getSession.mockReturnValueOnce(pending.promise);
    const { contacts, getDiff, getProfilePicture } =
        await setupContactsModule();
    await contacts.initContacts(101, getSession, getDiff, getProfilePicture);

    const pulling = contacts.pullContacts();
    expect(getSession).toHaveBeenCalledOnce();
    contacts.logoutContacts();
    pending.resolve({});
    await pulling;
    expect(getDiff).not.toHaveBeenCalled();
});

describe("profile picture loading", () => {
    test("negative-caches failed profile picture fetches and logs at info", async () => {
        const { contacts, getDiff, getProfilePicture, info } =
            await setupContactsModule({
                getProfilePictureError: new Error("network failure"),
            });

        await contacts.initContacts(
            101,
            getSession,
            getDiff,
            getProfilePicture,
        );
        await contacts.pullContacts();

        await contacts.__testing.preloadResolvedContactAvatar({
            userID: 101,
            email: "set@test.test",
        });
        await contacts.__testing.preloadResolvedContactAvatar({
            userID: 101,
            email: "set@test.test",
        });

        expect(getProfilePicture).toHaveBeenCalledTimes(1);
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
        const { contacts, getDiff, getProfilePicture } =
            await setupContactsModule({ getProfilePictureBytes: pngBytes });

        await contacts.initContacts(
            101,
            getSession,
            getDiff,
            getProfilePicture,
        );
        await contacts.pullContacts();
        await contacts.__testing.preloadResolvedContactAvatar({ userID: 101 });

        const blobArg = createObjectURL.mock.calls[0]?.[0] as Blob | undefined;
        expect(blobArg?.type).toBe("image/png");
    });

    test.each(["refresh", "account change", "avatar change"])(
        "handles an in-flight avatar during a contacts %s",
        async (change) => {
            const createObjectURL = vi
                .spyOn(URL, "createObjectURL")
                .mockReturnValue("blob:contact");
            const { contacts, getDiff, getProfilePicture } =
                await setupContactsModule();
            await contacts.initContacts(
                101,
                getSession,
                getDiff,
                getProfilePicture,
            );
            await contacts.pullContacts();

            const picture =
                Promise.withResolvers<
                    Awaited<ReturnType<typeof getProfilePicture>>
                >();
            getProfilePicture.mockReturnValueOnce(picture.promise);
            const loading = contacts.__testing.preloadResolvedContactAvatar({
                userID: 101,
            });

            getDiff.mockResolvedValue({ records: [] });
            if (change === "avatar change") {
                getDiff.mockResolvedValueOnce({
                    records: [
                        {
                            id: "ct_1",
                            contactUserId: 101,
                            profilePictureAttachmentID: "ua_2",
                            isDeleted: false,
                            updatedAt: 2,
                        },
                    ],
                });
            }
            await contacts.initContacts(
                change === "account change" ? 202 : 101,
                getSession,
                getDiff,
                getProfilePicture,
            );
            await contacts.pullContacts();

            picture.resolve({
                bytes: new Uint8Array([1, 2, 3]),
                wrappedRootContactKey: {
                    encryptedKey: "wrapped-root-key",
                    header: "wrapped-header",
                },
            });
            await loading;
            expect(createObjectURL).toHaveBeenCalledTimes(
                change === "refresh" ? 1 : 0,
            );
        },
    );
});

describe("retry after warm-up failure", () => {
    test("recovers from a transient failure with bounded background retry", async () => {
        vi.useFakeTimers();
        const { contacts, getDiff, getProfilePicture } =
            await setupContactsModule();
        getDiff.mockReset();
        getDiff
            .mockRejectedValueOnce(new Error("transient"))
            .mockResolvedValueOnce({
                records: [
                    {
                        id: "ct_1",
                        contactUserId: 101,
                        email: "set@test.test",
                        name: "Set",
                        profilePictureAttachmentID: "ua_1",
                        isDeleted: false,
                        updatedAt: 1,
                    },
                ],
            })
            .mockResolvedValueOnce({ records: [] });

        await contacts.initContacts(
            101,
            getSession,
            getDiff,
            getProfilePicture,
        );
        const ready = contacts.pullContacts();
        await vi.advanceTimersByTimeAsync(10_001);
        await expect(ready).resolves.toBeUndefined();

        expect(getDiff).toHaveBeenCalledTimes(3);
    });

    test("stops after bounded background retries keep failing", async () => {
        vi.useFakeTimers();
        const { contacts, getDiff, getProfilePicture } =
            await setupContactsModule();
        getDiff.mockReset();
        getDiff.mockRejectedValue(new Error("down"));

        await contacts.initContacts(
            101,
            getSession,
            getDiff,
            getProfilePicture,
        );
        const ready = expect(contacts.pullContacts()).rejects.toThrow("down");

        await vi.advanceTimersByTimeAsync(10_001);
        await vi.advanceTimersByTimeAsync(30_001);
        await vi.advanceTimersByTimeAsync(120_001);
        await ready;

        expect(getDiff).toHaveBeenCalledTimes(4);
        await vi.advanceTimersByTimeAsync(300_000);
        expect(getDiff).toHaveBeenCalledTimes(4);
    });

    test("a stale retry does not update a newer session", async () => {
        vi.useFakeTimers();
        const { contacts, getDiff, getProfilePicture } =
            await setupContactsModule();
        getDiff.mockReset();
        getDiff
            .mockRejectedValueOnce(new Error("transient"))
            .mockResolvedValue({ records: [] });

        await contacts.initContacts(
            101,
            getSession,
            getDiff,
            getProfilePicture,
        );
        const stalePull = contacts.pullContacts();
        await vi.advanceTimersByTimeAsync(0);
        expect(getDiff).toHaveBeenCalledTimes(1);

        contacts.logoutContacts();
        await contacts.pullContacts();
        expect(getDiff).toHaveBeenCalledTimes(1);

        await contacts.initContacts(
            101,
            getSession,
            getDiff,
            getProfilePicture,
        );
        await contacts.pullContacts();
        expect(getDiff).toHaveBeenCalledTimes(2);

        await vi.advanceTimersByTimeAsync(10_001);
        await expect(stalePull).resolves.toBeUndefined();
        expect(getDiff).toHaveBeenCalledTimes(2);
    });
});

describe("logout", () => {
    test("revokes cached avatars and notifies subscribers", async () => {
        vi.spyOn(URL, "createObjectURL").mockReturnValue("blob:contact");
        const revoke = vi
            .spyOn(URL, "revokeObjectURL")
            .mockImplementation(() => undefined);
        const { contacts, getDiff, getProfilePicture } =
            await setupContactsModule({
                getProfilePictureBytes: new Uint8Array([1, 2, 3]),
            });
        await contacts.initContacts(
            101,
            getSession,
            getDiff,
            getProfilePicture,
        );
        await contacts.pullContacts();
        await contacts.__testing.preloadResolvedContactAvatar({ userID: 101 });
        const changed = vi.fn();
        contacts.contactsDisplaySubscribe(changed);

        contacts.logoutContacts();

        expect(revoke).toHaveBeenCalledWith("blob:contact");
        expect(changed).toHaveBeenCalledOnce();
        expect(
            contacts.contactsDisplaySnapshot().avatarURLsByContactID.size,
        ).toBe(0);
    });
});
