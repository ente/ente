import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import DevicesIcon from "@mui/icons-material/Devices";
import RefreshIcon from "@mui/icons-material/Refresh";
import {
    Box,
    CircularProgress,
    Divider,
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
import { RowButton, RowButtonGroup } from "ente-base/components/RowButton";
import { useBaseContext } from "ente-base/context";
import { isHTTP401Error } from "ente-base/http";
import { formattedDateTime } from "ente-base/i18n-date";
import log from "ente-base/log";
import { savedAuthToken } from "ente-base/token";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";

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
            hideRootCloseButton
            actionButton={
                <IconButton
                    onClick={() => setRefreshTrigger((value) => value + 1)}
                    color="primary"
                    sx={{ opacity: 0.2 }}
                >
                    <RefreshIcon />
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

    const handleTerminateSession = useCallback(
        (session: Session) => {
            const isCurrentDevice = isCurrentSession(session, currentToken);

            showMiniDialog({
                title: t("terminate_session"),
                message: isCurrentDevice ? (
                    t("terminate_session_confirm_message_self")
                ) : (
                    <Box sx={{ whiteSpace: "pre-line" }}>
                        {`${t("terminate_session_confirm_message")}:\n\n${session.prettyUA}\n${session.ip}`}
                    </Box>
                ),
                continue: {
                    text: t("terminate"),
                    color: "critical",
                    action: async () => {
                        if (isCurrentDevice) {
                            logout();
                            return;
                        }

                        try {
                            await terminateSession(session.token);
                            await fetchSessions();
                        } catch (e) {
                            log.error("Failed to terminate session", e);
                            if (isHTTP401Error(e)) {
                                setTimeout(() => {
                                    showMiniDialog(
                                        sessionExpiredDialogAttributes(logout),
                                    );
                                }, 0);
                            } else {
                                showMiniDialog({
                                    title: t("error"),
                                    message: t("terminate_session_failed"),
                                });
                            }
                        }
                    },
                },
            });
        },
        [currentToken, fetchSessions, logout, showMiniDialog],
    );

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
        <Stack sx={{ px: 2, pb: "12px", gap: 2 }}>
            <Typography variant="small" sx={{ color: "text.faint" }}>
                {t("active_sessions_hint")}
            </Typography>
            <RowButtonGroup>
                {sessions.map((session, index) => (
                    <React.Fragment key={session.token}>
                        <SessionRow
                            session={session}
                            isCurrentDevice={isCurrentSession(
                                session,
                                currentToken,
                            )}
                            onTerminate={() => handleTerminateSession(session)}
                        />
                        {index < sessions.length - 1 && (
                            <Divider sx={{ opacity: 0.4 }} />
                        )}
                    </React.Fragment>
                ))}
            </RowButtonGroup>
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

    return (
        <RowButton
            startIcon={<DevicesIcon />}
            label={
                <Stack sx={{ gap: 0.5, alignItems: "flex-start" }}>
                    <Typography
                        sx={{
                            fontWeight: isCurrentDevice ? "bold" : "medium",
                            color: isCurrentDevice
                                ? "accent.main"
                                : "text.base",
                            textAlign: "left",
                        }}
                    >
                        {isCurrentDevice ? t("this_device") : session.prettyUA}
                    </Typography>
                    {!isCurrentDevice && (
                        <Typography
                            variant="small"
                            sx={{ color: "text.muted" }}
                        >
                            {session.ip.length > 28
                                ? `${session.ip.slice(0, 28)}…`
                                : session.ip}
                        </Typography>
                    )}
                    <Typography variant="small" sx={{ color: "text.faint" }}>
                        {lastUsedFormatted}
                    </Typography>
                </Stack>
            }
            endIcon={<ChevronRightIcon />}
            onClick={onTerminate}
        />
    );
};
