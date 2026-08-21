import { SignUpForm } from "@/components/auth/SignUpForm";
import { LockerAuthShell } from "@/components/LockerAuthShell";
import { featureFlags } from "@/featureFlags";
import type { SignUpPresentationProps } from "ente-accounts/components/SignUpContents";
import AccountsSignUpPage from "ente-accounts/pages/signup";
import type React from "react";

function SignUpPresentation(props: SignUpPresentationProps): React.JSX.Element {
    return (
        <LockerAuthShell>
            <SignUpForm {...props} />
        </LockerAuthShell>
    );
}

function SignUpPage(): React.JSX.Element {
    if (!featureFlags.enableNewLockerAuthFlow) {
        return <AccountsSignUpPage />;
    }

    return <AccountsSignUpPage presentation={SignUpPresentation} />;
}

export default SignUpPage;
