import { SpacePageMeta } from "components/PageMeta";
import React, { useState } from "react";
import {
    CreateAccountScreen,
    type CreateAccountInput,
} from "screens/CreateAccountScreen";
import { beginSpaceSignup, spaceSignupErrorMessage } from "services/signup";
import { useSpaceAppState } from "state/app-state";
import { spaceAppBackgroundColor } from "styles/colors";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const { setIsLiveSignupVerification, setSignupEmail } = useSpaceAppState();
    const [signupError, setSignupError] = useState<string>();
    const [isSubmitting, setIsSubmitting] = useState(false);

    const createAccount = async (input: CreateAccountInput) => {
        setIsSubmitting(true);
        setSignupError(undefined);
        try {
            const { email } = await beginSpaceSignup(input);
            setSignupEmail(email);
            setIsLiveSignupVerification(true);
            void router.push(spaceRoutes.verify);
        } catch (error) {
            setSignupError(await spaceSignupErrorMessage(error));
            setIsSubmitting(false);
        }
    };

    return (
        <>
            <SpacePageMeta themeColor={spaceAppBackgroundColor} />
            <CreateAccountScreen
                errorMessage={signupError}
                isSubmitting={isSubmitting}
                onBack={() => void router.back(spaceRoutes.onboarding)}
                onCreateAccount={(input) => void createAccount(input)}
            />
        </>
    );
};

export default Page;
