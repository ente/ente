import type { ChatSession } from "@/services/chat/store";
import {
    ArrowLeft01Icon,
    ArrowRight01Icon,
    Cancel01Icon,
    Delete01Icon,
    Edit01Icon,
    PlusSignIcon,
    Search01Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Button,
    IconButton,
    InputBase,
    List,
    ListItemButton,
    Stack,
    Tooltip,
    Typography,
} from "@mui/material";
import type { SxProps, Theme } from "@mui/material/styles";
import {
    memo,
    startTransition,
    useMemo,
    useState,
    type RefObject,
} from "react";

interface IconProps {
    size: number;
    strokeWidth: number;
}

export interface ChatSidebarProps {
    drawerCollapsed: boolean;
    drawerIconButtonSx: SxProps<Theme>;
    actionButtonSx: SxProps<Theme>;
    smallIconProps: IconProps;
    tinyIconProps: IconProps;
    actionIconProps: IconProps;
    showSessionSearch: boolean;
    sessionSearchRef: RefObject<string>;
    handleOpenSessionSearch: () => void;
    handleCloseSessionSearch: () => void;
    handleNewChat: () => void;
    handleOpenDrawer: () => void;
    handleCollapseDrawer: () => void;
    sessions: ChatSession[];
    currentSessionId?: string;
    handleSelectSession: (sessionId: string) => void;
    requestRenameSession: (session: ChatSession) => void;
    requestDeleteSession: (sessionId: string) => void;
    openSettingsModal: () => void;
}

export const ChatSidebar = memo(
    ({
        sessions,
        sessionSearchRef,
        handleCloseSessionSearch,
        ...props
    }: ChatSidebarProps) => {
        const [sessionSearch, setSessionSearch] = useState(
            sessionSearchRef.current,
        );
        const groupedSessions = useMemo(() => {
            const query = sessionSearch.trim().toLowerCase();
            const filteredSessions = query
                ? sessions.filter((session) => {
                      const title = session.title.toLowerCase();
                      const preview =
                          session.lastMessagePreview?.toLowerCase() ?? "";
                      return title.includes(query) || preview.includes(query);
                  })
                : sessions;
            return groupSessionsByDate(filteredSessions);
        }, [sessionSearch, sessions]);

        const closeSessionSearch = () => {
            sessionSearchRef.current = "";
            setSessionSearch("");
            handleCloseSessionSearch();
        };

        return (
            <ChatSidebarView
                {...props}
                groupedSessions={groupedSessions}
                handleCloseSessionSearch={closeSessionSearch}
                sessionSearchRef={sessionSearchRef}
                setSessionSearch={setSessionSearch}
            />
        );
    },
);

interface ChatSidebarViewProps extends Omit<ChatSidebarProps, "sessions"> {
    groupedSessions: [string, ChatSession[]][];
    setSessionSearch: (query: string) => void;
}

