import { LockerAuthShell } from "@/components/LockerAuthShell";
import { SetPasswordForm } from "ente-accounts/components/auth/SetPasswordForm";
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
    return (
        <AccountsChangePasswordPage
            resetPresentation={ResetPasswordPresentation}
        />
    );
}

export default ChangePasswordPage;
