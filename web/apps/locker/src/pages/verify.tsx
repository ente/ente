import { SecondFactorChoiceDialog } from "@/components/auth/SecondFactorChoiceDialog";
import { VerifyEmailForm } from "@/components/auth/VerifyEmailForm";
import { LockerAuthShell } from "@/components/LockerAuthShell";
import { featureFlags } from "@/feature-flags";
import AccountsVerifyPage, {
    type VerifyEmailPresentationProps,
} from "ente-accounts/pages/verify";
import type React from "react";

function VerifyEmailPresentation(
    props: VerifyEmailPresentationProps,
): React.JSX.Element {
    return (
        <LockerAuthShell>
            <VerifyEmailForm {...props} />
        </LockerAuthShell>
    );
}

function VerifyPage(): React.JSX.Element {
    if (!featureFlags.enableNewLockerAuthFlow) {
        return <AccountsVerifyPage />;
    }

    return (
        <AccountsVerifyPage
            presentation={VerifyEmailPresentation}
            secondFactorChoicePresentation={SecondFactorChoiceDialog}
        />
    );
}

export default VerifyPage;
