import {
    replaceSavedLocalUser,
    savedPartialLocalUser,
    savedSRPAttributes,
    saveIsFirstLogin,
    saveKeyAttributes,
    saveOriginalKeyAttributes,
    saveSRPAttributes,
    updateSavedLocalUser,
} from "ente-accounts/services/accounts-db";
import {
    deriveKey,
    fromB64URLSafeNoPadding,
} from "ente-accounts/services/crypto";
import {
    checkPasskeyVerificationStatus,
    clearInflightPasskeySessionID,
} from "ente-accounts/services/passkey";
import {
    stashKeyEncryptionKeyInSessionStore,
    unstashKeyEncryptionKeyFromSession,
} from "ente-accounts/services/prelogin-session";
import { getSRPAttributes, verifySRP } from "ente-accounts/services/srp";
import {
    type EmailOrSRPVerificationResponse,
    generateAndSaveInteractiveKeyAttributes,
    sendOTT,
    TwoFactorAuthorizationResponse,
    unlockAccountWithKEK,
    verifyEmail,
    verifyTwoFactor,
} from "ente-accounts/services/user";
import { clientPackageName } from "ente-base/app";
import { nullToUndefined } from "ente-utils/transform";
import { spaceAuthError } from "services/auth-error";
import {
    createSpaceBrowserSession,
    getOrCreateSpaceRootKey,
} from "services/persistent-session";

export interface SpaceLoginInput {
    email: string;
    password: string;
}

interface LoginKDFAttributes {
    kekSalt: string;
    memLimit: number;
    opsLimit: number;
}

export type SpaceLoginResult =
    | { status: "complete"; email: string }
    | { status: "email-otp"; email: string }
    | { status: "totp"; email: string }
    | {
          accountsUrl: string;
          hasTwoFactorFallback: boolean;
          passkeySessionID: string;
          status: "passkey";
          url: string;
      };

export type SpaceLoginPasskeyStatusResult =
    SpaceLoginResult | { status: "pending" };

let pendingSpaceLoginCredentials: SpaceLoginInput | undefined;

const cleanedEmail = (email: string) => email.trim();

const deriveLoginKEK = (
    password: string,
    { kekSalt, memLimit, opsLimit }: LoginKDFAttributes,
) => deriveKey(password, kekSalt, opsLimit, memLimit);

const savePendingSpaceLoginCredentials = (credentials: SpaceLoginInput) => {
    pendingSpaceLoginCredentials = {
        email: cleanedEmail(credentials.email),
        password: credentials.password,
    };
};

export const savedPendingSpaceLoginCredentials = () =>
    Promise.resolve(
        pendingSpaceLoginCredentials
            ? { ...pendingSpaceLoginCredentials }
            : undefined,
    );

const clearPendingSpaceLoginCredentials = () => {
    pendingSpaceLoginCredentials = undefined;
};

const spacePasskeyVerificationRedirectURL = (
    accountsURL: string,
    passkeySessionID: string,
) => {
    const redirect = `${window.location.origin}/passkeys/finish`;
    const params = new URLSearchParams({
        clientPackage: clientPackageName,
        passkeySessionID,
        redirect,
    });
    return `${accountsURL}/passkeys/verify?${params.toString()}`;
};

export const beginSpaceLogin = async ({
    email,
    password,
}: SpaceLoginInput): Promise<SpaceLoginResult> => {
    const emailForLogin = cleanedEmail(email);
    clearPendingSpaceLoginCredentials();
    const srpAttributes = await getSRPAttributes(emailForLogin);

    if (!srpAttributes) {
        await sendOTT(emailForLogin, "login");
        replaceSavedLocalUser({ email: emailForLogin });
        savePendingSpaceLoginCredentials({ email: emailForLogin, password });
        return { status: "email-otp", email: emailForLogin };
    }

    replaceSavedLocalUser({ email: emailForLogin });
    saveSRPAttributes(srpAttributes);

    if (srpAttributes.isEmailMFAEnabled) {
        await sendOTT(emailForLogin, "login");
        savePendingSpaceLoginCredentials({ email: emailForLogin, password });
        return { status: "email-otp", email: emailForLogin };
    }

    clearPendingSpaceLoginCredentials();
    const kek = await deriveLoginKEK(password, srpAttributes);

    return finishSpaceLoginVerification({
        email: emailForLogin,
        kek,
        password,
        verification: await verifySRP(srpAttributes, kek),
    });
};

export const completeSpaceLoginEmailVerification = async ({
    code,
    email,
    password,
}: SpaceLoginInput & { code: string }): Promise<SpaceLoginResult> => {
    const emailForLogin = cleanedEmail(email);
    const srpAttributes =
        savedSRPAttributes() ?? (await getSRPAttributes(emailForLogin));
    const verification = await verifyEmail(emailForLogin, code, undefined);

    if (!srpAttributes) {
        return finishSpaceLoginVerification({
            email: emailForLogin,
            password,
            verification,
        });
    }

    saveSRPAttributes(srpAttributes);
    return finishSpaceLoginVerification({
        email: emailForLogin,
        kek: await deriveLoginKEK(password, srpAttributes),
        password,
        verification,
    });
};

export const resendSpaceLoginCode = (email: string) =>
    sendOTT(email.trim(), "login");

interface FinishSpaceLoginVerificationInput {
    email: string;
    kek?: string;
    password?: string;
    verification: EmailOrSRPVerificationResponse;
}

