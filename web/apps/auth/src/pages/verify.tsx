import { SecondFactorChoiceDialog } from "@/components/auth/SecondFactorChoiceDialog";
import { VerifyEmailForm } from "@/components/auth/VerifyEmailForm";
import { AuthShell } from "@/components/AuthShell";
import { featureFlags } from "@/feature-flags";
import AccountsVerifyPage, {
    type VerifyEmailPresentationProps,
} from "ente-accounts/pages/verify";
import type React from "react";

function VerifyEmailPresentation(
    props: VerifyEmailPresentationProps,
): React.JSX.Element {
    return (
        <AuthShell>
            <VerifyEmailForm {...props} />
        </AuthShell>
    );
}

function VerifyPage(): React.JSX.Element {
    if (!featureFlags.enableNewAuthFlow) {
        return <AccountsVerifyPage />;
    }

    return (
        <AccountsVerifyPage
            presentation={VerifyEmailPresentation}
            secondFactorChoicePresentation={SecondFactorChoiceDialog}
        />
    );
}

export default VerifyPage;
