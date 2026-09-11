import { ComputerIcon, SmartPhone01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import RefreshIcon from "@mui/icons-material/Refresh";
import {
    Box,
    CircularProgress,
    IconButton,
    Stack,
    Typography,
} from "@mui/material";
import { sessionExpiredDialogAttributes } from "ente-accounts/components/utils/dialog";
import {
    getActiveSessions,
    isCurrentSession,
    terminateSession,
    type Session,
} from "ente-accounts/services/sessions";
import { useBaseContext } from "ente-base/context";
import { isHTTP401Error } from "ente-base/http";
import { formattedDateTime } from "ente-base/i18n-date";
import log from "ente-base/log";
import { savedAuthToken } from "ente-base/token";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";
import { lockerColorSx } from "../../styles/tokens";
import { LockerConfirmDialog } from "../ui/LockerConfirmDialog";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";
import {
    bodySx,
    miniSx,
    rowSurfaceSx,
    sidebarBackgroundSx,
    textBaseSx,
    textLightSx,
    titlebarActionButtonSx,
} from "./locker-sidebar-styles";

const mobileUserAgentRegex = /iphone|ipad|android|mobile/i;

export const LockerSessionsDrawer: React.FC<
    LockerNestedSidebarDrawerVisibilityProps
> = ({ open, onClose, onRootClose }) => {
    const [refreshTrigger, setRefreshTrigger] = useState(0);

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    return (
        <LockerTitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("active_sessions")}
            slotProps={{
                paper: {
                    sx: (theme) => ({
                        scrollbarWidth: "thin",
                        scrollbarColor: "#b3b3b3 transparent",
                        "&::-webkit-scrollbar": { width: 6 },
                        "&::-webkit-scrollbar-track": {
                            backgroundColor: "transparent",
                        },
                        "&::-webkit-scrollbar-thumb": {
                            backgroundColor: "#b3b3b3",
                            borderRadius: 3,
                        },
                        ...theme.applyStyles("dark", {
                            scrollbarColor: "#555555 transparent",
                            "&::-webkit-scrollbar-thumb": {
                                backgroundColor: "#555555",
                            },
                        }),
                    }),
                },
            }}
            actionButton={
                <IconButton
                    onClick={() => setRefreshTrigger((value) => value + 1)}
                    aria-label={t("refresh")}
                    sx={titlebarActionButtonSx}
                >
                    <RefreshIcon sx={{ fontSize: 18 }} />
                </IconButton>
            }
        >
            <SessionsContents refreshTrigger={refreshTrigger} />
        </LockerTitledNestedSidebarDrawer>
    );
};

interface SessionsContentsProps {
    refreshTrigger: number;
}