const finishSpaceLoginVerification = async ({
    email,
    kek,
    password,
    verification,
}: FinishSpaceLoginVerificationInput): Promise<SpaceLoginResult> => {
    const {
        accountsUrl,
        encryptedToken,
        id,
        keyAttributes,
        passkeySessionID,
        token,
        twoFactorSessionID,
        twoFactorSessionIDV2,
    } = verification;

    const secondFactorSessionID = twoFactorSessionID || twoFactorSessionIDV2;

    if (passkeySessionID) {
        if (!accountsUrl) {
            throw new Error("Passkey verification URL is missing.");
        }
        if (kek) await stashKeyEncryptionKeyInSessionStore(kek);
        updateSavedLocalUser({
            passkeySessionID,
            twoFactorSessionID: secondFactorSessionID,
            isTwoFactorEnabled: true,
        });
        saveIsFirstLogin();
        return {
            accountsUrl,
            hasTwoFactorFallback: Boolean(secondFactorSessionID),
            passkeySessionID,
            status: "passkey",
            url: spacePasskeyVerificationRedirectURL(
                accountsUrl,
                passkeySessionID,
            ),
        };
    }

    if (secondFactorSessionID) {
        if (kek) await stashKeyEncryptionKeyInSessionStore(kek);
        updateSavedLocalUser({
            passkeySessionID: undefined,
            twoFactorSessionID: secondFactorSessionID,
            isTwoFactorEnabled: true,
        });
        saveIsFirstLogin();
        return { status: "totp", email };
    }

    updateSavedLocalUser({
        id,
        token: undefined,
        encryptedToken: undefined,
        isTwoFactorEnabled: undefined,
        twoFactorSessionID: undefined,
        passkeySessionID: undefined,
    });
    if (!keyAttributes) {
        throw spaceAuthError("account_setup_incomplete");
    }

    const loginKEK =
        kek ??
        (password ? await deriveLoginKEK(password, keyAttributes) : undefined);
    if (!loginKEK) {
        throw spaceAuthError("login_session_expired");
    }

    await saveCompletedSpaceLogin({
        id,
        authToken: token,
        encryptedToken,
        keyAttributes,
        kek: loginKEK,
        password,
    });
    clearPendingSpaceLoginCredentials();

    return { status: "complete", email };
};

export const completeSpaceLoginSecondFactor = async (
    code: string,
    sessionID: string,
): Promise<SpaceLoginResult> => {
    const response = await verifyTwoFactor(code, sessionID);
    return finishSpaceLoginAuthorization(response);
};

export const completeSpaceLoginPasskey = async (
    passkeySessionID: string,
    response: string,
): Promise<SpaceLoginResult> => {
    const inflightPasskeySessionID = nullToUndefined(
        sessionStorage.getItem("inflightPasskeySessionID"),
    );
    if (
        !inflightPasskeySessionID ||
        inflightPasskeySessionID != passkeySessionID
    ) {
        throw new Error("Unexpected passkey verification response.");
    }

    clearInflightPasskeySessionID();
    return finishSpaceLoginAuthorization(
        TwoFactorAuthorizationResponse.parse(
            JSON.parse(
                new TextDecoder().decode(
                    await fromB64URLSafeNoPadding(response),
                ),
            ),
        ),
    );
};

export const checkSpaceLoginPasskeyStatus = async (
    passkeySessionID: string,
): Promise<SpaceLoginPasskeyStatusResult> => {
    const response = await checkPasskeyVerificationStatus(passkeySessionID);
    if (!response) return { status: "pending" };

    clearInflightPasskeySessionID();
    return finishSpaceLoginAuthorization(response);
};

export const useSpaceLoginTwoFactorInstead = () => {
    clearInflightPasskeySessionID();
    updateSavedLocalUser({ passkeySessionID: undefined });
};

const finishSpaceLoginAuthorization = async ({
    encryptedToken,
    id,
    keyAttributes,
}: TwoFactorAuthorizationResponse): Promise<SpaceLoginResult> => {
    const [stashedKEK, pendingCredentials] = await Promise.all([
        unstashKeyEncryptionKeyFromSession(),
        savedPendingSpaceLoginCredentials(),
    ]);
    const kek =
        stashedKEK ??
        (pendingCredentials
            ? await deriveLoginKEK(pendingCredentials.password, keyAttributes)
            : undefined);
    if (!kek) throw spaceAuthError("login_session_expired");

    updateSavedLocalUser({
        id,
        token: undefined,
        encryptedToken: undefined,
        isTwoFactorEnabled: undefined,
        twoFactorSessionID: undefined,
        passkeySessionID: undefined,
    });
    await saveCompletedSpaceLogin({
        id,
        encryptedToken,
        keyAttributes,
        kek,
        password: pendingCredentials?.password,
    });
    clearPendingSpaceLoginCredentials();

    return { status: "complete", email: savedPartialLocalUser()?.email ?? "" };
};

const saveCompletedSpaceLogin = async ({
    id,
    authToken,
    encryptedToken,
    keyAttributes,
    kek,
    password,
}: {
    id: number;
    authToken?: string;
    encryptedToken?: string;
    keyAttributes: EmailOrSRPVerificationResponse["keyAttributes"];
    kek: string;
    password?: string;
}) => {
    if (!keyAttributes) {
        throw spaceAuthError("account_setup_incomplete");
    }

    saveIsFirstLogin();
    saveKeyAttributes(keyAttributes);
    saveOriginalKeyAttributes(keyAttributes);

    const { masterKey, token: bootstrapAuthToken } = await unlockAccountWithKEK(
        { id, token: authToken, encryptedToken, keyAttributes },
        kek,
    );
    if (password)
        await generateAndSaveInteractiveKeyAttributes(
            password,
            keyAttributes,
            masterKey,
        );
    const spaceRootKey = await getOrCreateSpaceRootKey(
        masterKey,
        bootstrapAuthToken,
    );
    await createSpaceBrowserSession(spaceRootKey, bootstrapAuthToken);
};
