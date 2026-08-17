import {
    replaceSavedLocalUser,
    savedKeyAttributes,
    savedLocalUser,
    savedPartialLocalUser,
    saveKeyAttributes,
    updateSavedLocalUser,
} from "ente-accounts/services/accounts-db";
import {
    boxSealOpenBytes,
    decryptBox,
    deriveInteractiveKey,
    deriveSensitiveKey,
    encryptBox,
    generateKey,
    generateKeyPair,
    toB64URLSafe,
} from "ente-accounts/services/crypto";
import { ensureMasterKeyFromSession } from "ente-accounts/services/session-storage";
import {
    generateSRPSetupAttributes,
    getAndSaveSRPAttributes,
    updateSRPAndKeyAttributes,
    type UpdatedKeyAttr,
} from "ente-accounts/services/srp";
import {
    authenticatedRequestHeaders,
    ensureOk,
    publicRequestHeaders,
} from "ente-base/http";
import { apiURL } from "ente-base/origins";
import {
    removeAuthToken,
    saveAuthToken,
    savedAuthToken,
} from "ente-base/token";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import { clearInflightPasskeySessionID } from "./passkey";
import { getUserRecoveryKey, recoveryKeyFromMnemonic } from "./recovery-key";

export interface LocalUser {
    id: number;
    email: string;
    // Prefer savedAuthToken over this property; it is kept in sync with this
    // value and, being in IndexedDB, is also usable in web workers.
    token: string;
    isTwoFactorEnabled?: boolean;
}

export const ensureLocalUser = (): LocalUser =>
    ensureExpectedLoggedInValue(savedLocalUser());

export const ensureExpectedLoggedInValue = <T>(t: T | undefined): T => {
    if (!t) throw new Error("Not logged in");
    return t;
};

export interface KeyAttributes {
    encryptedKey: string;
    keyDecryptionNonce: string;
    kekSalt: string;
    opsLimit: number;
    memLimit: number;
    publicKey: string;
    // libsodium and the wire protocol call this the "secret" key, but
    // libsodium.js calls it the "private" key; the codebase uses "privateKey"
    // to match libsodium.js.
    // https://doc.libsodium.org/public-key_cryptography/authenticated_encryption#key-pair-generation
    encryptedSecretKey: string;
    secretKeyDecryptionNonce: string;
    masterKeyEncryptedWithRecoveryKey?: string;
    masterKeyDecryptionNonce?: string;
    recoveryKeyEncryptedWithMasterKey?: string;
    recoveryKeyDecryptionNonce?: string;
}

export const RemoteKeyAttributes = z.object({
    kekSalt: z.string(),
    encryptedKey: z.string(),
    keyDecryptionNonce: z.string(),
    publicKey: z.string(),
    encryptedSecretKey: z.string(),
    secretKeyDecryptionNonce: z.string(),
    memLimit: z.number(),
    opsLimit: z.number(),
    masterKeyEncryptedWithRecoveryKey: z
        .string()
        .nullish()
        .transform(nullToUndefined),
    masterKeyDecryptionNonce: z.string().nullish().transform(nullToUndefined),
    recoveryKeyEncryptedWithMasterKey: z
        .string()
        .nullish()
        .transform(nullToUndefined),
    recoveryKeyDecryptionNonce: z.string().nullish().transform(nullToUndefined),
});

export const ensureSavedKeyAttributes = (): KeyAttributes =>
    ensureExpectedLoggedInValue(savedKeyAttributes());

export interface UserKeyPair {
    publicKey: string;
    privateKey: string;
}

export const ensureUserKeyPair = async (): Promise<UserKeyPair> => {
    const { encryptedSecretKey, secretKeyDecryptionNonce, publicKey } =
        ensureSavedKeyAttributes();
    const privateKey = await decryptBox(
        { encryptedData: encryptedSecretKey, nonce: secretKeyDecryptionNonce },
        await ensureMasterKeyFromSession(),
    );
    return { publicKey, privateKey };
};

