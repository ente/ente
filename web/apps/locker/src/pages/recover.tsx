import { RecoverAccountForm } from "@/components/auth/RecoveryForm";
import { LockerAuthShell } from "@/components/LockerAuthShell";
import { featureFlags } from "@/feature-flags";
import AccountsRecoverPage, {
    type RecoverAccountPresentationProps,
} from "ente-accounts/pages/recover";
import type React from "react";

function RecoverAccountPresentation(
    props: RecoverAccountPresentationProps,
): React.JSX.Element {
    return (
        <LockerAuthShell contentWidth={420}>
            <RecoverAccountForm {...props} />
        </LockerAuthShell>
    );
}

function RecoverPage(): React.JSX.Element {
    if (!featureFlags.enableNewLockerAuthFlow) {
        return <AccountsRecoverPage />;
    }

    return <AccountsRecoverPage presentation={RecoverAccountPresentation} />;
}

export default RecoverPage;
