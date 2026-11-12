import { createHmac } from "node:crypto";
import { expect, test, vi } from "vitest";
import {
    createAccountsClient,
    deriveKey,
    encryptBox,
    getTwoFactorRecovery,
    recoverTwoFactor,
    recoveryKeyToMnemonic,
} from "../index";
import {
    authGenerateSrpSetup,
    cryptoGenerateKey,
} from "../pkg/ente_prelogin_wasm.js";

test("rejects unsupported password derivation limits", async () => {
    await expect(
        deriveKey("password", Buffer.alloc(16).toString("base64"), 5, 2 ** 32),
    ).rejects.toThrow("Password derivation exceeds supported resource limits");
});

test("generates SRP setup attributes from a kek", () => {
    const kek = cryptoGenerateKey();
    const generated = authGenerateSrpSetup(kek, "test-user-id");

    expect(generated.srpUserID).toBe("test-user-id");
    expect(Buffer.from(generated.srpSalt, "base64")).toHaveLength(16);
    expect(Buffer.from(generated.loginSubKey, "base64")).toHaveLength(16);
    expect(Buffer.from(generated.srpVerifier, "base64").length).toBeGreaterThan(
        0,
    );
});

test("recovers TOTP and passkey through Rust with session-bound recovery proofs", async () => {
    const recoveryKey = cryptoGenerateKey();
    const recoveryKeyHex = Buffer.from(recoveryKey, "base64").toString("hex");
    const authorization = {
        id: 123,
        encryptedToken: "sealed-token",
        keyAttributes: {
            kekSalt: "salt",
            encryptedKey: "key",
            keyDecryptionNonce: "nonce",
            publicKey: "public-key",
            encryptedSecretKey: "private-key",
            secretKeyDecryptionNonce: "private-key-nonce",
            memLimit: 67_108_864,
            opsLimit: 2,
        },
    };
    const factors = [
        ["totp", "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"],
        ["passkey", cryptoGenerateKey()],
    ] as const;
    try {
        for (const [factor, secret] of factors) {
            const clientVersion = factor == "totp" ? undefined : "test";
            const client = await createAccountsClient({
                origin: "http://localhost",
                clientPackage: "io.ente.auth.web",
                ...(clientVersion && { clientVersion }),
            });
            const encrypted = await encryptBox(secret, recoveryKey);
            const envelope = {
                encryptedSecret: encrypted.encryptedData,
                secretDecryptionNonce: encrypted.nonce,
            };
            let status = 200;
            const fetch = vi.fn(async (request: Request) => {
                const url = new URL(request.url);
                expect(url.origin).toBe("http://localhost");
                expect(request.headers.get("X-Client-Package")).toBe(
                    "io.ente.auth.web",
                );
                expect(request.headers.get("X-Client-Version")).toBe(
                    clientVersion ?? null,
                );
                expect(request.headers.get("X-Auth-Token")).toBeNull();
                if (request.method == "GET") {
                    expect(url.pathname).toBe("/users/two-factor/recover");
                    expect(Object.fromEntries(url.searchParams)).toStrictEqual({
                        sessionID: "recovery-session",
                        twoFactorType: factor,
                    });
                } else {
                    expect(request.method).toBe("POST");
                    expect(url.pathname).toBe("/users/two-factor/remove");
                    expect(await request.json()).toStrictEqual({
                        sessionID: "recovery-session",
                        twoFactorType: factor,
                        proof: createHmac("sha256", secret)
                            .update(`recovery:${factor}:recovery-session`)
                            .digest("base64"),
                    });
                }
                const response = Response.json(
                    request.method == "GET" ? envelope : authorization,
                    { status },
                );
                Object.defineProperty(response, "url", { value: request.url });
                return response;
            });
            vi.stubGlobal("fetch", fetch);
            const get = () =>
                getTwoFactorRecovery(client, factor, "recovery-session");
            expect(await get()).toStrictEqual(envelope);
            const recover = (key: string) =>
                recoverTwoFactor(
                    client,
                    factor,
                    "recovery-session",
                    envelope,
                    key,
                );
            await expect(recover("ff".repeat(32))).rejects.toMatchObject({
                name: "incorrect_recovery_key",
            });
            expect(fetch).toHaveBeenCalledTimes(1);
            const key =
                factor == "totp"
                    ? recoveryKeyHex
                    : await recoveryKeyToMnemonic(recoveryKey);
            await expect(recover(key)).resolves.toStrictEqual(authorization);
            expect(fetch).toHaveBeenCalledTimes(2);
            status = 404;
            await expect(get()).rejects.toMatchObject({
                name: "session_expired",
            });
            status = 400;
            await expect(get()).rejects.toMatchObject({
                name:
                    factor == "passkey"
                        ? "two_factor_recovery_not_configured"
                        : "Error",
            });
            status = 403;
            await expect(get()).rejects.toMatchObject({ name: "Error" });
            status = 500;
            const calls = fetch.mock.calls.length;
            await expect(recover(key)).rejects.toMatchObject({ name: "Error" });
            expect(fetch).toHaveBeenCalledTimes(calls + 1);
            client.free();
        }
    } finally {
        vi.unstubAllGlobals();
    }
});
