// The vault ties Ente's auth APIs together into the small state machine the
// extension UI and background worker need:
//
//   loggedOut -> (login) -> unlocked
//   locked    -> (unlock) -> unlocked        (master key was cleared but the
//                                             auth token + key attributes remain)
//
// The decrypted master key and the decrypted authenticator items only ever live
// in `browser.storage.session`, which is restricted to trusted extension
// contexts and cleared when the browser closes.
import { getAuthCodesAndTimeOffset } from "./ente/auth-data";
import type { Code } from "./ente/code";
import { decryptBox, deriveKey } from "./ente/crypto";
import { HTTPError } from "./ente/http";
import {
    decryptAndStoreTokenIfNeeded,
    RemoteKeyAttributes,
    remoteLogoutIfNeeded,
    sendOTT,
    verifyEmailOTT,
    verifyTwoFactor,
    type KeyAttributes,
} from "./ente/keys";
import {
    clearLocalState,
    savedKeyAttributes,
    savedLocalUser,
    savedPartialLocalUser,
    saveKeyAttributes,
    saveSRPAttributes,
    updateSavedLocalUser,
} from "./ente/local-state";
import { isSessionValid } from "./ente/session";
import { getSRPAttributes, SRPVerificationError, verifySRP } from "./ente/srp";
import {
    clearSessionStorage,
    getSession,
    removeSession,
    restrictSessionStorageToTrustedContexts,
    setSession,
} from "./ente/storage";
import { removeAuthToken, saveAuthToken, savedAuthToken } from "./ente/token";
import { SESSION } from "./session-keys";

export type LoginErrorCode =
    | "not_registered"
    | "email_mfa_unsupported"
    | "passkey_unsupported"
    | "incorrect_password"
    | "missing_keys"
    | "not_logged_in"
    | "locked"
    | "unknown";

export class LoginError extends Error {
    code: LoginErrorCode;
    constructor(code: LoginErrorCode, message?: string) {
        super(message ?? code);
        this.name = "LoginError";
        this.code = code;
    }
}

export type VaultStatus =
    "loggedOut" | "locked" | "unlocked" | "twoFactor" | "emailCode";

export interface VaultState {
    status: VaultStatus;
    email?: string;
    twoFactorSessionID?: string;
}

export const getVaultState = async (): Promise<VaultState> => {
    await restrictSessionStorageToTrustedContexts();
    const token = await savedAuthToken();
    const partial = await savedPartialLocalUser();

    if (!token) {
        // A login that is paused waiting for the second factor. The popup may
        // have been closed in between (e.g. the user switched to their 2FA
        // app), so we resume it from storage.
        if (
            partial?.twoFactorSessionID &&
            (await getSession<string>(SESSION.pendingKek))
        ) {
            return {
                status: "twoFactor",
                email: partial.email,
                twoFactorSessionID: partial.twoFactorSessionID,
            };
        }
        // A login paused waiting for the email verification code.
        if (
            (await getSession<string>(SESSION.emailCodeLogin)) &&
            (await getSession<string>(SESSION.pendingKek))
        ) {
            return { status: "emailCode", email: partial?.email };
        }
        return { status: "loggedOut" };
    }

    const email = (await savedLocalUser())?.email ?? partial?.email;
    const masterKey = await getSession<string>(SESSION.masterKey);

    if (masterKey) return { status: "unlocked", email };
    return { status: "locked", email };
};

export interface LoginResult {
    status: "unlocked" | "twoFactor" | "emailCode";
    sessionID?: string;
}

