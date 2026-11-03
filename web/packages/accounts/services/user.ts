import {
    replaceSavedLocalUser,
    savedKeyAttributes,
    savedLocalUser,
    savedPartialLocalUser,
    saveKeyAttributes,
    updateSavedLocalUser,
} from "ente-accounts/services/accounts-db";
import { generateSignupKeys as rustGenerateSignupKeys } from "ente-accounts/services/crypto";
import { generateInteractiveKeyAttributes } from "ente-accounts/services/key-attributes";
import { namedError } from "ente-base/error";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import {
    ensureAuthToken,
    removeAuthToken,
    saveAuthToken,
    savedAuthToken,
} from "ente-base/token";
import {
    getTwoFactorRecovery,
    recoverTwoFactor,
    enableTwoFactor as rustEnableTwoFactor,
    recoverAccount as rustRecoverAccount,
    setupTwoFactor as rustSetupTwoFactor,
    verifyEmail as rustVerifyEmail,
    verifyTwoFactor as rustVerifyTwoFactor,
    sendOTP,
    setKeyAttributes,
    unlockAccount,
    unlockAccountWithMasterKey,
    type AccountsClient,
} from "ente-prelogin-wasm";
import { nullToUndefined } from "ente-utils/transform";
import { v4 as uuidv4 } from "uuid";
import { z } from "zod";
import { getAccountsClient, withAccountsClient } from "./accounts-client";
import { clearInflightPasskeySessionID } from "./passkey";

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

const ensureExpectedLoggedInValue = <T>(t: T | undefined): T => {
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

export const generateSignupKeys = async (password: string) => {
    const generated = await rustGenerateSignupKeys(password, uuidv4());
    return {
        ...generated,
        keyAttributes: RemoteKeyAttributes.parse(generated.keyAttributes),
    };
};

export const putUserKeyAttributes = async (keyAttributes: KeyAttributes) => {
    const token = await ensureAuthToken();
    return withAccountsClient((client) =>
        setKeyAttributes(client, token, keyAttributes),
    );
};

export const sendOTT = (
    email: string,
    purpose: "change" | "signup" | "login" | undefined,
) => withAccountsClient((client) => sendOTP(client, email, purpose ?? ""));

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

export const RemoteEmailOrSRPVerificationResponse =
    RemoteEmailOrSRPVerificationResponseBase.refine(
        requireAccountsUrlForPasskey,
        accountsUrlForPasskeyRefinement,
    );

export const verifyEmail = async (
    email: string,
    ott: string,
    source: string | undefined,
): Promise<EmailOrSRPVerificationResponse> =>
    RemoteEmailOrSRPVerificationResponse.parse(
        await withAccountsClient((client) =>
            rustVerifyEmail(client, email, ott, source),
        ),
    );

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
    const interactiveKeyAttributes = await generateInteractiveKeyAttributes(
        password,
        keyAttributes,
        key,
    );
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

const UnlockedAccount = z.object({ masterKey: z.string(), token: z.string() });

export const unlockAccountWithKEK = async (
    response: EmailOrSRPVerificationResponse,
    kek: string,
) =>
    UnlockedAccount.parse(
        await withAccountsClient((client) =>
            unlockAccount(client, response, kek),
        ),
    );

export const unlockAccountWithKey = async (
    response: EmailOrSRPVerificationResponse,
    masterKey: string,
) =>
    UnlockedAccount.parse(
        await withAccountsClient((client) =>
            unlockAccountWithMasterKey(client, response, masterKey),
        ),
    );

export const recoverAccount = async (
    keyAttributes: KeyAttributes,
    recoveryKey: string,
) => {
    const user = savedPartialLocalUser()!;
    return UnlockedAccount.parse(
        await withAccountsClient((client) =>
            rustRecoverAccount(
                client,
                { ...user, id: user.id!, keyAttributes },
                recoveryKey,
            ),
        ),
    );
};

export const decryptAndStoreTokenIfNeeded = async (
    keyAttributes: KeyAttributes,
    masterKey: string,
) => {
    const user = savedPartialLocalUser();
    if (!user?.encryptedToken) return;
    const { token } = await unlockAccountWithKey(
        { ...user, id: user.id!, keyAttributes },
        masterKey,
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
    const token = await ensureAuthToken();
    return TwoFactorSecret.parse(
        await withAccountsClient((client) => rustSetupTwoFactor(client, token)),
    );
};

export const setupTwoFactorFinish = async (
    secret: string,
    recoveryKey: string,
    code: string,
) => {
    const token = await ensureAuthToken();
    await withAccountsClient((client) =>
        rustEnableTwoFactor(client, token, secret, recoveryKey, code),
    );
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
): Promise<TwoFactorAuthorizationResponse> =>
    TwoFactorAuthorizationResponse.parse(
        await withAccountsClient((client) =>
            rustVerifyTwoFactor(client, sessionID, code),
        ),
    );

export type TwoFactorType = "totp" | "passkey";

const TwoFactorRecoveryResponse = z.object({
    encryptedSecret: z.string(),
    secretDecryptionNonce: z.string(),
});

export interface TwoFactorRecovery {
    client: AccountsClient;
    response: z.infer<typeof TwoFactorRecoveryResponse>;
}

export const getRecoverTwoFactor = async (
    twoFactorType: TwoFactorType,
    sessionID: string,
): Promise<TwoFactorRecovery> => {
    const client = await getAccountsClient();
    const response = TwoFactorRecoveryResponse.parse(
        await getTwoFactorRecovery(client, twoFactorType, sessionID),
    );
    return { client, response };
};

export const recoverTwoFactorFinish = async (
    twoFactorType: TwoFactorType,
    sessionID: string,
    recovery: TwoFactorRecovery,
    recoveryKeyMnemonic: string,
) => {
    const { client, response } = recovery;
    if (client !== (await getAccountsClient())) {
        throw namedError("session_expired", "Server endpoint changed");
    }
    const { id, keyAttributes, encryptedToken } =
        TwoFactorAuthorizationResponse.parse(
            await recoverTwoFactor(
                client,
                twoFactorType,
                sessionID,
                response,
                recoveryKeyMnemonic,
            ),
        );
    if (client !== (await getAccountsClient())) {
        throw namedError("session_expired", "Server endpoint changed");
    }
    await resetSavedLocalUserTokens(id, encryptedToken);
    updateSavedLocalUser({
        isTwoFactorEnabled: undefined,
        twoFactorSessionID: undefined,
        passkeySessionID: undefined,
    });
    if (twoFactorType == "passkey") clearInflightPasskeySessionID();
    saveKeyAttributes(keyAttributes);
};
