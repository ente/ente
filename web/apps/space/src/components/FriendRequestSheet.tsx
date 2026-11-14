import { Box, Dialog } from "@mui/material";
import {
    spaceActionDoneDurationMs,
    SpaceActionFeedbackIcon,
    type SpaceActionPhase,
} from "components/ActionFeedback";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import {
    spaceControlBackgroundHover,
    spaceDanger,
    spaceDialogBackground,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { friendRequestErrorMessage } from "utils/friend-errors";

const green = "#08C225";

export interface FriendRequestSheetActions {
    direction: "sent" | "received" | "suggested";
    username: string;
    onPrimary?: () => Promise<boolean>;
    onSecondary: () => Promise<void>;
}

interface FriendRequestSheetProps extends FriendRequestSheetActions {
    onClose: () => void;
}

export const FriendRequestSheet: React.FC<FriendRequestSheetProps> = ({
    direction,
    username,
    onPrimary,
    onSecondary,
    onClose,
}) => {
    const [open, setOpen] = React.useState(true);
    const [action, setAction] = React.useState<{
        type: "primary" | "secondary";
        phase: SpaceActionPhase;
    } | null>(null);
    const [errorMessage, setErrorMessage] = React.useState("");
    const titleID = React.useId();
    const descriptionID = React.useId();
    const copy = {
        received: {
            title: `Be friends with @${username}?`,
            description: "Share photos, and keep up with each other.",
            primary: "Accept",
            secondary: "Decline",
            done: "Request accepted",
        },
        sent: {
            title: `Waiting for @${username}`,
            description: "You’ll see their posts once they accept.",
            primary: "",
            secondary: "Cancel request",
            done: "",
        },
        suggested: {
            title: `You might know @${username}`,
            description: "",
            primary: "Send friend request",
            secondary: "Hide suggestion",
            done: "Request sent",
        },
    }[direction];
    const dismiss = () => {
        if (!action) setOpen(false);
    };

    useBrowserBackClose({
        open,
        onClose: dismiss,
        stateKey: "space-friend-request",
    });

    React.useEffect(() => {
        if (action?.phase != "done") return;
        const timeout = window.setTimeout(
            () => setOpen(false),
            spaceActionDoneDurationMs,
        );
        return () => window.clearTimeout(timeout);
    }, [action?.phase]);

    const updateRequest = async (type: "primary" | "secondary") => {
        if (action) return;
        setAction({ type, phase: "busy" });
        setErrorMessage("");
        try {
            if (type == "primary") {
                if (await onPrimary?.()) setAction({ type, phase: "done" });
                else setOpen(false);
            } else {
                await onSecondary();
                setOpen(false);
            }
        } catch (error) {
            log.error("Failed to update friend request", error);
            setAction(null);
            if (direction == "suggested") {
                setErrorMessage(
                    type == "primary"
                        ? friendRequestErrorMessage(error, username)
                        : "Couldn’t hide the suggestion. Please try again.",
                );
            } else {
                setErrorMessage(
                    "Couldn’t update the request. Please try again.",
                );
            }
        }
    };

    const actions = [
        ...(onPrimary
            ? [{ type: "primary" as const, label: copy.primary }]
            : []),
        { type: "secondary" as const, label: copy.secondary },
    ];

    return (
        <Dialog
            open={open}
            onClose={dismiss}
            maxWidth={false}
            aria-labelledby={titleID}
            aria-describedby={copy.description ? descriptionID : undefined}
            sx={{ "--space-dialog-backdrop": "rgba(0 0 0 / 0.64)" }}
            slotProps={{
                paper: {
                    sx: {
                        bgcolor: spaceDialogBackground,
                        borderRadius: "28px 28px 0 0",
                        bottom: 0,
                        boxShadow: "none",
                        boxSizing: "border-box",
                        left: 0,
                        m: 0,
                        maxWidth: "none",
                        p: "26px 20px max(24px, env(safe-area-inset-bottom))",
                        position: "fixed",
                        width: "100vw",
                        "@media (min-width: 600px)": {
                            borderRadius: "20px",
                            bottom: "auto",
                            left: "50%",
                            maxWidth: 363,
                            top: "50%",
                            transform: "translate(-50%, -50%)",
                            width: 363,
                        },
                    },
                },
                transition: { onExited: onClose },
            }}
        >
            <Box
                sx={{
                    maxWidth: 320,
                    mx: "auto",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: "none" },
                }}
            >
                <Box
                    component="h2"
                    id={titleID}
                    sx={{
                        color: spaceText,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 15,
                        fontWeight: 600,
                        lineHeight: "20px",
                        m: 0,
                        overflowWrap: "anywhere",
                        px: "20px",
                        textAlign: "center",
                    }}
                >
                    {copy.title}
                </Box>
                {copy.description && (
                    <Box
                        id={descriptionID}
                        sx={{
                            color: spaceTextMuted,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            lineHeight: "18px",
                            mt: "8px",
                            overflowWrap: "anywhere",
                            px: "20px",
                            textAlign: "center",
                        }}
                    >
                        {copy.description}
                    </Box>
                )}
                <Box sx={{ display: "grid", gap: "12px", mt: "20px" }}>
                    {actions.map(({ type, label }) => {
                        const phase =
                            action?.type == type ? action.phase : null;
                        return (
                            <Box
                                key={type}
                                component="button"
                                type="button"
                                className={
                                    type == "primary" ? "green-bg" : undefined
                                }
                                aria-label={phase == "done" ? copy.done : label}
                                aria-busy={phase == "busy"}
                                aria-live="polite"
                                disabled={action !== null}
                                onClick={() => void updateRequest(type)}
                                sx={{
                                    alignItems: "center",
                                    bgcolor:
                                        type == "primary"
                                            ? green
                                            : spaceControlBackgroundHover,
                                    border: 0,
                                    borderRadius: "24px",
                                    color: spaceText,
                                    cursor: action ? "default" : "pointer",
                                    display: "flex",
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 14,
                                    fontWeight: 600,
                                    height: 48,
                                    justifyContent: "center",
                                    p: "0 20px",
                                    "&:hover:not(:disabled)": {
                                        filter: "brightness(1.08)",
                                    },
                                    "&:focus-visible": {
                                        outline: `2px solid ${green}`,
                                        outlineOffset: 2,
                                    },
                                }}
                            >
                                {phase ? (
                                    <SpaceActionFeedbackIcon phase={phase} />
                                ) : (
                                    label
                                )}
                            </Box>
                        );
                    })}
                </Box>
                {errorMessage && (
                    <Box
                        role="alert"
                        sx={{
                            color: spaceDanger,
                            fontSize: 13,
                            mt: "12px",
                            textAlign: "center",
                        }}
                    >
                        {errorMessage}
                    </Box>
                )}
            </Box>
        </Dialog>
    );
};