// First-time login on this browser: verifies the password against the server's
// SRP verifier.
export const login = async (
    email: string,
    password: string,
): Promise<LoginResult> => {
    await restrictSessionStorageToTrustedContexts();

    const srpAttributes = await getSRPAttributes(email);
    if (!srpAttributes) throw new LoginError("not_registered");

    await updateSavedLocalUser({ email });

    const kek = await deriveKey(
        password,
        srpAttributes.kekSalt,
        srpAttributes.opsLimit,
        srpAttributes.memLimit,
    );

    // Accounts with email MFA cannot log in over SRP: the server returns
    // `EMAIL_MFA_ENABLED` for the SRP session. Instead we trigger an email
    // one-time code and verify it in a second step (`submitEmailCode`), keeping
    // the already-derived KEK so the password is only entered once.
    if (srpAttributes.isEmailMFAEnabled) {
        await saveSRPAttributes(srpAttributes);
        await sendOTT(email, "login");
        await setSession(SESSION.pendingKek, kek);
        await setSession(SESSION.emailCodeLogin, email);
        return { status: "emailCode" };
    }

    let result;
    try {
        result = await verifySRP(srpAttributes, kek);
    } catch (e) {
        if (e instanceof SRPVerificationError)
            throw new LoginError("incorrect_password");
        throw e;
    }

    await saveSRPAttributes(srpAttributes);

    if (result.passkeySessionID) throw new LoginError("passkey_unsupported");

    if (result.twoFactorSessionID) {
        await setSession(SESSION.pendingKek, kek);
        await updateSavedLocalUser({
            isTwoFactorEnabled: true,
            twoFactorSessionID: result.twoFactorSessionID,
        });
        return { status: "twoFactor", sessionID: result.twoFactorSessionID };
    }

    await finishLogin(result, kek, email);
    return { status: "unlocked" };
};

// Completes a login that was paused for an email verification code. `code` is
// the OTT from the email; the KEK stashed by `login` finishes the flow.
export const submitEmailCode = async (code: string): Promise<LoginResult> => {
    const kek = await getSession<string>(SESSION.pendingKek);
    const email = await getSession<string>(SESSION.emailCodeLogin);
    if (!kek || !email)
        throw new LoginError("unknown", "Email verification session expired");

    const result = await verifyEmailOTT(email, code);

    if (result.passkeySessionID) throw new LoginError("passkey_unsupported");

    if (result.twoFactorSessionID) {
        // Email code satisfied, but a second factor is still required. Hand
        // over to the TOTP flow, which reuses the same pending KEK.
        await removeSession(SESSION.emailCodeLogin);
        await updateSavedLocalUser({
            isTwoFactorEnabled: true,
            twoFactorSessionID: result.twoFactorSessionID,
        });
        return { status: "twoFactor", sessionID: result.twoFactorSessionID };
    }

    await removeSession(SESSION.emailCodeLogin);
    await finishLogin(result, kek, email);
    return { status: "unlocked" };
};

// Re-sends the login email code (e.g. the first one expired).
export const resendEmailCode = async (): Promise<void> => {
    const email =
        (await getSession<string>(SESSION.emailCodeLogin)) ??
        (await savedPartialLocalUser())?.email;
    if (!email) throw new LoginError("unknown", "No pending email login");
    await sendOTT(email, "login");
};

export const submitTwoFactor = async (
    code: string,
    sessionID: string,
): Promise<void> => {
    const kek = await getSession<string>(SESSION.pendingKek);
    if (!kek) throw new LoginError("unknown", "Two-factor session expired");

    const result = await verifyTwoFactor(code, sessionID);
    const email = (await savedPartialLocalUser())?.email;
    await removeSession(SESSION.pendingKek);
    await finishLogin(result, kek, email);
};

interface FinishLoginInput {
    id: number;
    keyAttributes?: KeyAttributes;
    token?: string;
    encryptedToken?: string;
    email?: string;
}

const finishLogin = async (
    result: FinishLoginInput,
    kek: string,
    email: string | undefined,
) => {
    const { id, keyAttributes, token, encryptedToken } = result;
    if (!keyAttributes) throw new LoginError("missing_keys");
    if (!token && !encryptedToken) throw new LoginError("missing_keys");

    const masterKey = await decryptBox(
        {
            encryptedData: keyAttributes.encryptedKey,
            nonce: keyAttributes.keyDecryptionNonce,
        },
        kek,
    );

    await saveKeyAttributes(keyAttributes);
    await updateSavedLocalUser({
        id,
        email,
        isTwoFactorEnabled: undefined,
        twoFactorSessionID: undefined,
    });

    if (token) {
        await saveAuthToken(token);
        await updateSavedLocalUser({ token });
    }

    if (encryptedToken) {
        await updateSavedLocalUser({ encryptedToken });
        await decryptAndStoreTokenIfNeeded(keyAttributes, masterKey);
    }

    await setSession(SESSION.masterKey, masterKey);
    await refreshCodes();
};