export const getPublicKey = async (email: string) => {
    const res = await fetch(await apiURL("/users/public-key", { email }), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return z.object({ publicKey: z.string() }).parse(await res.json())
        .publicKey;
};

export const getTwoFactorStatus = async () => {
    const res = await fetch(await apiURL("/users/two-factor/status"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return z.object({ status: z.boolean() }).parse(await res.json()).status;
};

export interface GenerateKeysAndAttributesResult {
    masterKey: string;
    kek: string;
    keyAttributes: KeyAttributes;
}

export async function generateKeysAndAttributes(
    password: string,
): Promise<GenerateKeysAndAttributesResult> {
    const masterKey = await generateKey();
    const recoveryKey = await generateKey();
    const {
        key: kek,
        salt: kekSalt,
        opsLimit,
        memLimit,
    } = await deriveSensitiveKey(password);

    const { encryptedData: encryptedKey, nonce: keyDecryptionNonce } =
        await encryptBox(masterKey, kek);
    const {
        encryptedData: masterKeyEncryptedWithRecoveryKey,
        nonce: masterKeyDecryptionNonce,
    } = await encryptBox(masterKey, recoveryKey);
    const {
        encryptedData: recoveryKeyEncryptedWithMasterKey,
        nonce: recoveryKeyDecryptionNonce,
    } = await encryptBox(recoveryKey, masterKey);

    const keyPair = await generateKeyPair();
    const {
        encryptedData: encryptedSecretKey,
        nonce: secretKeyDecryptionNonce,
    } = await encryptBox(keyPair.privateKey, masterKey);

    const keyAttributes: KeyAttributes = {
        encryptedKey,
        keyDecryptionNonce,
        kekSalt,
        opsLimit,
        memLimit,
        publicKey: keyPair.publicKey,
        encryptedSecretKey,
        secretKeyDecryptionNonce,
        masterKeyEncryptedWithRecoveryKey,
        masterKeyDecryptionNonce,
        recoveryKeyEncryptedWithMasterKey,
        recoveryKeyDecryptionNonce,
    };

    return { masterKey, kek, keyAttributes };
}

export const putUserKeyAttributes = async (keyAttributes: KeyAttributes) =>
    ensureOk(
        await fetch(await apiURL("/users/attributes"), {
            method: "PUT",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({ keyAttributes }),
        }),
    );

export interface RecoveryKeyAttributes {
    masterKeyEncryptedWithRecoveryKey: string;
    masterKeyDecryptionNonce: string;
    recoveryKeyEncryptedWithMasterKey: string;
    recoveryKeyDecryptionNonce: string;
}

// This is a rare fallback for very old accounts that predate recovery key
// attributes being set during account setup.
export const putUserRecoveryKeyAttributes = async (
    recoveryKeyAttributes: RecoveryKeyAttributes,
) =>
    ensureOk(
        await fetch(await apiURL("/users/recovery-key"), {
            method: "PUT",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify(recoveryKeyAttributes),
        }),
    );

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

export interface EmailOrSRPVerificationResponse {
    id: number;
    keyAttributes?: KeyAttributes;
    encryptedToken?: string;
    token?: string;
    twoFactorSessionID?: string;
    passkeySessionID?: string;
    accountsUrl?: string;
    twoFactorSessionIDV2?: string;
}

const RemoteEmailOrSRPVerificationResponseBase = z.object({
    id: z.number(),
    keyAttributes: RemoteKeyAttributes.nullish().transform(nullToUndefined),
    encryptedToken: z.string().nullish().transform(nullToUndefined),
    token: z.string().nullish().transform(nullToUndefined),
    twoFactorSessionID: z.string().nullish().transform(nullToUndefined),
    passkeySessionID: z.string().nullish().transform(nullToUndefined),
    accountsUrl: z.string().nullish().transform(nullToUndefined),
    twoFactorSessionIDV2: z.string().nullish().transform(nullToUndefined),
});

const requireAccountsUrlForPasskey = (response: {
    passkeySessionID?: string;
    accountsUrl?: string;
}) => (response.passkeySessionID ? !!response.accountsUrl : true);

const accountsUrlForPasskeyRefinement = {
    path: ["accountsUrl"],
    message: "accountsUrl is required when passkeySessionID is present",
};

const RemoteEmailOrSRPVerificationResponse =
    RemoteEmailOrSRPVerificationResponseBase.refine(
        requireAccountsUrlForPasskey,
        accountsUrlForPasskeyRefinement,
    );

// This declaration conceptually belongs to srp.ts, but lives here to avoid a
// cyclic dependency.
export const RemoteSRPVerificationResponse =
    RemoteEmailOrSRPVerificationResponseBase.extend({
        srpM2: z.string(),
    }).refine(requireAccountsUrlForPasskey, accountsUrlForPasskeyRefinement);

export const verifyEmail = async (
    email: string,
    ott: string,
    source: string | undefined,
): Promise<EmailOrSRPVerificationResponse> => {
    const res = await fetch(await apiURL("/users/verify-email"), {
        method: "POST",
        headers: publicRequestHeaders(),
        body: JSON.stringify({ email, ott, ...(source && { source }) }),
    });
    ensureOk(res);
    return RemoteEmailOrSRPVerificationResponse.parse(await res.json());
};

export const remoteLogoutIfNeeded = async () => {
    if (!(await savedAuthToken())) {
        // The logout was attempted during the login / signup flow itself, so
        // there is no auth token yet and nothing to log out on remote.
        return;
    }

    const res = await fetch(await apiURL("/users/logout"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
    });
    if (res.status == 401) {
        // A 401 is expected when the token has already expired; ignore it.
        return;
    }

    ensureOk(res);
};

// The interactive KEK and the key attributes this function saves are local
// only and are never sent to remote; the saved SRP attributes retain the
// original KEK derivation parameters from remote.
export const generateAndSaveInteractiveKeyAttributes = async (
    password: string,
    keyAttributes: KeyAttributes,
    key: string,
): Promise<KeyAttributes> => {
    const {
        key: interactiveKEK,
        salt: kekSalt,
        opsLimit,
        memLimit,
    } = await deriveInteractiveKey(password);

    const { encryptedData: encryptedKey, nonce: keyDecryptionNonce } =
        await encryptBox(key, interactiveKEK);

    const interactiveKeyAttributes = {
        ...keyAttributes,
        encryptedKey,
        keyDecryptionNonce,
        kekSalt,
        opsLimit,
        memLimit,
    };
    saveKeyAttributes(interactiveKeyAttributes);
    return interactiveKeyAttributes;
};

export const changeEmail = async (email: string, ott: string) => {
    await postChangeEmail(email, ott);
    updateSavedLocalUser({ email });
};

const postChangeEmail = async (email: string, ott: string) =>
    ensureOk(
        await fetch(await apiURL("/users/change-email"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({ email, ott }),
        }),
    );

export const changePassword = async (password: string) => {
    const user = ensureLocalUser();
    const masterKey = await ensureMasterKeyFromSession();
    const keyAttributes = ensureSavedKeyAttributes();

    const {
        key: kek,
        salt: kekSalt,
        opsLimit,
        memLimit,
    } = await deriveSensitiveKey(password);

    const { encryptedData: encryptedKey, nonce: keyDecryptionNonce } =
        await encryptBox(masterKey, kek);
    const updatedKeyAttr: UpdatedKeyAttr = {
        encryptedKey,
        keyDecryptionNonce,
        kekSalt,
        opsLimit,
        memLimit,
    };

    await updateSRPAndKeyAttributes(
        await generateSRPSetupAttributes(kek),
        updatedKeyAttr,
    );

    await getAndSaveSRPAttributes(user.email);

    await generateAndSaveInteractiveKeyAttributes(
        password,
        { ...keyAttributes, ...updatedKeyAttr },
        masterKey,
    );
};

export const resetSavedLocalUserTokens = async (
    userID: number,
    encryptedToken: string,
) => {
    const user = savedPartialLocalUser();
    if (user?.id && user.id != userID) {
        throw new Error(`User ID mismatch (${user.id}, ${userID})`);
    }
    replaceSavedLocalUser({
        ...user,
        id: userID,
        token: undefined,
        encryptedToken,
    });
    return removeAuthToken();
};

export const decryptAndStoreTokenIfNeeded = async (
    keyAttributes: KeyAttributes,
    masterKey: string,
) => {
    const { encryptedToken } = savedPartialLocalUser() ?? {};
    if (!encryptedToken) return;

    const { encryptedSecretKey, secretKeyDecryptionNonce, publicKey } =
        keyAttributes;
    const privateKey = await decryptBox(
        { encryptedData: encryptedSecretKey, nonce: secretKeyDecryptionNonce },
        masterKey,
    );

    const token = await toB64URLSafe(
        await boxSealOpenBytes(encryptedToken, { publicKey, privateKey }),
    );

    updateSavedLocalUser({ token, encryptedToken: undefined });
    return saveAuthToken(token);
};

const TwoFactorSecret = z.object({
    secretCode: z.string(),
    // The value is a base64 encoded PNG image.
    qrCode: z.string(),
});

export type TwoFactorSecret = z.infer<typeof TwoFactorSecret>;

export const setupTwoFactor = async (): Promise<TwoFactorSecret> => {
    const res = await fetch(await apiURL("/users/two-factor/setup"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return TwoFactorSecret.parse(await res.json());
};

export const setupTwoFactorFinish = async (
    secretCode: string,
    totp: string,
) => {
    const box = await encryptBox(secretCode, await getUserRecoveryKey());
    await enableTwoFactor({
        code: totp,
        encryptedTwoFactorSecret: box.encryptedData,
        twoFactorSecretDecryptionNonce: box.nonce,
    });
    updateSavedLocalUser({ isTwoFactorEnabled: true });
};

export const disableTwoFactor = async () => {
    ensureOk(
        await fetch(await apiURL("/users/two-factor/disable"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
        }),
    );
    updateSavedLocalUser({ isTwoFactorEnabled: false });
};

interface EnableTwoFactorRequest {
    code: string;
    encryptedTwoFactorSecret: string;
    twoFactorSecretDecryptionNonce: string;
}

const enableTwoFactor = async (req: EnableTwoFactorRequest) =>
    ensureOk(
        await fetch(await apiURL("/users/two-factor/enable"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify(req),
        }),
    );

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

export type TwoFactorType = "totp" | "passkey";

const TwoFactorRecoveryResponse = z.object({
    encryptedSecret: z.string(),
    secretDecryptionNonce: z.string(),
});

export type TwoFactorRecoveryResponse = z.infer<
    typeof TwoFactorRecoveryResponse
>;

export const getRecoverTwoFactor = async (
    twoFactorType: TwoFactorType,
    sessionID: string,
): Promise<TwoFactorRecoveryResponse> => {
    const res = await fetch(
        await apiURL("/users/two-factor/recover", { twoFactorType, sessionID }),
        { headers: publicRequestHeaders() },
    );
    ensureOk(res);
    return TwoFactorRecoveryResponse.parse(await res.json());
};

export const recoverTwoFactorFinish = async (
    twoFactorType: TwoFactorType,
    sessionID: string,
    recoveryResponse: TwoFactorRecoveryResponse,
    recoveryKeyMnemonic: string,
) => {
    const { encryptedSecret: encryptedData, secretDecryptionNonce: nonce } =
        recoveryResponse;
    const twoFactorSecret = await decryptBox(
        { encryptedData, nonce },
        await recoveryKeyFromMnemonic(recoveryKeyMnemonic),
    );
    const { id, keyAttributes, encryptedToken } = await removeTwoFactor(
        twoFactorType,
        sessionID,
        twoFactorSecret,
    );
    await resetSavedLocalUserTokens(id, encryptedToken);
    updateSavedLocalUser({
        isTwoFactorEnabled: undefined,
        twoFactorSessionID: undefined,
        passkeySessionID: undefined,
    });
    if (twoFactorType == "passkey") clearInflightPasskeySessionID();
    saveKeyAttributes(keyAttributes);
};

const removeTwoFactor = async (
    twoFactorType: TwoFactorType,
    sessionID: string,
    secret: string,
): Promise<TwoFactorAuthorizationResponse> => {
    const res = await fetch(await apiURL("/users/two-factor/remove"), {
        method: "POST",
        headers: publicRequestHeaders(),
        body: JSON.stringify({ twoFactorType, sessionID, secret }),
    });
    ensureOk(res);
    return TwoFactorAuthorizationResponse.parse(await res.json());
};
