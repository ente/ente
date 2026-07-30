import {
    boxSealOpenBytes,
    decryptBox,
    toB64URLSafe,
} from "ente-accounts-rs/services/crypto";
import type { SRPSetupAttributes } from "ente-accounts-rs/services/srp";
import type { KeyAttributes } from "ente-accounts-rs/services/user";
import { ensureOk, publicRequestHeaders } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { loadEnteWasm } from "ente-wasm/load";
import { z } from "zod";

export const spaceBootstrapAuthHeaders = (authToken: string) => ({
    ...publicRequestHeaders(),
    "X-Auth-Token": authToken,
});

export const decryptSpaceBootstrapAuthToken = async (
    encryptedToken: string,
    keyAttributes: KeyAttributes,
    masterKey: string,
) => {
    const { encryptedSecretKey, secretKeyDecryptionNonce, publicKey } =
        keyAttributes;
    const privateKey = await decryptBox(
        { encryptedData: encryptedSecretKey, nonce: secretKeyDecryptionNonce },
        masterKey,
    );

    return toB64URLSafe(
        await boxSealOpenBytes(encryptedToken, { publicKey, privateKey }),
    );
};

export const putSpaceSignupKeyAttributes = async (
    keyAttributes: KeyAttributes,
    authToken: string,
) =>
    ensureOk(
        await fetch(await apiURL("/users/attributes"), {
            method: "PUT",
            headers: spaceBootstrapAuthHeaders(authToken),
            body: JSON.stringify({ keyAttributes }),
        }),
    );

const SetupSRPResponse = z.object({ setupID: z.string(), srpB: z.string() });

const CompleteSRPSetupResponse = z.object({
    setupID: z.string(),
    srpM2: z.string(),
});

export const setupSpaceSignupSRP = async (
    { srpSalt, srpUserID, srpVerifier, loginSubKey }: SRPSetupAttributes,
    authToken: string,
) => {
    const wasm = await loadEnteWasm();
    const session = new wasm.SrpSession(srpUserID, srpSalt, loginSubKey);

    const setupRes = await fetch(await apiURL("/users/srp/setup"), {
        method: "POST",
        headers: spaceBootstrapAuthHeaders(authToken),
        body: JSON.stringify({
            srpUserID,
            srpSalt,
            srpVerifier,
            srpA: session.public_a(),
        }),
    });
    ensureOk(setupRes);
    const { setupID, srpB } = SetupSRPResponse.parse(await setupRes.json());

    const completeRes = await fetch(await apiURL("/users/srp/complete"), {
        method: "POST",
        headers: spaceBootstrapAuthHeaders(authToken),
        body: JSON.stringify({ setupID, srpM1: session.compute_m1(srpB) }),
    });
    ensureOk(completeRes);
    const { srpM2 } = CompleteSRPSetupResponse.parse(await completeRes.json());

    session.verify_m2(srpM2);
};
