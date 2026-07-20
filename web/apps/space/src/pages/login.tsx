import { SpacePageMeta } from "components/SpacePageMeta";
import React, { useState } from "react";
import {
    LoginScreen,
    loginBackground,
    type SpaceLoginCredentials,
} from "screens/LoginScreen";
import { beginSpaceLogin, type SpaceLoginResult } from "services/spaceLogin";
import { savePendingSpacePasskeyVerification } from "services/spacePasskeyVerification";
import { useSpaceAppState } from "state/spaceAppState";
import { routeAfterCompletedLogin } from "utils/spaceLoginNavigation";
import { spaceRoutes } from "utils/spaceRoutes";
import { useSpaceRouter } from "utils/spaceRouteTransitions";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const {
        refreshProfile,
        setPendingLoginCredentials,
        setPendingPasskeyVerification,
    } = useSpaceAppState();
    const [loginError, setLoginError] = useState<string>();
    const [isSubmitting, setIsSubmitting] = useState(false);

    const loginErrorMessage = (error: unknown) =>
        error instanceof Error
            ? error.message
            : "Couldn't sign in. Please try again.";

    const handleLoginResult = async (
        result: SpaceLoginResult,
        credentials: SpaceLoginCredentials,
    ) => {
        switch (result.status) {
            case "complete":
                setPendingLoginCredentials(null);
                await routeAfterCompletedLogin(router, refreshProfile);
                break;
            case "email-otp":
                setPendingLoginCredentials({
                    email: result.email,
                    password: credentials.password,
                });
                void router.push(spaceRoutes.verifyLogin);
                break;
            case "totp":
                setPendingLoginCredentials(null);
                void router.push(spaceRoutes.twoFactorVerify);
                break;
            case "passkey":
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
        }
    };

    return (
        <>
            <SpacePageMeta themeColor={loginBackground} />
            <LoginScreen
                errorMessage={loginError}
                isSubmitting={isSubmitting}
                onBack={() => void router.push(spaceRoutes.onboarding)}
                onContinue={async (credentials) => {
                    setIsSubmitting(true);
                    setLoginError(undefined);
                    try {
                        await handleLoginResult(
                            await beginSpaceLogin(credentials),
                            credentials,
                        );
                    } catch (error) {
                        setLoginError(loginErrorMessage(error));
                        setIsSubmitting(false);
                    }
                }}
            />
        </>
    );
};

export default Page;