const ChatSidebarView = memo(
    ({
        drawerCollapsed,
        drawerIconButtonSx,
        actionButtonSx,
        smallIconProps,
        tinyIconProps,
        actionIconProps,
        showSessionSearch,
        sessionSearchRef,
        setSessionSearch,
        handleOpenSessionSearch,
        handleCloseSessionSearch,
        handleNewChat,
        handleOpenDrawer,
        handleCollapseDrawer,
        groupedSessions,
        currentSessionId,
        handleSelectSession,
        requestRenameSession,
        requestDeleteSession,
        openSettingsModal,
    }: ChatSidebarViewProps) => (
        <Stack
            sx={{
                width: "100%",
                height: "100%",
                bgcolor: "background.default",
            }}
        >
            <List
                sx={{
                    flex: 1,
                    overflowY: "auto",
                    px: 1,
                    overscrollBehaviorY: "contain",
                    scrollbarWidth: "thin",
                    "&::-webkit-scrollbar": { width: "8px" },
                    "&::-webkit-scrollbar-thumb": {
                        backgroundColor: "divider",
                        borderRadius: "999px",
                    },
                    "&::-webkit-scrollbar-track": {
                        backgroundColor: "transparent",
                    },
                }}
            >
                <Stack
                    direction="row"
                    sx={{
                        alignItems: "center",
                        justifyContent: "flex-start",
                        gap: 1,
                        my: 1,
                        px: 1,
                        width: "100%",
                    }}
                >
                    {showSessionSearch ? (
                        <>
                            <SessionSearchInput
                                sessionSearchRef={sessionSearchRef}
                                setSessionSearch={setSessionSearch}
                                tinyIconProps={tinyIconProps}
                            />
                            <IconButton
                                aria-label="Close search"
                                sx={drawerIconButtonSx}
                                onClick={handleCloseSessionSearch}
                            >
                                <HugeiconsIcon
                                    icon={Cancel01Icon}
                                    {...tinyIconProps}
                                />
                            </IconButton>
                            <IconButton
                                aria-label={
                                    drawerCollapsed
                                        ? "Expand drawer"
                                        : "Collapse drawer"
                                }
                                sx={drawerIconButtonSx}
                                onClick={
                                    drawerCollapsed
                                        ? handleOpenDrawer
                                        : handleCollapseDrawer
                                }
                            >
                                <HugeiconsIcon
                                    icon={
                                        drawerCollapsed
                                            ? ArrowRight01Icon
                                            : ArrowLeft01Icon
                                    }
                                    {...smallIconProps}
                                />
                            </IconButton>
                        </>
                    ) : (
                        <>
                            <Button
                                onClick={handleOpenSessionSearch}
                                variant="outlined"
                                startIcon={
                                    <HugeiconsIcon
                                        icon={Search01Icon}
                                        {...tinyIconProps}
                                    />
                                }
                                sx={{
                                    flex: 1,
                                    minWidth: 0,
                                    height: 40,
                                    minHeight: 40,
                                    px: 1.5,
                                    textTransform: "none",
                                    fontWeight: 600,
                                    fontSize: "13px",
                                    whiteSpace: "nowrap",
                                    textOverflow: "ellipsis",
                                    overflow: "hidden",
                                    borderRadius: 2,
                                    borderColor: "divider",
                                    color: "text.base",
                                    bgcolor: "fill.faint",
                                    flexWrap: "nowrap",
                                    justifyContent: "flex-start",
                                    textAlign: "left",
                                    "& .MuiButton-startIcon": {
                                        marginRight: 0.75,
                                        marginLeft: 0,
                                    },
                                    "&:hover": {
                                        bgcolor: "fill.faintHover",
                                        borderColor: "divider",
                                    },
                                }}
                            >
                                <Box
                                    component="span"
                                    sx={{
                                        whiteSpace: "nowrap",
                                        overflow: "hidden",
                                        textOverflow: "ellipsis",
                                    }}
                                >
                                    Search
                                </Box>
                            </Button>
                            <Tooltip title="New Chat">
                                <IconButton
                                    aria-label="New Chat"
                                    onClick={handleNewChat}
                                    sx={drawerIconButtonSx}
                                >
                                    <HugeiconsIcon
                                        icon={PlusSignIcon}
                                        {...tinyIconProps}
                                    />
                                </IconButton>
                            </Tooltip>
                            <IconButton
                                aria-label={
                                    drawerCollapsed
                                        ? "Expand drawer"
                                        : "Collapse drawer"
                                }
                                sx={drawerIconButtonSx}
                                onClick={
                                    drawerCollapsed
                                        ? handleOpenDrawer
                                        : handleCollapseDrawer
                                }
                            >
                                <HugeiconsIcon
                                    icon={
                                        drawerCollapsed
                                            ? ArrowRight01Icon
                                            : ArrowLeft01Icon
                                    }
                                    {...smallIconProps}
                                />
                            </IconButton>
                        </>
                    )}
                </Stack>

                {groupedSessions.map(([label, group]) => (
                    <Box key={label} sx={{ pb: 1 }}>
                        <Typography
                            variant="mini"
                            sx={{
                                px: 1,
                                pt: 2,
                                pb: 0.5,
                                letterSpacing: "0.12em",
                                color: "text.muted",
                            }}
                        >
                            {label}
                        </Typography>
                        {group.map((session) => {
                            const sessionTitle =
                                session.title.trim() || "New chat";
                            return (
                                <ListItemButton
                                    key={session.sessionUuid}
                                    selected={
                                        session.sessionUuid === currentSessionId
                                    }
                                    onClick={() =>
                                        handleSelectSession(session.sessionUuid)
                                    }
                                    sx={{
                                        alignItems: "flex-start",
                                        py: 1.5,
                                        borderRadius: 2,
                                        my: 0.5,
                                        "&:hover": {
                                            backgroundColor: "fill.faintHover",
                                        },
                                        "&.Mui-selected": {
                                            backgroundColor: "fill.faint",
                                        },
                                        "&.Mui-selected:hover": {
                                            backgroundColor: "fill.faintHover",
                                        },
                                        "& .rename-chat-button": {
                                            visibility: "hidden",
                                        },
                                        "&:hover .rename-chat-button, &:focus-within .rename-chat-button":
                                            { visibility: "visible" },
                                    }}
                                >
                                    <Stack
                                        direction="row"
                                        sx={{
                                            width: "100%",
                                            alignItems: "flex-start",
                                            gap: 1,
                                        }}
                                    >
                                        <Box sx={{ flex: 1, minWidth: 0 }}>
                                            <Tooltip title={sessionTitle}>
                                                <Typography
                                                    variant="small"
                                                    sx={{
                                                        fontWeight: 600,
                                                        fontFamily: "inherit",
                                                        whiteSpace: "nowrap",
                                                        overflow: "hidden",
                                                        textOverflow:
                                                            "ellipsis",
                                                    }}
                                                >
                                                    {sessionTitle}
                                                </Typography>
                                            </Tooltip>
                                            <Typography
                                                variant="mini"
                                                sx={{
                                                    color: "text.muted",
                                                    fontFamily: "inherit",
                                                    display: "-webkit-box",
                                                    WebkitLineClamp: 1,
                                                    WebkitBoxOrient: "vertical",
                                                    overflow: "hidden",
                                                }}
                                            >
                                                {session.lastMessagePreview ??
                                                    "Nothing here"}
                                            </Typography>
                                        </Box>
                                        <IconButton
                                            className="rename-chat-button"
                                            aria-label="Rename chat"
                                            sx={actionButtonSx}
                                            onClick={(event) => {
                                                event.stopPropagation();
                                                requestRenameSession(session);
                                            }}
                                        >
                                            <HugeiconsIcon
                                                icon={Edit01Icon}
                                                {...actionIconProps}
                                            />
                                        </IconButton>
                                        <IconButton
                                            aria-label="Delete chat"
                                            sx={actionButtonSx}
                                            onClick={(event) => {
                                                event.stopPropagation();
                                                requestDeleteSession(
                                                    session.sessionUuid,
                                                );
                                            }}
                                        >
                                            <HugeiconsIcon
                                                icon={Delete01Icon}
                                                {...actionIconProps}
                                            />
                                        </IconButton>
                                    </Stack>
                                </ListItemButton>
                            );
                        })}
                    </Box>
                ))}
            </List>

            {!drawerCollapsed && (
                <Stack sx={{ p: 1 }}>
                    <ListItemButton
                        onClick={openSettingsModal}
                        sx={{
                            alignItems: "center",
                            gap: 1,
                            px: 2,
                            py: 1.25,
                            width: "100%",
                            borderRadius: 2,
                            border: "1px solid",
                            borderColor: "divider",
                            bgcolor: "background.paper",
                            boxShadow: "0px 10px 24px rgba(0, 0, 0, 0.08)",
                            "&:hover": { backgroundColor: "fill.faintHover" },
                        }}
                    >
                        <Typography
                            variant="small"
                            sx={{ flex: 1, fontWeight: 600 }}
                        >
                            Settings
                        </Typography>
                        <HugeiconsIcon
                            icon={ArrowRight01Icon}
                            {...smallIconProps}
                        />
                    </ListItemButton>
                </Stack>
            )}
        </Stack>
    ),
);

