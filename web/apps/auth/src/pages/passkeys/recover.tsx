import { AuthShell } from "@/components/AuthShell";
import { RecoverTwoFactorForm } from "ente-accounts/components/auth/RecoveryForm";
import AccountsTwoFactorRecoverPage, {
    type TwoFactorRecoverPresentationProps,
} from "ente-accounts/pages/two-factor/recover";
import type React from "react";

function RecoverTwoFactorPresentation(
    props: TwoFactorRecoverPresentationProps,
): React.JSX.Element {
    return (
        <AuthShell contentWidth={420}>
            <RecoverTwoFactorForm {...props} />
        </AuthShell>
    );
}

function PasskeyRecoverPage(): React.JSX.Element {
    return (
        <AccountsTwoFactorRecoverPage
            twoFactorType="passkey"
            presentation={RecoverTwoFactorPresentation}
        />
    );
}

export default PasskeyRecoverPage;
