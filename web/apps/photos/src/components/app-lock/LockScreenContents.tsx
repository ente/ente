import ErrorOutlinedIcon from "@mui/icons-material/ErrorOutlined";
import { Box, Modal, Stack, Typography } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { useBaseContext } from "ente-base/context";
import { AppLockCard } from "ente-new/photos/components/app-lock/AppLockCard";
import { AppLockLogoutConfirmation } from "ente-new/photos/components/app-lock/AppLockFeedback";
import { AppLockPrompt } from "ente-new/photos/components/app-lock/AppLockPrompt";
import { t } from "i18next";
import type { CSSProperties, PropsWithChildren } from "react";
import { useState } from "react";

export const AppLockScreen = ({ children }: PropsWithChildren) => (
    <Modal
        open
        aria-label={t("app_lock")}
        slotProps={{
            backdrop: {
                sx: (theme) => ({
                    backgroundColor: "secondary.main",
                    ...theme.applyStyles("dark", { backgroundColor: "#000" }),
                }),
            },
        }}
        sx={{ zIndex: "calc(var(--mui-zIndex-tooltip) + 1)" }}
    >
        <Box
            sx={{
                position: "fixed",
                inset: 0,
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                outline: "none",
            }}
            style={{ WebkitAppRegion: "no-drag" } as CSSProperties}
        >
            {children}
        </Box>
    </Modal>
);

interface LockScreenHeaderProps {
    showLogoutButton: boolean;
    onLogout: () => void;
}

const LockScreenHeader = ({
    showLogoutButton,
    onLogout,
}: LockScreenHeaderProps) => (
    <Box
        sx={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            p: 3,
        }}
    >
        <EnteLogo />
        {showLogoutButton && (
            <FocusVisibleButton
                variant="text"
                color="secondary"
                size="small"
                onClick={onLogout}
                sx={{
                    textTransform: "none",
                    position: "absolute",
                    right: 24,
                    color: "text.muted",
                }}
            >
                {t("logout")}
            </FocusVisibleButton>
        )}
    </Box>
);

export const LockScreenContents = () => (
    <AppLockPrompt
        lockScreenMode="lock"
        renderHeader={({ showLogoutConfirm, showLogout }) => (
            <LockScreenHeader
                showLogoutButton={!showLogoutConfirm}
                onLogout={showLogout}
            />
        )}
    />
);

export const AppLockSetupError = ({ onRetry }: { onRetry: () => void }) => {
    const { logout } = useBaseContext();
    const [showLogoutConfirm, setShowLogoutConfirm] = useState(false);

    return (
        <AppLockScreen>
            <LockScreenHeader
                showLogoutButton={!showLogoutConfirm}
                onLogout={() => setShowLogoutConfirm(true)}
            />
            {showLogoutConfirm ? (
                <AppLockLogoutConfirmation
                    onConfirm={logout}
                    onCancel={() => setShowLogoutConfirm(false)}
                />
            ) : (
                <AppLockCard>
                    <Stack
                        spacing={0}
                        sx={{ width: "100%", alignItems: "center" }}
                    >
                        <ErrorOutlinedIcon
                            sx={{ fontSize: 48, color: "text.muted", mb: 3 }}
                        />
                        <Typography
                            sx={{
                                maxWidth: 320,
                                fontSize: 20,
                                fontWeight: 600,
                                lineHeight: "26px",
                                textAlign: "center",
                                mb: 4,
                            }}
                        >
                            {t("app_lock_unavailable")}
                        </Typography>
                        <FocusVisibleButton
                            fullWidth
                            color="secondary"
                            onClick={onRetry}
                            sx={{
                                minHeight: 56,
                                borderRadius: "20px",
                                fontSize: 16,
                                fontWeight: 600,
                                lineHeight: "20px",
                            }}
                        >
                            {t("retry")}
                        </FocusVisibleButton>
                    </Stack>
                </AppLockCard>
            )}
        </AppLockScreen>
    );
};
