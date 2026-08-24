import { RecoverAccountForm } from "@/components/auth/RecoveryForm";
import { AuthShell } from "@/components/AuthShell";
import { featureFlags } from "@/featureFlags";
import AccountsRecoverPage, {
    type RecoverAccountPresentationProps,
} from "ente-accounts/pages/recover";
import type React from "react";

function RecoverAccountPresentation(
    props: RecoverAccountPresentationProps,
): React.JSX.Element {
    return (
        <AuthShell contentWidth={420}>
            <RecoverAccountForm {...props} />
        </AuthShell>
    );
}

function RecoverPage(): React.JSX.Element {
    if (!featureFlags.enableNewAuthFlow) {
        return <AccountsRecoverPage />;
    }

    return <AccountsRecoverPage presentation={RecoverAccountPresentation} />;
}

export default RecoverPage;
