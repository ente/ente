import { PasskeyVerificationForm } from "@/components/auth/PasskeyVerificationForm";
import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import {
    CredentialsForm,
    PasswordForm,
} from "ente-accounts/components/auth/CredentialsForm";
import { SecondFactorChoiceDialog } from "ente-accounts/components/auth/SecondFactorChoiceDialog";
import type { VerifyingPasskeyPresentationProps } from "ente-accounts/components/LoginComponents";
import AccountsCredentialsPage, {
    type CredentialsPresentationProps,
} from "ente-accounts/pages/credentials";
import type React from "react";

function CredentialsPresentation(
    props: CredentialsPresentationProps,
): React.JSX.Element {
    return (
        <PhotosAuthShell>
            <CredentialsForm {...props} />
        </PhotosAuthShell>
    );
}

function PasskeyPresentation(
    props: VerifyingPasskeyPresentationProps,
): React.JSX.Element {
    return (
        <PhotosAuthShell>
            <PasskeyVerificationForm {...props} />
        </PhotosAuthShell>
    );
}

function CredentialsPage(): React.JSX.Element {
    return (
        <AccountsCredentialsPage
            presentation={CredentialsPresentation}
            passwordPresentation={PasswordForm}
            passkeyPresentation={PasskeyPresentation}
            secondFactorChoicePresentation={SecondFactorChoiceDialog}
        />
    );
}

export default CredentialsPage;
