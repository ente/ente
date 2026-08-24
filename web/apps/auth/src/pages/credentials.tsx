import {
    CredentialsForm,
    PasswordForm,
} from "@/components/auth/CredentialsForm";
import { SecondFactorChoiceDialog } from "@/components/auth/SecondFactorChoiceDialog";
import { AuthShell } from "@/components/AuthShell";
import { featureFlags } from "@/featureFlags";
import AccountsCredentialsPage, {
    type CredentialsPresentationProps,
} from "ente-accounts/pages/credentials";
import type React from "react";

function CredentialsPresentation(
    props: CredentialsPresentationProps,
): React.JSX.Element {
    return (
        <AuthShell>
            <CredentialsForm {...props} />
        </AuthShell>
    );
}

function CredentialsPage(): React.JSX.Element {
    if (!featureFlags.enableNewAuthFlow) {
        return <AccountsCredentialsPage />;
    }

    return (
        <AccountsCredentialsPage
            presentation={CredentialsPresentation}
            passwordPresentation={PasswordForm}
            secondFactorChoicePresentation={SecondFactorChoiceDialog}
        />
    );
}

export default CredentialsPage;
