import * as cast from "ente-cast-wasm";
import * as locker from "ente-locker-wasm";
import * as legacy from "ente-locker-wasm/legacy";
import * as photos from "ente-photos-wasm";
import { deriveKey, encryptBox, generateKey } from "ente-prelogin-wasm";
import { afterEach, describe, expect, test, vi } from "vitest";
import {
    cryptoBoxSeal,
    lockerPrepareFileLinkPayload,
} from "../locker/pkg/ente_locker_wasm";

afterEach(() => vi.unstubAllGlobals());

test("Photos deletion keeps summary fallback and decrypts the challenge in Rust", async () => {
    const masterKey = await generateKey();
    const input = await sessionKeyAttributes(masterKey);
    const encryptedChallenge = cryptoBoxSeal(
        Buffer.from("deletion-jwt").toString("base64"),
        input.keyAttributes.publicKey,
    );
    const summary = {
        photosAndVideosCount: 12,
        authenticatorCodesCount: 3,
        lockerRecordsCount: 4,
    };
    let summaryStatus = 404;
    let feedback: string | undefined;
    let deletions = 0;
    mockFetch(async (request) => {
        expect(request.headers.get("X-Auth-Token")).toBe("test-token");
        switch (new URL(request.url).pathname) {
            case "/users/deletion-summary":
                return summaryStatus == 200
                    ? Response.json(summary)
                    : new Response(null, { status: summaryStatus });
            case "/users/delete-challenge":
                return Response.json({ encryptedChallenge });
            case "/users/delete":
                expect(request.method).toBe("DELETE");
                expect(await request.json()).toStrictEqual({
                    challenge: "deletion-jwt",
                    reasonCategory: "not_listed",
                    ...(feedback && { feedback }),
                });
                deletions++;
                return Response.json({});
            default:
                throw new Error(`Unexpected request: ${request.url}`);
        }
    });
    const session = await photos.openSession({
        baseUrl: "http://localhost",
        authToken: "test-token",
        masterKeyB64: masterKey,
        ...input,
    });
    try {
        expect(await photos.getAccountDeletionSummary(session)).toBeUndefined();
        summaryStatus = 200;
        expect(await photos.getAccountDeletionSummary(session)).toStrictEqual(
            summary,
        );
        summaryStatus = 500;
        await expect(photos.getAccountDeletionSummary(session)).rejects.toThrow(
            "HTTP 500",
        );
        const challenge = await photos.getAccountDeleteChallenge(session);
        expect(challenge).toBe(encryptedChallenge);
        for (feedback of ["Feedback", undefined]) {
            await photos.deleteAccount(
                session,
                challenge,
                "not_listed",
                feedback,
            );
        }
        expect(deletions).toBe(2);
    } finally {
        session.free();
    }
});

