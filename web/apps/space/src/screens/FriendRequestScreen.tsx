import { ArrowLeft02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import log from "ente-base/log";
import React from "react";
import { spaceEmptyStateButtonSx } from "styles/buttons";
import {
    spaceAppBackgroundColor,
    spaceControlBackground,
    spaceText,
    spaceTextMuted,
} from "styles/colors";

interface FriendRequestScreenProps {
    username: string;
    onBack: () => void;
    onAddFriend: () => Promise<"friend" | "requested">;
}

export const FriendRequestScreen: React.FC<FriendRequestScreenProps> = ({
    username,
    onBack,
    onAddFriend,
}) => {
    const [phase, setPhase] = React.useState<"sending" | "sent">();
    const [failed, setFailed] = React.useState(false);

    const addFriend = async () => {
        setPhase("sending");
        setFailed(false);
        try {
            if ((await onAddFriend()) == "requested") setPhase("sent");
        } catch (error) {
            log.error("Failed to send friend request", error);
            setFailed(true);
            setPhase(undefined);
        }
    };

    return (
        <Box
            sx={{
                bgcolor: spaceAppBackgroundColor,
                color: spaceText,
                minHeight: "var(--space-page-height, 100svh)",
                pt: "env(safe-area-inset-top)",
            }}
        >
            <Box
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    minHeight:
                        "calc(var(--space-page-height, 100svh) - env(safe-area-inset-top))",
                    mx: "auto",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <Box
                    component="header"
                    sx={{
                        alignItems: "center",
                        display: "grid",
                        flexShrink: 0,
                        gridTemplateColumns: "44px 1fr 44px",
                        height: 56,
                        px: 2,
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label="Back"
                        onClick={onBack}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            borderRadius: "50%",
                            color: spaceText,
                            cursor: "pointer",
                            display: "flex",
                            height: 44,
                            justifyContent: "flex-start",
                            ml: "-2px",
                            p: 0,
                            width: 44,
                            "&:focus-visible": { outline: "2px solid #08C225" },
                        }}
                    >
                        <HugeiconsIcon
                            icon={ArrowLeft02Icon}
                            size={24}
                            strokeWidth={1.8}
                        />
                    </Box>
                    <Box
                        component="h1"
                        sx={{
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 18,
                            fontWeight: 700,
                            justifySelf: "center",
                            lineHeight: "24px",
                            m: 0,
                        }}
                    >
                        Add friend
                    </Box>
                </Box>
                <Box
                    component="main"
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        flex: 1,
                        flexDirection: "column",
                        justifyContent: "center",
                        px: 3,
                        py: 4,
                        textAlign: "center",
                    }}
                >
                    <Box
                        component="h2"
                        sx={{
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 24,
                            fontWeight: 700,
                            lineHeight: "32px",
                            m: 0,
                            maxWidth: "100%",
                            overflowWrap: "anywhere",
                        }}
                    >
                        @{username}
                    </Box>
                    <Box aria-live="polite" sx={{ mt: "24px" }}>
                        <Box
                            component="button"
                            type="button"
                            disabled={Boolean(phase)}
                            aria-busy={phase == "sending"}
                            onClick={() => void addFriend()}
                            sx={{
                                ...spaceEmptyStateButtonSx,
                                minWidth: 144,
                                ...(phase == "sent" && {
                                    bgcolor: spaceControlBackground,
                                    color: spaceTextMuted,
                                    "&:disabled": { opacity: 1 },
                                }),
                            }}
                        >
                            {phase == "sent"
                                ? "Request sent"
                                : "Send friend request"}
                        </Box>
                    </Box>
                    {failed && (
                        <Box
                            role="alert"
                            sx={{
                                color: spaceTextMuted,
                                fontSize: 14,
                                lineHeight: "20px",
                                mt: "16px",
                            }}
                        >
                            Couldn&apos;t send your request. Try again.
                        </Box>
                    )}
                </Box>
            </Box>
        </Box>
    );
};
