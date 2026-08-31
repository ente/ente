import { SpaceRouteFallback } from "components/RouteFallback";
import log from "ente-base/log";
import React, { useEffect, useRef } from "react";
import { verifyEmailBackground } from "screens/VerifyEmailScreen";
import { completeSpaceLoginPasskey } from "services/login";
import { clearPendingSpacePasskeyVerification } from "services/passkey-verification";
import { useSpaceAppState } from "state/app-state";
import { routeAfterCompletedLogin } from "utils/login-navigation";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const { refreshProfile, setPendingPasskeyVerification } =
        useSpaceAppState();
    const hasStartedRef = useRef(false);

    useEffect(() => {
        if (hasStartedRef.current) return;
        hasStartedRef.current = true;

        const searchParams = new URLSearchParams(window.location.search);
        const passkeySessionID = searchParams.get("passkeySessionID");
        const response = searchParams.get("response");

        if (!passkeySessionID || !response) {
            void router.replace(spaceRoutes.login);
            return;
        }

        void (async () => {
            try {
                await completeSpaceLoginPasskey(passkeySessionID, response);
                clearPendingSpacePasskeyVerification();
                setPendingPasskeyVerification(null);
                await routeAfterCompletedLogin(
                    router,
                    refreshProfile,
                    "replace",
                );
            } catch (error) {
                log.error("Space passkey verification failed", error);
                void router.replace(spaceRoutes.login);
            }
        })();
    }, [refreshProfile, router, setPendingPasskeyVerification]);

    return <SpaceRouteFallback background={verifyEmailBackground} />;
};

export default Page;