test("Photos plans and executes duplicate removal in one WASM call", async () => {
    const masterKey = await generateKey();
    const input = await sessionKeyAttributes(masterKey);
    const albumKey = await generateKey();
    const fileKey = await generateKey();
    const requests: string[] = [];
    const progress: number[][] = [];
    mockFetch(async (request) => {
        expect(request.headers.get("X-Auth-Token")).toBe("test-token");
        const path = new URL(request.url).pathname;
        requests.push(path);
        const body = (await request.json()) as {
            collectionID: number;
            files: {
                id: number;
                encryptedKey: string;
                keyDecryptionNonce: string;
            }[];
        };
        if (path === "/collections/add-files") {
            expect(body.collectionID).toBe(11);
            expect(body.files).toHaveLength(1);
            expect(body.files[0]!.id).toBe(2);
            expect(
                await photos.decryptBox(
                    {
                        encryptedData: body.files[0]!.encryptedKey,
                        nonce: body.files[0]!.keyDecryptionNonce,
                    },
                    albumKey,
                ),
            ).toBe(fileKey);
        } else {
            expect(path).toBe("/files/trash");
            expect(requests).toEqual([
                "/collections/add-files",
                "/files/trash",
            ]);
            expect(body).toEqual({ items: [{ fileID: 1, collectionID: 11 }] });
        }
        return Response.json({});
    });
    const session = await photos.openSession({
        baseUrl: "http://localhost",
        authToken: "test-token",
        masterKeyB64: masterKey,
        ...input,
    });
    const removal = {
        groups: [
            [
                {
                    fileId: 1,
                    collectionIds: [11],
                    caption: undefined,
                    editedName: undefined,
                    editedTime: undefined,
                },
                {
                    fileId: 2,
                    collectionIds: [12],
                    caption: "keep",
                    editedName: undefined,
                    editedTime: undefined,
                },
            ],
        ],
        collections: [
            { id: 11, key: albumKey },
            { id: 99, key: await generateKey() },
        ],
        files: [
            { id: 1, collectionId: 11, key: await generateKey() },
            { id: 2, collectionId: 12, key: fileKey },
        ],
    };
    try {
        expect(
            await photos.executeDuplicateRemoval(
                session,
                removal,
                (completed, total) => progress.push([completed, total]),
            ),
        ).toEqual({ trashIds: [1] });
        expect(requests).toEqual(["/collections/add-files", "/files/trash"]);
        expect(progress).toEqual([
            [1, 2],
            [2, 2],
        ]);
        requests.length = 0;
        const invalid = structuredClone(removal);
        invalid.groups[0]![0]!.fileId = Number.MAX_SAFE_INTEGER + 1;
        await expect(
            photos.executeDuplicateRemoval(session, invalid, vi.fn()),
        ).rejects.toBeInstanceOf(Error);
        expect(requests).toEqual([]);
        expect(
            await photos.executeDuplicateRemoval(
                session,
                { groups: [], collections: [], files: [] },
                vi.fn(),
            ),
        ).toEqual({ trashIds: [] });
        expect(requests).toEqual([]);
    } finally {
        session.free();
    }
});

test.each(["classical", "post-quantum"])(
    "Photos %s Cast payloads round-trip and enforce safe collection IDs",
    async (encryption) => {
        const receiver = await cast.createCastReceiver();
        const collectionKey = await generateKey();
        try {
            for (const collectionID of [
                Number.MAX_SAFE_INTEGER,
                Number.MAX_SAFE_INTEGER + 1,
            ]) {
                const { castToken, encryptedPayload } =
                    await photos.prepareCastPayload(
                        receiver.publicKey,
                        encryption === "post-quantum"
                            ? receiver.pqPublicKey
                            : undefined,
                        collectionID,
                        collectionKey,
                    );
                if (Number.isSafeInteger(collectionID)) {
                    expect(
                        cast.openCastPayload(receiver, encryptedPayload),
                    ).toStrictEqual({ castToken, collectionID, collectionKey });
                } else {
                    expect(() =>
                        cast.openCastPayload(receiver, encryptedPayload),
                    ).toThrow(Error);
                }
            }
        } finally {
            receiver.free();
        }
    },
);

