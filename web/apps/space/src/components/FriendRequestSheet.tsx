import { Box, Dialog } from "@mui/material";
import {
    spaceActionDoneDurationMs,
    SpaceActionFeedbackIcon,
    type SpaceActionPhase,
} from "components/ActionFeedback";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import type { SpaceFriendRequest } from "services/space";
import {
    spaceControlBackgroundHover,
    spaceDanger,
    spaceDialogBackground,
    spaceText,
    spaceTextMuted,
} from "styles/colors";

const green = "#08C225";

interface FriendRequestSheetProps {
    request: SpaceFriendRequest;
    onAccept: (requestID: number) => Promise<boolean>;
    onDelete: (requestID: number) => Promise<void>;
    onClose: () => void;
}

export const FriendRequestSheet: React.FC<FriendRequestSheetProps> = ({
    request,
    onAccept,
    onDelete,
    onClose,
}) => {
    const [open, setOpen] = React.useState(true);
    const [action, setAction] = React.useState<{
        type: "accept" | "delete";
        phase: SpaceActionPhase;
    } | null>(null);
    const [failed, setFailed] = React.useState(false);
    const titleID = React.useId();
    const descriptionID = React.useId();
    const isIncoming = request.direction == "received";
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

    const updateRequest = async (type: "accept" | "delete") => {
        if (action) return;
        setAction({ type, phase: "busy" });
        setFailed(false);
        try {
            if (type == "accept") {
                const accepted = await onAccept(request.requestId);
                if (accepted) setAction({ type, phase: "done" });
                else setOpen(false);
            } else {
                await onDelete(request.requestId);
                setOpen(false);
            }
        } catch (error) {
            log.error("Failed to update friend request", error);
            setAction(null);
            setFailed(true);
        }
    };

    const actions = [
        ...(isIncoming ? [{ type: "accept" as const, label: "Accept" }] : []),
        {
            type: "delete" as const,
            label: isIncoming ? "Decline" : "Cancel request",
        },
    ];

    return (
        <Dialog
            open={open}
            onClose={dismiss}
            maxWidth={false}
            aria-labelledby={titleID}
            aria-describedby={descriptionID}
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
                    {isIncoming
                        ? `Be friends with @${request.friend.username}?`
                        : `Waiting for @${request.friend.username}`}
                </Box>
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
                    {isIncoming
                        ? "Share photos, and keep up with each other."
                        : "You’ll see their posts once they accept."}
                </Box>
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
                                    type == "accept" ? "green-bg" : undefined
                                }
                                aria-label={
                                    phase == "done" ? "Request accepted" : label
                                }
                                aria-busy={phase == "busy"}
                                aria-live="polite"
                                disabled={action !== null}
                                onClick={() => void updateRequest(type)}
                                sx={{
                                    alignItems: "center",
                                    bgcolor:
                                        type == "accept"
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
                {failed && (
                    <Box
                        role="alert"
                        sx={{
                            color: spaceDanger,
                            fontSize: 13,
                            mt: "12px",
                            textAlign: "center",
                        }}
                    >
                        Couldn&apos;t update the request. Please try again.
                    </Box>
                )}
            </Box>
        </Dialog>
    );
};
