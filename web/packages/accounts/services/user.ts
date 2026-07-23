import {
    replaceSavedLocalUser,
    savedKeyAttributes,
    savedLocalUser,
    savedPartialLocalUser,
    saveKeyAttributes,
    saveSRPAttributes,
    updateSavedLocalUser,
} from "ente-accounts/services/accounts-db";
import {
    generateSRPSetupAttributes,
    getAndSaveSRPAttributes,
    getSRPAttributes,
    updateSRPAndKeyAttributes,
    type UpdatedKeyAttr,
} from "ente-accounts/services/srp";
import {
    boxSealOpenBytes,
    decryptBox,
    deriveInteractiveKey,
    deriveSensitiveKey,
    encryptBox,
    generateKey,
    generateKeyPair,
    toB64URLSafe,
} from "ente-base/crypto";
import {
    authenticatedRequestHeaders,
    ensureOk,
    publicRequestHeaders,
} from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { ensureMasterKeyFromSession } from "ente-base/session";
import {
    removeAuthToken,
    saveAuthToken,
    savedAuthToken,
} from "ente-base/token";
import { ensure } from "ente-utils/ensure";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import { clearInflightPasskeySessionID } from "./passkey";
import { getUserRecoveryKey, recoveryKeyFromMnemonic } from "./recovery-key";

/**
 * The locally persisted data we have about the user after they've logged in.
 *
 * This type arguably belongs to accounts-db (since that's what persists it and
 * its shadow alias, {@link PartialLocalUser}), but since most code that will
 * need this will need this after login has completed, and will be using the
 * {@link ensureLocalUser} method below, we keep this in the same file to reduce
 * the need to import the type from a separate file.
 */
export interface LocalUser {
    /**
     * The user's ID.
     */
    id: number;
    /**
     * The email associated with the user's Ente account.
     */
    email: string;
    /**
     * The user's (plaintext) auth token.
     *
     * It is used for making API calls on their behalf, by passing this token as
     * the value of the X-Auth-Token header in the HTTP request.
     *
     * Usually you shouldn't be needing to access this property; instead use
     * {@link savedAuthToken()} which is kept in sync with this value, and lives
     * in IndexedDB and thus can also be used in web workers.
     */
    token: string;
    /**
     * `true` if the TOTP based second factor is enabled for the user.
     */
    isTwoFactorEnabled?: boolean;
}

/**
 * Return the currently logged in {@link LocalUser}, throwing it the user is not
 * logged in.
 *
 * This is a wrapper over the {@link savedLocalUser} function that throws if no
 * one is logged in. A more appropriate name for this function, keeping in line
 * with the conventions the other methods follow, would've been
 * {@link ensureSavedLocalUser}. The shorter name is for readability.
 */
export const ensureLocalUser = (): LocalUser =>
    ensureExpectedLoggedInValue(savedLocalUser());

/**
 * A function throws an error if a value that is expected to be truthy when the
 * user is logged in is instead falsey.
 *
 * This is meant as a convenience wrapper to assert that a value we expect when
 * the user is logged in is indeed there.
 */
export const ensureExpectedLoggedInValue = <T>(t: T | undefined): T => {
    if (!t) throw new Error("Not logged in");
    return t;
};

/**
 * The user's various encrypted keys and their related attributes.
 *
 * - Attributes to derive the KEK, the (master) key encryption key.
 * - Encrypted master key (with KEK)
 * - Encrypted master key (with recovery key)
 * - Encrypted recovery key (with master key).
 * - Public key and encrypted private key (with master key).
 *
 * The various "key" attributes are base64 encoded representations of the
 * underlying binary data.
 *
 * [Note: Key attribute mutability]
 *
 * The key attributes contain two subsets:
 *
 * - Attributes that changes when the user changes their password. These are the
 *   {@link UpdatedKeyAttr}.
 *
 * - All other attributes never change after initial setup.
 */
