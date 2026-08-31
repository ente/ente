import { RecoverAccountForm } from "@/components/auth/RecoveryForm";
import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import { featureFlags } from "@/feature-flags";
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
    if (!featureFlags.enableNewPhotosAuthFlow) {
        return <AccountsRecoverPage />;
    }

    return <AccountsRecoverPage presentation={RecoverAccountPresentation} />;
}

export default RecoverPage;
