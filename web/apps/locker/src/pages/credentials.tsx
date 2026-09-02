import { LockerAuthShell } from "@/components/LockerAuthShell";
import {
    CredentialsForm,
    PasswordForm,
} from "ente-accounts/components/auth/CredentialsForm";
import { SecondFactorChoiceDialog } from "ente-accounts/components/auth/SecondFactorChoiceDialog";
import AccountsCredentialsPage, {
    type CredentialsPresentationProps,
} from "ente-accounts/pages/credentials";
import type React from "react";

function CredentialsPresentation(
    props: CredentialsPresentationProps,
): React.JSX.Element {
    return (
        <LockerAuthShell>
            <CredentialsForm {...props} />
        </LockerAuthShell>
    );
}

function CredentialsPage(): React.JSX.Element {
    return (
        <AccountsCredentialsPage
            presentation={CredentialsPresentation}
            passwordPresentation={PasswordForm}
            secondFactorChoicePresentation={SecondFactorChoiceDialog}
        />
    );
}

export default CredentialsPage;
