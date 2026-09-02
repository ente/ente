import { LockerAuthShell } from "@/components/LockerAuthShell";
import { RecoveryKeyForm } from "ente-accounts/components/auth/RecoveryKeyForm";
import { SetPasswordForm } from "ente-accounts/components/auth/SetPasswordForm";
import type { NewPasswordPresentationProps } from "ente-accounts/components/NewPasswordForm";
import type { RecoveryKeyPresentationProps } from "ente-accounts/components/RecoveryKey";
import AccountsGeneratePage from "ente-accounts/pages/generate";
import type React from "react";

function RecoveryKeyPresentation(
    props: RecoveryKeyPresentationProps,
): React.JSX.Element {
    return (
        <LockerAuthShell>
            <RecoveryKeyForm {...props} />
        </LockerAuthShell>
    );
}

function SetPasswordPresentation(
    props: NewPasswordPresentationProps,
): React.JSX.Element {
    return (
        <LockerAuthShell>
            <SetPasswordForm {...props} />
        </LockerAuthShell>
    );
}

function GeneratePage(): React.JSX.Element {
    return (
        <AccountsGeneratePage
            passwordPresentation={SetPasswordPresentation}
            recoveryKeyPresentation={RecoveryKeyPresentation}
        />
    );
}

export default GeneratePage;
