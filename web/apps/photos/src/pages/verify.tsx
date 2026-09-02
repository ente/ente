import { PasskeyVerificationForm } from "@/components/auth/PasskeyVerificationForm";
import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import { SecondFactorChoiceDialog } from "ente-accounts/components/auth/SecondFactorChoiceDialog";
import { VerifyEmailForm } from "ente-accounts/components/auth/VerifyEmailForm";
import type { VerifyingPasskeyPresentationProps } from "ente-accounts/components/LoginComponents";
import AccountsVerifyPage, {
    type VerifyEmailPresentationProps,
} from "ente-accounts/pages/verify";
import type React from "react";

function VerifyEmailPresentation(
    props: VerifyEmailPresentationProps,
): React.JSX.Element {
    return (
        <PhotosAuthShell>
            <VerifyEmailForm {...props} />
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

function VerifyPage(): React.JSX.Element {
    return (
        <AccountsVerifyPage
            presentation={VerifyEmailPresentation}
            passkeyPresentation={PasskeyPresentation}
            secondFactorChoicePresentation={SecondFactorChoiceDialog}
        />
    );
}

export default VerifyPage;
