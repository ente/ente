import { SetPasswordForm } from "@/components/auth/SetPasswordForm";
import { AuthShell } from "@/components/AuthShell";
import { featureFlags } from "@/feature-flags";
import type { NewPasswordPresentationProps } from "ente-accounts/components/NewPasswordForm";
import AccountsChangePasswordPage from "ente-accounts/pages/change-password";
import type React from "react";

function ResetPasswordPresentation(
    props: NewPasswordPresentationProps,
): React.JSX.Element {
    return (
        <AuthShell>
            <SetPasswordForm {...props} />
        </AuthShell>
    );
}

function ChangePasswordPage(): React.JSX.Element {
    if (!featureFlags.enableNewAuthFlow) {
        return <AccountsChangePasswordPage />;
    }

    return (
        <AccountsChangePasswordPage
            resetPresentation={ResetPasswordPresentation}
        />
    );
}

export default ChangePasswordPage;
