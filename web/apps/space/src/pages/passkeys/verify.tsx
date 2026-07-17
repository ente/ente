import { SpacePageMeta } from "components/SpacePageMeta";
import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import { savedPartialLocalUser } from "ente-accounts-rs/services/accounts-db";
import { openPasskeyVerificationURL } from "ente-accounts-rs/services/passkey";
import React, { useEffect, useState } from "react";
import {
    PasskeyVerificationScreen,
    passkeyVerificationBackground,
    type PasskeyVerificationStatus,
} from "screens/PasskeyVerificationScreen";
import {
    checkSpaceLoginPasskeyStatus,
    spaceLoginPasskeySessionExpiredErrorMessage,
    useSpaceLoginTwoFactorInstead,
} from "services/spaceLogin";
import {
    clearPendingSpacePasskeyVerification,
    hasAutoOpenedSpacePasskeyVerification,
    markAutoOpenedSpacePasskeyVerification,
    savedPendingSpacePasskeyVerification,
    type PendingSpacePasskeyVerification,
} from "services/spacePasskeyVerification";
import { useSpaceAppState } from "state/spaceAppState";
import { routeAfterCompletedLogin } from "utils/spaceLoginNavigation";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

const passkeyErrorMessage = (error: unknown) => {
    if (
        error instanceof Error &&
        error.message == spaceLoginPasskeySessionExpiredErrorMessage
    ) {
        return "Passkey session expired. Please sign in again.";
    }
    return error instanceof Error
        ? error.message
        : "Couldn't check passkey status. Please try again.";
};

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const {
        pendingPasskeyVerification,
        refreshProfile,
        setPendingPasskeyVerification,
    } = useSpaceAppState();
    const [verification, setVerification] =
        useState<PendingSpacePasskeyVerification>();
    const [status, setStatus] = useState<PasskeyVerificationStatus>("waiting");
    const [errorMessage, setErrorMessage] = useState<string>();

    useEffect(() => {
        const nextVerification =
            pendingPasskeyVerification ??
            savedPendingSpacePasskeyVerification();
        const user = savedPartialLocalUser();

        if (
            !nextVerification ||
            !user?.email ||
            user.passkeySessionID != nextVerification.passkeySessionID
        ) {
            void router.replace(spaceRoutes.login);
            return;
        }

        setVerification(nextVerification);
        setPendingPasskeyVerification(nextVerification);

        if (
            !hasAutoOpenedSpacePasskeyVerification(
                nextVerification.passkeySessionID,
            )
        ) {
            markAutoOpenedSpacePasskeyVerification(
                nextVerification.passkeySessionID,
            );
            openPasskeyVerificationURL(nextVerification);
        }
    }, [pendingPasskeyVerification, router, setPendingPasskeyVerification]);

    const clearPasskeyVerification = () => {
        clearPendingSpacePasskeyVerification();
        setPendingPasskeyVerification(null);
    };

    const tryAgain = () => {
        if (!verification) return;
        setStatus("waiting");
        setErrorMessage(undefined);
        openPasskeyVerificationURL(verification);
    };

    const checkStatus = async () => {
        if (!verification || status == "checking") return;

        setStatus("checking");
        setErrorMessage(undefined);
        try {
            const result = await checkSpaceLoginPasskeyStatus(
                verification.passkeySessionID,
            );
            if (result.status == "pending") {
                setStatus("pending");
                return;
            }

            clearPasskeyVerification();
            await routeAfterCompletedLogin(router, refreshProfile);
        } catch (error) {
            console.error("Space passkey status check failed", error);
            setErrorMessage(passkeyErrorMessage(error));
            setStatus("waiting");
        }
    };

    const useTwoFactor = () => {
        useSpaceLoginTwoFactorInstead();
        clearPasskeyVerification();
        void router.push(spaceRoutes.twoFactorVerify);
    };

    if (!verification) {
        return (
            <SpaceRouteFallback background={passkeyVerificationBackground} />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={passkeyVerificationBackground} />
            <PasskeyVerificationScreen
                canUseTwoFactor={verification.hasTwoFactorFallback}
                errorMessage={errorMessage}
                onBack={() => void router.push(spaceRoutes.login)}
                onCheckStatus={() => void checkStatus()}
                onTryAgain={tryAgain}
                onUseTwoFactor={useTwoFactor}
                status={status}
            />
        </>
    );
};

export default Page;
