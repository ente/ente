import {
    replaceSavedLocalUser,
    savedOriginalKeyAttributes,
    saveIsFirstLogin,
    saveJustSignedUp,
    saveKeyAttributes,
    saveOriginalKeyAttributes,
    stashReferralSource,
    stashSRPSetupAttributes,
    unstashAfterUseSRPSetupAttributes,
    unstashReferralSource,
} from "ente-accounts-rs/services/accounts-db";
import {
    generateSRPSetupAttributes,
    getAndSaveSRPAttributes,
} from "ente-accounts-rs/services/srp";
import {
    generateAndSaveInteractiveKeyAttributes,
    generateKeysAndAttributes,
    sendOTT,
    verifyEmail,
    type KeyAttributes,
} from "ente-accounts-rs/services/user";
import { isMuseumHTTPError } from "ente-base/http";
import {
    decryptSpaceBootstrapAuthToken,
    putSpaceSignupKeyAttributes,
    setupSpaceSignupSRP,
} from "services/spaceBootstrapAuth";
import {
    createSpaceBrowserSession,
    getOrCreateSpaceRootKey,
} from "services/spacePersistentSession";
import {
    authMasterKeyFromSpaceSession,
    clearAuthMasterKeyFromSpaceSession,
    saveAuthMasterKeyInSpaceSession,
} from "services/spaceSecureSessionStorage";

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

    const { masterKey, kek, keyAttributes } =
        await generateKeysAndAttributes(password);
    saveOriginalKeyAttributes(keyAttributes);
    stashSRPSetupAttributes(await generateSRPSetupAttributes(kek));
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
    if (token) return token;
    if (encryptedToken) {
        return decryptSpaceBootstrapAuthToken(
            encryptedToken,
            keyAttributes,
            masterKey,
        );
    }
    throw new Error("Signup session expired. Please sign in.");
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
    if (!masterKey) throw new Error("Signup session expired. Please sign in.");

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
            throw new Error("Signup session expired. Please sign in.");
        }
        bootstrapAuthToken = await verifiedSignupAuthToken({
            encryptedToken,
            keyAttributes: originalKeyAttributes,
            masterKey,
            token,
        });
        await putSpaceSignupKeyAttributes(
            originalKeyAttributes,
            bootstrapAuthToken,
        );
        await unstashAfterUseSRPSetupAttributes((srpSetupAttributes) =>
            setupSpaceSignupSRP(srpSetupAttributes, bootstrapAuthToken),
        );
        await getAndSaveSRPAttributes(email);
    }

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

export const spaceSignupErrorMessage = async (error: unknown) => {
    if (await isMuseumHTTPError(error, 409, "USER_ALREADY_REGISTERED")) {
        return "This email already has an account. Please sign in.";
    }
    return error instanceof Error
        ? error.message
        : "Couldn't create account. Please try again.";
};
