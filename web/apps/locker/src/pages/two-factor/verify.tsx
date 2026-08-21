import { TwoFactorForm } from "@/components/auth/TwoFactorForm";
import { LockerAuthShell } from "@/components/LockerAuthShell";
import { featureFlags } from "@/featureFlags";
import AccountsTwoFactorVerifyPage, {
    type TwoFactorVerifyPresentationProps,
} from "ente-accounts/pages/two-factor/verify";
import type React from "react";

function TwoFactorPresentation(
    props: TwoFactorVerifyPresentationProps,
): React.JSX.Element {
    return (
        <LockerAuthShell>
            <TwoFactorForm {...props} />
        </LockerAuthShell>
    );
}

function TwoFactorVerifyPage(): React.JSX.Element {
    if (!featureFlags.enableNewLockerAuthFlow) {
        return <AccountsTwoFactorVerifyPage />;
    }

    return <AccountsTwoFactorVerifyPage presentation={TwoFactorPresentation} />;
}

export default TwoFactorVerifyPage;
