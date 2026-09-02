import { DevSettingsDialog } from "@/components/auth/DevSettingsDialog";
import { AuthShell } from "@/components/AuthShell";
import { styled } from "@mui/material";
import { LoginForm } from "ente-accounts/components/auth/LoginForm";
import {
    LoginContents,
    type LoginPresentationProps,
} from "ente-accounts/components/LoginContents";
import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import { LoadingIndicator } from "ente-base/components/loaders";
import { customAPIHost } from "ente-base/origins";
import { DevSettings } from "ente-new/photos/components/DevSettings";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useRef, useState } from "react";

function LoginPresentation(props: LoginPresentationProps): React.JSX.Element {
    return (
        <AuthShell>
            <LoginForm {...props} />
        </AuthShell>
    );
}

function LoginPage(): React.JSX.Element {
    const [loading, setLoading] = useState(true);
    const [host, setHost] = useState<string | undefined>(undefined);
    const [showDevSettings, setShowDevSettings] = useState(false);
    const tapCount = useRef(0);

    const router = useRouter();

    const refreshHost = useCallback(
        () => void customAPIHost().then(setHost),
        [],
    );

    useEffect(() => {
        refreshHost();
        if (savedPartialLocalUser()?.email) void router.replace("/verify");
        setLoading(false);
    }, [router, refreshHost]);

    const onSignUp = useCallback(() => void router.push("/signup"), [router]);

    const countDevSettingsTap = () => {
        tapCount.current += 1;
        if (tapCount.current == 7) {
            tapCount.current = 0;
            setShowDevSettings(true);
        }
    };

    const handleBackgroundClick: React.MouseEventHandler = (event) => {
        if (!shouldAllowChangingAPIOrigin()) return;
        if (showDevSettings) return;
        if (
            event.target instanceof Element &&
            event.target.closest(
                'button, a, input, textarea, select, [role="button"]',
            )
        ) {
            return;
        }
        countDevSettingsTap();
    };

    const handleClose = () => {
        setShowDevSettings(false);
        refreshHost();
    };

    if (loading) return <LoadingIndicator />;

    return (
        <NewAuthRoot onClick={handleBackgroundClick}>
            <LoginContents
                {...{ host, onSignUp }}
                presentation={LoginPresentation}
            />
            <DevSettings
                open={showDevSettings}
                onClose={handleClose}
                presentation={DevSettingsDialog}
            />
        </NewAuthRoot>
    );
}

export default LoginPage;

const NewAuthRoot = styled("div")({ width: "100%", minHeight: "100svh" });

const shouldAllowChangingAPIOrigin = () => {
    const hostname = new URL(window.location.origin).hostname;
    return !(
        hostname.endsWith(".ente.com") ||
        hostname.endsWith(".ente.io") ||
        hostname.endsWith(".ente.sh")
    );
};
