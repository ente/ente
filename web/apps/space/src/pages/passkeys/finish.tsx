import { SpaceRouteFallback } from "components/SpaceRouteFallback";
import React, { useEffect } from "react";
import { verifyEmailBackground } from "screens/VerifyEmailScreen";
import { completeSpaceLoginPasskey } from "services/spaceLogin";
import { clearPendingSpacePasskeyVerification } from "services/spacePasskeyVerification";
import { useSpaceAppState } from "state/spaceAppState";
import { routeAfterCompletedLogin } from "utils/spaceLoginNavigation";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const { refreshProfile, setPendingPasskeyVerification } =
        useSpaceAppState();

    useEffect(() => {
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
                console.error("Space passkey verification failed", error);
                void router.replace(spaceRoutes.login);
            }
        })();
    }, [refreshProfile, router, setPendingPasskeyVerification]);

    return <SpaceRouteFallback background={verifyEmailBackground} />;
};

export default Page;
