import { LoginForm } from "@/components/auth/LoginForm";
import { PhotosAuthShell } from "@/components/PhotosAuthShell";
import { featureFlags } from "@/featureFlags";
import type { LoginPresentationProps } from "ente-accounts/components/LoginContents";
import AccountsLoginPage from "ente-accounts/pages/login";
import type React from "react";

function LoginPresentation(props: LoginPresentationProps): React.JSX.Element {
    return (
        <PhotosAuthShell>
            <LoginForm {...props} />
        </PhotosAuthShell>
    );
}

function LoginPage(): React.JSX.Element {
    if (!featureFlags.enableNewPhotosAuthFlow) {
        return <AccountsLoginPage />;
    }

    return <AccountsLoginPage presentation={LoginPresentation} />;
}

export default LoginPage;