interface SessionSearchInputProps {
    sessionSearchRef: RefObject<string>;
    setSessionSearch: (query: string) => void;
    tinyIconProps: IconProps;
}

const SessionSearchInput = memo(
    ({
        sessionSearchRef,
        setSessionSearch,
        tinyIconProps,
    }: SessionSearchInputProps) => {
        const [value, setValue] = useState(sessionSearchRef.current);

        return (
            <Box
                sx={{
                    flex: 1,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "flex-start",
                    gap: 1,
                    px: 1.5,
                    height: 40,
                    borderRadius: 2,
                    bgcolor: "fill.faint",
                    textAlign: "left",
                }}
            >
                <HugeiconsIcon icon={Search01Icon} {...tinyIconProps} />
                <InputBase
                    placeholder="Search chats"
                    autoFocus
                    value={value}
                    onChange={(event) => {
                        const query = event.target.value;
                        sessionSearchRef.current = query;
                        setValue(query);
                        startTransition(() => setSessionSearch(query));
                    }}
                    inputProps={{ style: { textAlign: "left" } }}
                    sx={{
                        flex: 1,
                        color: "text.base",
                        fontFamily: "inherit",
                        fontSize: "13px",
                        textAlign: "left",
                        "& input": { textAlign: "left" },
                    }}
                />
            </Box>
        );
    },
);

type SessionGroupLabel =
    | "TODAY"
    | "YESTERDAY"
    | "THIS WEEK"
    | "LAST WEEK"
    | "THIS MONTH"
    | "OLDER";

const groupSessionsByDate = (sessions: ChatSession[]) => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);

    const thisWeekStart = new Date(today);
    thisWeekStart.setDate(
        thisWeekStart.getDate() - (thisWeekStart.getDay() || 7) + 1,
    );

    const lastWeekStart = new Date(thisWeekStart);
    lastWeekStart.setDate(lastWeekStart.getDate() - 7);

    const thisMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    const grouped: Record<SessionGroupLabel, ChatSession[]> = {
        TODAY: [],
        YESTERDAY: [],
        "THIS WEEK": [],
        "LAST WEEK": [],
        "THIS MONTH": [],
        OLDER: [],
    };

    sessions.forEach((session) => {
        const sessionDate = new Date(Math.floor(session.updatedAt / 1000));
        const sessionDay = new Date(
            sessionDate.getFullYear(),
            sessionDate.getMonth(),
            sessionDate.getDate(),
        );

        let category: SessionGroupLabel = "OLDER";

        if (sessionDay >= today) {
            category = "TODAY";
        } else if (sessionDay.getTime() === yesterday.getTime()) {
            category = "YESTERDAY";
        } else if (sessionDay >= thisWeekStart) {
            category = "THIS WEEK";
        } else if (sessionDay >= lastWeekStart) {
            category = "LAST WEEK";
        } else if (sessionDay >= thisMonthStart) {
            category = "THIS MONTH";
        }

        grouped[category].push(session);
    });

    return (
        Object.entries(grouped) as [SessionGroupLabel, ChatSession[]][]
    ).filter(([, group]) => group.length > 0);
};