for (const [name, api] of [
    ["Photos", photos],
    ["Locker", locker],
] as const) {
    describe(name, () => {
        test("returns decrypted contacts and picture bytes as plain values", async () => {
            const fixture = await encryptedContact();
            mockFetch((request) => {
                switch (new URL(request.url).pathname) {
                    case "/contacts/diff":
                        return Response.json({
                            diff: Array.from({ length: 2 }, (_, i) => ({
                                ...fixture.contact,
                                id: `ct_${i}`,
                            })),
                        });
                    case "/contacts/ct_test":
                        return Response.json(fixture.contact);
                    case "/attachments/profile_picture/att_test":
                        return Response.json({
                            url: "http://localhost/picture",
                        });
                    case "/picture":
                        return new Response(fixture.encryptedPicture);
                    default:
                        throw new Error(`Unexpected request: ${request.url}`);
                }
            });

            const session = await api.openSession({
                baseUrl: "http://localhost",
                authToken: "test-token",
                masterKeyB64: fixture.masterKey,
                ...(await sessionKeyAttributes(fixture.masterKey)),
            });
            try {
                const diff = await api.contactsGetDiff(
                    session,
                    fixture.wrappedRootContactKey,
                    0,
                    2,
                );
                expect(diff).toStrictEqual({
                    records: Array.from({ length: 2 }, (_, i) => ({
                        id: `ct_${i}`,
                        contactUserId: 42,
                        email: "friend@example.com",
                        name: "Zoë 🦋",
                        profilePictureAttachmentID: "att_test",
                        isDeleted: false,
                        updatedAt: 1725000000000000,
                    })),
                    wrappedRootContactKey: fixture.wrappedRootContactKey,
                });

                const picture = await api.contactsGetProfilePicture(
                    session,
                    fixture.wrappedRootContactKey,
                    "ct_test",
                );
                expect(picture.bytes).toBeInstanceOf(Uint8Array);
                expect(picture).toStrictEqual({
                    bytes: fixture.picture,
                    wrappedRootContactKey: fixture.wrappedRootContactKey,
                });
            } finally {
                session.free();
            }
        });

        test("preserves tombstone optionals and rejects failures as Errors", async () => {
            const contact = {
                id: "ct_deleted",
                contactUserID: 42,
                isDeleted: true,
                createdAt: 100,
                updatedAt: 200,
            };
            mockFetch(() => Response.json({ diff: [contact] }));

            const masterKey = await generateKey();
            const session = await api.openSession({
                baseUrl: "http://localhost",
                authToken: "test-token",
                masterKeyB64: masterKey,
                ...(await sessionKeyAttributes(masterKey)),
            });
            try {
                expect(
                    await api.contactsGetDiff(session, undefined, 0, 1000),
                ).toStrictEqual({
                    records: [
                        {
                            id: "ct_deleted",
                            contactUserId: 42,
                            email: undefined,
                            name: undefined,
                            profilePictureAttachmentID: undefined,
                            isDeleted: true,
                            updatedAt: 200,
                        },
                    ],
                    wrappedRootContactKey: undefined,
                });

                contact.updatedAt = Number.MAX_SAFE_INTEGER + 1;
                await expect(
                    api.contactsGetDiff(session, undefined, 0, 1000),
                ).rejects.toBeInstanceOf(Error);

                mockFetch(() => new Response(null, { status: 500 }));
                await expect(
                    api.contactsGetDiff(session, undefined, 0, 1000),
                ).rejects.toBeInstanceOf(Error);
            } finally {
                session.free();
            }
        });
    });
}

test("Locker file-link payload survives cloning and unlocks its file key", async () => {
    const fileKey = await generateKey();
    const prepared = lockerPrepareFileLinkPayload(fileKey);
    const payload = structuredClone(prepared);
    expect(payload).toStrictEqual(prepared);

    const key = await deriveKey(
        payload.fragment,
        payload.kdfNonce,
        payload.kdfOpsLimit,
        payload.kdfMemLimit,
    );
    expect(
        await locker.decryptBox(
            {
                encryptedData: payload.encryptedFileKey,
                nonce: payload.encryptedFileKeyNonce,
            },
            key,
        ),
    ).toBe(fileKey);
});

describe("Locker Legacy", () => {
    test("returns plain information and sends typed updates through a reused session", async () => {
        const user = { id: 42, email: "owner@example.com" };
        const emergencyContact = { id: 43, email: "friend@example.com" };
        const contact = {
            user,
            emergencyContact,
            state: "ACCEPTED",
            recoveryNoticeInDays: 14,
        };
        const recovery = {
            id: "recovery-id",
            user,
            emergencyContact,
            status: "WAITING",
            waitTill: 14 * 86400 * 1000000,
            createdAt: 1725000000000000,
        };
        const info = {
            contacts: [contact],
            recoverSessions: [recovery],
            othersEmergencyContact: [{ ...contact, state: "INVITED" }],
            othersRecoverySession: [{ ...recovery, status: "READY" }],
        };
        let updateBody: unknown;
        let recoveryErrorBody: object = { code: "ACTIVE_RECOVERY_SESSION" };
        mockFetch(async (request) => {
            switch (new URL(request.url).pathname) {
                case "/emergency-contacts/info":
                    return Response.json(info);
                case "/emergency-contacts/update":
                    expect(request.headers.get("X-Auth-Token")).toBe(
                        "rotated-token",
                    );
                    updateBody = await request.json();
                    return new Response(null, { status: 204 });
                case "/emergency-contacts/update-recovery-notice":
                    return Response.json(recoveryErrorBody, { status: 400 });
                default:
                    throw new Error(`Unexpected request: ${request.url}`);
            }
        });
        const masterKey = await generateKey();
        const session = await locker.openSession({
            baseUrl: "http://localhost",
            authToken: "token",
            masterKeyB64: masterKey,
            ...(await sessionKeyAttributes(masterKey)),
        });
        try {
            expect(await legacy.getInfo(session)).toStrictEqual(info);
            session.updateAuthToken("rotated-token");
            await legacy.updateContact(session, 42, 43, "CONTACT_LEFT");
            expect(updateBody).toStrictEqual({
                userID: 42,
                emergencyContactID: 43,
                state: "CONTACT_LEFT",
            });
            await expect(
                legacy.updateRecoveryNotice(session, 43, 30),
            ).rejects.toMatchObject({ name: "active_recovery_session" });
            recoveryErrorBody = {
                code: "BAD_REQUEST",
                message: "Cannot update during an active recovery session",
            };
            await expect(
                legacy.updateRecoveryNotice(session, 43, 30),
            ).rejects.not.toMatchObject({ name: "active_recovery_session" });
            recovery.createdAt = Number.MAX_SAFE_INTEGER + 1;
            await expect(legacy.getInfo(session)).rejects.toBeInstanceOf(Error);
        } finally {
            session.free();
        }
    });
});

