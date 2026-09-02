import { AuthShell } from "@/components/AuthShell";
import { SecondFactorChoiceDialog } from "ente-accounts/components/auth/SecondFactorChoiceDialog";
import { VerifyEmailForm } from "ente-accounts/components/auth/VerifyEmailForm";
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
    return (
        <AccountsVerifyPage
            presentation={VerifyEmailPresentation}
            secondFactorChoicePresentation={SecondFactorChoiceDialog}
        />
    );
}

export default VerifyPage;
