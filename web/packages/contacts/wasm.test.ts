import {
    boxSealOpen,
    encryptBlob,
    encryptBox,
    generateKey,
    generateKeyPair,
} from "ente-core-wasm";
import * as legacy from "ente-legacy-wasm/authenticated";
import * as locker from "ente-locker-wasm";
import * as photos from "ente-photos-wasm";
import { afterEach, describe, expect, test, vi } from "vitest";

afterEach(() => vi.unstubAllGlobals());

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
                            diff: Array.from({ length: 1000 }, (_, i) => ({
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
            });
            try {
                const diff = await api.contactsGetDiff(
                    session,
                    fixture.wrappedRootContactKey,
                    0,
                    1000,
                );
                expect(diff).toStrictEqual({
                    records: Array.from({ length: 1000 }, (_, i) => ({
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

            const session = await api.openSession({
                baseUrl: "http://localhost",
                authToken: "test-token",
                masterKeyB64: await generateKey(),
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

describe("Legacy", () => {
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
                    return new Response(
                        "Cannot update during an active recovery session",
                        { status: 400 },
                    );
                default:
                    throw new Error(`Unexpected request: ${request.url}`);
            }
        });
        const session = await legacy.openSession({
            baseUrl: "http://localhost",
            authToken: "token",
            masterKeyB64: await generateKey(),
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
            recovery.createdAt = Number.MAX_SAFE_INTEGER + 1;
            await expect(legacy.getInfo(session)).rejects.toBeInstanceOf(Error);
        } finally {
            session.free();
        }
    });

    test("uses the typed key attributes to share a decryptable recovery key", async () => {
        const masterKey = await generateKey();
        const recoveryKey = await generateKey();
        const encryptedRecoveryKey = await encryptBox(recoveryKey, masterKey);
        const recipient = await generateKeyPair();
        const keyAttributes = {
            kekSalt: "",
            encryptedKey: "",
            keyDecryptionNonce: "",
            publicKey: "",
            encryptedSecretKey: "",
            secretKeyDecryptionNonce: "",
            memLimit: 0,
            opsLimit: 0,
            recoveryKeyEncryptedWithMasterKey:
                encryptedRecoveryKey.encryptedData,
            recoveryKeyDecryptionNonce: encryptedRecoveryKey.nonce,
        };
        let sharedRecoveryKey: string | undefined;
        mockFetch(async (request) => {
            switch (new URL(request.url).pathname) {
                case "/users/public-key":
                    return Response.json({ publicKey: recipient.publicKey });
                case "/emergency-contacts/add": {
                    const body = (await request.json()) as {
                        email: string;
                        encryptedKey: string;
                        recoveryNoticeInDays: number;
                    };
                    expect(body.email).toBe("friend@example.com");
                    expect(body.recoveryNoticeInDays).toBe(30);
                    sharedRecoveryKey = await boxSealOpen(
                        body.encryptedKey,
                        recipient,
                    );
                    return new Response(null, { status: 204 });
                }
                default:
                    throw new Error(`Unexpected request: ${request.url}`);
            }
        });
        const session = await legacy.openSession({
            baseUrl: "http://localhost",
            authToken: "token",
            masterKeyB64: masterKey,
        });
        try {
            await legacy.addContact(
                session,
                "friend@example.com",
                keyAttributes,
                30,
            );
            expect(sharedRecoveryKey).toBe(recoveryKey);
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

const encryptedContact = async () => {
    const masterKey = await generateKey();
    const rootKey = await generateKey();
    const contactKey = await generateKey();
    const wrappedRootKey = await encryptBox(rootKey, masterKey);
    const wrappedContactKey = await encryptBox(contactKey, rootKey);
    const data = await encryptBlob(
        Buffer.from(
            JSON.stringify({ contactUserId: 42, name: "Zoë 🦋" }),
        ).toString("base64"),
        contactKey,
    );
    const picture = Uint8Array.from({ length: 4096 }, (_, i) => i % 256);
    const encryptedPicture = await encryptBlob(
        Buffer.from(picture).toString("base64"),
        contactKey,
    );
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
