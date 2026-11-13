import { useAuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
import { VerifyEmailForm } from "ente-accounts/components/auth/VerifyEmailForm";
import { VerifyingPasskey } from "ente-accounts/components/LoginComponents";
import { SecondFactorChoice } from "ente-accounts/components/SecondFactorChoice";
import { useSecondFactorChoiceIfNeeded } from "ente-accounts/components/utils/second-factor-choice";
import {
    replaceSavedLocalUser,
    savedKeyAttributes,
    savedPartialLocalUser,
    savedSRPAttributes,
    saveIsFirstLogin,
    saveKeyAttributes,
    saveOriginalKeyAttributes,
    unstashReferralSource,
    updateSavedLocalUser,
} from "ente-accounts/services/accounts-db";
import {
    openPasskeyVerificationURL,
    passkeyVerificationRedirectURL,
} from "ente-accounts/services/passkey";
import {
    stashedRedirect,
    unstashRedirect,
} from "ente-accounts/services/redirect";
import {
    completePendingSignup,
    getSRPAttributes,
} from "ente-accounts/services/srp";
import { sendOTT, verifyEmail } from "ente-accounts/services/user";
import { LoadingIndicator } from "ente-base/components/loaders";
import type { SingleInputFormProps } from "ente-base/components/SingleInputForm";
import { useBaseContext } from "ente-base/context";
import { isNamedError } from "ente-base/error";
import log from "ente-base/log";
import { clearSessionStorage } from "ente-base/session-storage";
import { saveAuthToken } from "ente-base/token";
import { t } from "i18next";
import { useRouter } from "next/router";
import { useCallback, useEffect, useState } from "react";

export interface VerifyEmailPresentationProps {
    email: string;
    resend: "enable" | "sending" | "sent";
    onSubmit: SingleInputFormProps["onSubmit"];
    onResend: () => void;
    onChangeEmail: () => void;
}

const Page: React.FC = () => {
    const { Shell, passkeyPresentation } = useAuthPageConfig();
    const { logout, showMiniDialog } = useBaseContext();

    const [email, setEmail] = useState("");
    const [resend, setResend] = useState<"enable" | "sending" | "sent">(
        "enable",
    );
    const [passkeyVerificationData, setPasskeyVerificationData] = useState<
        { passkeySessionID: string; url: string } | undefined
    >();

    const {
        secondFactorChoiceProps,
        userVerificationResultAfterResolvingSecondFactorChoice,
    } = useSecondFactorChoiceIfNeeded();

    const router = useRouter();

    useEffect(() => {
        void redirectionIfNeededOrEmail().then((redirectOrEmail) => {
            if (typeof redirectOrEmail == "string") {
                void router.replace(redirectOrEmail);
            } else {
                setEmail(redirectOrEmail.email);
            }
        });
    }, [router]);

    const onSubmit: SingleInputFormProps["onSubmit"] = async (
        ott,
        setFieldError,
    ) => {
        try {
            const referralSource = unstashReferralSource();
            const cleanedReferral = referralSource
                ? `web:${referralSource}`
                : undefined;
            const {
                keyAttributes,
                encryptedToken,
                token,
                id,
                twoFactorSessionID,
                passkeySessionID,
                accountsUrl,
            } = await userVerificationResultAfterResolvingSecondFactorChoice(
                await verifyEmail(email, ott, cleanedReferral),
            );

            if (passkeySessionID) {
                const url = passkeyVerificationRedirectURL(
                    accountsUrl!,
                    passkeySessionID,
                );
                updateSavedLocalUser({ passkeySessionID });
                saveIsFirstLogin();
                setPasskeyVerificationData({ passkeySessionID, url });
                openPasskeyVerificationURL({ passkeySessionID, url });
            } else if (twoFactorSessionID) {
                updateSavedLocalUser({
                    isTwoFactorEnabled: true,
                    twoFactorSessionID,
                });
                saveIsFirstLogin();
                void router.push("/two-factor/verify");
            } else {
                if (token) await saveAuthToken(token);
                replaceSavedLocalUser({ id, email, token, encryptedToken });
                if (keyAttributes) {
                    saveKeyAttributes(keyAttributes);
                    saveOriginalKeyAttributes(keyAttributes);
                } else {
                    if (token) await completePendingSignup(email, token);
                }
                saveIsFirstLogin();
                if (keyAttributes) {
                    clearSessionStorage();
                    void router.push(unstashRedirect() ?? "/credentials");
                } else {
                    void router.push(unstashRedirect() ?? "/generate");
                }
            }
        } catch (e) {
            if (isNamedError(e, "incorrect_email_code")) {
                setFieldError(t("invalid_code_error"));
            } else if (isNamedError(e, "email_code_expired")) {
                setFieldError(t("expired_code_error"));
            } else {
                log.error("OTT verification failed", e);
                throw e;
            }
        }
    };

    const resendEmail = useCallback(async () => {
        setResend("sending");
        await sendOTT(email, undefined);
        setResend("sent");
        setTimeout(() => setResend("enable"), 3000);
    }, [email]);

    const handlePasskeyRetry = useCallback(() => {
        if (passkeyVerificationData) {
            openPasskeyVerificationURL(passkeyVerificationData);
        }
    }, [passkeyVerificationData]);

    if (!email) {
        return <LoadingIndicator />;
    }

    if (passkeyVerificationData) {
        // Only the desktop app needs this UI; the web app is already
        // navigating to the passkey verification URL. Show a spinner on web
        // so that the VerifyingPasskey component does not flash before the
        // redirect completes.
        if (!globalThis.electron) {
            return <LoadingIndicator />;
        }

        return (
            <VerifyingPasskey
                email={email}
                passkeySessionID={passkeyVerificationData.passkeySessionID}
                onRetry={handlePasskeyRetry}
                presentation={passkeyPresentation}
                {...{ logout, showMiniDialog }}
            />
        );
    }

    return (
        <>
            <Shell>
                <VerifyEmailForm
                    email={email}
                    resend={resend}
                    onSubmit={onSubmit}
                    onResend={resendEmail}
                    onChangeEmail={logout}
                />
            </Shell>
            <SecondFactorChoice {...secondFactorChoiceProps} />
        </>
    );
};

export default Page;

const redirectionIfNeededOrEmail = async () => {
    const user = savedPartialLocalUser();

    const email = user?.email;
    if (!email) {
        return "/";
    }

    if (savedKeyAttributes() && (user.token || user.encryptedToken)) {
        return "/credentials";
    }

    if (stashedRedirect() == "/recover") return { email };

    const srpAttributes = savedSRPAttributes();
    if (srpAttributes && !srpAttributes.isEmailMFAEnabled) {
        // Fetch the latest SRP attributes instead of trusting the potentially
        // stale saved values. This path is infrequent, so the extra API call
        // is fine.
        const latestSRPAttributes = await getSRPAttributes(email);
        if (latestSRPAttributes && !latestSRPAttributes.isEmailMFAEnabled) {
            return "/credentials";
        }
    }

    return { email };
};
