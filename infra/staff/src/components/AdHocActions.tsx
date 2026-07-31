import MoreVertIcon from "@mui/icons-material/MoreVert";
import RestoreRoundedIcon from "@mui/icons-material/RestoreRounded";
import StorageRoundedIcon from "@mui/icons-material/StorageRounded";
import {
    Box,
    Button,
    Divider,
    ListSubheader,
    Menu,
    MenuItem,
    Tooltip,
    Typography,
} from "@mui/material";
import React, { useState } from "react";
import type { ScheduledDeletion } from "../services/admin-user";
import {
    recoverScheduledDeletion,
    unblockStorageWarningLogin,
} from "../services/admin-user";
import { useStaffSession } from "../services/session";
import { dateFromMicroseconds, formatStorageSize } from "../utils";
import { ConfirmationDialog } from "./ConfirmationDialog";

interface AdHocActionsProps {
    email: string;
    activeUserID?: number | undefined;
    scheduledDeletions: ScheduledDeletion[];
    scheduledDeletionsLoading: boolean;
    scheduledDeletionsLoaded: boolean;
    disabled: boolean;
    onOpen: () => Promise<void>;
    onRecovered: () => Promise<void>;
}

export const AdHocActions: React.FC<AdHocActionsProps> = ({
    email,
    activeUserID,
    scheduledDeletions,
    scheduledDeletionsLoading,
    scheduledDeletionsLoaded,
    disabled,
    onOpen,
    onRecovered,
}) => {
    const session = useStaffSession();
    const [anchorEl, setAnchorEl] = useState<HTMLElement>();
    const [recovering, setRecovering] = useState<ScheduledDeletion>();
    const [unblocking, setUnblocking] = useState(false);
    const [loading, setLoading] = useState(false);
    const [scheduledDeletionError, setScheduledDeletionError] =
        useState<string>();

    const closeMenu = () => setAnchorEl(undefined);
    const recoveryAvailable = activeUserID === undefined;

    const loadScheduledDeletions = async () => {
        setScheduledDeletionError(undefined);
        if (scheduledDeletionsLoaded || scheduledDeletionsLoading) return;
        try {
            await onOpen();
        } catch (error) {
            setScheduledDeletionError(
                error instanceof Error
                    ? error.message
                    : "Failed to check scheduled deletion",
            );
        }
    };

    const openMenu = (event: React.MouseEvent<HTMLButtonElement>) => {
        setAnchorEl(event.currentTarget);
        loadScheduledDeletions().catch(console.error);
    };

    const recover = async () => {
        if (!recovering) return;
        setLoading(true);
        try {
            await recoverScheduledDeletion(session, recovering.userID, email);
            setRecovering(undefined);
            await onRecovered();
        } catch (error) {
            alert(
                error instanceof Error
                    ? error.message
                    : "Failed to recover account",
            );
        } finally {
            setLoading(false);
        }
    };

    const unblock = async () => {
        if (activeUserID === undefined) return;
        setLoading(true);
        try {
            await unblockStorageWarningLogin(session, activeUserID);
            setUnblocking(false);
            alert(
                "Unblock request completed. If the account was storage-warning blocked, temporary login grace is now active.",
            );
        } catch (error) {
            alert(
                error instanceof Error
                    ? error.message
                    : "Failed to unblock login",
            );
        } finally {
            setLoading(false);
        }
    };

    return (
        <>
            <Tooltip
                title={disabled ? "Fetch an account first" : "Account actions"}
            >
                <span>
                    <Button
                        aria-label="Account actions"
                        className="ad-hoc-actions-button"
                        disabled={disabled}
                        endIcon={<MoreVertIcon />}
                        onClick={openMenu}
                        type="button"
                        variant="outlined"
                    >
                        Actions
                    </Button>
                </span>
            </Tooltip>
            <Menu
                anchorEl={anchorEl}
                open={anchorEl !== undefined}
                onClose={closeMenu}
                slotProps={{
                    paper: {
                        sx: {
                            width: 390,
                            mt: 1,
                            borderRadius: 2,
                            boxShadow: "0 12px 28px rgb(0 0 0 / 18%)",
                        },
                    },
                }}
            >
                <Box sx={{ px: 2, pt: 1.75, pb: 1.25 }}>
                    <Typography sx={{ fontWeight: 700 }} variant="subtitle1">
                        Account actions
                    </Typography>
                    <Typography color="text.secondary" variant="body2">
                        {email}
                    </Typography>
                </Box>
                <Divider />
                <ListSubheader disableSticky>Scheduled deletion</ListSubheader>
                {scheduledDeletionsLoading ? (
                    <MenuItem disabled sx={{ py: 1.25 }}>
                        <Typography variant="body2">
                            Checking for scheduled deletion…
                        </Typography>
                    </MenuItem>
                ) : scheduledDeletionError ? (
                    <MenuItem
                        onClick={() => {
                            loadScheduledDeletions().catch(console.error);
                        }}
                        sx={{
                            alignItems: "flex-start",
                            gap: 1.5,
                            py: 1.25,
                            whiteSpace: "normal",
                        }}
                    >
                        <Box sx={{ flex: 1, minWidth: 0 }}>
                            <Typography color="error" variant="body2">
                                Could not check scheduled deletion.
                            </Typography>
                            <Typography
                                color="text.secondary"
                                sx={{ display: "block" }}
                                variant="caption"
                            >
                                {scheduledDeletionError}
                            </Typography>
                        </Box>
                        <Typography
                            color="success.main"
                            component="span"
                            sx={{ flexShrink: 0, fontWeight: 600 }}
                            variant="button"
                        >
                            Retry
                        </Typography>
                    </MenuItem>
                ) : scheduledDeletions.length === 0 ? (
                    <MenuItem disabled sx={{ py: 1.25 }}>
                        <Typography variant="body2">
                            No scheduled deletion found for this email.
                        </Typography>
                    </MenuItem>
                ) : (
                    scheduledDeletions.map((deletion) => (
                        <MenuItem
                            key={deletion.userID}
                            disableRipple
                            disabled={!recoveryAvailable}
                            onClick={() => {
                                closeMenu();
                                setRecovering(deletion);
                            }}
                            sx={{
                                alignItems: "flex-start",
                                gap: 1.5,
                                py: 1.25,
                                whiteSpace: "normal",
                                "&.Mui-disabled": { opacity: 0.55 },
                            }}
                        >
                            <RestoreRoundedIcon
                                color="success"
                                sx={{ mt: 0.25 }}
                            />
                            <Box
                                sx={{ flex: 1, minWidth: 0, textAlign: "left" }}
                            >
                                <Typography
                                    sx={{ fontWeight: 600 }}
                                    variant="body2"
                                >
                                    Account #{deletion.userID}
                                </Typography>
                                <Typography
                                    color="text.secondary"
                                    sx={{ display: "block" }}
                                    variant="caption"
                                >
                                    Scheduled {formatDate(deletion.scheduledAt)}
                                </Typography>
                                <Typography
                                    color="text.secondary"
                                    sx={{ display: "block" }}
                                    variant="caption"
                                >
                                    Cleanup starts{" "}
                                    {formatDate(deletion.deletionStartsAt)}
                                </Typography>
                                <Typography
                                    color="text.secondary"
                                    sx={{ display: "block" }}
                                    variant="caption"
                                >
                                    Created{" "}
                                    {formatDate(deletion.userCreatedAt, false)}{" "}
                                    ·{" "}
                                    {formatStorageSize(
                                        deletion.storageConsumed,
                                    )}{" "}
                                    stored · {deletion.authenticatorEntryCount}{" "}
                                    auth entries
                                </Typography>
                            </Box>
                            <Typography
                                color="success.contrastText"
                                component="span"
                                sx={{
                                    bgcolor: "success.main",
                                    borderRadius: 1,
                                    flexShrink: 0,
                                    fontWeight: 600,
                                    px: 1.25,
                                    py: 0.5,
                                }}
                                variant="button"
                            >
                                Recover
                            </Typography>
                        </MenuItem>
                    ))
                )}
                {activeUserID !== undefined &&
                    scheduledDeletions.length > 0 && (
                        <Typography
                            color="text.secondary"
                            sx={{ px: 2, py: 1 }}
                            variant="caption"
                        >
                            Recovery is unavailable while active account #
                            {activeUserID} uses this email.
                        </Typography>
                    )}
                <Divider sx={{ mt: 0.5 }} />
                <ListSubheader>Storage warning</ListSubheader>
                <MenuItem
                    disabled={activeUserID === undefined}
                    disableRipple
                    onClick={() => {
                        closeMenu();
                        setUnblocking(true);
                    }}
                    sx={{ gap: 1.5, py: 1.25 }}
                >
                    <StorageRoundedIcon color="warning" />
                    <Box sx={{ flex: 1, textAlign: "left" }}>
                        <Typography sx={{ fontWeight: 600 }} variant="body2">
                            Storage-warning login
                        </Typography>
                        <Typography color="text.secondary" variant="caption">
                            Grant a temporary sign-in grace period.
                        </Typography>
                    </Box>
                    <Typography
                        color="warning.main"
                        component="span"
                        sx={{
                            border: 1,
                            borderColor: "warning.main",
                            borderRadius: 1,
                            flexShrink: 0,
                            fontWeight: 600,
                            px: 1.25,
                            py: 0.375,
                        }}
                        variant="button"
                    >
                        Unblock
                    </Typography>
                </MenuItem>
            </Menu>
            <ConfirmationDialog
                open={recovering !== undefined}
                onClose={() => setRecovering(undefined)}
                title="Recover deleted account?"
                actions={[
                    {
                        label: "Recover",
                        loadingLabel: "Recovering...",
                        loading,
                        tone: "success",
                        onClick: () => {
                            recover().catch(console.error);
                        },
                    },
                ]}
            >
                Restore the deleted account for {email} (user #
                {recovering?.userID}). This cannot succeed while another active
                account uses this email.
            </ConfirmationDialog>
            <ConfirmationDialog
                open={unblocking}
                onClose={() => setUnblocking(false)}
                title="Unblock storage-warning login?"
                actions={[
                    {
                        label: "Unblock",
                        loadingLabel: "Unblocking...",
                        loading,
                        onClick: () => {
                            unblock().catch(console.error);
                        },
                    },
                ]}
            >
                This grants a temporary login grace; it does not restore sharing
                or family access.
            </ConfirmationDialog>
        </>
    );
};

const formatDate = (timestamp: number, includeTime = true) =>
    dateFromMicroseconds(timestamp).toLocaleString([], {
        dateStyle: "medium",
        ...(includeTime && { timeStyle: "short" }),
    });
