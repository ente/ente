import { RecoverTwoFactorForm } from "@/components/auth/RecoveryForm";
import { LockerAuthShell } from "@/components/LockerAuthShell";
import { featureFlags } from "@/feature-flags";
import AccountsTwoFactorRecoverPage, {
    type TwoFactorRecoverPresentationProps,
} from "ente-accounts/pages/two-factor/recover";
import type React from "react";

function RecoverTwoFactorPresentation(
    props: TwoFactorRecoverPresentationProps,
): React.JSX.Element {
    return (
        <LockerAuthShell contentWidth={420}>
            <RecoverTwoFactorForm {...props} />
        </LockerAuthShell>
    );
}

function TwoFactorRecoverPage(): React.JSX.Element {
    if (!featureFlags.enableNewLockerAuthFlow) {
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
