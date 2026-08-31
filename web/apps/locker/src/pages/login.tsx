import { LoginForm } from "@/components/auth/LoginForm";
import { LockerAuthShell } from "@/components/LockerAuthShell";
import { featureFlags } from "@/feature-flags";
import {
    LoginContents,
    type LoginPresentationProps,
} from "ente-accounts/components/LoginContents";
import AccountsLoginPage from "ente-accounts/pages/login";
import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import { LoadingIndicator } from "ente-base/components/loaders";
import { customAPIHost } from "ente-base/origins";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useState } from "react";

function LoginPresentation(props: LoginPresentationProps): React.JSX.Element {
    return (
        <LockerAuthShell>
            <LoginForm {...props} />
        </LockerAuthShell>
    );
}

function LoginPage(): React.JSX.Element {
    if (!featureFlags.enableNewLockerAuthFlow) {
        return <AccountsLoginPage />;
    }

    return <NewLoginPage />;
}

function NewLoginPage(): React.JSX.Element {
    const [loading, setLoading] = useState(true);
    const [host, setHost] = useState<string | undefined>(undefined);

    const router = useRouter();

    const refreshHost = useCallback(
        () => void customAPIHost().then(setHost),
        [],
    );

    useEffect(() => {
        refreshHost();
        if (savedPartialLocalUser()?.email) {
            void router.replace("/verify");
            return;
        }
        setLoading(false);
    }, [router, refreshHost]);

    const onSignUp = useCallback(() => void router.push("/signup"), [router]);

    return loading ? (
        <LoadingIndicator />
    ) : (
        <LoginContents
            {...{ host, onSignUp }}
            presentation={LoginPresentation}
        />
    );
}

export default LoginPage;
