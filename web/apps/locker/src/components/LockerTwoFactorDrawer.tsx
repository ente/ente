import LockIcon from "@mui/icons-material/Lock";
import { CircularProgress, Stack, Typography } from "@mui/material";
import { sessionExpiredDialogAttributes } from "ente-accounts/components/utils/dialog";
import { updateSavedLocalUser } from "ente-accounts/services/accounts-db";
import {
    disableTwoFactor,
    getTwoFactorStatus,
} from "ente-accounts/services/user";
import {
    RowButton,
    RowButtonGroup,
    RowButtonGroupHint,
    RowSwitch,
} from "ente-base/components/RowButton";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { useBaseContext } from "ente-base/context";
import { isHTTP401Error } from "ente-base/http";
import log from "ente-base/log";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useState } from "react";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";

export const LockerTwoFactorDrawer: React.FC<
    LockerNestedSidebarDrawerVisibilityProps
> = ({ open, onClose, onRootClose }) => {
    const router = useRouter();

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const handleConfigure = () => {
        handleRootClose();
        void router.push("/two-factor/setup");
    };

    return (
        <LockerTitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("two_factor_authentication")}
            hideRootCloseButton
        >
            <TwoFactorContents
                open={open}
                onRootClose={handleRootClose}
                onConfigure={handleConfigure}
            />
        </LockerTitledNestedSidebarDrawer>
    );
};

interface TwoFactorContentsProps {
    open: boolean;
    onRootClose: () => void;
    onConfigure: () => void;
}

const TwoFactorContents: React.FC<TwoFactorContentsProps> = ({
    open,
    onRootClose,
    onConfigure,
}) => {
    const { logout, showMiniDialog } = useBaseContext();

    const [isTwoFactorEnabled, setIsTwoFactorEnabled] = useState<
        boolean | undefined
    >();
    const [isLoading, setIsLoading] = useState(false);
    const [error, setError] = useState<string | undefined>();

    const handleError = useCallback(
        (e: unknown, message: string) => {
            log.error(message, e);
            if (isHTTP401Error(e)) {
                setTimeout(() => {
                    showMiniDialog(sessionExpiredDialogAttributes(logout));
                }, 0);
            } else {
                const isNetworkError =
                    e instanceof TypeError && e.message === "Failed to fetch";
                setError(
                    isNetworkError ? t("network_error") : t("generic_error"),
                );
            }
        },
        [logout, showMiniDialog],
    );

    const refreshStatus = useCallback(async () => {
        setIsLoading(true);
        setError(undefined);
        try {
            const isEnabled = await getTwoFactorStatus();
            setIsTwoFactorEnabled(isEnabled);
            updateSavedLocalUser({ isTwoFactorEnabled: isEnabled });
        } catch (e) {
            handleError(e, "Failed to fetch two-factor status");
        } finally {
            setIsLoading(false);
        }
    }, [handleError]);

    useEffect(() => {
        if (!open) return;
        setIsTwoFactorEnabled(undefined);
        void refreshStatus();
    }, [open, refreshStatus]);

    const confirmDisable = () =>
        showMiniDialog({
            title: t("disable_two_factor"),
            message: t("disable_two_factor_message"),
            continue: {
                text: t("disable"),
                color: "critical",
                action: async () => {
                    setError(undefined);
                    try {
                        await disableTwoFactor();
                        onRootClose();
                    } catch (e) {
                        log.error("Failed to disable two-factor", e);
                        if (isHTTP401Error(e)) {
                            setTimeout(() => {
                                showMiniDialog(
                                    sessionExpiredDialogAttributes(logout),
                                );
                            }, 0);
                            return;
                        }
                        throw e;
                    }
                },
            },
        });

    const confirmReconfigure = () =>
        showMiniDialog({
            title: t("update_two_factor"),
            message: t("update_two_factor_message"),
            continue: {
                text: t("update"),
                color: "primary",
                action: onConfigure,
            },
        });

    if (isLoading && isTwoFactorEnabled === undefined) {
        return (
            <Stack
                sx={{
                    flex: 1,
                    alignItems: "center",
                    justifyContent: "center",
                    py: 4,
                }}
            >
                <CircularProgress color="accent" />
            </Stack>
        );
    }

    if (error && isTwoFactorEnabled === undefined) {
        return (
            <Stack sx={{ px: 2, py: 2 }}>
                <Typography
                    variant="small"
                    sx={{ color: "critical.main", textAlign: "center" }}
                >
                    {error}
                </Typography>
            </Stack>
        );
    }

    return isTwoFactorEnabled ? (
        <ManageTwoFactor
            onDisable={confirmDisable}
            onReconfigure={confirmReconfigure}
        />
    ) : (
        <SetupTwoFactor onConfigure={onConfigure} />
    );
};

interface SetupTwoFactorProps {
    onConfigure: () => void;
}

const SetupTwoFactor: React.FC<SetupTwoFactorProps> = ({ onConfigure }) => (
    <Stack sx={{ px: "16px", py: "20px", alignItems: "center" }}>
        <LockIcon sx={{ fontSize: "40px", color: "text.muted" }} />
        <Typography
            sx={{
                color: "text.muted",
                textAlign: "center",
                marginBlock: "32px 36px",
            }}
        >
            {t("two_factor_info")}
        </Typography>
        <FocusVisibleButton color="accent" fullWidth onClick={onConfigure}>
            {t("enable_two_factor")}
        </FocusVisibleButton>
    </Stack>
);

interface ManageTwoFactorProps {
    onDisable: () => void;
    onReconfigure: () => void;
}

const ManageTwoFactor: React.FC<ManageTwoFactorProps> = ({
    onDisable,
    onReconfigure,
}) => (
    <Stack sx={{ px: "16px", py: "20px", gap: "24px" }}>
        <RowButtonGroup>
            <RowSwitch
                label={t("enabled")}
                checked={true}
                onClick={onDisable}
            />
        </RowButtonGroup>

        <Stack>
            <RowButtonGroup>
                <RowButton label={t("reconfigure")} onClick={onReconfigure} />
            </RowButtonGroup>
            <RowButtonGroupHint>
                {t("reconfigure_two_factor_hint")}
            </RowButtonGroupHint>
        </Stack>
    </Stack>
);