const SessionsContents: React.FC<SessionsContentsProps> = ({
    refreshTrigger,
}) => {
    const { logout, showMiniDialog } = useBaseContext();

    const [sessions, setSessions] = useState<Session[] | undefined>();
    const [currentToken, setCurrentToken] = useState<string | undefined>();
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | undefined>();
    const [sessionToTerminate, setSessionToTerminate] = useState<Session>();
    const [terminationOpen, setTerminationOpen] = useState(false);
    const [isTerminating, setIsTerminating] = useState(false);
    const [terminationError, setTerminationError] = useState<string>();

    const fetchSessions = useCallback(async () => {
        setIsLoading(true);
        setError(undefined);
        try {
            const [activeSessions, token] = await Promise.all([
                getActiveSessions(),
                savedAuthToken(),
            ]);
            setSessions(activeSessions);
            setCurrentToken(token ?? undefined);
        } catch (e) {
            log.error("Failed to fetch active sessions", e);
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
        } finally {
            setIsLoading(false);
        }
    }, [logout, showMiniDialog]);

    useEffect(() => {
        void fetchSessions();
    }, [fetchSessions, refreshTrigger]);

    const handleTerminateSession = async () => {
        if (!terminationOpen || !sessionToTerminate || isTerminating) return;
        setIsTerminating(true);
        setTerminationError(undefined);
        try {
            if (isCurrentSession(sessionToTerminate, currentToken)) {
                logout();
                setTerminationOpen(false);
                return;
            }
            await terminateSession(sessionToTerminate.token);
            setTerminationOpen(false);
            await fetchSessions();
        } catch (e) {
            log.error("Failed to terminate session", e);
            if (isHTTP401Error(e)) {
                setTerminationOpen(false);
                setTimeout(() => {
                    showMiniDialog(sessionExpiredDialogAttributes(logout));
                }, 0);
            } else {
                setTerminationError(t("terminate_session_failed"));
            }
        } finally {
            setIsTerminating(false);
        }
    };

    if (isLoading) {
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

    if (error) {
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

    if (!sessions || sessions.length === 0) {
        return (
            <Stack sx={{ px: 2, py: 2 }}>
                <Typography
                    variant="small"
                    sx={{ color: "text.muted", textAlign: "center" }}
                >
                    {t("nothing_here")}
                </Typography>
            </Stack>
        );
    }

    return (
        <Stack sx={{ gap: 1 }}>
            <Typography sx={[miniSx, textLightSx]}>
                {t("active_sessions_hint")}
            </Typography>
            {sessions.map((session) => (
                <SessionRow
                    key={session.token}
                    session={session}
                    isCurrentDevice={isCurrentSession(session, currentToken)}
                    onTerminate={() => {
                        setTerminationError(undefined);
                        setSessionToTerminate(session);
                        setTerminationOpen(true);
                    }}
                />
            ))}
            <LockerConfirmDialog
                open={terminationOpen}
                illustration="/images/warning-red.png"
                title={t("terminate_session")}
                body={
                    sessionToTerminate &&
                    isCurrentSession(sessionToTerminate, currentToken) ? (
                        t("terminate_session_confirm_message_self")
                    ) : (
                        <>
                            {t("terminate_session_confirm_message")}
                            <Box
                                component="span"
                                sx={(theme) => ({
                                    display: "block",
                                    mt: 2,
                                    p: 1.5,
                                    borderRadius: "12px",
                                    overflowWrap: "anywhere",
                                    ...lockerColorSx(theme, {
                                        backgroundColor: "fillDark",
                                        color: "textLight",
                                    }),
                                })}
                            >
                                {sessionToTerminate?.prettyUA}
                                <Box
                                    component="span"
                                    sx={{ display: "block", mt: 0.5 }}
                                >
                                    {sessionToTerminate?.ip}
                                </Box>
                            </Box>
                        </>
                    )
                }
                confirmLabel={t("terminate")}
                loading={isTerminating}
                error={terminationError}
                onClose={() => setTerminationOpen(false)}
                onConfirm={handleTerminateSession}
            />
        </Stack>
    );
};

interface SessionRowProps {
    session: Session;
    isCurrentDevice: boolean;
    onTerminate: () => void;
}

const SessionRow: React.FC<SessionRowProps> = ({
    session,
    isCurrentDevice,
    onTerminate,
}) => {
    const lastUsedFormatted = formattedDateTime(session.lastUsedTime);

    const ip =
        session.ip.length > 28 ? `${session.ip.slice(0, 28)}…` : session.ip;

    return (
        <Box
            component="button"
            type="button"
            onClick={onTerminate}
            sx={[
                rowSurfaceSx,
                {
                    p: 1.5,
                    borderRadius: "20px",
                    border: 0,
                    m: 0,
                    display: "flex",
                    alignItems: "center",
                    gap: 1.5,
                    width: "100%",
                    textAlign: "left",
                    cursor: "pointer",
                    "&:focus-visible": {
                        outline: "2px solid",
                        outlineColor: "accent.main",
                        outlineOffset: 2,
                    },
                },
            ]}
        >
            <Box
                sx={[
                    sidebarBackgroundSx,
                    textLightSx,
                    {
                        width: 40,
                        height: 40,
                        borderRadius: "12px",
                        flexShrink: 0,
                        display: "grid",
                        placeItems: "center",
                    },
                ]}
            >
                <HugeiconsIcon
                    icon={
                        mobileUserAgentRegex.test(session.prettyUA)
                            ? SmartPhone01Icon
                            : ComputerIcon
                    }
                    size={18}
                    strokeWidth={1.6}
                    color="currentColor"
                />
            </Box>
            <Box sx={{ flex: 1, minWidth: 0 }}>
                <Typography
                    noWrap
                    sx={[
                        bodySx,
                        textBaseSx,
                        ...(isCurrentDevice
                            ? [{ "&&": { color: "accent.main" } }]
                            : []),
                    ]}
                >
                    {isCurrentDevice ? t("this_device") : session.prettyUA}
                </Typography>
                <Typography sx={[miniSx, textLightSx, { mt: 0.5 }]}>
                    {isCurrentDevice
                        ? lastUsedFormatted
                        : `${ip} · ${lastUsedFormatted}`}
                </Typography>
            </Box>
        </Box>
    );
};