export interface KeyAttributes {
    /**
     * The user's master key encrypted with the key encryption key.
     *
     * Base64 encoded.
     *
     * [Note: Key encryption key]
     *
     * The user's master key is encrypted with a "key encryption key" (lovingly
     * called a "KEK" sometimes).
     *
     * The KEK itself is derived from the user's password.
     *
     * 1. User enters password on new device.
     *
     * 2. Client derives KEK from this password (using the {@link kekSalt},
     *    {@link opsLimit} and {@link memLimit} as parameters for the
     *    derivation).
     *
     * 3. Client use KEK to decrypt the master key from {@link encryptedKey} and
     *    {@link keyDecryptionNonce}.
     */
    encryptedKey: string;
    /**
     * The nonce used during the encryption of the master key.
     *
     * Base64 encoded.
     *
     * @see {@link encryptedKey}.
     */
    keyDecryptionNonce: string;
    /**
     * The salt used during the derivation of the KEK.
     *
     * Base64 encoded.
     *
     * [Note: KEK three tuple]
     *
     * The three tuple (kekSalt, opsLimit, memLimit) is needed (along with the
     * user's password) to rederive the KEK when the user logs in on a new
     * client (See: [Note: Key encryption key]).
     *
     * The client can obtain these three by fetching their key attributes from
     * remote, however unless {@link isEmailMFAEnabled} is enabled (which is not
     * by default), then the user's credentials are verified using SRP instead
     * of email verification. So as a convenience for this (majority) flow,
     * remote also provides this exact same three tuple as part of the
     * {@link SRPAttributes} fetched from remote.
     *
     * So on remote the KEK three tuple is the same whether it be part of key
     * attributes or SRP attributes. When the user changes their password, both
     * of them also get updated simulataneously (they use the same storage).
     *
     * However, on the client side these two sets of three tuples might diverge
     * because of the client generating interactive key attributes. When that
     * happens, the locally saved key attributes will be overwritten by the KEK
     * three tuple for the new generated interactive KEK parameters, while the
     * SRP attributes will continue to reflect the "original" KEK three tuple we
     * got from remote.
     */
    kekSalt: string;
    /**
     * The operation limit used during the derivation of the KEK.
     *
     * The {@link opsLimit} and {@link memLimit} are complementary parameters
     * that define the amount of work done by the key derivation function. See
     * the {@link deriveKey}, {@link deriveSensitiveKey} and
     * {@link deriveInteractiveKey} functions for more detail about them.
     *
     * See: [Note: Key encryption key].
     */
    opsLimit: number;
    /**
     * The memory limit used during the derivation of the KEK.
     *
     * See {@link opsLimit} for more details.
     */
    memLimit: number;
    /**
     * The user's public key (part of their public-key keypair, the other half
     * being the {@link encryptedSecretKey}).
     *
     * Base64 encoded.
     */
    publicKey: string;
    /**
     * The user's private key (part of their public-key keypair, the other half
     * being the {@link publicKey}) encrypted with their master key.
     *
     * Base64 encoded.
     *
     * [Note: privateKey and secretKey]
     *
     * The nomenclature for the key pair follows libsodium's conventions
     * (https://doc.libsodium.org/public-key_cryptography/authenticated_encryption#key-pair-generation),
     * who possibly chose public + secret instead of public + private to avoid
     * confusion with shorthand notation (pk).
     *
     * However, the library author later changed their mind on this, so while
     * libsodium itself (the C library) and the documentation uses "secretKey",
     * the JavaScript implementation (libsodium.js) uses "privateKey".
     *
     * This structure uses the term "secretKey" since that is what the remote
     * protocol already was based on. Within the web app codebase, we use
     * "privateKey" since that is what the underlying libsodium.js uses.
     */
    encryptedSecretKey: string;
    /**
     * The nonce used during the encryption of {@link encryptedSecretKey}.
     */
    secretKeyDecryptionNonce: string;
    /**
     * The user's master key after being encrypted with their recovery key.
     *
     * Base64 encoded.
     *
     * This allows the user to recover their master key if they forget their
     * password but still have their recovery key.
     *
     * Note: This value doesn't change after being initially created.
     */
    masterKeyEncryptedWithRecoveryKey?: string;
    /**
     * The nonce used during the encryption of
     * {@link masterKeyEncryptedWithRecoveryKey}.
     *
     * Base64 encoded.
     */
    masterKeyDecryptionNonce?: string;
    /**
     * The user's recovery key after being encrypted with their master key.
     *
     * Base64 encoded.
     *
     * Note: This value doesn't change after being initially created.
     */
    recoveryKeyEncryptedWithMasterKey?: string;
    /**
     * The nonce used during the encryption of
     * {@link recoveryKeyEncryptedWithMasterKey}.
     *
     * Base64 encoded.
     */
    recoveryKeyDecryptionNonce?: string;
}

