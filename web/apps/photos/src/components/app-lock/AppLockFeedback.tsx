import { Box, Stack, Typography } from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { t } from "i18next";
import { AppLockCard } from "./AppLockCard";
import {
    CooldownIllustration,
    LogoutIllustration,
} from "./AppLockIllustrations";
import { LOGOUT_MODAL_WIDTH, subtitleTextSx, titleTextSx } from "./styles";

const DANGER_RED = "#E53935";
const DANGER_RED_HOVER = "#D32F2F";
const SECONDARY_ACTION_BG_LIGHT = "#F2F2F2";
const SECONDARY_ACTION_BG_HOVER_LIGHT = "#E8E8E8";
const SECONDARY_ACTION_BG_DARK = "rgba(255, 255, 255, 0.08)";
const SECONDARY_ACTION_BG_HOVER_DARK = "rgba(255, 255, 255, 0.12)";

const logoutModalContentSx = {
    width: LOGOUT_MODAL_WIDTH - 32,
    maxWidth: "100%",
} as const;

const dangerActionButtonSx = (theme: Parameters<typeof titleTextSx>[0]) => ({
    display: "flex",
    minHeight: 56,
    padding: "18px 16px",
    justifyContent: "center",
    alignItems: "center",
    gap: 1,
    borderRadius: "20px",
    backgroundColor: DANGER_RED,
    fontSize: 16,
    fontWeight: 500,
    lineHeight: "20px",
    textTransform: "none" as const,
    color: "#fff",
    boxShadow: "none",
    "&:hover": { backgroundColor: DANGER_RED_HOVER, boxShadow: "none" },
    "&.Mui-disabled": {
        backgroundColor: "rgba(0, 0, 0, 0.04)",
        color: "#999",
        opacity: 1,
    },
    ...theme.applyStyles("dark", {
        "&.Mui-disabled": {
            backgroundColor: "rgba(255, 255, 255, 0.08)",
            color: "rgba(255, 255, 255, 0.5)",
            opacity: 1,
        },
    }),
});

const secondaryActionButtonSx = (theme: Parameters<typeof titleTextSx>[0]) => ({
    display: "flex",
    minHeight: 60,
    padding: "20px 16px",
    justifyContent: "center",
    alignItems: "center",
    gap: 1,
    borderRadius: "20px",
    backgroundColor: SECONDARY_ACTION_BG_LIGHT,
    fontSize: 16,
    fontWeight: 600,
    lineHeight: "20px",
    textTransform: "none" as const,
    color: "#333",
    boxShadow: "none",
    "&:hover": {
        backgroundColor: SECONDARY_ACTION_BG_HOVER_LIGHT,
        boxShadow: "none",
    },
    ...theme.applyStyles("dark", {
        backgroundColor: SECONDARY_ACTION_BG_DARK,
        color: "rgba(255, 255, 255, 0.9)",
        "&:hover": { backgroundColor: SECONDARY_ACTION_BG_HOVER_DARK },
    }),
});

interface ErrorMessageProps {
    error: string | undefined;
    attemptCount: number;
}

export const ErrorMessage = ({ error, attemptCount }: ErrorMessageProps) => {
    if (!error) return null;

    return (
        <Typography
            sx={(theme) => ({
                ...subtitleTextSx(theme),
                color: "#E53935",
                mt: 3,
                ...theme.applyStyles("dark", { color: "#FF6B6B" }),
            })}
        >
            {error}
            {attemptCount > 0 && ` (${String(attemptCount)}/10)`}
        </Typography>
    );
};

interface AppLockLogoutConfirmationProps {
    onConfirm: () => void;
    onCancel: () => void;
}

export const AppLockLogoutConfirmation = ({
    onConfirm,
    onCancel,
}: AppLockLogoutConfirmationProps) => (
    <AppLockCard width={LOGOUT_MODAL_WIDTH}>
        <Stack
            spacing={0}
            useFlexGap
            sx={[{ alignItems: "center" }, logoutModalContentSx]}
        >
            <Box
                sx={{
                    mt: 0.5,
                    mb: 1,
                    display: "flex",
                    justifyContent: "center",
                    width: "100%",
                }}
            >
                <LogoutIllustration />
            </Box>

            <Box
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    gap: "9px",
                    textAlign: "center",
                    mb: 4,
                }}
            >
                <Typography sx={titleTextSx}>{t("logout")}</Typography>
                <Typography sx={subtitleTextSx}>
                    {t("logout_message")}
                </Typography>
            </Box>

            <Stack spacing={1.5} sx={{ width: "100%" }}>
                <FocusVisibleButton
                    fullWidth
                    onClick={onCancel}
                    sx={secondaryActionButtonSx}
                >
                    {t("cancel")}
                </FocusVisibleButton>
                <FocusVisibleButton
                    fullWidth
                    onClick={onConfirm}
                    sx={dangerActionButtonSx}
                >
                    {t("logout")}
                </FocusVisibleButton>
            </Stack>
        </Stack>
    </AppLockCard>
);

interface CooldownScreenProps {
    remainingMs: number;
    cooldownText: string;
    attemptCount: number;
    onLogout: () => void;
}

export const CooldownScreen = ({
    remainingMs,
    cooldownText,
    attemptCount,
    onLogout,
}: CooldownScreenProps) => {
    void remainingMs;
    void attemptCount;
    const retryDescriptionText = t("app_lock_please_try_again_in", {
        time: cooldownText,
    });

    return (
        <Stack
            spacing={0}
            useFlexGap
            sx={[
                { alignItems: "center", justifyContent: "center" },
                logoutModalContentSx,
            ]}
        >
            <Box
                sx={{
                    mt: 0.5,
                    mb: 1,
                    display: "flex",
                    justifyContent: "center",
                    width: "100%",
                }}
            >
                <CooldownIllustration />
            </Box>

            <Box
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    gap: 0,
                    textAlign: "center",
                    mb: 2.5,
                }}
            >
                <Typography
                    sx={(theme) => ({ ...titleTextSx(theme), mb: 0.5 })}
                >
                    {t("app_locked")}
                </Typography>
                <Typography
                    sx={(theme) => ({ ...subtitleTextSx(theme), mt: 0.75 })}
                >
                    {retryDescriptionText}
                </Typography>
            </Box>

            <FocusVisibleButton
                fullWidth
                color="secondary"
                onClick={onLogout}
                sx={(theme) => ({ ...dangerActionButtonSx(theme), mt: 1.5 })}
            >
                {t("logout")}
            </FocusVisibleButton>
        </Stack>
    );
};
