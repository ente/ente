import { Box, Dialog, useMediaQuery } from "@mui/material";
import {
    SpaceActionFeedbackIcon,
    spaceActionDoneDurationMs,
} from "components/ActionFeedback";
import { SpaceBottomSheetTransition } from "components/BottomSheetTransition";
import { SpaceShareInviteButton } from "components/ShareInviteButton";
import type { FriendProfile } from "data/friends";
import log from "ente-base/log";
import React from "react";
import {
    normalizeSpaceUsername,
    spaceUsernameValidationError,
} from "services/profile";
import type { SpaceFriendRequest } from "services/space";
import {
    spaceOnAccent,
    spaceSurface,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import {
    friendRequestErrorMessage,
    isSpaceFriendLimitError,
} from "utils/friend-errors";
import {
    maximumSpaceFriendCount,
    spaceFriendLimitMessage,
} from "utils/friend-limits";

const green = "#08C225";
const dangerColor = "#F63A3A";

interface SpaceAddFriendDialogProps {
    friendRequests: SpaceFriendRequest[];
    friends: FriendProfile[];
    onAddFriend: (username: string) => Promise<"friend" | "requested">;
    onClose: () => void;
    open: boolean;
    profileLink?: string;
    username: string;
}

export const SpaceAddFriendDialog: React.FC<SpaceAddFriendDialogProps> = ({
    friendRequests,
    friends,
    onAddFriend,
    onClose,
    open,
    profileLink,
    username: currentUsername,
}) => {
    const titleID = React.useId();
    const isBottomSheet = useMediaQuery("(max-width: 599px)");
    const [username, setUsername] = React.useState("");
    const [isSubmitting, setIsSubmitting] = React.useState(false);
    const [isSent, setIsSent] = React.useState(false);
    const [errorMessage, setErrorMessage] = React.useState<string>();
    const [isSharing, setIsSharing] = React.useState(false);
    const [shareErrorMessage, setShareErrorMessage] = React.useState<string>();

    const submit = () => {
        if (isSubmitting || isSent) return;

        const normalizedUsername = normalizeSpaceUsername(username);
        const validationError = normalizedUsername
            ? spaceUsernameValidationError(normalizedUsername)
            : "Enter a username.";
        if (validationError) {
            setErrorMessage(validationError);
            return;
        }
        if (normalizedUsername == normalizeSpaceUsername(currentUsername)) {
            setErrorMessage("You can't add yourself as a friend.");
            return;
        }
        if (
            friends.some(
                (friend) =>
                    normalizeSpaceUsername(friend.username) ==
                    normalizedUsername,
            )
        ) {
            setErrorMessage(
                `You're already friends with @${normalizedUsername}.`,
            );
            return;
        }
        if (
            friendRequests.some(
                (request) =>
                    request.direction == "sent" &&
                    normalizeSpaceUsername(request.friend.username) ==
                        normalizedUsername,
            )
        ) {
            setErrorMessage(
                `Friend request already sent to @${normalizedUsername}.`,
            );
            return;
        }
        const sentRequestCount = friendRequests.filter(
            (request) => request.direction == "sent",
        ).length;
        if (friends.length + sentRequestCount >= maximumSpaceFriendCount) {
            setErrorMessage(spaceFriendLimitMessage);
            return;
        }

        setErrorMessage(undefined);
        setIsSubmitting(true);
        void onAddFriend(normalizedUsername)
            .then(() => setIsSent(true))
            .catch((error: unknown) => {
                if (!isSpaceFriendLimitError(error)) {
                    log.error("Failed to send space friend request", error);
                }
                setErrorMessage(
                    friendRequestErrorMessage(error, normalizedUsername),
                );
            })
            .finally(() => setIsSubmitting(false));
    };

    React.useEffect(() => {
        if (!open || !isSent) return;

        const timeoutID = window.setTimeout(onClose, spaceActionDoneDurationMs);
        return () => window.clearTimeout(timeoutID);
    }, [isSent, onClose, open]);

    return (
        <Dialog
            open={open}
            onClose={isSubmitting ? undefined : onClose}
            maxWidth={false}
            aria-labelledby={titleID}
            slots={
                isBottomSheet
                    ? { transition: SpaceBottomSheetTransition }
                    : undefined
            }
            slotProps={{
                paper: {
                    sx: {
                        borderRadius: "28px 28px 0 0",
                        bottom: 0,
                        boxShadow: "none",
                        boxSizing: "border-box",
                        left: 0,
                        m: 0,
                        maxWidth: "none",
                        p: "26px 20px 24px",
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
                transition: {
                    onExited: () => {
                        setUsername("");
                        setIsSent(false);
                        setErrorMessage(undefined);
                        setShareErrorMessage(undefined);
                    },
                },
            }}
        >
            <Box
                component="form"
                noValidate
                onSubmit={(event) => {
                    event.preventDefault();
                    submit();
                }}
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
                        px: "20px",
                        textAlign: "center",
                    }}
                >
                    Add a friend
                </Box>
                <Box
                    sx={{
                        color: spaceTextMuted,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 13,
                        lineHeight: "18px",
                        mt: "8px",
                        textAlign: "center",
                    }}
                >
                    Enter your friend&apos;s username to add them on Space
                </Box>
                <Box
                    component="label"
                    sx={{ display: "block", mt: "20px", width: "100%" }}
                >
                    <Box
                        sx={{
                            alignItems: "center",
                            bgcolor: spaceSurface,
                            border: `1px solid ${errorMessage ? dangerColor : "transparent"}`,
                            borderRadius: "14px",
                            display: "flex",
                            height: 48,
                            px: "14px",
                            width: "100%",
                            "&:focus-within": {
                                borderColor: green,
                                boxShadow: `0 0 0 1px ${green}`,
                            },
                        }}
                    >
                        <Box
                            component="span"
                            aria-hidden
                            sx={{
                                color: spaceTextMuted,
                                flexShrink: 0,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 600,
                            }}
                        >
                            @
                        </Box>
                        <Box
                            component="input"
                            autoCapitalize="none"
                            autoComplete="off"
                            autoCorrect="off"
                            autoFocus
                            aria-label="Friend's username"
                            aria-invalid={Boolean(errorMessage) || undefined}
                            disabled={isSubmitting || isSent}
                            onChange={(
                                event: React.ChangeEvent<HTMLInputElement>,
                            ) => {
                                const value = event.target.value;
                                setUsername(
                                    value.startsWith("@")
                                        ? value.slice(1)
                                        : value,
                                );
                                setErrorMessage(undefined);
                            }}
                            placeholder="username"
                            spellCheck={false}
                            value={username}
                            sx={{
                                bgcolor: "transparent",
                                border: 0,
                                color: spaceText,
                                flex: 1,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 500,
                                height: "100%",
                                minWidth: 0,
                                outline: 0,
                                p: 0,
                                "&::placeholder": {
                                    color: spaceTextMuted,
                                    opacity: 1,
                                },
                            }}
                        />
                    </Box>
                </Box>
                {errorMessage && (
                    <Box
                        role="alert"
                        sx={{
                            color: dangerColor,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            fontWeight: 600,
                            lineHeight: "18px",
                            mt: "8px",
                            textAlign: "center",
                        }}
                    >
                        {errorMessage}
                    </Box>
                )}
                <Box
                    className="green-bg"
                    component="button"
                    type="submit"
                    disabled={isSubmitting || isSent}
                    sx={{
                        alignItems: "center",
                        bgcolor: green,
                        border: 0,
                        borderRadius: "20px",
                        color: spaceOnAccent,
                        cursor: isSubmitting || isSent ? "default" : "pointer",
                        display: "flex",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 14,
                        fontWeight: 600,
                        height: 48,
                        justifyContent: "center",
                        lineHeight: "20px",
                        mt: "20px",
                        px: "24px",
                        width: "100%",
                        "&:disabled": { opacity: isSent ? 1 : 0.6 },
                        "&:focus-visible": {
                            outline: `2px solid ${green}`,
                            outlineOffset: 2,
                        },
                    }}
                >
                    {isSubmitting ? (
                        <SpaceActionFeedbackIcon phase="busy" />
                    ) : isSent ? (
                        <SpaceActionFeedbackIcon phase="done" />
                    ) : (
                        "Send request"
                    )}
                </Box>
                {profileLink && (
                    <Box sx={{ mt: "12px", textAlign: "center" }}>
                        <SpaceShareInviteButton
                            disabled={isSubmitting || isSent}
                            profileLink={profileLink}
                            sharing={isSharing}
                            variant="text"
                            onSharingChange={(sharing) => {
                                setIsSharing(sharing);
                                if (sharing) setShareErrorMessage(undefined);
                            }}
                            onShareError={(error) => {
                                log.error(
                                    "Failed to share Space invite link",
                                    error,
                                );
                                setShareErrorMessage(
                                    "Couldn't share the invite link. Please try again.",
                                );
                            }}
                        />
                        {shareErrorMessage && (
                            <Box
                                role="alert"
                                sx={{
                                    color: dangerColor,
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 13,
                                    fontWeight: 600,
                                    lineHeight: "18px",
                                }}
                            >
                                {shareErrorMessage}
                            </Box>
                        )}
                    </Box>
                )}
            </Box>
        </Dialog>
    );
};