/**
 * Zod schema for {@link KeyAttributes}.
 */
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

/**
 * A variant of {@link savedKeyAttributes} that throws if keyAttributes are not
 * present in local storage.
 */
export const ensureSavedKeyAttributes = (): KeyAttributes =>
    ensureExpectedLoggedInValue(savedKeyAttributes());

export interface GenerateKeysAndAttributesResult {
    masterKey: string;
    kek: string;
    keyAttributes: KeyAttributes;
}

/**
 * Generate a new set of key attributes.
 *
 * @param password The password to use for deriving the key encryption key.
 *
 * @returns a newly generated master key (base64 string), kek (base64 string)
 * and the key attributes associated with the combination.
 */
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

/**
 * Update or set the user's {@link KeyAttributes} on remote.
 */
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

/**
 * Update the encrypted recovery key attributes for the logged in user.
 *
 * In practice, this is not expected to be called and is meant as a rare
 * fallback for very old accounts created prior to recovery key related
 * attributes being assigned on account setup. Even for these, it'll be called
 * only once.
 */
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

/**
 * Ask remote to send a OTP / OTT to the given email to verify that the user has
 * access to it. Subsequent the app will pass this OTT back via the
 * {@link verifyOTT} method.
 *
 * @param email The email to verify.
 *
 * @param purpose In which context is the email being verified. Remote applies
 * additional business rules depending on this. For example, passing the purpose
 * "login" ensures that the OTT is only sent to an already registered email.
 *
 * In cases where the purpose is ambiguous (e.g. we're not sure if it is an
 * existing login or a new signup), the purpose can be set to `undefined`.
 */
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

/**
 * The response from remote on a successful user verification, either via
 * {@link verifyEmail} or {@link verifySRP}.
 *
 * The {@link id} is always present. The rest of the values are are optional
 * since only a subset of them will be returned depending on the case:
 *
 * 1. If the user has both passkeys and TOTP based second factor enabled, then
 *    the following will be set:
 *    - {@link passkeySessionID}, {@link accountsUrl}
 *    - {@link twoFactorSessionIDV2}
 *
 * 2. If the user has only passkeys enabled, then the following will be set:
 *    - {@link passkeySessionID}, {@link accountsUrl}
 *
 * 3. If the user has only TOTP based second factor enabled, then the following
 *    will be set:
 *    - {@link twoFactorSessionID}
 *
 * 4. If the user doesn't have any second factor, but has already setup their
 *    key attributes, then the following will be set:
 *    - {@link keyAttributes}
 *    - {@link encryptedToken}
 *
 * 5. Finally, in the rare case that the user has not yet setup their key
 *    attributes, then the following will be set:
 *    - {@link token}
 */
