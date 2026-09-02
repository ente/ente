import { LockerAuthShell } from "@/components/LockerAuthShell";
import { RecoverTwoFactorForm } from "ente-accounts/components/auth/RecoveryForm";
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
    return (
        <AccountsTwoFactorRecoverPage
            twoFactorType="totp"
            presentation={RecoverTwoFactorPresentation}
        />
    );
}

export default TwoFactorRecoverPage;
