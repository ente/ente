import { RecoverTwoFactorForm } from "@/components/auth/RecoveryForm";
import { AuthShell } from "@/components/AuthShell";
import { featureFlags } from "@/featureFlags";
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
    if (!featureFlags.enableNewAuthFlow) {
        return <AccountsTwoFactorRecoverPage twoFactorType="passkey" />;
    }

    return (
        <AccountsTwoFactorRecoverPage
            twoFactorType="passkey"
            presentation={RecoverTwoFactorPresentation}
        />
    );
}

export default PasskeyRecoverPage;