export interface EmailOrSRPVerificationResponse {
    /**
     * The user's ID.
     */
    id: number;
    /**
     * The user's key attributes.
     *
     * These will be set (along with the {@link encryptedToken}) if the user
     * does not have a second factor.
     */
    keyAttributes?: KeyAttributes;
    /**
     * The base64 representation of an encrypted auth token, encrypted using the
     * user's public key.
     *
     * These will be set (along with the {@link keyAttributes}) if the user
     * does not have a second factor.
     */
    encryptedToken?: string;
    /**
     * The base64 representation of an auth token.
     *
     * This will be set in the rare edge case for when the user has not yet
     * setup their key attributes.
     */
    token?: string;
    /**
     * A session ID that can be used to complete the TOTP based second factor.
     *
     * This will be set if the user has enabled a TOTP based second factor but
     * has not enabled passkeys.
     */
    twoFactorSessionID?: string;
    /**
     * A session ID that can be used to complete passkey verification.
     *
     * This will be set if the user has added a passkey to their account.
     */
    passkeySessionID?: string;
    /**
     * Base URL for the accounts app where we should redirect to for passkey
     * verification.
     *
     * This will only be set if the user has setup a passkey (i.e., whenever
     * {@link passkeySessionID} is defined).
     */
    accountsUrl?: string;
    /**
     * A session ID that can be used to complete the TOTP based second fator.
     *
     * This will be set in lieu of {@link twoFactorSessionID} if the user has
     * setup both passkeys and TOTP based two factors are enabled for their
     * account.
     *
     * ---
     *
     * Historical context: {@link twoFactorSessionIDV2} is only set if user has
     * both passkey and two factor enabled. This is to ensure older clients keep
     * using passkey flow when both are set. It is intended to be removed once
     * all clients starts surfacing both options for performing 2FA.
     *
     * See also {@link useSecondFactorChoiceIfNeeded}.
     */
    twoFactorSessionIDV2?: string;
}

/**
 * Zod schema for the {@link EmailOrSRPVerificationResponse} type.
 *
 * See: [Note: Duplicated Zod schema and TypeScript type]
 */
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

/**
 * A specialization of {@link RemoteEmailOrSRPVerificationResponse} for SRP
 * verification, which results in the {@link srpM2} field in addition to the
 * other ones.
 *
 * The declaration conceptually belongs to `srp.ts`, but is here to avoid cyclic
 * dependencies.
 */
export const RemoteSRPVerificationResponse =
    RemoteEmailOrSRPVerificationResponseBase.extend({
        /**
         * The SRP M2 (evidence message), the proof that the server has the
         * verifier.
         */
        srpM2: z.string(),
    }).refine(requireAccountsUrlForPasskey, accountsUrlForPasskeyRefinement);

/**
 * Verify user's access to the given {@link email} by comparing the OTT that
 * remote previously sent to that email.
 *
 * @param email The email to verify.
 *
 * @param ott The OTT that the user entered.
 *
 * @param source During signup, we ask the user the referral "source" through
 * which they heard about Ente. When present (i.e. during signup, and if the
 * user indeed provided it), that source should be passed as this parameter.
 */
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

/**
 * Log the user out on remote, if possible and needed.
 */
export const remoteLogoutIfNeeded = async () => {
    if (!(await savedAuthToken())) {
        // If the logout is attempted during the login / signup flow itself,
        // then we won't have an auth token. Handle that gracefully.
        return;
    }

    const res = await fetch(await apiURL("/users/logout"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
    });
    if (res.status == 401) {
        // Ignore if we get a 401 Unauthorized, this is expected to happen on
        // token expiry.
        return;
    }

    ensureOk(res);
};

/**
 * Generate a new local-only KEK (key encryption key) suitable for interactive
 * use and update the locally saved key attributes to reflect it.
 *
 * See {@link deriveInteractiveKey} for more details.
 *
 * In brief, after the initial password verification, we create a new
 * inetractive KEK derived from the same password as the original KEK, but with
 * so called interactive mem and ops limits which result in a noticeably faster
 * key derivation.
 *
 * We then overwrite the encrypted master key, encryption nonce and the KEK
 * derivation parameters (see: [Note: KEK three tuple]) in the locally persisted
 * {@link KeyAttributes} so that these interactive parameters get used
 * subsequent reauthentication.
 *
 * These are more ergonomic for the user especially in the web app where they
 * need to enter their password to access their masterKey when repopening the
 * app in a new tab (on desktop we can avoid this by using OS storage, see
 * [Note: Safe storage and interactive KEK attributes]).
 *
 * @param password The user's password.
 *
 * @param keyAttributes The existing "original" key attributes, which we
 * might've generated locally (new signup) or fetched from remote (existing
 * login).
 *
 * @param masterKey The user's master key (base64 encoded).
 *
 * @returns the update key attributes.
 */
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