const mockFetch = (
    respond: (request: Request) => Response | Promise<Response>,
) =>
    vi.stubGlobal("fetch", async (request: Request) => {
        const response = await respond(request);
        // reqwest reads the response URL, which constructed Responses omit.
        Object.defineProperty(response, "url", { value: request.url });
        return response;
    });

const sessionKeyAttributes = async (
    masterKey: string,
    recoveryKey?: string,
) => {
    const publicKey = "W/Vcc7guviK+gPNDBmevVw+uJVamQV5rMNQGUwCqlH0=";
    const privateKey = "UEatwduoOIZ7K7v90MNCPli1eXC1JnqQ9XlgkkqH8ZY=";
    const encryptedSecretKey = await encryptBox(privateKey, masterKey);
    const encryptedRecoveryKey = await encryptBox(
        recoveryKey ?? (await generateKey()),
        masterKey,
    );
    return {
        userID: 42,
        keyAttributes: {
            publicKey,
            encryptedSecretKey: encryptedSecretKey.encryptedData,
            secretKeyDecryptionNonce: encryptedSecretKey.nonce,
            recoveryKeyEncryptedWithMasterKey:
                encryptedRecoveryKey.encryptedData,
            recoveryKeyDecryptionNonce: encryptedRecoveryKey.nonce,
        },
    };
};

const encryptedContact = async () => {
    const masterKey = await generateKey();
    const rootKey = await generateKey();
    const contactKey = await generateKey();
    const wrappedRootKey = await encryptBox(rootKey, masterKey);
    const wrappedContactKey = await encryptBox(contactKey, rootKey);
    const data = await locker.encryptBlob(
        Buffer.from(JSON.stringify({ contactUserId: 42, name: "Zoë 🦋" })),
        contactKey,
    );
    const picture = Uint8Array.from({ length: 4096 }, (_, i) => i % 256);
    const encryptedPicture = await locker.encryptBlob(picture, contactKey);
    const fixture = {
        masterKey,
        wrappedRootContactKey: {
            encryptedKey: wrappedRootKey.encryptedData,
            header: wrappedRootKey.nonce,
        },
        contact: {
            id: "ct_test",
            contactUserID: 42,
            email: "friend@example.com",
            profilePictureAttachmentID: "att_test",
            encryptedKey: combined(
                wrappedContactKey.nonce,
                wrappedContactKey.encryptedData,
            ).toString("base64"),
            encryptedData: combined(
                data.decryptionHeader,
                data.encryptedData,
            ).toString("base64"),
            isDeleted: false,
            createdAt: 100,
            updatedAt: 1725000000000000,
        },
        picture,
        encryptedPicture: combined(
            encryptedPicture.decryptionHeader,
            encryptedPicture.encryptedData,
        ),
    };
    return fixture;
};

const combined = (header: string, ciphertext: string) =>
    Buffer.concat([
        Buffer.from(header, "base64"),
        Buffer.from(ciphertext, "base64"),
    ]);
