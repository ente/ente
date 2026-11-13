import CloseIcon from "@mui/icons-material/Close";
import { IconButton } from "@mui/material";
import { useBaseContext } from "ente-base/context";
import { useAppLockSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import { cancelReauthentication } from "ente-new/photos/services/app-lock";
import { t } from "i18next";
import type { ReactNode } from "react";
import { useCallback, useEffect, useState } from "react";
import { AppLockLogoutConfirmation } from "./AppLockFeedback";
import { AppLockUnlockForm } from "./AppLockUnlockForm";

type AppLockSnapshot = ReturnType<typeof useAppLockSnapshot>;

interface AppLockPromptProps {
    lockScreenMode: AppLockSnapshot["lockScreenMode"];
    renderHeader?: (props: {
        showLogoutConfirm: boolean;
        showLogout: () => void;
    }) => ReactNode;
}

const AppLockCloseAction = () => (
    <IconButton
        aria-label={t("close")}
        onClick={cancelReauthentication}
        sx={(theme) => ({
            backgroundColor: "#FAFAFA",
            color: "#000",
            p: 1.25,
            "&:hover": { backgroundColor: "#F0F0F0" },
            ...theme.applyStyles("dark", {
                backgroundColor: "rgba(255, 255, 255, 0.12)",
                color: "#fff",
                "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.16)" },
            }),
        })}
    >
        <CloseIcon sx={{ fontSize: 20 }} />
    </IconButton>
);

export const AppLockPrompt = ({
    lockScreenMode,
    renderHeader,
}: AppLockPromptProps) => {
    const appLock = useAppLockSnapshot();
    const { logout } = useBaseContext();
    const [showLogoutConfirm, setShowLogoutConfirm] = useState(false);

    const isVisible =
        appLock.isLocked && appLock.lockScreenMode === lockScreenMode;
    const isReauthentication = lockScreenMode === "reauthenticate";

    useEffect(() => {
        if (!isVisible) {
            setShowLogoutConfirm(false);
        }
    }, [isVisible]);

    const showLogout = useCallback(() => setShowLogoutConfirm(true), []);
    const hideLogout = useCallback(() => setShowLogoutConfirm(false), []);

    if (!isVisible) return null;

    const closeAction =
        isReauthentication && !showLogoutConfirm ? (
            <AppLockCloseAction />
        ) : undefined;

    return (
        <>
            {renderHeader?.({ showLogoutConfirm, showLogout })}
            {showLogoutConfirm ? (
                <AppLockLogoutConfirmation
                    onConfirm={logout}
                    onCancel={hideLogout}
                />
            ) : (
                <AppLockUnlockForm
                    appLock={appLock}
                    isReauthentication={isReauthentication}
                    onLogout={showLogout}
                    closeAction={closeAction}
                />
            )}
        </>
    );
};
