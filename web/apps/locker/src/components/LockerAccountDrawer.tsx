import {
    ComputerPhoneSyncIcon,
    Key01Icon,
    Key02Icon,
    Mail01Icon,
    PasswordValidationIcon,
    SecurityCheckIcon,
} from "@hugeicons/core-free-icons";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import NorthEastIcon from "@mui/icons-material/NorthEast";
import { Box, Stack, Typography, useTheme } from "@mui/material";
import { RecoveryKey } from "ente-accounts/components/RecoveryKey";
import { openAccountsManagePasskeysPage } from "ente-accounts/services/passkey";
import { useBaseContext } from "ente-base/context";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useEffect, useState } from "react";
import { LockerAuthenticateUser } from "./LockerAuthenticateUser";
import { LockerSessionsDrawer } from "./LockerSessionsDrawer";
import { LockerSidebarCardButton } from "./LockerSidebarCardButton";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";
import { LockerTwoFactorDrawer } from "./LockerTwoFactorDrawer";

type AuthenticatedAccountAction =
    | "recoveryKey"
    | "activeSessions"
    | "changePassword"
    | "changeEmail";

export const LockerAccountDrawer: React.FC<
    LockerNestedSidebarDrawerVisibilityProps
> = ({ open, onClose, onRootClose }) => {
    const { showMiniDialog, onGenericError } = useBaseContext();
    const router = useRouter();
    const theme = useTheme();

    const [isRecoveryKeyOpen, setIsRecoveryKeyOpen] = useState(false);
    const [isSessionsOpen, setIsSessionsOpen] = useState(false);
    const [isTwoFactorOpen, setIsTwoFactorOpen] = useState(false);
    const [authenticatedAction, setAuthenticatedAction] =
        useState<AuthenticatedAccountAction>();

    useEffect(() => {
        if (!open) {
            setIsRecoveryKeyOpen(false);
            setIsSessionsOpen(false);
            setIsTwoFactorOpen(false);
            setAuthenticatedAction(undefined);
        }
    }, [open]);

    const handleRootClose = () => {
        setIsRecoveryKeyOpen(false);
        setIsSessionsOpen(false);
        setIsTwoFactorOpen(false);
        setAuthenticatedAction(undefined);
        onClose();
        onRootClose();
    };

    const authenticateBefore = (action: AuthenticatedAccountAction) => {
        setAuthenticatedAction(action);
    };

    const handleNavigate = (path: string) => {
        handleRootClose();
        void router.push(path);
    };

    const handleAuthenticatedAction = () => {
        switch (authenticatedAction) {
            case "recoveryKey":
                setIsRecoveryKeyOpen(true);
                break;
            case "activeSessions":
                setIsSessionsOpen(true);
                break;
            case "changePassword":
                handleNavigate("/change-password");
                break;
            case "changeEmail":
                handleNavigate("/change-email");
                break;
        }
        setAuthenticatedAction(undefined);
    };

    const handleOpenPasskeys = async () => {
        handleRootClose();
        try {
            await openAccountsManagePasskeysPage();
        } catch (e) {
            onGenericError(e);
        }
    };

    return (
        <>
            <LockerTitledNestedSidebarDrawer
                {...{ open, onClose }}
                onRootClose={handleRootClose}
                title={t("account")}
                hideRootCloseButton
            >
                <Stack
                    sx={{
                        px: 2,
                        pb: 2,
                        gap: 2,
                        backgroundColor: "background.default",
                        ...theme.applyStyles("dark", {
                            backgroundColor: "background.paper",
                        }),
                    }}
                >
                    <LockerSidebarCardButton
                        icon={Key02Icon}
                        label={t("recovery_key")}
                        onClick={() => authenticateBefore("recoveryKey")}
                    />

                    <Stack sx={{ gap: 1 }}>
                        <Typography
                            variant="mini"
                            sx={{
                                px: 1,
                                color: "text.faint",
                                textTransform: "uppercase",
                                letterSpacing: "0.08em",
                                fontWeight: "bold",
                            }}
                        >
                            {t("security")}
                        </Typography>
                        <LockerSidebarCardButton
                            icon={SecurityCheckIcon}
                            label={t("two_factor")}
                            onClick={() => setIsTwoFactorOpen(true)}
                        />
                        <LockerSidebarCardButton
                            icon={Key01Icon}
                            label={t("passkeys")}
                            endIcon={<NorthEastIcon />}
                            onClick={handleOpenPasskeys}
                        />
                        <LockerSidebarCardButton
                            icon={ComputerPhoneSyncIcon}
                            label={t("active_sessions")}
                            endIcon={<ChevronRightIcon />}
                            onClick={() => authenticateBefore("activeSessions")}
                        />
                    </Stack>

                    <Box sx={{ borderTop: 1, borderColor: "divider", mx: 1 }} />

                    <Stack sx={{ gap: 1 }}>
                        <LockerSidebarCardButton
                            icon={PasswordValidationIcon}
                            label={t("change_password")}
                            onClick={() => authenticateBefore("changePassword")}
                        />
                        <LockerSidebarCardButton
                            icon={Mail01Icon}
                            label={t("change_email")}
                            onClick={() => authenticateBefore("changeEmail")}
                        />
                    </Stack>
                </Stack>
            </LockerTitledNestedSidebarDrawer>

            <LockerSessionsDrawer
                open={isSessionsOpen}
                onClose={() => setIsSessionsOpen(false)}
                onRootClose={handleRootClose}
            />

            <LockerTwoFactorDrawer
                open={isTwoFactorOpen}
                onClose={() => setIsTwoFactorOpen(false)}
                onRootClose={handleRootClose}
            />

            <LockerAuthenticateUser
                open={!!authenticatedAction}
                onClose={() => setAuthenticatedAction(undefined)}
                onAuthenticate={handleAuthenticatedAction}
            />

            <RecoveryKey
                open={isRecoveryKeyOpen}
                onClose={() => setIsRecoveryKeyOpen(false)}
                showMiniDialog={showMiniDialog}
            />
        </>
    );
};
