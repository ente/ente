import { DevSettingsDialog } from "@/components/auth/DevSettingsDialog";
import { styled } from "@mui/material";
import type { AuthLoginFrameProps } from "ente-accounts/components/auth/AuthPageProvider";
import { DevSettings } from "ente-new/photos/components/DevSettings";
import React, { useRef, useState } from "react";

export function LoginFrame({
    children,
    onHostChanged,
}: AuthLoginFrameProps): React.JSX.Element {
    const [showDevSettings, setShowDevSettings] = useState(false);
    const tapCount = useRef(0);

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
        onHostChanged();
    };

    return (
        <NewAuthRoot onClick={handleBackgroundClick}>
            {children}
            <DevSettings
                open={showDevSettings}
                onClose={handleClose}
                presentation={DevSettingsDialog}
            />
        </NewAuthRoot>
    );
}

const NewAuthRoot = styled("div")({ width: "100%", minHeight: "100svh" });

const shouldAllowChangingAPIOrigin = () => {
    const hostname = new URL(window.location.origin).hostname;
    return !(
        hostname.endsWith(".ente.com") ||
        hostname.endsWith(".ente.io") ||
        hostname.endsWith(".ente.sh")
    );
};
