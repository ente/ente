// Adapted from `web/packages/accounts/services/user.ts` (key + 2FA paths).
import { z } from "zod";
import { boxSealOpenBytes, decryptBox, toB64URLSafe } from "./crypto";
import {
    authenticatedRequestHeaders,
    ensureOk,
    publicRequestHeaders,
} from "./http";
import { savedPartialLocalUser, updateSavedLocalUser } from "./local-state";
import { apiURL } from "./origins";
import { saveAuthToken } from "./token";

export interface LocalUser {
    id: number;
    email: string;
    token: string;
    isTwoFactorEnabled?: boolean;
}

export interface KeyAttributes {
    encryptedKey: string;
    keyDecryptionNonce: string;
    kekSalt: string;
    opsLimit: number;
    memLimit: number;
    publicKey: string;
    encryptedSecretKey: string;
    secretKeyDecryptionNonce: string;
    masterKeyEncryptedWithRecoveryKey?: string;
    masterKeyDecryptionNonce?: string;
    recoveryKeyEncryptedWithMasterKey?: string;
    recoveryKeyDecryptionNonce?: string;
}

const optionalString = z
    .string()
    .nullish()
    .transform((v) => v ?? undefined);

export const RemoteKeyAttributes = z.object({
    kekSalt: z.string(),
    encryptedKey: z.string(),
    keyDecryptionNonce: z.string(),
    publicKey: z.string(),
    encryptedSecretKey: z.string(),
    secretKeyDecryptionNonce: z.string(),
    memLimit: z.number(),
    opsLimit: z.number(),
    masterKeyEncryptedWithRecoveryKey: optionalString,
    masterKeyDecryptionNonce: optionalString,
    recoveryKeyEncryptedWithMasterKey: optionalString,
    recoveryKeyDecryptionNonce: optionalString,
});

export const RemoteEmailOrSRPVerificationResponseBase = z.object({
    id: z.number(),
    keyAttributes: RemoteKeyAttributes.nullish().transform(
        (v) => v ?? undefined,
    ),
    encryptedToken: optionalString,
    token: optionalString,
    twoFactorSessionID: optionalString,
    passkeySessionID: optionalString,
    accountsUrl: optionalString,
    twoFactorSessionIDV2: optionalString,
});

export type EmailOrSRPVerificationResponseShape = z.infer<
    typeof RemoteEmailOrSRPVerificationResponseBase
>;

export interface EmailOrSRPVerificationResponse extends EmailOrSRPVerificationResponseShape {}

export const RemoteSRPVerificationResponse =
    RemoteEmailOrSRPVerificationResponseBase.extend({ srpM2: z.string() });

// Regenerates a fresh auth token from the `encryptedToken` returned by the
// server (used after a 2FA / passkey login).
export const decryptAndStoreTokenIfNeeded = async (
    keyAttributes: KeyAttributes,
    masterKey: string,
) => {
    const { encryptedToken } = (await savedPartialLocalUser()) ?? {};
    if (!encryptedToken) return;

    const { encryptedSecretKey, secretKeyDecryptionNonce, publicKey } =
        keyAttributes;
    const privateKey = await decryptBox(
        { encryptedData: encryptedSecretKey, nonce: secretKeyDecryptionNonce },
        masterKey,
    );

    const token = toB64URLSafe(
        await boxSealOpenBytes(encryptedToken, { publicKey, privateKey }),
    );

    await updateSavedLocalUser({ token, encryptedToken: undefined });
    return saveAuthToken(token);
};

export const TwoFactorAuthorizationResponse = z.object({
    id: z.number(),
    keyAttributes: RemoteKeyAttributes,
    encryptedToken: z.string(),
});

export type TwoFactorAuthorizationResponse = z.infer<
    typeof TwoFactorAuthorizationResponse
>;

export const verifyTwoFactor = async (
    code: string,
    sessionID: string,
): Promise<TwoFactorAuthorizationResponse> => {
    const res = await fetch(await apiURL("/users/two-factor/verify"), {
        method: "POST",
        headers: publicRequestHeaders(),
        body: JSON.stringify({ code, sessionID }),
    });
    ensureOk(res);
    return TwoFactorAuthorizationResponse.parse(await res.json());
};

// --- Email verification (OTT) login -----------------------------------------
//
// Accounts with "email MFA" enabled reject SRP logins, so they instead receive
// a one-time code by email and are verified through `/users/verify-email`.
// Mirrors `web/packages/accounts/services/user.ts` (`sendOTT`, `verifyEmail`)
// and the `LoginContents` -> `/verify` flow.

export const sendOTT = async (
    email: string,
    purpose: "change" | "signup" | "login" | undefined,
) =>
    ensureOk(
        await fetch(await apiURL("/users/ott"), {
            method: "POST",
            headers: publicRequestHeaders(),
            body: JSON.stringify({ email, purpose }),
        }),
    );

export const verifyEmailOTT = async (
    email: string,
    ott: string,
): Promise<EmailOrSRPVerificationResponseShape> => {
    const res = await fetch(await apiURL("/users/verify-email"), {
        method: "POST",
        headers: publicRequestHeaders(),
        body: JSON.stringify({ email, ott }),
    });
    ensureOk(res);
    return RemoteEmailOrSRPVerificationResponseBase.parse(await res.json());
};

export const remoteLogoutIfNeeded = async () => {
    const res = await fetch(await apiURL("/users/logout"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
    });
    if (res.status == 401) return;
    ensureOk(res);
};
