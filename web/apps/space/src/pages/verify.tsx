import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import { isHTTPErrorWithStatus } from "ente-base/http";
import React, { useEffect, useState } from "react";
import {
    VerifyEmailScreen,
    verifyEmailBackground,
} from "screens/VerifyEmailScreen";
import {
    completeSpaceLoginEmailVerification,
    resendSpaceLoginCode,
    savedPendingSpaceLoginCredentials,
    type SpaceLoginInput,
    type SpaceLoginResult,
} from "services/spaceLogin";
import { savePendingSpacePasskeyVerification } from "services/spacePasskeyVerification";
import {
    completeSpaceSignup,
    resendSpaceSignupCode,
} from "services/spaceSignup";
import { useSpaceAppState } from "state/spaceAppState";
import { routeAfterCompletedLogin } from "utils/spaceLoginNavigation";
import { spaceRoutes, verifyFlowFromQuery } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

const verificationErrorMessage = (error: unknown) => {
    if (isHTTPErrorWithStatus(error, 401)) {
        return "Incorrect code. Please try again.";
    }
    if (isHTTPErrorWithStatus(error, 410)) {
        return "This code has expired. Please request a new one.";
    }
    return error instanceof Error
        ? error.message
        : "Couldn't verify this code. Please try again.";
};

const isExpectedVerificationError = (error: unknown) =>
    isHTTPErrorWithStatus(error, 401) || isHTTPErrorWithStatus(error, 410);

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const {
        isLiveSignupVerification,
        pendingLoginCredentials,
        refreshProfile,
        setIsLiveSignupVerification,
        setPendingLoginCredentials,
        setPendingPasskeyVerification,
        signupEmail,
    } = useSpaceAppState();
    const [codeResetKey, setCodeResetKey] = useState(0);
    const [verificationError, setVerificationError] = useState<string>();
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [isResending, setIsResending] = useState(false);
    const [loginCredentials, setLoginCredentials] =
        useState<SpaceLoginInput | null>(null);
    const verifyFlow = verifyFlowFromQuery(router.query.flow);
    const isLoginVerification = router.isReady && verifyFlow == "login";
    const email = isLoginVerification ? loginCredentials?.email : signupEmail;

    useEffect(() => {
        if (!router.isReady) return undefined;

        if (isLoginVerification) {
            if (pendingLoginCredentials) {
                setLoginCredentials(pendingLoginCredentials);
                return undefined;
            }

            let cancelled = false;
            void savedPendingSpaceLoginCredentials().then((credentials) => {
                if (cancelled) return;
                if (!credentials) {
                    void router.replace(spaceRoutes.login);
                    return;
                }
                setLoginCredentials(credentials);
                setPendingLoginCredentials(credentials);
            });

            return () => {
                cancelled = true;
            };
        }

        if (!signupEmail) {
            void router.replace(spaceRoutes.signup);
        }
        return undefined;
    }, [
        isLoginVerification,
        pendingLoginCredentials,
        router,
        router.isReady,
        setPendingLoginCredentials,
        signupEmail,
    ]);

    const handleLoginResult = async (result: SpaceLoginResult) => {
        switch (result.status) {
            case "complete":
                await routeAfterCompletedLogin(router, refreshProfile);
                setPendingLoginCredentials(null);
                break;
            case "totp":
                setLoginCredentials(null);
                setPendingLoginCredentials(null);
                void router.push(spaceRoutes.twoFactorVerify);
                break;
            case "passkey":
                setLoginCredentials(null);
                setPendingLoginCredentials(null);
                setPendingPasskeyVerification({
                    hasTwoFactorFallback: result.hasTwoFactorFallback,
                    passkeySessionID: result.passkeySessionID,
                    url: result.url,
                });
                savePendingSpacePasskeyVerification({
                    hasTwoFactorFallback: result.hasTwoFactorFallback,
                    passkeySessionID: result.passkeySessionID,
                    url: result.url,
                });
                void router.push(spaceRoutes.passkeysVerify);
                break;
            case "email-otp":
                setVerificationError("Please enter the latest code we sent.");
                setIsSubmitting(false);
                break;
        }
    };

    const verifySignupEmail = async (code: string) => {
        if (!isLiveSignupVerification) {
            void router.push(spaceRoutes.createProfile());
            return;
        }

        try {
            await completeSpaceSignup(signupEmail, code);
            setIsLiveSignupVerification(false);
            void router.push(spaceRoutes.createProfile());
        } catch (error) {
            if (!isExpectedVerificationError(error)) {
                console.error("Space signup verification failed", error);
            }
            if (isHTTPErrorWithStatus(error, 401)) {
                setCodeResetKey((key) => key + 1);
            }
            setVerificationError(verificationErrorMessage(error));
            setIsSubmitting(false);
        }
    };

    const verifyLoginEmail = async (code: string) => {
        if (!loginCredentials) {
            void router.replace(spaceRoutes.login);
            return;
        }

        try {
            await handleLoginResult(
                await completeSpaceLoginEmailVerification({
                    ...loginCredentials,
                    code,
                }),
            );
        } catch (error) {
            if (!isExpectedVerificationError(error)) {
                console.error("Space login email verification failed", error);
            }
            if (isHTTPErrorWithStatus(error, 401)) {
                setCodeResetKey((key) => key + 1);
            }
            setVerificationError(verificationErrorMessage(error));
            setIsSubmitting(false);
        }
    };

    const verifyEmail = (code: string) => {
        setIsSubmitting(true);
        setVerificationError(undefined);
        if (isLoginVerification) void verifyLoginEmail(code);
        else void verifySignupEmail(code);
    };

    const resendVerificationCode = async () => {
        if (!email || isResending) return;

        setIsResending(true);
        setVerificationError(undefined);
        try {
            if (isLoginVerification) await resendSpaceLoginCode(email);
            else await resendSpaceSignupCode(email);
        } catch (error) {
            console.error("Space verification resend failed", error);
            setVerificationError(
                error instanceof Error
                    ? error.message
                    : "Couldn't resend the code. Please try again.",
            );
        } finally {
            setIsResending(false);
        }
    };

    if (!router.isReady || !email) {
        return <SpaceRouteFallback background={verifyEmailBackground} />;
    }

    return (
        <>
            <SpacePageMeta themeColor={verifyEmailBackground} />
            <VerifyEmailScreen
                codeResetKey={codeResetKey}
                email={email}
                errorMessage={verificationError}
                initialCode={
                    isLoginVerification || isLiveSignupVerification
                        ? ""
                        : undefined
                }
                isResending={isResending}
                isSubmitting={isSubmitting}
                onBack={() =>
                    void router.push(
                        isLoginVerification
                            ? spaceRoutes.login
                            : spaceRoutes.signup,
                    )
                }
                onChangeEmail={() =>
                    void router.push(
                        isLoginVerification
                            ? spaceRoutes.login
                            : spaceRoutes.signup,
                    )
                }
                onResendCode={
                    isLoginVerification || isLiveSignupVerification
                        ? () => void resendVerificationCode()
                        : undefined
                }
                onVerify={verifyEmail}
            />
        </>
    );
};

export default Page;
