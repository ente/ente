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

function TwoFactorRecoverPage(): React.JSX.Element {
    return (
        <AccountsTwoFactorRecoverPage
            twoFactorType="totp"
            presentation={RecoverTwoFactorPresentation}
        />
    );
}

export default TwoFactorRecoverPage;
