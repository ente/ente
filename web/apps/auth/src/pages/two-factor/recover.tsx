import { RecoverTwoFactorForm } from "@/components/auth/RecoveryForm";
import { AuthShell } from "@/components/AuthShell";
import { featureFlags } from "@/feature-flags";
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
    if (!featureFlags.enableNewAuthFlow) {
        return <AccountsTwoFactorRecoverPage twoFactorType="totp" />;
    }

    return (
        <AccountsTwoFactorRecoverPage
            twoFactorType="totp"
            presentation={RecoverTwoFactorPresentation}
        />
    );
}

export default TwoFactorRecoverPage;
