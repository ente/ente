import { TwoFactorForm } from "@/components/auth/TwoFactorForm";
import { AuthShell } from "@/components/AuthShell";
import { featureFlags } from "@/feature-flags";
import AccountsTwoFactorVerifyPage, {
    type TwoFactorVerifyPresentationProps,
} from "ente-accounts/pages/two-factor/verify";
import type React from "react";

function TwoFactorPresentation(
    props: TwoFactorVerifyPresentationProps,
): React.JSX.Element {
    return (
        <AuthShell>
            <TwoFactorForm {...props} />
        </AuthShell>
    );
}

function TwoFactorVerifyPage(): React.JSX.Element {
    if (!featureFlags.enableNewAuthFlow) {
        return <AccountsTwoFactorVerifyPage />;
    }

    return <AccountsTwoFactorVerifyPage presentation={TwoFactorPresentation} />;
}

export default TwoFactorVerifyPage;
