import { AuthShell } from "@/components/AuthShell";
import { TwoFactorForm } from "ente-accounts/components/auth/TwoFactorForm";
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
    return <AccountsTwoFactorVerifyPage presentation={TwoFactorPresentation} />;
}

export default TwoFactorVerifyPage;
