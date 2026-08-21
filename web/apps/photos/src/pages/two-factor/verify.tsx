import { TwoFactorForm } from "@/components/auth/TwoFactorForm";
import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import { featureFlags } from "@/featureFlags";
import AccountsTwoFactorVerifyPage, {
    type TwoFactorVerifyPresentationProps,
} from "ente-accounts/pages/two-factor/verify";
import type React from "react";

function TwoFactorPresentation(
    props: TwoFactorVerifyPresentationProps,
): React.JSX.Element {
    return (
        <PhotosAuthShell>
            <TwoFactorForm {...props} />
        </PhotosAuthShell>
    );
}

function TwoFactorVerifyPage(): React.JSX.Element {
    if (!featureFlags.enableNewPhotosAuthFlow) {
        return <AccountsTwoFactorVerifyPage />;
    }

    return <AccountsTwoFactorVerifyPage presentation={TwoFactorPresentation} />;
}

export default TwoFactorVerifyPage;
