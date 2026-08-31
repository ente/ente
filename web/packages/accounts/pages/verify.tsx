import { Box, Typography } from "@mui/material";
import {
    AccountsPageContents,
    AccountsPageFooter,
    AccountsPageTitle,
} from "ente-accounts/components/layouts/centered-paper";
import {
    VerifyingPasskey,
    type VerifyingPasskeyPresentationProps,
} from "ente-accounts/components/LoginComponents";
import {
    SecondFactorChoice,
    type SecondFactorChoicePresentationProps,
} from "ente-accounts/components/SecondFactorChoice";
import { useSecondFactorChoiceIfNeeded } from "ente-accounts/components/utils/second-factor-choice";
import {
    replaceSavedLocalUser,
    savedKeyAttributes,
    savedOriginalKeyAttributes,
    savedPartialLocalUser,
    savedSRPAttributes,
    saveIsFirstLogin,
    saveKeyAttributes,
    saveOriginalKeyAttributes,
    unstashAfterUseSRPSetupAttributes,
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
import { clearSessionStorage } from "ente-accounts/services/session-storage";
import {
    getAndSaveSRPAttributes,
    getSRPAttributes,
    setupSRP,
} from "ente-accounts/services/srp";
import {
    putUserKeyAttributes,
    sendOTT,
    verifyEmail,
} from "ente-accounts/services/user";
import { LinkButton } from "ente-base/components/LinkButton";
import { LoadingIndicator } from "ente-base/components/loaders";
import {
    SingleInputForm,
    type SingleInputFormProps,
} from "ente-base/components/SingleInputForm";
import { useBaseContext } from "ente-base/context";
import { isHTTPErrorWithStatus } from "ente-base/http";
import log from "ente-base/log";
import { saveAuthToken } from "ente-base/token";
import { t } from "i18next";
import { useRouter } from "next/router";
import { useCallback, useEffect, useState, type ComponentType } from "react";
import { Trans } from "react-i18next";

export interface VerifyEmailPresentationProps {
    email: string;
    resend: "enable" | "sending" | "sent";
    onSubmit: SingleInputFormProps["onSubmit"];
    onResend: () => void;
    onChangeEmail: () => void;
}

export interface VerifyPageProps {
    presentation?: ComponentType<VerifyEmailPresentationProps>;
    passkeyPresentation?: ComponentType<VerifyingPasskeyPresentationProps>;
    secondFactorChoicePresentation?: ComponentType<SecondFactorChoicePresentationProps>;
}

const Page: React.FC<VerifyPageProps> = ({
    presentation: Presentation,
    passkeyPresentation,
    secondFactorChoicePresentation,
}) => {
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
                updateSavedLocalUser({ passkeySessionID });
                saveIsFirstLogin();
                const url = passkeyVerificationRedirectURL(
                    accountsUrl!,
                    passkeySessionID,
                );
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
                    const originalKeyAttributes = savedOriginalKeyAttributes();
                    if (originalKeyAttributes) {
                        await putUserKeyAttributes(originalKeyAttributes);
                    }
                    await unstashAfterUseSRPSetupAttributes(setupSRP);
                    await getAndSaveSRPAttributes(email);
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
            if (isHTTPErrorWithStatus(e, 401)) {
                setFieldError(t("invalid_code_error"));
            } else if (isHTTPErrorWithStatus(e, 410)) {
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

    if (Presentation) {
        return (
            <>
                <Presentation
                    email={email}
                    resend={resend}
                    onSubmit={onSubmit}
                    onResend={resendEmail}
                    onChangeEmail={logout}
                />
                <SecondFactorChoice
                    {...secondFactorChoiceProps}
                    presentation={secondFactorChoicePresentation}
                />
            </>
        );
    }

    return (
        <AccountsPageContents>
            <AccountsPageTitle>
                <Trans
                    i18nKey="email_sent"
                    components={{
                        a: (
                            <Box
                                component={"span"}
                                sx={{
                                    color: "text.muted",
                                    wordBreak: "break-word",
                                }}
                            />
                        ),
                    }}
                    values={{ email }}
                />
            </AccountsPageTitle>

            <Typography variant="small" sx={{ color: "text.muted", mb: 2 }}>
                {t("check_inbox_hint")}
            </Typography>
            <SingleInputForm
                autoComplete="one-time-code"
                label={t("verification_code")}
                submitButtonTitle={t("verify")}
                onSubmit={onSubmit}
            />

            <AccountsPageFooter>
                {resend == "enable" && (
                    <LinkButton onClick={resendEmail}>
                        {t("resend_code")}
                    </LinkButton>
                )}
                {resend == "sending" && <span>{t("status_sending")}</span>}
                {resend == "sent" && <span>{t("status_sent")}</span>}
                <LinkButton onClick={logout}>{t("change_email")}</LinkButton>
            </AccountsPageFooter>

            <SecondFactorChoice
                {...secondFactorChoiceProps}
                presentation={secondFactorChoicePresentation}
            />
        </AccountsPageContents>
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
