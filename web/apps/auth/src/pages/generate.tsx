import { RecoveryKeyForm } from "@/components/auth/RecoveryKeyForm";
import { SetPasswordForm } from "@/components/auth/SetPasswordForm";
import { AuthShell } from "@/components/AuthShell";
import { featureFlags } from "@/feature-flags";
import type { NewPasswordPresentationProps } from "ente-accounts/components/NewPasswordForm";
import type { RecoveryKeyPresentationProps } from "ente-accounts/components/RecoveryKey";
import AccountsGeneratePage from "ente-accounts/pages/generate";
import type React from "react";

function RecoveryKeyPresentation(
    props: RecoveryKeyPresentationProps,
): React.JSX.Element {
    return (
        <AuthShell>
            <RecoveryKeyForm {...props} />
        </AuthShell>
    );
}

function SetPasswordPresentation(
    props: NewPasswordPresentationProps,
): React.JSX.Element {
    return (
        <AuthShell>
            <SetPasswordForm {...props} />
        </AuthShell>
    );
}

function GeneratePage(): React.JSX.Element {
    if (!featureFlags.enableNewAuthFlow) {
        return <AccountsGeneratePage />;
    }

    return (
        <AccountsGeneratePage
            passwordPresentation={SetPasswordPresentation}
            recoveryKeyPresentation={RecoveryKeyPresentation}
        />
    );
}

export default GeneratePage;