// Unlock an already-logged-in browser without a network round trip: the stored
// key attributes let us derive the KEK and decrypt the master key locally.
export const unlock = async (password: string): Promise<void> => {
    await restrictSessionStorageToTrustedContexts();

    const keyAttributes = await savedKeyAttributes();
    if (!keyAttributes) throw new LoginError("not_logged_in");

    let masterKey: string;
    try {
        const kek = await deriveKey(
            password,
            keyAttributes.kekSalt,
            keyAttributes.opsLimit,
            keyAttributes.memLimit,
        );
        masterKey = await decryptBox(
            {
                encryptedData: keyAttributes.encryptedKey,
                nonce: keyAttributes.keyDecryptionNonce,
            },
            kek,
        );
    } catch {
        throw new LoginError("incorrect_password");
    }

    await setSession(SESSION.masterKey, masterKey);
    await refreshCodes();
};

// Imports a session captured from a logged-in `auth.ente.com` tab. This is the
// fallback for logins the extension cannot perform itself (passkey / email
// verification), delegating them to the web app.
export interface ImportedWebSession {
    token: string;
    keyAttributes: unknown;
    user?: { id?: number; email?: string };
    masterKeyBox: { encryptedData: string; nonce: string; key: string };
}

export const importWebSession = async (
    session: ImportedWebSession,
): Promise<void> => {
    await restrictSessionStorageToTrustedContexts();

    const keyAttributes = RemoteKeyAttributes.parse(session.keyAttributes);
    const masterKey = await decryptBox(
        {
            encryptedData: session.masterKeyBox.encryptedData,
            nonce: session.masterKeyBox.nonce,
        },
        session.masterKeyBox.key,
    );

    await saveKeyAttributes(keyAttributes);
    await saveAuthToken(session.token);
    await updateSavedLocalUser({
        id: session.user?.id,
        email: session.user?.email,
        token: session.token,
        isTwoFactorEnabled: undefined,
        twoFactorSessionID: undefined,
    });
    await setSession(SESSION.masterKey, masterKey);
    await refreshCodes();
};

// If the background worker stashed credentials from a completed web login,
// unbox them and finish the login. Returns true when a pending session was
// found (and imported). Runs in the popup, which can load the WASM crypto
// stack.
export const consumePendingWebLogin = async (): Promise<boolean> => {
    const credentials = await getSession<ImportedWebSession>(
        SESSION.pendingWebLogin,
    );
    if (!credentials) return false;
    await importWebSession(credentials);
    await removeSession(SESSION.pendingWebLogin);
    return true;
};

export const refreshCodes = async (): Promise<Code[]> => {
    const masterKey = await getSession<string>(SESSION.masterKey);
    if (!masterKey) throw new LoginError("locked");

    try {
        const { codes, timeOffset } =
            await getAuthCodesAndTimeOffset(masterKey);
        await setSession(SESSION.codes, codes);
        await setSession(SESSION.timeOffset, timeOffset);
        return codes;
    } catch (e) {
        if (e instanceof HTTPError && e.res.status == 401) {
            await logout();
            throw new LoginError("not_logged_in");
        }
        throw e;
    }
};

export const getCachedCodes = async (): Promise<Code[]> =>
    (await getSession<Code[]>(SESSION.codes)) ?? [];

export const getTimeOffset = async (): Promise<number> =>
    (await getSession<number>(SESSION.timeOffset)) ?? 0;

export const ensureUnlocked = async (): Promise<boolean> => {
    if (await getSession<string>(SESSION.masterKey)) return true;
    // Best effort cleanup if the server no longer accepts our token.
    if (!(await isSessionValid())) {
        await logout();
        return false;
    }
    return false;
};

export const logout = async () => {
    try {
        await remoteLogoutIfNeeded();
    } catch {
        // Ignore: we are logging out regardless.
    }
    await removeAuthToken();
    await clearLocalState();
    await clearSessionStorage();
};
