import { Box } from "@mui/material";
import type { SpaceActionPhase } from "components/ActionFeedback";
import { spacePostLikePopDurationMs } from "components/post-like-animation";
import {
    SpacePostReplyControls,
    spacePostReplyInputMinHeight,
} from "components/PostReplyControls";
import log from "ente-base/log";
import React from "react";
import { spaceSurface, spaceTextMuted } from "styles/colors";
import {
    spaceProfilePostRadius,
    spaceTileCornerStyles,
    spaceTilePillInset,
} from "styles/tiles";
import { clampSpaceMessageText } from "utils/message-limits";

interface ProfileLatestPostProps {
    caption?: string;
    children: React.ReactNode;
    disabled: boolean;
    liked: boolean;
    onReply?: (text: string) => Promise<void>;
    onSetLiked?: (liked: boolean) => Promise<void>;
}

export const ProfileLatestPost: React.FC<ProfileLatestPostProps> = ({
    caption,
    children,
    disabled,
    liked,
    onReply,
    onSetLiked,
}) => {
    const [isLikePending, setIsLikePending] = React.useState(false);
    const [likePopID, setLikePopID] = React.useState(0);
    const [replyText, setReplyText] = React.useState("");
    const [isReplyFocused, setIsReplyFocused] = React.useState(false);
    const [replyActionPhase, setReplyActionPhase] =
        React.useState<SpaceActionPhase | null>(null);
    const [errorMessage, setErrorMessage] = React.useState<string>();
    const replyInputRef = React.useRef<HTMLTextAreaElement | null>(null);
    const isReplyMode = Boolean(
        onReply && (isReplyFocused || replyText.trim() || replyActionPhase),
    );
    const canSendReply = Boolean(
        onReply && replyText.trim() && !replyActionPhase && !disabled,
    );

    React.useEffect(() => {
        if (likePopID == 0) return;
        const timeoutID = window.setTimeout(
            () => setLikePopID(0),
            spacePostLikePopDurationMs,
        );
        return () => window.clearTimeout(timeoutID);
    }, [likePopID]);

    React.useEffect(() => {
        if (replyActionPhase != "done") return;
        const timeoutID = window.setTimeout(() => {
            setReplyActionPhase(null);
            setIsReplyFocused(false);
            replyInputRef.current?.blur();
        }, 1000);
        return () => window.clearTimeout(timeoutID);
    }, [replyActionPhase]);

    const toggleLike = async () => {
        if (!onSetLiked || isLikePending || disabled) return;
        setIsLikePending(true);
        setErrorMessage(undefined);
        if (!liked) setLikePopID((id) => id + 1);
        try {
            await onSetLiked(!liked);
        } catch (error) {
            log.error("Failed to update latest post like", error);
            setErrorMessage("Couldn't update like. Try again.");
        } finally {
            setIsLikePending(false);
        }
    };

    const sendReply = async () => {
        if (!onReply || !canSendReply) return;
        setReplyActionPhase("busy");
        setErrorMessage(undefined);
        try {
            await onReply(replyText.trim());
            setReplyText("");
            setReplyActionPhase("done");
        } catch (error) {
            log.error("Failed to reply to latest post", error);
            setReplyActionPhase(null);
            setErrorMessage("Couldn't send reply. Try again.");
        }
    };

    return (
        <Box
            component="article"
            aria-label="Latest post"
            sx={{
                ...spaceTileCornerStyles(spaceProfilePostRadius),
                bgcolor: spaceSurface,
                minWidth: 0,
                overflow: "hidden",
                width: "100%",
            }}
        >
            <Box
                sx={{
                    borderRadius: "var(--space-tile-radius)",
                    display: "flex",
                    overflow: "hidden",
                    position: "relative",
                }}
            >
                {children}
                {!disabled && caption?.trim() && (
                    <Box
                        title={caption}
                        sx={{
                            bottom: 20,
                            clipPath: "inset(-2px -7px 0)",
                            color: "#FFFFFF",
                            display: "-webkit-box",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            fontWeight: 650,
                            left: "50%",
                            lineHeight: "19px",
                            maxWidth: "78%",
                            overflowWrap: "anywhere",
                            pointerEvents: "none",
                            position: "absolute",
                            textAlign: "center",
                            textShadow: "0 1px 10px rgba(0, 0, 0, 0.74)",
                            textWrap: "balance",
                            transform: "translateX(-50%)",
                            WebkitBoxOrient: "vertical",
                            WebkitLineClamp: 2,
                            width: "max-content",
                        }}
                    >
                        <Box
                            component="span"
                            sx={{
                                bgcolor: "rgba(48, 48, 48, 0.79)",
                                borderRadius: "5px",
                                boxDecorationBreak: "clone",
                                px: "7px",
                                py: "2px",
                                WebkitBoxDecorationBreak: "clone",
                            }}
                        >
                            {caption.trim()}
                        </Box>
                    </Box>
                )}
            </Box>
            {(onReply || onSetLiked) && (
                <Box
                    sx={{ p: spaceTilePillInset(spacePostReplyInputMinHeight) }}
                >
                    <SpacePostReplyControls
                        canSendReply={canSendReply}
                        disabled={disabled}
                        isLikePending={isLikePending}
                        isReplyMode={isReplyMode}
                        liked={liked}
                        likePopID={likePopID}
                        onLike={() => void toggleLike()}
                        onSendReply={() => void sendReply()}
                        replyActionPhase={replyActionPhase}
                        replyInputRef={replyInputRef}
                        replyInputProps={
                            onReply
                                ? {
                                      onBlur: () => setIsReplyFocused(false),
                                      onFocus: () => setIsReplyFocused(true),
                                      onChange: (event) =>
                                          setReplyText(
                                              clampSpaceMessageText(
                                                  event.target.value,
                                              ),
                                          ),
                                      onKeyDown: (event) => {
                                          if (
                                              event.key != "Enter" ||
                                              event.shiftKey ||
                                              event.nativeEvent.isComposing
                                          )
                                              return;
                                          event.preventDefault();
                                          void sendReply();
                                      },
                                      value: replyText,
                                  }
                                : undefined
                        }
                    />
                    {errorMessage && (
                        <Box
                            role="alert"
                            sx={{
                                color: spaceTextMuted,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 13,
                                mt: "8px",
                            }}
                        >
                            {errorMessage}
                        </Box>
                    )}
                </Box>
            )}
        </Box>
    );
};
