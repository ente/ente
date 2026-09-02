import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import { RecoverAccountForm } from "ente-accounts/components/auth/RecoveryForm";
import AccountsRecoverPage, {
    type RecoverAccountPresentationProps,
} from "ente-accounts/pages/recover";
import type React from "react";

function RecoverAccountPresentation(
    props: RecoverAccountPresentationProps,
): React.JSX.Element {
    return (
        <PhotosAuthShell contentWidth={420}>
            <RecoverAccountForm {...props} />
        </PhotosAuthShell>
    );
}

function RecoverPage(): React.JSX.Element {
    return <AccountsRecoverPage presentation={RecoverAccountPresentation} />;
}

export default RecoverPage;
