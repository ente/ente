import { expect, test } from "vitest";
import { deriveKey } from "../index";
import {
    authDeriveSrpLoginKey,
    authGenerateInteractiveKek,
    authGenerateSrpSetup,
    cryptoGenerateKey,
} from "../pkg/ente_prelogin_wasm.js";

test("generates an interactive kek bundle", async () => {
    const generated = authGenerateInteractiveKek(
        "correct horse battery staple",
    );

    expect(Buffer.from(generated.key, "base64")).toHaveLength(32);
    expect(Buffer.from(generated.salt, "base64")).toHaveLength(16);
    expect(generated.memLimit).toBe(67_108_864);
    expect(generated.opsLimit).toBe(2);
    await expect(
        deriveKey(
            "correct horse battery staple",
            generated.salt,
            generated.opsLimit,
            generated.memLimit,
        ),
    ).resolves.toBe(generated.key);
    await expect(
        deriveKey("password", generated.salt, 5, 2 ** 32),
    ).rejects.toThrow("Password derivation exceeds supported resource limits");
});

test("generates SRP setup attributes from a kek", () => {
    const kek = cryptoGenerateKey();
    const generated = authGenerateSrpSetup(kek, "test-user-id");

    expect(Buffer.from(generated.srpSalt, "base64")).toHaveLength(16);
    expect(authDeriveSrpLoginKey(kek)).toBe(generated.loginSubKey);
    expect(Buffer.from(generated.loginSubKey, "base64")).toHaveLength(16);
    expect(Buffer.from(generated.srpVerifier, "base64").length).toBeGreaterThan(
        0,
    );
});
