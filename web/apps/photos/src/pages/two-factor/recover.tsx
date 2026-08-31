import { RecoverTwoFactorForm } from "@/components/auth/RecoveryForm";
import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import { featureFlags } from "@/feature-flags";
import AccountsTwoFactorRecoverPage, {
    type TwoFactorRecoverPresentationProps,
} from "ente-accounts/pages/two-factor/recover";
import type React from "react";

function RecoverTwoFactorPresentation(
    props: TwoFactorRecoverPresentationProps,
): React.JSX.Element {
    return (
        <PhotosAuthShell contentWidth={420}>
            <RecoverTwoFactorForm {...props} />
        </PhotosAuthShell>
    );
}

function TwoFactorRecoverPage(): React.JSX.Element {
    if (!featureFlags.enableNewPhotosAuthFlow) {
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
