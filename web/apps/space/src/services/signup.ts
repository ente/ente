import {
    replaceSavedLocalUser,
    savedOriginalKeyAttributes,
    savedPartialLocalUser,
    saveIsFirstLogin,
    saveJustSignedUp,
    saveKeyAttributes,
    saveOriginalKeyAttributes,
    stashReferralSource,
    stashSRPSetupAttributes,
    unstashReferralSource,
} from "ente-accounts/services/accounts-db";
import { completePendingSignup } from "ente-accounts/services/srp";
import {
    generateAndSaveInteractiveKeyAttributes,
    generateSignupKeys,
    sendOTT,
    unlockAccountWithKey,
    verifyEmail,
    type KeyAttributes,
} from "ente-accounts/services/user";
import { spaceAuthError } from "services/auth-error";
import {
    createSpaceBrowserSession,
    getOrCreateSpaceRootKey,
} from "services/persistent-session";
import {
    authMasterKeyFromSpaceSession,
    clearAuthMasterKeyFromSpaceSession,
    saveAuthMasterKeyInSpaceSession,
} from "services/secure-session-storage";

export interface SpaceSignupInput {
    email: string;
    password: string;
    referralSource: string;
}

export const beginSpaceSignup = async ({
    email,
    password,
    referralSource,
}: SpaceSignupInput) => {
    const cleanedEmail = email.trim();
    const cleanedReferralSource = referralSource.trim();
    unstashReferralSource();
    if (cleanedReferralSource) stashReferralSource(cleanedReferralSource);

    await sendOTT(cleanedEmail, "signup");
    replaceSavedLocalUser({ email: cleanedEmail });

    const { masterKey, keyAttributes, srp } =
        await generateSignupKeys(password);
    saveOriginalKeyAttributes(keyAttributes);
    stashSRPSetupAttributes(srp);
    await generateAndSaveInteractiveKeyAttributes(
        password,
        keyAttributes,
        masterKey,
    );
    saveAuthMasterKeyInSpaceSession(masterKey);
    saveJustSignedUp();

    return { email: cleanedEmail };
};

const verifiedSignupAuthToken = async ({
    encryptedToken,
    keyAttributes,
    masterKey,
    token,
}: {
    encryptedToken?: string;
    keyAttributes: KeyAttributes;
    masterKey: string;
    token?: string;
}) => {
    if (!token && !encryptedToken)
        throw spaceAuthError("signup_session_expired");
    return (
        await unlockAccountWithKey(
            {
                id: savedPartialLocalUser()!.id!,
                token,
                encryptedToken,
                keyAttributes,
            },
            masterKey,
        )
    ).token;
};

export const completeSpaceSignup = async (email: string, code: string) => {
    const referralSource = unstashReferralSource();
    const cleanedReferralSource = referralSource
        ? `web:${referralSource}`
        : undefined;
    const {
        keyAttributes,
        encryptedToken,
        token,
        id,
        twoFactorSessionID,
        passkeySessionID,
    } = await verifyEmail(email, code, cleanedReferralSource);

    if (passkeySessionID || twoFactorSessionID) {
        throw new Error("Unexpected second factor during signup");
    }

    replaceSavedLocalUser({ id, email });

    const masterKey = authMasterKeyFromSpaceSession();
    if (!masterKey) throw spaceAuthError("signup_session_expired");

    let bootstrapAuthToken: string;
    if (keyAttributes) {
        saveKeyAttributes(keyAttributes);
        saveOriginalKeyAttributes(keyAttributes);
        bootstrapAuthToken = await verifiedSignupAuthToken({
            encryptedToken,
            keyAttributes,
            masterKey,
            token,
        });
    } else {
        const originalKeyAttributes = savedOriginalKeyAttributes();
        if (!originalKeyAttributes) {
            throw spaceAuthError("signup_session_expired");
        }
        bootstrapAuthToken = await verifiedSignupAuthToken({
            encryptedToken,
            keyAttributes: originalKeyAttributes,
            masterKey,
            token,
        });
    }
    await completePendingSignup(email, bootstrapAuthToken);

    const spaceRootKey = await getOrCreateSpaceRootKey(
        masterKey,
        bootstrapAuthToken,
    );
    await createSpaceBrowserSession(spaceRootKey, bootstrapAuthToken);
    clearAuthMasterKeyFromSpaceSession();
    saveIsFirstLogin();
};

export const resendSpaceSignupCode = (email: string) =>
    sendOTT(email.trim(), "signup");
