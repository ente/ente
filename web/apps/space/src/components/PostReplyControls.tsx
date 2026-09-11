import {
    FavouriteIcon,
    Loading03Icon,
    Navigation03Icon,
    Tick02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { keyframes } from "@mui/material/styles";
import type { SpaceActionPhase } from "components/ActionFeedback";
import {
    spacePostLikeButtonPop,
    spacePostLikeHeartPop,
    spacePostLikePopDurationMs,
    spacePostLikePopTiming,
} from "components/post-like-animation";
import React from "react";

const green = "#08C225";
const textBase = "#F4F4F4";
const textSecondary = "#A6A6A6";
const controlBackground = "#36363A";
const controlBackgroundHover = "#404044";
const controlBackgroundActive = "#48484D";
const controlIcon = "#D8D8D8";
export const spacePostReplyInputMinHeight = 48;
const replyInputPadding = 14;
const replyInputPaddingLeft = 18;
const captionInputMaxHeight = 112;
const postButtonSpin = keyframes`from { transform: rotate(0deg); } to { transform: rotate(360deg); }`;

const viewerActionButtonSx = {
    alignItems: "center",
    bgcolor: controlBackground,
    border: 0,
    borderRadius: "50%",
    color: controlIcon,
    cursor: "pointer",
    display: "flex",
    height: 48,
    justifyContent: "center",
    p: 0,
    width: 48,
    "&:active": { bgcolor: controlBackgroundActive },
    "&:focus-visible": { outline: `2px solid ${green}`, outlineOffset: 2 },
    "&:hover": { bgcolor: controlBackgroundHover },
};

interface SpacePostReplyControlsProps {
    canSendReply: boolean;
    disabled?: boolean;
    isLikePending?: boolean;
    isReplyMode: boolean;
    liked: boolean;
    likePopID: number;
    onLike: () => void;
    onSendReply: () => void;
    replyActionPhase: SpaceActionPhase | null;
    replyInputProps?: React.TextareaHTMLAttributes<HTMLTextAreaElement>;
    replyInputRef?: React.RefObject<HTMLTextAreaElement | null>;
}

export const SpacePostReplyControls: React.FC<SpacePostReplyControlsProps> = ({
    canSendReply,
    disabled = false,
    isLikePending = false,
    isReplyMode,
    liked,
    likePopID,
    onLike,
    onSendReply,
    replyActionPhase,
    replyInputProps,
    replyInputRef: externalReplyInputRef,
}) => {
    const internalReplyInputRef = React.useRef<HTMLTextAreaElement | null>(
        null,
    );
    const replyInputRef = externalReplyInputRef ?? internalReplyInputRef;
    const isLikePopping = !isReplyMode && liked && likePopID > 0;
    const isSendActive = isReplyMode && canSendReply;
    React.useLayoutEffect(() => {
        const input = replyInputRef.current;
        if (!input) return;
        input.style.height = `${spacePostReplyInputMinHeight}px`;
        input.style.height = `${Math.max(spacePostReplyInputMinHeight, Math.min(input.scrollHeight, captionInputMaxHeight))}px`;
        input.style.overflowY =
            input.scrollHeight > captionInputMaxHeight ? "auto" : "hidden";
    }, [replyInputRef, replyInputProps?.value]);
    return (
        <Box
            sx={{
                alignItems: "flex-end",
                display: "flex",
                gap: "8px",
                justifyContent: "flex-end",
                width: "100%",
            }}
        >
            {replyInputProps && (
                <Box
                    ref={replyInputRef}
                    component="textarea"
                    aria-label="Reply to post"
                    disabled={disabled || replyActionPhase != null}
                    placeholder="Reply..."
                    rows={1}
                    {...replyInputProps}
                    sx={{
                        bgcolor: controlBackground,
                        border: 0,
                        borderRadius: `${spacePostReplyInputMinHeight / 2}px`,
                        boxSizing: "border-box",
                        color: textBase,
                        flex: "1 1 auto",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 14,
                        fontWeight: 500,
                        lineHeight: "20px",
                        maxHeight: captionInputMaxHeight,
                        minHeight: spacePostReplyInputMinHeight,
                        minWidth: 0,
                        outline: 0,
                        overflow: "hidden",
                        pb: `${replyInputPadding}px`,
                        pl: `${replyInputPaddingLeft}px`,
                        pr: `${replyInputPadding}px`,
                        pt: `${replyInputPadding}px`,
                        resize: "none",
                        "&::placeholder": { color: textSecondary },
                        "&:disabled": { opacity: 0.74 },
                        "&:focus": { bgcolor: controlBackgroundHover },
                    }}
                />
            )}
            <Box
                sx={{
                    flexShrink: 0,
                    height: 48,
                    position: "relative",
                    width: 48,
                }}
            >
                <Box
                    component="button"
                    type="button"
                    className={isSendActive ? "green-bg" : undefined}
                    aria-label={
                        isReplyMode
                            ? replyActionPhase == "busy"
                                ? "Sending reply"
                                : replyActionPhase == "done"
                                  ? "Reply sent"
                                  : "Send reply"
                            : liked
                              ? "Unlike photo"
                              : "Like photo"
                    }
                    aria-pressed={isReplyMode ? undefined : liked}
                    aria-disabled={
                        isReplyMode && !canSendReply ? true : undefined
                    }
                    disabled={disabled || (!isReplyMode && isLikePending)}
                    onClick={isReplyMode ? onSendReply : onLike}
                    onPointerDown={
                        isReplyMode
                            ? (event) => event.preventDefault()
                            : undefined
                    }
                    sx={{
                        ...viewerActionButtonSx,
                        animation: isLikePopping
                            ? `${spacePostLikeButtonPop} ${spacePostLikePopDurationMs}ms ${spacePostLikePopTiming} both`
                            : undefined,
                        bgcolor: isSendActive ? green : controlBackground,
                        color: isReplyMode ? "#FFFFFF" : controlIcon,
                        cursor:
                            isReplyMode && !canSendReply
                                ? "default"
                                : "pointer",
                        touchAction: "manipulation",
                        userSelect: "none",
                        WebkitTouchCallout: "none",
                        WebkitUserSelect: "none",
                        "&:hover": {
                            bgcolor: isSendActive
                                ? "#07AE22"
                                : isReplyMode
                                  ? controlBackground
                                  : controlBackgroundHover,
                        },
                        "&:active": {
                            bgcolor: isSendActive
                                ? "#069B1E"
                                : controlBackgroundActive,
                        },
                        "@media (prefers-reduced-motion: reduce)": {
                            animation: "none",
                        },
                    }}
                >
                    {isReplyMode ? (
                        replyActionPhase == "busy" ? (
                            <Box
                                component="span"
                                sx={{
                                    animation: `${postButtonSpin} 2.4s linear infinite`,
                                    display: "flex",
                                    lineHeight: 0,
                                }}
                            >
                                <HugeiconsIcon
                                    icon={Loading03Icon}
                                    size={22}
                                    strokeWidth={1.8}
                                />
                            </Box>
                        ) : replyActionPhase == "done" ? (
                            <HugeiconsIcon
                                icon={Tick02Icon}
                                primaryColor={green}
                                size={22}
                                strokeWidth={1.8}
                            />
                        ) : (
                            <HugeiconsIcon
                                icon={Navigation03Icon}
                                size={24}
                                strokeWidth={1.8}
                                style={{ transform: "translate(-1px, 1px)" }}
                            />
                        )
                    ) : (
                        <Box
                            key={isLikePopping ? `heart-${likePopID}` : "heart"}
                            component="span"
                            sx={{
                                animation: isLikePopping
                                    ? `${spacePostLikeHeartPop} ${spacePostLikePopDurationMs}ms ${spacePostLikePopTiming} both`
                                    : undefined,
                                display: "flex",
                                lineHeight: 0,
                                transformOrigin: "50% 58%",
                                "@media (prefers-reduced-motion: reduce)": {
                                    animation: "none",
                                },
                            }}
                        >
                            <HugeiconsIcon
                                fill={liked ? green : "none"}
                                icon={FavouriteIcon}
                                primaryColor={liked ? green : undefined}
                                size={26}
                                strokeWidth={1.8}
                            />
                        </Box>
                    )}
                </Box>
            </Box>
        </Box>
    );
};
