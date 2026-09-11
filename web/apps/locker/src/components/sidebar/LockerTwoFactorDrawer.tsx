import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import LockIcon from "@mui/icons-material/Lock";
import {
    Box,
    Button,
    CircularProgress,
    FormControlLabel,
    Stack,
    Switch,
    Typography,
} from "@mui/material";
import { sessionExpiredDialogAttributes } from "ente-accounts/components/utils/dialog";
import { updateSavedLocalUser } from "ente-accounts/services/accounts-db";
import {
    disableTwoFactor,
    getTwoFactorStatus,
} from "ente-accounts/services/user";
import { useBaseContext } from "ente-base/context";
import { isHTTP401Error } from "ente-base/http";
import log from "ente-base/log";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useCallback, useEffect, useState } from "react";
import {
    lockerColorSx,
    lockerTextBodyBoldSx,
    lockerTextBodySx,
    lockerTextMiniSx,
} from "../../styles/tokens";
import { LockerConfirmDialog } from "../ui/LockerConfirmDialog";
import { LockerSidebarCardButton } from "./LockerSidebarCardButton";
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
    const [confirmation, setConfirmation] = useState<
        "disable" | "reconfigure"
    >();
    const [isDisabling, setIsDisabling] = useState(false);

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
        if (!open) {
            setConfirmation(undefined);
            return;
        }
        setIsTwoFactorEnabled(undefined);
        void refreshStatus();
    }, [open, refreshStatus]);

    const handleConfirm = async () => {
        if (!confirmation || isDisabling) return;
        if (confirmation === "reconfigure") {
            setConfirmation(undefined);
            onConfigure();
            return;
        }
        setIsDisabling(true);
        setError(undefined);
        try {
            await disableTwoFactor();
            setConfirmation(undefined);
            onRootClose();
        } catch (e) {
            handleError(e, "Failed to disable two-factor");
            if (isHTTP401Error(e)) setConfirmation(undefined);
        } finally {
            setIsDisabling(false);
        }
    };

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

    return (
        <>
            {isTwoFactorEnabled ? (
                <ManageTwoFactor
                    onDisable={() => {
                        setError(undefined);
                        setConfirmation("disable");
                    }}
                    onReconfigure={() => {
                        setError(undefined);
                        setConfirmation("reconfigure");
                    }}
                />
            ) : (
                <SetupTwoFactor onConfigure={onConfigure} />
            )}
            <LockerConfirmDialog
                open={!!confirmation}
                illustration={
                    confirmation === "disable"
                        ? "/images/warning-red.png"
                        : "/images/warning-grey.png"
                }
                title={t(
                    confirmation === "disable"
                        ? "disable_two_factor"
                        : "update_two_factor",
                )}
                body={t(
                    confirmation === "disable"
                        ? "disable_two_factor_message"
                        : "update_two_factor_message",
                )}
                confirmLabel={t(
                    confirmation === "disable" ? "disable" : "update",
                )}
                tone={confirmation === "disable" ? "critical" : "primary"}
                loading={isDisabling}
                error={error}
                onClose={() => setConfirmation(undefined)}
                onConfirm={handleConfirm}
            />
        </>
    );
};

interface SetupTwoFactorProps {
    onConfigure: () => void;
}

const SetupTwoFactor: React.FC<SetupTwoFactorProps> = ({ onConfigure }) => (
    <Stack sx={{ py: 2, alignItems: "center", gap: 3 }}>
        <Box
            sx={(theme) => ({
                width: 80,
                height: 80,
                borderRadius: "20px",
                display: "grid",
                placeItems: "center",
                ...lockerColorSx(theme, {
                    backgroundColor: "fillLight",
                    color: "textLight",
                }),
            })}
        >
            <LockIcon sx={{ fontSize: 32 }} />
        </Box>
        <Typography
            sx={(theme) => ({
                ...lockerTextBodySx,
                textAlign: "center",
                ...lockerColorSx(theme, { color: "textLight" }),
            })}
        >
            {t("two_factor_info")}
        </Typography>
        <Button
            variant="contained"
            color="primary"
            fullWidth
            onClick={onConfigure}
            sx={(theme) => ({
                ...lockerTextBodyBoldSx,
                minHeight: 52,
                borderRadius: "20px",
                textTransform: "none",
                ...lockerColorSx(theme, {
                    backgroundColor: "primary",
                    color: "specialWhite",
                }),
                "&:hover": lockerColorSx(theme, {
                    backgroundColor: "primaryDark",
                }),
            })}
        >
            {t("enable_two_factor")}
        </Button>
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
    <Stack sx={{ gap: 1 }}>
        <FormControlLabel
            label={t("enabled")}
            labelPlacement="start"
            control={<Switch checked onChange={onDisable} color="primary" />}
            sx={(theme) => ({
                m: 0,
                px: 1.5,
                minHeight: 54,
                borderRadius: "20px",
                justifyContent: "space-between",
                ...lockerColorSx(theme, {
                    backgroundColor: "fillLight",
                    color: "textBase",
                }),
                "& .MuiFormControlLabel-label": lockerTextBodySx,
            })}
        />
        <LockerSidebarCardButton
            label={t("reconfigure")}
            onClick={onReconfigure}
            endIcon={<ChevronRightIcon />}
        />
        <Typography
            sx={(theme) => ({
                ...lockerTextMiniSx,
                px: 1.5,
                mt: 0.5,
                ...lockerColorSx(theme, { color: "textLight" }),
            })}
        >
            {t("reconfigure_two_factor_hint")}
        </Typography>
    </Stack>
);
