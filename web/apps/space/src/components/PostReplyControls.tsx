import {
    FavouriteIcon,
    Loading03Icon,
    Navigation03Icon,
    Tick02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Collapse, useMediaQuery } from "@mui/material";
import { keyframes } from "@mui/material/styles";
import type { SpaceActionPhase } from "components/ActionFeedback";
import {
    spacePostLikeButtonPop,
    spacePostLikeHeartPop,
    spacePostLikePopDurationMs,
    spacePostLikePopTiming,
} from "components/post-like-animation";
import { SpacePostLikeHeart } from "components/PostLikeHeart";
import React from "react";
import {
    spaceControlBackground,
    spaceControlBackgroundHover,
    spaceMenuHover,
    spaceText,
} from "styles/colors";

const green = "#08C225";
const textBase = spaceText;
const textSecondary = "#C4C4C8";
const controlBackground = spaceControlBackground;
const controlBackgroundHover = spaceControlBackgroundHover;
const controlBackgroundActive = spaceMenuHover;
const controlIcon = spaceText;
const spacePostReplyInputMinHeight = 48;
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

export const SpacePostInputButton: React.FC<{
    backgroundColor?: string;
    hoverBackgroundColor?: string;
    disabled?: boolean;
    label: string;
    placeholder: string;
    onClick: () => void;
}> = ({
    backgroundColor = controlBackground,
    hoverBackgroundColor = controlBackgroundHover,
    disabled,
    label,
    placeholder,
    onClick,
}) => (
    <Box
        component="button"
        type="button"
        aria-label={label}
        title={label}
        disabled={disabled}
        onClick={onClick}
        sx={{
            ...viewerActionButtonSx,
            bgcolor: backgroundColor,
            borderRadius: "24px",
            color: textSecondary,
            display: "block",
            flex: "1 1 auto",
            font: "inherit",
            fontSize: 14,
            fontWeight: 400,
            lineHeight: "20px",
            minWidth: 0,
            overflow: "hidden",
            px: `${replyInputPaddingLeft}px`,
            textAlign: "left",
            textOverflow: "ellipsis",
            whiteSpace: "nowrap",
            width: "auto",
            "&:disabled": { cursor: "default" },
            "&:hover": { bgcolor: hoverBackgroundColor },
        }}
    >
        {placeholder}
    </Box>
);

interface SpacePostReplyControlsProps {
    ref?: React.Ref<HTMLDivElement>;
    canSendReply: boolean;
    commentsButton?: React.ReactNode;
    disabled?: boolean;
    isLikePending?: boolean;
    isReplyMode: boolean;
    liked: boolean;
    likePopID: number;
    likeToggleID: number;
    postKey: string;
    onBlur?: React.FocusEventHandler<HTMLDivElement>;
    onLike: () => void;
    onSendReply: () => void;
    replyActionPhase: SpaceActionPhase | null;
    replyInputProps?: React.TextareaHTMLAttributes<HTMLTextAreaElement>;
    replyInputRef?: React.RefObject<HTMLTextAreaElement | null>;
}

export const SpacePostReplyControls: React.FC<SpacePostReplyControlsProps> = ({
    ref,
    canSendReply,
    commentsButton,
    disabled = false,
    isLikePending = false,
    isReplyMode,
    liked,
    likePopID,
    likeToggleID,
    postKey,
    onBlur,
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
    const prefersReducedMotion = useMediaQuery(
        "(prefers-reduced-motion: reduce)",
    );
    React.useLayoutEffect(() => {
        const input = replyInputRef.current;
        if (!input) return;
        const resize = () => {
            input.style.height = `${spacePostReplyInputMinHeight}px`;
            input.style.overflowY = "hidden";
            if (!isReplyMode) return;
            input.style.height = `${Math.max(spacePostReplyInputMinHeight, Math.min(input.scrollHeight, captionInputMaxHeight))}px`;
            input.style.overflowY =
                input.scrollHeight > captionInputMaxHeight ? "auto" : "hidden";
        };
        resize();
        let width = input.clientWidth;
        const observer = new ResizeObserver(() => {
            if (input.clientWidth == width) return;
            width = input.clientWidth;
            resize();
        });
        observer.observe(input);
        return () => observer.disconnect();
    }, [isReplyMode, replyInputRef, replyInputProps?.value]);
    return (
        <Box
            ref={ref}
            onBlur={onBlur}
            sx={{
                alignItems: "flex-end",
                display: "flex",
                justifyContent: "flex-end",
                width: "100%",
            }}
        >
            {replyInputProps && (
                <Box
                    ref={replyInputRef}
                    component="textarea"
                    aria-label="Reply privately"
                    disabled={disabled || replyActionPhase != null}
                    placeholder="Reply privately…"
                    rows={1}
                    {...replyInputProps}
                    sx={{
                        bgcolor: controlBackground,
                        border: 0,
                        borderRadius: "24px",
                        boxSizing: "border-box",
                        color: textBase,
                        flex: "1 1 auto",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 14,
                        fontWeight: 400,
                        lineHeight: "20px",
                        maxHeight: captionInputMaxHeight,
                        minHeight: spacePostReplyInputMinHeight,
                        minWidth: 0,
                        mr: 1,
                        outline: 0,
                        overflow: "hidden",
                        pb: `${replyInputPadding}px`,
                        pl: `${replyInputPaddingLeft}px`,
                        pr: `${replyInputPadding}px`,
                        pt: `${replyInputPadding}px`,
                        resize: "none",
                        textOverflow: isReplyMode ? "clip" : "ellipsis",
                        whiteSpace: isReplyMode ? "pre-wrap" : "nowrap",
                        "&::placeholder": { color: textSecondary },
                        "&:disabled": { opacity: 0.74 },
                        "&:focus": { bgcolor: controlBackgroundHover },
                    }}
                />
            )}
            {commentsButton && (
                <Collapse
                    in={!isReplyMode}
                    inert={isReplyMode}
                    orientation="horizontal"
                    timeout={prefersReducedMotion ? 0 : 220}
                    easing="cubic-bezier(0.22, 1, 0.36, 1)"
                    sx={{
                        flexShrink: 0,
                        opacity: isReplyMode ? 0 : 1,
                        transitionProperty: "width, opacity",
                    }}
                >
                    <Box sx={{ pr: 1 }}>{commentsButton}</Box>
                </Collapse>
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
                        <SpacePostLikeHeart
                            key={postKey}
                            liked={liked}
                            toggleID={likeToggleID}
                            popID={likePopID}
                            size={26}
                            fallback={
                                <Box
                                    key={
                                        isLikePopping
                                            ? `heart-${likePopID}`
                                            : "heart"
                                    }
                                    component="span"
                                    sx={{
                                        animation: isLikePopping
                                            ? `${spacePostLikeHeartPop} ${spacePostLikePopDurationMs}ms ${spacePostLikePopTiming} both`
                                            : undefined,
                                        display: "flex",
                                        lineHeight: 0,
                                        transformOrigin: "50% 58%",
                                        "@media (prefers-reduced-motion: reduce)":
                                            { animation: "none" },
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
                            }
                        />
                    )}
                </Box>
            </Box>
        </Box>
    );
};