/**
 * Change the email associated with the user's account (both locally and on
 * remote)
 *
 * @param email The new email.
 *
 * @param ott The verification code that was sent to the new email.
 */
export const changeEmail = async (email: string, ott: string) => {
    await postChangeEmail(email, ott);
    updateSavedLocalUser({ email });
};

/**
 * Change the email associated with the user's account on remote.
 */
const postChangeEmail = async (email: string, ott: string) =>
    ensureOk(
        await fetch(await apiURL("/users/change-email"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({ email, ott }),
        }),
    );

/**
 * Change the user's password on both remote and locally.
 *
 * @param password The new password.
 */
export const changePassword = async (password: string) => {
    const user = ensureLocalUser();
    const masterKey = await ensureMasterKeyFromSession();
    const keyAttributes = ensureSavedKeyAttributes();

    // Generate new KEK.
    const {
        key: kek,
        salt: kekSalt,
        opsLimit,
        memLimit,
    } = await deriveSensitiveKey(password);

    // Generate new key attributes.
    const { encryptedData: encryptedKey, nonce: keyDecryptionNonce } =
        await encryptBox(masterKey, kek);
    const updatedKeyAttr: UpdatedKeyAttr = {
        encryptedKey,
        keyDecryptionNonce,
        kekSalt,
        opsLimit,
        memLimit,
    };

    // Update SRP and key attributes on remote.
    await updateSRPAndKeyAttributes(
        await generateSRPSetupAttributes(kek),
        updatedKeyAttr,
    );

    // Update SRP attributes locally.
    await getAndSaveSRPAttributes(user.email);

    const srpAttributes = await getSRPAttributes(user.email);
    saveSRPAttributes(ensure(srpAttributes));

    // Update key attributes locally, generating a new interactive kek while
    // we're at it.
    await generateAndSaveInteractiveKeyAttributes(
        password,
        { ...keyAttributes, ...updatedKeyAttr },
        masterKey,
    );
};

/**
 * Update the {@link id} and {@link encryptedToken} present in the saved partial
 * local user.
 *
 * This function removes the {@link token}, if any, present in the saved partial
 * local user and sets the provided {@link encryptedToken}.
 *
 * It is expected that the code will subsequently redirect to "/credentials",
 * which should call {@link decryptAndStoreTokenIfNeeded} which will decrypt the
 * newly set {@link encryptedToken} and write out the decrypted value as the
 * {@link token} in the saved local user.
 *
 * @param userID The ID of the user whose token this is. This is also saved to
 * the partial local user (after doing a sanity check that we're not replacing
 * partial data with a different userID).
 *
 * @param encryptedToken The newly obtained base64 encoded encrypted token from
 * remote (e.g. as a result of the user verifying their email).
 */
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

/**
 * Decrypt the user's {@link encryptedToken}, if present, and use it to update
 * both the locally saved user and the KV DB.
 *
 * @param keyAttributes The user's key attributes.
 *
 * @param masterKey The user's master key (base64 encoded).
 */
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
    /**
     * The 2FA secret code.
     */
    secretCode: z.string(),
    /**
     * A base64 encoded "image/png".
     */
    qrCode: z.string(),
});

export type TwoFactorSecret = z.infer<typeof TwoFactorSecret>;

/**
 * Start a TOTP based two factor setup process by fetching a secret code (and
 * the corresponding QR code) from remote.
 *
 * Once the user provides us with a TOTP generated using the provided secret, we
 * can finish the setup with {@link setupTwoFactorFinish}.
 */
