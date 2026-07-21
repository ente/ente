import {
    replaceSavedLocalUser,
    savedPartialLocalUser,
    savedSRPAttributes,
    saveIsFirstLogin,
    saveKeyAttributes,
    saveOriginalKeyAttributes,
    saveSRPAttributes,
    updateSavedLocalUser,
} from "ente-accounts-rs/services/accounts-db";
import {
    decryptBox,
    deriveKey,
    fromB64URLSafeNoPadding,
} from "ente-accounts-rs/services/crypto";
import {
    checkPasskeyVerificationStatus,
    clearInflightPasskeySessionID,
    passkeySessionExpiredErrorMessage,
} from "ente-accounts-rs/services/passkey";
import {
    stashKeyEncryptionKeyInSessionStore,
    unstashKeyEncryptionKeyFromSession,
} from "ente-accounts-rs/services/session-storage";
import {
    getSRPAttributes,
    srpVerificationUnauthorizedErrorMessage,
    verifySRP,
} from "ente-accounts-rs/services/srp";
import {
    type EmailOrSRPVerificationResponse,
    generateAndSaveInteractiveKeyAttributes,
    sendOTT,
    TwoFactorAuthorizationResponse,
    verifyEmail,
    verifyTwoFactor,
} from "ente-accounts-rs/services/user";
import { clientPackageName } from "ente-base/app";
import { HTTPError } from "ente-base/http";
import log from "ente-base/log";
import { nullToUndefined } from "ente-utils/transform";
import { decryptSpaceBootstrapAuthToken } from "services/spaceBootstrapAuth";
import {
    createSpaceBrowserSession,
    getOrCreateSpaceRootKey,
} from "services/spacePersistentSession";
import { z } from "zod";

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
    | SpaceLoginResult
    | { status: "pending" };

export const spaceLoginPasskeySessionExpiredErrorMessage =
    passkeySessionExpiredErrorMessage;

let pendingSpaceLoginCredentials: SpaceLoginInput | undefined;

const cleanedEmail = (email: string) => email.trim();

const deriveLoginKEK = (
    password: string,
    { kekSalt, memLimit, opsLimit }: LoginKDFAttributes,
) => deriveKey(password, kekSalt, opsLimit, memLimit);

export const savePendingSpaceLoginCredentials = (
    credentials: SpaceLoginInput,
) => {
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

export const clearPendingSpaceLoginCredentials = () => {
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

const sendSpaceLoginOTT = async (email: string) => {
    try {
        await sendOTT(email, "login");
    } catch (error) {
        if (error instanceof HTTPError && error.res.status == 404) {
            let errorCode: string | undefined;
            try {
                errorCode = z
                    .object({ code: z.string() })
                    .parse(await error.res.json()).code;
            } catch (parseErr) {
                log.warn("Ignoring error when parsing error payload", parseErr);
            }
            if (errorCode == "USER_NOT_REGISTERED") {
                throw new Error("Email not registered", { cause: error });
            }
            if (errorCode == "USER_SIGNUP_INCOMPLETE") {
                throw new Error(
                    "Account setup incomplete. Create account to finish setup.",
                    { cause: error },
                );
            }
        }
        throw error;
    }
};

export const beginSpaceLogin = async ({
    email,
    password,
}: SpaceLoginInput): Promise<SpaceLoginResult> => {
    const emailForLogin = cleanedEmail(email);
    clearPendingSpaceLoginCredentials();
    const srpAttributes = await getSRPAttributes(emailForLogin);

    if (!srpAttributes) {
        await sendSpaceLoginOTT(emailForLogin);
        replaceSavedLocalUser({ email: emailForLogin });
        savePendingSpaceLoginCredentials({ email: emailForLogin, password });
        return { status: "email-otp", email: emailForLogin };
    }

    replaceSavedLocalUser({ email: emailForLogin });
    saveSRPAttributes(srpAttributes);

    if (srpAttributes.isEmailMFAEnabled) {
        await sendSpaceLoginOTT(emailForLogin);
        savePendingSpaceLoginCredentials({ email: emailForLogin, password });
        return { status: "email-otp", email: emailForLogin };
    }

    clearPendingSpaceLoginCredentials();
    const kek = await deriveLoginKEK(password, srpAttributes);

    let verification;
    try {
        verification = await verifySRP(srpAttributes, kek);
    } catch (error) {
        if (
            error instanceof Error &&
            error.message == srpVerificationUnauthorizedErrorMessage
        ) {
            throw new Error("Incorrect email or password.", { cause: error });
        }
        throw error;
    }

    return finishSpaceLoginVerification({
        email: emailForLogin,
        kek,
        password,
        verification,
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
    sendSpaceLoginOTT(email.trim());

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
        throw new Error("This account has not finished setup.");
    }

    const loginKEK =
        kek ??
        (password ? await deriveLoginKEK(password, keyAttributes) : undefined);
    if (!loginKEK) {
        throw new Error("Login session expired. Please sign in again.");
    }

    await saveCompletedSpaceLogin({
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
    if (!kek) throw new Error("Login session expired. Please sign in again.");

    updateSavedLocalUser({
        id,
        token: undefined,
        encryptedToken: undefined,
        isTwoFactorEnabled: undefined,
        twoFactorSessionID: undefined,
        passkeySessionID: undefined,
    });
    await saveCompletedSpaceLogin({
        encryptedToken,
        keyAttributes,
        kek,
        password: pendingCredentials?.password,
    });
    clearPendingSpaceLoginCredentials();

    return { status: "complete", email: savedPartialLocalUser()?.email ?? "" };
};

const saveCompletedSpaceLogin = async ({
    authToken,
    encryptedToken,
    keyAttributes,
    kek,
    password,
}: {
    authToken?: string;
    encryptedToken?: string;
    keyAttributes: EmailOrSRPVerificationResponse["keyAttributes"];
    kek: string;
    password?: string;
}) => {
    if (!keyAttributes) {
        throw new Error("This account has not finished setup.");
    }

    saveIsFirstLogin();
    saveKeyAttributes(keyAttributes);
    saveOriginalKeyAttributes(keyAttributes);

    const masterKey = await decryptBox(
        {
            encryptedData: keyAttributes.encryptedKey,
            nonce: keyAttributes.keyDecryptionNonce,
        },
        kek,
    );
    const tokenKeyAttributes = password
        ? await generateAndSaveInteractiveKeyAttributes(
              password,
              keyAttributes,
              masterKey,
          )
        : keyAttributes;
    const bootstrapAuthToken =
        authToken ??
        (encryptedToken
            ? await decryptSpaceBootstrapAuthToken(
                  encryptedToken,
                  tokenKeyAttributes,
                  masterKey,
              )
            : undefined);
    if (!bootstrapAuthToken) {
        throw new Error("Login session expired. Please sign in again.");
    }
    const spaceRootKey = await getOrCreateSpaceRootKey(
        masterKey,
        bootstrapAuthToken,
    );
    await createSpaceBrowserSession(spaceRootKey, bootstrapAuthToken);
};
