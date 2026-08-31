import { DevSettingsDialog } from "@/components/auth/DevSettingsDialog";
import { LoginForm } from "@/components/auth/LoginForm";
import { AuthShell } from "@/components/AuthShell";
import { featureFlags } from "@/feature-flags";
import { Paper, Stack, styled } from "@mui/material";
import {
    LoginContents,
    type LoginPresentationProps,
} from "ente-accounts/components/LoginContents";
import { savedPartialLocalUser } from "ente-accounts/services/accounts-db";
import { CenteredFill } from "ente-base/components/containers";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { LoadingIndicator } from "ente-base/components/loaders";
import { NavbarBase } from "ente-base/components/Navbar";
import { customAPIHost } from "ente-base/origins";
import { DevSettings } from "ente-new/photos/components/DevSettings";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useRef, useState } from "react";

const AccountsPagePaper = styled(Paper)(({ theme }) => ({
    marginBlock: theme.spacing(2),
    padding: theme.spacing(5, 3),
    [theme.breakpoints.up("sm")]: { padding: theme.spacing(5) },
    width: "min(420px, 85vw)",
    minHeight: "375px",
    display: "flex",
    flexDirection: "column",
    gap: theme.spacing(4),
    boxShadow: "none",
    borderRadius: "20px",
}));

function LoginPresentation(props: LoginPresentationProps): React.JSX.Element {
    return (
        <AuthShell>
            <LoginForm {...props} />
        </AuthShell>
    );
}

const LoginPage: React.FC = () => {
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

    const handleLegacyBackgroundClick: React.MouseEventHandler = (event) => {
        if (!shouldAllowChangingAPIOrigin()) return;
        if (event.target !== event.currentTarget) return;
        if (showDevSettings) return;
        countDevSettingsTap();
    };

    const handleNewAuthBackgroundClick: React.MouseEventHandler = (event) => {
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

    if (featureFlags.enableNewAuthFlow) {
        return (
            <NewAuthRoot onClick={handleNewAuthBackgroundClick}>
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

    return (
        <Stack
            sx={[
                { minHeight: "100svh", bgcolor: "secondary.main" },
                (theme) =>
                    theme.applyStyles("dark", {
                        bgcolor: "background.default",
                    }),
            ]}
        >
            <NavbarBase
                sx={{
                    boxShadow: "none",
                    borderBottom: "none",
                    bgcolor: "transparent",
                }}
            >
                <EnteLogo />
            </NavbarBase>
            <CenteredFill
                onClick={handleLegacyBackgroundClick}
                sx={[
                    { bgcolor: "secondary.main" },
                    (theme) =>
                        theme.applyStyles("dark", {
                            bgcolor: "background.default",
                        }),
                ]}
            >
                <AccountsPagePaper>
                    <LoginContents {...{ host, onSignUp }} />
                </AccountsPagePaper>
            </CenteredFill>
            <DevSettings open={showDevSettings} onClose={handleClose} />
        </Stack>
    );
};

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