export const setupTwoFactor = async (): Promise<TwoFactorSecret> => {
    const res = await fetch(await apiURL("/users/two-factor/setup"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return TwoFactorSecret.parse(await res.json());
};

/**
 * Finish the TOTP based two factor setup by provided a previously obtained
 * secret (using {@link setupTwoFactor}) and the current TOTP generated using
 * that secret.
 *
 * This updates both the state both locally and on remote.
 *
 * @param secretCode The value of {@link secretCode} from the
 * {@link TwoFactorSecret} obtained by {@link setupTwoFactor}.
 *
 * @param totp The current TOTP corresponding to {@link secretCode}.
 */
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

interface EnableTwoFactorRequest {
    /**
     * The current value of the TOTP corresponding to the two factor {@link
     * secretCode} obtained from a previous call to {@link setupTwoFactor}.
     */
    code: string;
    /**
     * The {@link secretCode} encrypted with the user's recovery key.
     *
     * This is used in the case of second factor recovery.
     */
    encryptedTwoFactorSecret: string;
    /**
     * The nonce that was used when encrypting {@link encryptedTwoFactorSecret}.
     */
    twoFactorSecretDecryptionNonce: string;
}

/**
 * Enable the TOTP based two factor for the user by providing the current 2FA
 * code corresponding the two factor secret, and encrypted secrets for future
 * recovery (if needed).
 */
const enableTwoFactor = async (req: EnableTwoFactorRequest) =>
    ensureOk(
        await fetch(await apiURL("/users/two-factor/enable"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify(req),
        }),
    );

/**
 * The result of a successful two factor verification (TOTP or passkey),
 * recovery removal (TOTP) or recovery bypass (passkey).
 */
export const TwoFactorAuthorizationResponse = z.object({
    /**
     * The user's ID.
     */
    id: z.number(),
    /**
     * The user's key attributes.
     */
    keyAttributes: RemoteKeyAttributes,
    /**
     * A encrypted auth token.
     */
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

/** The type of the second factor we're trying to act on */
export type TwoFactorType = "totp" | "passkey";

const TwoFactorRecoveryResponse = z.object({
    /**
     * The recovery secret, encrypted using the user's recovery key.
     */
    encryptedSecret: z.string(),
    /**
     * The nonce used during encryption of {@link encryptedSecret}.
     */
    secretDecryptionNonce: z.string(),
});

export type TwoFactorRecoveryResponse = z.infer<
    typeof TwoFactorRecoveryResponse
>;

/**
 * Initiate second factor reset or bypass by requesting the encrypted second
 * factor recovery secret (and nonce) from remote. The user can then decrypt
 * these using their recovery key to reset or bypass their second factor.
 *
 * @param twoFactorType The type of second factor to reset or bypass.
 *
 * @param sessionID A two factor session ID ({@link twoFactorSessionID} or
 * {@link passkeySessionID}) for the user.
 *
 * [Note: Second factor recovery]
 *
 * 1. When setting up a TOTP based second factor, client sends a (encrypted 2fa
 *    recovery secret, nonce) pair to remote. This is a randomly generated
 *    secret (and nonce) encrypted using the user's recovery key.
 *
 * 2. Similarly, when setting up a passkey as the second factor, the client
 *    sends a encrypted recovery secret (see {@link configurePasskeyRecovery}).
 *
 * 3. When the user wishes to reset or bypass their second factor, the client
 *    asks remote for these encrypted secrets (using {@link getRecoverTwoFactor}).
 *
 * 4. User then enters their recovery key, which the client uses to decrypt the
 *    recovery secret and provide it back to remote for verification (using
 *    {@link removeTwoFactor}).
 *
 * 5. If the recovery secret matches, then remote resets (TOTP based) or bypass
 *    (passkey based) the user's second factor.
 */
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

/**
 * Finish the second factor recovery / bypass initiated by
 * {@link getRecoverTwoFactor} using the provided recovery key mnemonic entered
 * by the user.
 *
 * See: [Note: Second factor recovery].
 *
 * This completes the recovery process both locally, and on remote.
 *
 * @param twoFactorType The second factor type (same value as what would've been
 * passed to {@link getRecoverTwoFactor} for obtaining
 * {@link recoveryResponse}).
 *
 * @param sessionID The second factor session ID (same value as what would've
 * been passed to {@link getRecoverTwoFactor} for obtaining
 * {@link recoveryResponse}).
 *
 * @param recoveryResponse The response to a previous call to
 * {@link getRecoverTwoFactor}.
 *
 * @param recoveryKeyMnemonic The 24-word BIP-39 recovery key mnemonic provided
 * by the user to complete recovery.
 */
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
