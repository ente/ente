import { AuthShell } from "@/components/AuthShell";
import { RecoverAccountForm } from "ente-accounts/components/auth/RecoveryForm";
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
    return <AccountsRecoverPage presentation={RecoverAccountPresentation} />;
}

export default RecoverPage;
