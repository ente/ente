import { SetPasswordForm } from "@/components/auth/SetPasswordForm";
import { LockerAuthShell } from "@/components/LockerAuthShell";
import { featureFlags } from "@/featureFlags";
import type { NewPasswordPresentationProps } from "ente-accounts/components/NewPasswordForm";
import AccountsChangePasswordPage from "ente-accounts/pages/change-password";
import type React from "react";

function ResetPasswordPresentation(
    props: NewPasswordPresentationProps,
): React.JSX.Element {
    return (
        <LockerAuthShell>
            <SetPasswordForm {...props} />
        </LockerAuthShell>
    );
}

function ChangePasswordPage(): React.JSX.Element {
    if (!featureFlags.enableNewLockerAuthFlow) {
        return <AccountsChangePasswordPage />;
    }

    return (
        <AccountsChangePasswordPage
            resetPresentation={ResetPasswordPresentation}
        />
    );
}

export default ChangePasswordPage;
