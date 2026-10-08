import {
    ArrowDown01Icon,
    ArrowLeft02Icon,
    Cancel01Icon,
    FavouriteIcon,
    ImageDelete02Icon,
    Navigation03Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    alpha,
    Box,
    ClickAwayListener,
    Grow,
    MenuItem,
    MenuList,
    Popper,
    useMediaQuery,
} from "@mui/material";
import { SpaceActionToast } from "components/ActionToast";
import {
    SpaceActivityAvatar as Avatar,
    SpaceActivityIdentity,
} from "components/ActivityList";
import { SpaceLiveStatus } from "components/LiveStatus";
import {
    MessageQuickReactions,
    MessageReactionPicker,
} from "components/MessageReactionPicker";
import { SpaceMessageText } from "components/MessageText";
import {
    SpacePostPhotosBadge,
    SpacePostVideoBadge,
} from "components/PostPhotosBadge";
import { SpacePostPreviewThumbnail } from "components/PostPreviewThumbnail";
import { SpaceLoadingSpinner } from "components/RouteFallback";
import { SpaceShareInviteButton } from "components/ShareInviteButton";
import { SpaceSkipLink } from "components/SkipLink";
import { emojiName } from "data/emojis";
import log from "ente-base/log";
import React from "react";
import { flushSync } from "react-dom";
import type { SetupProfile } from "screens/SetupProfileScreen";
import type {
    SpaceMessage,
    SpaceMessageActivityPost,
    SpaceMessageConversation,
    SpaceMessageQuote,
} from "services/space";
import {
    spaceActivityListSx,
    spaceActivityPreviewSx,
    spaceActivityRowSx,
} from "styles/activity-list";
import {
    spaceAppBackground,
    spaceAppBackgroundColor,
    spaceDialogBackground,
    spaceMenuBackground,
    spaceMenuHover,
    spaceOnAccent,
    spaceSurface,
    spaceSurfaceHover,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";
import { firstNameFrom } from "utils/display";
import { clampSpaceMessageText } from "utils/message-limits";
import { spacePostDeletedEvent } from "utils/post-events";
import { postQuoteErrorState, postQuoteKey } from "utils/post-quote";

const green = "#08C225";
const textBase = spaceText;
const textSecondary = spaceTextMuted;
const composerSurface = spaceSurface;
const outgoingBubble = "#176B2A";
const incomingBubble = spaceSurface;
const outgoingMessageText = "#FFFFFF";
const incomingMessageText = spaceText;
const conversationPrimaryText = spaceText;
const outgoingQuoteBubble = "#213425";
const incomingQuoteBubble = spaceSurfaceHover;
const incomingQuoteText = spaceTextMuted;
const quoteRule = "#666666";
const dangerColor = "#F63A3A";
const composerHeight = 48;
const composerMaxHeight = 112;
const messageBubblePaddingX = "16px";
const messageBubblePaddingY = "14px";
const composerPadding = 14;
const composerPaddingLeft = 18;
const postQuoteThumbnailSize = 200;
const threadBottomThresholdPx = 96;
const messageGroupTimeThresholdMs = 10 * 60 * 1000;
const messageTimeSeparatorThresholdMs = 60 * 60 * 1000;
const messageLongPressMs = 520;
const messageLongPressMoveTolerancePx = 10;
const messageReplySwipeThresholdPx = 64;
const messageReplySwipeMinThresholdPx = 20;
const messageActionsTouchOpenMouseSuppressMs = 900;
interface MessagesScreenProps {
    conversations: SpaceMessageConversation[];
    friendsCount?: number;
    isConversationsLoading?: boolean;
    isThreadLoading?: boolean;
    isThreadReadOnly?: boolean;
    isThreadRecipientLoading?: boolean;
    messages: SpaceMessage[];
    onCloseThread: () => void;
    onDeleteMessage: (messageId: string) => Promise<void>;
    onOpenSelectedFriendProfile: (
        friend: SpaceMessageConversation["friend"],
    ) => void;
    onOpenQuotePost: (quote: SpaceMessageQuote) => void;
    onOpenThread: (conversation: SpaceMessageConversation) => void;
    onLoadActivityPost?: (
        post: SpaceMessageActivityPost,
    ) => Promise<SpaceMessageActivityPost | undefined>;
    onReplyToMessage: (
        spaceId: string,
        messageId: string,
        text: string,
    ) => Promise<void>;
    onSendMessage: (spaceId: string, text: string) => Promise<void>;
    onSetMessageReaction: (
        messageId: string,
        emoji: string | undefined,
    ) => Promise<void>;
    profileLink?: string;
    profile: SetupProfile;
    selectedFriend?: SpaceMessageConversation["friend"];
    threadBackLabel?: string;
}

interface MessageContextMenuState {
    anchorEl: HTMLElement;
    anchorOffset?: { x: number; y: number };
    message: SpaceMessage;
    open: boolean;
}

type MessageActionsOpenSource = "button" | "contextmenu" | "touch";

const resizeComposer = (input: HTMLTextAreaElement | null) => {
    if (!input) return;

    input.style.height = `${composerHeight}px`;
    const nextHeight = Math.min(input.scrollHeight, composerMaxHeight);
    input.style.height = `${Math.max(composerHeight, nextHeight)}px`;
    input.style.overflowY =
        input.scrollHeight > composerMaxHeight ? "auto" : "hidden";
};

const isThreadNearBottom = (scroller: HTMLDivElement) =>
    scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight <=
    threadBottomThresholdPx;

const copyTextToClipboard = async (text: string) => {
    await navigator.clipboard.writeText(text);
};

const truncateMessageText = (text: string): string => {
    const lines = text.split("\n");
    const firstLine = lines[0] ?? text;
    if (firstLine.length > 100) return `${firstLine.slice(0, 100)}...`;
    return lines.length > 1 ? `${firstLine}...` : firstLine;
};

const isCurrentProfileMessage = (
    message: SpaceMessage,
    profile: SetupProfile,
) => isCurrentProfileActor(message.sender, profile);

const isCurrentProfileActor = (
    actor: SpaceMessage["sender"],
    profile: SetupProfile,
) => {
    if (actor.spaceId && profile.spaceId) {
        return actor.spaceId == profile.spaceId;
    }
    if (actor.spaceSlug && profile.spaceSlug) {
        return actor.spaceSlug == profile.spaceSlug;
    }
    return actor.username == profile.username;
};

const conversationPreview = (conversation: SpaceMessageConversation) => {
    const activity = conversation.latestActivity;
    if (activity.isUnavailable) return "Message unavailable";
    if (activity.type == "empty") {
        return "No messages yet";
    }
    const text = activity.text ? truncateMessageText(activity.text) : "";
    if (activity.type == "post_reply") {
        if (text) {
            return activity.outgoing ? `You: ${text}` : text;
        }
        return "Replied";
    }
    if (activity.type == "message_like") {
        return text
            ? activity.outgoing
                ? `You reacted ${activity.reaction ?? ""} to "${text}"`
                : `Reacted ${activity.reaction ?? ""} to "${text}"`
            : activity.outgoing
              ? `You reacted ${activity.reaction ?? ""} to a message`
              : `Reacted ${activity.reaction ?? ""} to a message`;
    }
    if (activity.kind == "poke") {
        return activity.outgoing
            ? `You poked ${firstNameFrom(conversation.friend.fullName.trim() || conversation.friend.username)}`
            : "Poked you";
    }
    if (text) {
        return activity.outgoing ? `You: ${text}` : text;
    }

    return activity.outgoing ? "You sent a message" : "Message";
};

const ConversationPreviewLine: React.FC<{
    conversation: SpaceMessageConversation;
}> = ({ conversation }) => {
    const activity = conversation.latestActivity;
    const previewLineSx = spaceActivityPreviewSx;

    if (activity.type == "message_like" && activity.text) {
        return (
            <Box sx={{ ...previewLineSx, display: "flex" }}>
                <Box component="span" sx={{ flexShrink: 0 }}>
                    {`${activity.outgoing ? "You reacted" : "Reacted"} ${activity.reaction ?? ""} to "`}
                </Box>
                <Box
                    component="span"
                    sx={{
                        minWidth: 0,
                        overflow: "hidden",
                        textOverflow: "ellipsis",
                    }}
                >
                    {truncateMessageText(activity.text)}
                </Box>
                <Box component="span" sx={{ flexShrink: 0 }}>
                    &quot;
                </Box>
            </Box>
        );
    }

    return <Box sx={previewLineSx}>{conversationPreview(conversation)}</Box>;
};

const conversationId = (conversation: SpaceMessageConversation) =>
    conversation.friend.spaceId ?? conversation.friend.id;

const conversationUnreadLabel = (count: number) =>
    count > 99 ? "99+" : String(count);

const isSameLocalDate = (first: Date, second: Date) =>
    first.getFullYear() == second.getFullYear() &&
    first.getMonth() == second.getMonth() &&
    first.getDate() == second.getDate();

const monthLabels = [
    "JAN",
    "FEB",
    "MAR",
    "APR",
    "MAY",
    "JUN",
    "JUL",
    "AUG",
    "SEP",
    "OCT",
    "NOV",
    "DEC",
] as const;

const messageTimeLabel = (timestampMs: number) =>
    new Intl.DateTimeFormat("en-US", {
        hour: "numeric",
        hour12: true,
        minute: "2-digit",
    }).format(new Date(timestampMs));

const messageDateTimeLabel = (timestampMs: number) => {
    const date = new Date(timestampMs);
    const now = new Date();
    if (isSameLocalDate(date, now)) return messageTimeLabel(timestampMs);

    return `${date.getDate()} ${monthLabels[date.getMonth()]}, ${messageTimeLabel(timestampMs)}`;
};

const shouldShowMessageTimeSeparator = (
    lastSeparatorMessage: SpaceMessage | undefined,
    previousMessage: SpaceMessage | undefined,
    message: SpaceMessage,
) => {
    if (!lastSeparatorMessage || !previousMessage) return true;

    const separatorDate = new Date(lastSeparatorMessage.createdAtMs);
    const messageDate = new Date(message.createdAtMs);
    if (!isSameLocalDate(separatorDate, messageDate)) return true;

    return (
        message.createdAtMs - lastSeparatorMessage.createdAtMs >=
        messageTimeSeparatorThresholdMs
    );
};

const MessageTimeSeparator: React.FC<{ timestampMs: number }> = ({
    timestampMs,
}) => (
    <Box
        component="li"
        sx={{
            color: textSecondary,
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 12,
            fontWeight: 500,
            lineHeight: "16px",
            listStyle: "none",
            py: "32px",
            textAlign: "center",
        }}
    >
        <Box component="time" dateTime={new Date(timestampMs).toISOString()}>
            {messageDateTimeLabel(timestampMs)}
        </Box>
    </Box>
);

const ConversationListItem: React.FC<{
    activityPost?: SpaceMessageActivityPost;
    conversation: SpaceMessageConversation;
    onLoadActivityPost?: (post: SpaceMessageActivityPost) => void;
    onOpenFriendProfile: (friend: SpaceMessageConversation["friend"]) => void;
    onOpenThread: (conversation: SpaceMessageConversation) => void;
}> = ({
    activityPost,
    conversation,
    onLoadActivityPost,
    onOpenFriendProfile,
    onOpenThread,
}) => {
    const name =
        conversation.friend.fullName.trim() || conversation.friend.username;
    const post = conversation.latestActivity.post;
    const showPostThumbnailSlot = Boolean(post);
    const unreadCount = conversation.unreadCount;
    React.useEffect(() => {
        if (!post || post.isUnavailable || post.imageUrl || activityPost) {
            return;
        }
        onLoadActivityPost?.(post);
    }, [
        activityPost,
        onLoadActivityPost,
        post,
        post?.imageUrl,
        post?.isUnavailable,
    ]);

    return (
        <Box component="li" sx={{ listStyle: "none" }}>
            <Box
                sx={{
                    ...spaceActivityRowSx,
                    gridTemplateColumns: "44px minmax(0, 1fr)",
                    "&:has(> [data-space-row-action]:active)": {
                        bgcolor: "transparent",
                    },
                    "&:has(> [data-space-row-action]:hover)": {
                        bgcolor: "transparent",
                    },
                }}
            >
                <Box
                    sx={{
                        flexShrink: 0,
                        height: 44,
                        position: "relative",
                        width: 44,
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label={`Open ${name}'s profile`}
                        onClick={() => onOpenFriendProfile(conversation.friend)}
                        sx={{
                            appearance: "none",
                            bgcolor: "transparent",
                            border: 0,
                            borderRadius: "50%",
                            cursor: "pointer",
                            display: "block",
                            height: 44,
                            p: 0,
                            width: 44,
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <Avatar
                            avatarUrl={conversation.friend.avatarUrl}
                            size={44}
                        />
                    </Box>
                    {unreadCount > 0 && (
                        <Box
                            aria-label={`${unreadCount} unread update${unreadCount == 1 ? "" : "s"}`}
                            component="span"
                            sx={{
                                alignItems: "center",
                                bgcolor: dangerColor,
                                borderRadius: "8px",
                                boxShadow: `0 0 0 2px ${spaceAppBackgroundColor}`,
                                color: spaceOnAccent,
                                display: "inline-flex",
                                flexShrink: 0,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 10,
                                fontWeight: 700,
                                height: 16,
                                justifyContent: "center",
                                lineHeight: "16px",
                                minWidth: 16,
                                position: "absolute",
                                pointerEvents: "none",
                                px: "4px",
                                right: -2,
                                top: -2,
                                zIndex: 1,
                            }}
                        >
                            {conversationUnreadLabel(unreadCount)}
                        </Box>
                    )}
                </Box>
                <Box
                    component="button"
                    type="button"
                    aria-label={`Open conversation with ${name}`}
                    onClick={() => onOpenThread(conversation)}
                    sx={{
                        alignItems: "center",
                        appearance: "none",
                        bgcolor: "transparent",
                        border: 0,
                        color: "inherit",
                        cursor: "pointer",
                        display: "grid",
                        gap: "10px",
                        gridColumn: "2 / -1",
                        gridTemplateColumns: showPostThumbnailSlot
                            ? "minmax(0, 1fr) 44px"
                            : "minmax(0, 1fr)",
                        minWidth: 0,
                        p: 0,
                        textAlign: "left",
                        width: "100%",
                        "&:focus-visible": {
                            borderRadius: "8px",
                            outline: `2px solid ${green}`,
                            outlineOffset: 2,
                        },
                    }}
                >
                    <Box sx={{ minWidth: 0 }}>
                        <SpaceActivityIdentity
                            name={firstNameFrom(name)}
                            createdAtMs={
                                conversation.latestActivity.createdAtMs
                            }
                        />
                        <ConversationPreviewLine conversation={conversation} />
                    </Box>
                    {showPostThumbnailSlot && (
                        <SpacePostPreviewThumbnail
                            post={activityPost ?? post}
                        />
                    )}
                </Box>
            </Box>
        </Box>
    );
};

const sameMessageSender = (
    first: SpaceMessage | undefined,
    second: SpaceMessage | undefined,
) => Boolean(first && second && first.sender.spaceId == second.sender.spaceId);

const bodyBubblesCanGroup = (
    first: SpaceMessage | undefined,
    second: SpaceMessage | undefined,
) => {
    if (!first || !second) return false;
    if (!sameMessageSender(first, second)) return false;
    if (first.reaction) return false;
    if (first.kind == "friend_added") return false;
    if (
        (second.kind != "regular" && second.kind != "poke") ||
        second.replyMessageId
    )
        return false;
    if (
        !isSameLocalDate(
            new Date(first.createdAtMs),
            new Date(second.createdAtMs),
        )
    )
        return false;
    return (
        second.createdAtMs - first.createdAtMs <= messageGroupTimeThresholdMs
    );
};

const ReplyIcon: React.FC = () => (
    <svg
        width="12"
        height="9"
        viewBox="0 0 12 9"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            fillRule="evenodd"
            clipRule="evenodd"
            d="M4.5241 0.242677C4.62341 0.34442 4.67919 0.482337 4.67919 0.626134C4.67919 0.76993 4.62341 0.907847 4.5241 1.00959L1.89369 3.70102H7.68483C8.3587 3.70102 9.35854 3.9036 10.2042 4.52653C11.0775 5.17045 11.7507 6.23762 11.7507 7.86116C11.7507 8.00507 11.6948 8.14309 11.5953 8.24485C11.4959 8.34661 11.361 8.40378 11.2203 8.40378C11.0797 8.40378 10.9448 8.34661 10.8453 8.24485C10.7459 8.14309 10.69 8.00507 10.69 7.86116C10.69 6.59069 10.1844 5.84982 9.58481 5.40776C8.95761 4.94544 8.18899 4.78627 7.68483 4.78627H1.89369L4.5241 7.4777C4.5762 7.52738 4.61799 7.58728 4.64698 7.65384C4.67597 7.72041 4.69155 7.79226 4.69281 7.86512C4.69406 7.93798 4.68096 8.01035 4.65429 8.07791C4.62762 8.14548 4.58792 8.20686 4.53756 8.25839C4.4872 8.30991 4.42722 8.35053 4.36118 8.37782C4.29515 8.40512 4.22442 8.41852 4.15321 8.41723C4.082 8.41595 4.01178 8.4 3.94673 8.37034C3.88167 8.34068 3.82313 8.29792 3.77457 8.24461L0.23908 4.6271C0.139767 4.52536 0.0839844 4.38744 0.0839844 4.24364C0.0839844 4.09985 0.139767 3.96193 0.23908 3.86019L3.77457 0.242677C3.87401 0.141061 4.0088 0.0839844 4.14934 0.0839844C4.28987 0.0839844 4.42466 0.141061 4.5241 0.242677Z"
            fill="currentColor"
            stroke="currentColor"
            strokeWidth="0.166667"
        />
    </svg>
);

const DeleteIcon: React.FC = () => (
    <svg
        width="13"
        height="15"
        viewBox="0 0 13 15"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M11.5 2.83203L11.0869 9.51543C10.9813 11.223 10.9285 12.0768 10.5005 12.6906C10.2889 12.9941 10.0165 13.2502 9.70047 13.4427C9.0614 13.832 8.206 13.832 6.49513 13.832C4.78208 13.832 3.92553 13.832 3.28603 13.442C2.96987 13.2492 2.69733 12.9926 2.48579 12.6886C2.05792 12.0738 2.0063 11.2188 1.90307 9.50883L1.5 2.83203M0.5 2.83333H12.5M9.2038 2.83333L8.74873 1.89449C8.4464 1.27084 8.2952 0.959013 8.03447 0.76454C7.97667 0.7214 7.9154 0.683027 7.85133 0.6498C7.5626 0.5 7.21607 0.5 6.523 0.5C5.81253 0.5 5.45733 0.5 5.16379 0.65608C5.09873 0.690673 5.03665 0.7306 4.97819 0.775447C4.71443 0.9778 4.56709 1.30103 4.27241 1.94751L3.86861 2.83333M4.83203 10.166V6.16602M8.16797 10.166V6.16602"
            stroke="currentColor"
            strokeLinecap="round"
        />
    </svg>
);

const CopyIcon: React.FC = () => (
    <svg
        width="14"
        height="14"
        viewBox="0 0 14 14"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M4.5 4.5V2.5C4.5 1.39543 5.39543 0.5 6.5 0.5H11.5C12.6046 0.5 13.5 1.39543 13.5 2.5V7.5C13.5 8.60457 12.6046 9.5 11.5 9.5H9.5M2.5 4.5H7.5C8.60457 4.5 9.5 5.39543 9.5 6.5V11.5C9.5 12.6046 8.60457 13.5 7.5 13.5H2.5C1.39543 13.5 0.5 12.6046 0.5 11.5V6.5C0.5 5.39543 1.39543 4.5 2.5 4.5Z"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
    </svg>
);

const messageActionsTransitionDuration = { enter: 300, exit: 100 };

const MessageActionMenuItem: React.FC<{
    icon: React.ReactNode;
    label: string;
    onClick: () => void;
    tone?: "default" | "danger";
}> = ({ icon, label, onClick, tone = "default" }) => (
    <MenuItem
        disableRipple
        onClick={onClick}
        sx={{
            WebkitTapHighlightColor: "transparent",
            borderRadius: "12px",
            color: tone == "danger" ? dangerColor : textBase,
            gap: "8px",
            minHeight: spaceTouchTargetSize,
            outline: 0,
            px: "8px",
            py: "7px",
            "&.Mui-focusVisible": {
                bgcolor:
                    tone == "danger"
                        ? "rgba(246, 58, 58, 0.14)"
                        : spaceMenuHover,
                outline: 0,
            },
            "&:focus": { outline: 0 },
            "&:focus-visible": { outline: 0 },
            "&:hover": {
                bgcolor:
                    tone == "danger"
                        ? "rgba(246, 58, 58, 0.14)"
                        : spaceMenuHover,
            },
        }}
    >
        {icon}
        <Box
            sx={{
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 13,
                fontWeight: 650,
                lineHeight: "18px",
            }}
        >
            {label}
        </Box>
    </MenuItem>
);

const messageActionsTriggerSize = 24;
const messageActionsTriggerOffset = -6;

const MessageActionsTrigger: React.FC<{
    isOpen: boolean;
    isOwn: boolean;
    onClick: (event: React.MouseEvent<HTMLButtonElement>) => void;
}> = ({ isOpen, isOwn, onClick }) => {
    const iconColor = isOwn ? outgoingMessageText : incomingMessageText;

    return (
        <Box
            component="button"
            type="button"
            data-message-actions-trigger
            aria-expanded={isOpen}
            aria-haspopup="menu"
            aria-label="Message actions"
            tabIndex={-1}
            onClick={onClick}
            onContextMenu={(event) => {
                event.preventDefault();
                onClick(event);
            }}
            sx={{
                WebkitTapHighlightColor: "transparent",
                alignItems: "center",
                bgcolor: isOwn ? outgoingBubble : incomingBubble,
                border: `2px solid ${spaceAppBackgroundColor}`,
                borderRadius: "50%",
                boxSizing: "border-box",
                color: isOpen ? iconColor : alpha(iconColor, 0.72),
                cursor: "pointer",
                display: "none",
                height: messageActionsTriggerSize,
                justifyContent: "center",
                opacity: isOpen ? 1 : 0,
                p: 0,
                position: "absolute",
                top: messageActionsTriggerOffset,
                transform: isOpen ? "none" : "scale(0.8)",
                transition:
                    "opacity 140ms ease, transform 140ms ease, color 140ms ease",
                width: messageActionsTriggerSize,
                zIndex: 2,
                ...(isOwn
                    ? { left: messageActionsTriggerOffset }
                    : { right: messageActionsTriggerOffset }),
                "@media (hover: hover) and (pointer: fine)": {
                    display: "inline-flex",
                },
                "&:hover": { color: iconColor },
                "&:focus-visible": {
                    opacity: 1,
                    outline: `2px solid ${green}`,
                    outlineOffset: 1,
                    transform: "none",
                },
                "& svg": {
                    transform: isOpen ? "rotate(180deg)" : "none",
                    transition: "transform 180ms ease",
                },
                "@media (prefers-reduced-motion: reduce)": {
                    transform: "none",
                    transition: "none",
                    "& svg": { transition: "none" },
                },
            }}
        >
            <HugeiconsIcon
                icon={ArrowDown01Icon}
                primaryColor="currentColor"
                size={14}
                strokeWidth={2}
            />
        </Box>
    );
};

type MessageActionLabelIcon = "like" | "reply";

const MessageActionLabelIconView: React.FC<{
    icon: MessageActionLabelIcon;
    isOwn: boolean;
}> = ({ icon, isOwn }) => (
    <Box
        component="span"
        sx={{
            alignItems: "center",
            display: "inline-flex",
            flexShrink: 0,
            height: 14,
            justifyContent: "center",
            lineHeight: 0,
            ml: isOwn ? 0 : "-5px",
            mr: isOwn ? "-5px" : 0,
            transform: "scale(0.88)",
            width: 14,
        }}
    >
        {icon == "reply" ? (
            <ReplyIcon />
        ) : (
            <HugeiconsIcon
                fill="none"
                icon={FavouriteIcon}
                primaryColor="currentColor"
                size={14}
                strokeWidth={2}
            />
        )}
    </Box>
);

const MessageActionLabel: React.FC<{
    icon: MessageActionLabelIcon;
    isOwn: boolean;
    label: string;
}> = ({ icon, isOwn, label }) => (
    <Box
        sx={{
            alignSelf: isOwn ? "flex-end" : "flex-start",
            alignItems: "center",
            color: textSecondary,
            display: "inline-flex",
            gap: "4px",
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 12,
            fontWeight: 500,
            justifyContent: isOwn ? "flex-end" : "flex-start",
            lineHeight: "16px",
            mb: "5px",
        }}
    >
        {!isOwn && <MessageActionLabelIconView icon={icon} isOwn={isOwn} />}
        <Box component="span">{label}</Box>
        {isOwn && <MessageActionLabelIconView icon={icon} isOwn={isOwn} />}
    </Box>
);

const FriendAddedSystemMessage: React.FC = () => (
    <Box
        sx={{
            alignSelf: "center",
            bgcolor: spaceSurface,
            borderRadius: "999px",
            color: textSecondary,
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 12,
            fontWeight: 600,
            lineHeight: "16px",
            px: "10px",
            py: "5px",
            textAlign: "center",
        }}
    >
        You are now friends
    </Box>
);

const QuoteFrame: React.FC<{
    children: React.ReactNode;
    isOwn: boolean;
    mb?: string;
    subtle?: boolean;
}> = ({ children, isOwn, mb = "8px", subtle = false }) => (
    <Box
        sx={{
            alignItems: "stretch",
            display: "flex",
            flexDirection: isOwn ? "row-reverse" : "row",
            gap: "8px",
            mb,
            maxWidth: "100%",
            minWidth: 0,
            width: "fit-content",
        }}
    >
        <Box
            aria-hidden
            sx={{
                alignSelf: "stretch",
                bgcolor: subtle ? "#444444" : quoteRule,
                borderRadius: "999px",
                flexShrink: 0,
                width: 3,
            }}
        />
        {children}
    </Box>
);

const MessageReplyPreview: React.FC<{
    borderRadius: string;
    isOwn: boolean;
    parentMessage?: SpaceMessage;
    profile: SetupProfile;
}> = ({ borderRadius, isOwn, parentMessage, profile }) => {
    const isDeleted = !parentMessage || parentMessage.isDeleted;
    const parentIsOwn = parentMessage
        ? isCurrentProfileMessage(parentMessage, profile)
        : false;

    return (
        <QuoteFrame isOwn={isOwn} subtle>
            <Box
                sx={{
                    bgcolor: parentIsOwn ? outgoingQuoteBubble : spaceSurface,
                    borderRadius,
                    color: textSecondary,
                    fontFamily: '"Inter Variable", Inter, sans-serif',
                    fontSize: 13,
                    fontWeight: 600,
                    lineHeight: "19px",
                    maxWidth: "100%",
                    minWidth: 0,
                    overflowWrap: "anywhere",
                    px: messageBubblePaddingX,
                    py: messageBubblePaddingY,
                    whiteSpace: "pre-wrap",
                    width: "fit-content",
                }}
            >
                {isDeleted
                    ? "Deleted message"
                    : parentMessage.isUnavailable
                      ? "Message unavailable"
                      : truncateMessageText(parentMessage.text)}
            </Box>
        </QuoteFrame>
    );
};

const PostQuotePreview: React.FC<{
    activityPost?: SpaceMessageActivityPost;
    isOwn: boolean;
    message: SpaceMessage;
    mb?: string;
    onLoadActivityPost?: (post: SpaceMessageActivityPost) => void;
    onOpenQuotePost: (quote: SpaceMessageQuote) => void;
}> = ({
    activityPost,
    isOwn,
    message,
    mb,
    onLoadActivityPost,
    onOpenQuotePost,
}) => {
    const quote = message.quote;
    const preview = activityPost ?? quote;
    const isUnavailable = !quote || Boolean(preview?.isUnavailable);
    const hasLoadError = Boolean(preview?.hasLoadError);
    const retryAt = preview?.retryAt;
    const [now, setNow] = React.useState(Date.now);
    const isRateLimited = retryAt !== undefined && now < retryAt;
    React.useEffect(() => {
        if (retryAt === undefined) return;
        setNow(Date.now());
        const timer = window.setTimeout(
            () => setNow(Date.now()),
            Math.max(0, retryAt - Date.now()),
        );
        return () => window.clearTimeout(timer);
    }, [retryAt]);
    const imageUrl =
        isUnavailable || hasLoadError ? undefined : preview?.imageUrl;
    const photoCount = preview?.photoCount ?? 1;
    const loadedQuote =
        quote && imageUrl ? { ...quote, ...preview, imageUrl } : undefined;
    const isLoading = Boolean(
        quote && !imageUrl && !isUnavailable && !hasLoadError,
    );
    const canOpen = Boolean(loadedQuote);
    const canRetry =
        hasLoadError && !isRateLimited && Boolean(onLoadActivityPost);
    const unavailableLabel =
        quote?.objectKey !== undefined && preview?.photoCount !== undefined
            ? "Photo unavailable"
            : "Post unavailable";

    React.useEffect(() => {
        if (!quote || activityPost || imageUrl || isUnavailable || hasLoadError)
            return;
        onLoadActivityPost?.(quote);
    }, [
        activityPost,
        hasLoadError,
        imageUrl,
        isUnavailable,
        onLoadActivityPost,
        quote,
    ]);

    return (
        <QuoteFrame isOwn={isOwn} mb={mb}>
            <Box
                component={canOpen || canRetry ? "button" : "div"}
                type={canOpen || canRetry ? "button" : undefined}
                aria-label={
                    canOpen
                        ? "Open quoted photo"
                        : canRetry
                          ? "Retry loading post"
                          : undefined
                }
                onClick={(event: React.MouseEvent) => {
                    event.stopPropagation();
                    if (canRetry && quote) onLoadActivityPost?.(quote);
                    else if (loadedQuote) onOpenQuotePost(loadedQuote);
                }}
                sx={{
                    appearance: "none",
                    bgcolor: "transparent",
                    border: 0,
                    borderRadius: "28px",
                    color: "inherit",
                    cursor: canOpen || canRetry ? "pointer" : "default",
                    display: "inline-flex",
                    font: "inherit",
                    overflow: "hidden",
                    p: 0,
                    position: "relative",
                    "&:focus-visible": {
                        outline: `2px solid ${green}`,
                        outlineOffset: 2,
                    },
                }}
            >
                {imageUrl ? (
                    <Box
                        component="img"
                        alt=""
                        src={imageUrl}
                        sx={{
                            display: "block",
                            height: postQuoteThumbnailSize,
                            objectFit: "cover",
                            objectPosition: "center",
                            width: postQuoteThumbnailSize,
                        }}
                    />
                ) : (
                    <Box
                        role="img"
                        aria-label={
                            isLoading
                                ? "Loading photo"
                                : hasLoadError
                                  ? isRateLimited
                                      ? "Couldn't load post. Please try again later."
                                      : "Couldn't load post"
                                  : unavailableLabel
                        }
                        sx={{
                            alignItems: "center",
                            bgcolor: incomingQuoteBubble,
                            color: incomingQuoteText,
                            display: "flex",
                            flexDirection: "column",
                            gap: "8px",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 12,
                            fontWeight: 700,
                            height: postQuoteThumbnailSize,
                            justifyContent: "center",
                            lineHeight: "16px",
                            textAlign: "center",
                            textWrap: "balance",
                            width: postQuoteThumbnailSize,
                            px: "12px",
                        }}
                    >
                        {isUnavailable && (
                            <HugeiconsIcon
                                icon={ImageDelete02Icon}
                                size={28}
                                strokeWidth={1.5}
                            />
                        )}
                        {isUnavailable ? (
                            unavailableLabel
                        ) : hasLoadError ? (
                            isRateLimited ? (
                                "Couldn't load post. Please try again later."
                            ) : (
                                "Couldn't load post. Tap to retry."
                            )
                        ) : (
                            <SpaceLoadingSpinner />
                        )}
                    </Box>
                )}
                {canOpen && <SpacePostPhotosBadge count={photoCount} />}
                {canOpen && (
                    <SpacePostVideoBadge durationMs={loadedQuote?.durationMs} />
                )}
            </Box>
        </QuoteFrame>
    );
};

const isMessageInteractiveTarget = (target: EventTarget | null) =>
    target instanceof Element && Boolean(target.closest("a, button"));

const MessageBubble: React.FC<{
    activityPost?: SpaceMessageActivityPost;
    areActionsOpen: boolean;
    canOpenActions: boolean;
    canReply: boolean;
    friendName: string;
    groupsWithNext: boolean;
    groupsWithPrevious: boolean;
    isHighlighted: boolean;
    message: SpaceMessage;
    onOpenActions: (
        message: SpaceMessage,
        anchorEl: HTMLElement,
        source: MessageActionsOpenSource,
        anchorOffset?: MessageContextMenuState["anchorOffset"],
    ) => void;
    onLoadActivityPost?: (post: SpaceMessageActivityPost) => void;
    onOpenQuotePost: (quote: SpaceMessageQuote) => void;
    onReply: (message: SpaceMessage) => void;
    ownSpaceID?: string;
    parentMessage?: SpaceMessage;
    profile: SetupProfile;
}> = ({
    activityPost,
    areActionsOpen,
    canOpenActions,
    canReply,
    friendName,
    groupsWithNext,
    groupsWithPrevious,
    isHighlighted,
    message,
    onOpenActions,
    onLoadActivityPost,
    onOpenQuotePost,
    onReply,
    ownSpaceID,
    parentMessage,
    profile,
}) => {
    const isOwn = message.sender.spaceId == ownSpaceID;
    const isUnavailable = Boolean(message.isUnavailable);
    const isPoke = !isUnavailable && message.kind == "poke";
    const pokeName = firstNameFrom(friendName);
    const pokeText = isOwn ? `You poked ${pokeName}` : `${pokeName} poked you`;
    const bubbleBorderRadius = isOwn
        ? `20px ${groupsWithPrevious ? "6px" : "20px"} ${groupsWithNext ? "6px" : "20px"} 20px`
        : `${groupsWithPrevious ? "6px" : "20px"} 20px 20px ${groupsWithNext ? "6px" : "20px"}`;
    const isFriendAdded = !isUnavailable && message.kind == "friend_added";
    const isPostReply = !isUnavailable && message.kind == "post_reply";
    const isSystemMessage = isFriendAdded;
    const hasMessageReply = !isUnavailable && Boolean(message.replyMessageId);
    const actionLabel = isPostReply
        ? isOwn
            ? "You replied to a post"
            : "Replied to your post"
        : hasMessageReply
          ? isOwn
              ? "You replied"
              : "Replied to you"
          : undefined;
    const hasBodyBubble = !isSystemMessage;
    const hasActionsTrigger = canOpenActions && !isUnavailable;
    const rowAlignItems = isFriendAdded
        ? "center"
        : isOwn
          ? "flex-end"
          : "flex-start";
    const longPressTimerRef = React.useRef<number | undefined>(undefined);
    const didOpenLongPressRef = React.useRef(false);
    const gestureStartRef = React.useRef<
        | {
              pointerId: number;
              x: number;
              y: number;
              active: boolean;
              thresholdPx: number;
              maxOffsetPx: number;
              resistancePx: number;
          }
        | undefined
    >(undefined);
    const [swipeOffset, setSwipeOffset] = React.useState(0);
    const reactionRef = React.useRef<HTMLSpanElement>(null);
    const previousReactionRef = React.useRef(message.reaction);

    React.useEffect(() => {
        if (previousReactionRef.current == message.reaction) return;
        previousReactionRef.current = message.reaction;
        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches)
            return;
        const animation = reactionRef.current?.animate(
            [
                { opacity: 0, transform: "scale(0.85)" },
                { opacity: 1, transform: "scale(1)" },
            ],
            { duration: 160, easing: "ease-out" },
        );
        return () => animation?.cancel();
    }, [message.reaction]);

    const clearLongPressTimer = React.useCallback(() => {
        if (longPressTimerRef.current == undefined) return;
        window.clearTimeout(longPressTimerRef.current);
        longPressTimerRef.current = undefined;
    }, []);

    const cancelGesture = () => {
        clearLongPressTimer();
        gestureStartRef.current = undefined;
        didOpenLongPressRef.current = false;
        setSwipeOffset(0);
    };

    const openActions = React.useCallback(
        (
            anchorEl: HTMLElement,
            source: MessageActionsOpenSource,
            anchorOffset?: MessageContextMenuState["anchorOffset"],
        ) => {
            if (isSystemMessage || isUnavailable) return;
            clearLongPressTimer();
            setSwipeOffset(0);
            window.getSelection()?.removeAllRanges();
            onOpenActions(message, anchorEl, source, anchorOffset);
        },
        [
            clearLongPressTimer,
            isSystemMessage,
            isUnavailable,
            message,
            onOpenActions,
        ],
    );

    const handleContextMenu = (event: React.MouseEvent<HTMLElement>) => {
        if (
            isSystemMessage ||
            isUnavailable ||
            isMessageInteractiveTarget(event.target)
        )
            return;
        event.preventDefault();
        event.stopPropagation();
        const rect = event.currentTarget.getBoundingClientRect();
        const offset = {
            x: event.clientX - rect.left,
            y: event.clientY - rect.top,
        };
        const isPointerInside =
            offset.x >= 0 &&
            offset.x <= rect.width &&
            offset.y >= 0 &&
            offset.y <= rect.height;
        openActions(
            event.currentTarget,
            "contextmenu",
            isPointerInside && !gestureStartRef.current ? offset : undefined,
        );
    };

    const handlePointerDown = (event: React.PointerEvent<HTMLElement>) => {
        if (event.pointerType != "touch") return;
        if (
            isSystemMessage ||
            isUnavailable ||
            event.button != 0 ||
            gestureStartRef.current ||
            isMessageInteractiveTarget(event.target)
        ) {
            cancelGesture();
            return;
        }

        const rowRect = event.currentTarget
            .closest("li")!
            .getBoundingClientRect();
        const availableRightPx = Math.max(
            0,
            Math.min(window.innerWidth - 8, rowRect.right + 8) - event.clientX,
        );
        const resistancePx = rowRect.width * 0.42;
        gestureStartRef.current = {
            pointerId: event.pointerId,
            x: event.clientX,
            y: event.clientY,
            active: false,
            thresholdPx: Math.min(
                messageReplySwipeThresholdPx,
                Math.max(
                    messageReplySwipeMinThresholdPx,
                    availableRightPx * 0.65,
                ),
                availableRightPx,
            ),
            maxOffsetPx:
                resistancePx * Math.log1p(availableRightPx / resistancePx),
            resistancePx,
        };
        didOpenLongPressRef.current = false;
        event.currentTarget.setPointerCapture(event.pointerId);

        const bubbleElement = event.currentTarget;
        longPressTimerRef.current = window.setTimeout(() => {
            longPressTimerRef.current = undefined;
            didOpenLongPressRef.current = true;
            openActions(bubbleElement, "touch");
        }, messageLongPressMs);
    };

    const handlePointerMove = (event: React.PointerEvent<HTMLElement>) => {
        const start = gestureStartRef.current;
        if (!start) return;
        if (event.pointerId != start.pointerId) return;
        if (didOpenLongPressRef.current) return;
        const dx = event.clientX - start.x;
        const dy = event.clientY - start.y;
        if (Math.hypot(dx, dy) > messageLongPressMoveTolerancePx)
            clearLongPressTimer();
        if (!canReply || isPoke) return;
        if (!start.active) {
            if (
                (Math.abs(dy) > messageLongPressMoveTolerancePx &&
                    Math.abs(dy) >= Math.abs(dx)) ||
                dx < -messageLongPressMoveTolerancePx
            ) {
                gestureStartRef.current = undefined;
                return;
            }
            if (
                dx <= messageLongPressMoveTolerancePx ||
                dx <= Math.abs(dy) * 1.2
            )
                return;
            start.active = true;
        }
        setSwipeOffset(
            Math.min(
                start.maxOffsetPx,
                start.resistancePx *
                    Math.log1p(Math.max(dx, 0) / start.resistancePx),
            ),
        );
    };

    const handlePointerUp = (event: React.PointerEvent<HTMLElement>) => {
        const start = gestureStartRef.current;
        if (!start) return;
        if (event.pointerId != start.pointerId) return;
        clearLongPressTimer();
        gestureStartRef.current = undefined;
        setSwipeOffset(0);
        if (didOpenLongPressRef.current) {
            if (event.cancelable) event.preventDefault();
            event.stopPropagation();
            return;
        }

        if (!start.active) return;
        const dx = event.clientX - start.x;
        const dy = event.clientY - start.y;
        if (dx < start.thresholdPx || dx <= Math.abs(dy) * 1.2) return;
        if (event.cancelable) event.preventDefault();
        event.stopPropagation();
        onReply(message);
    };

    const handleTouchEnd = (event: React.TouchEvent<HTMLElement>) => {
        if (!didOpenLongPressRef.current) return;
        if (event.cancelable) event.preventDefault();
        event.stopPropagation();
        didOpenLongPressRef.current = false;
    };

    const handleActionsTriggerClick = (
        event: React.MouseEvent<HTMLButtonElement>,
    ) => openActions(event.currentTarget, "button");

    React.useEffect(() => clearLongPressTimer, [clearLongPressTimer]);

    return (
        <Box
            component="li"
            sx={{
                alignItems: rowAlignItems,
                display: "flex",
                flexDirection: "column",
                listStyle: "none",
                mb: groupsWithNext ? "6px" : "24px",
                maxWidth: "100%",
                minWidth: 0,
                position: "relative",
                transition: "margin-bottom 180ms ease-out",
                width: "100%",
                zIndex: isHighlighted ? 3 : message.reaction ? 1 : "auto",
                "@media (prefers-reduced-motion: reduce)": {
                    transition: "none",
                },
                "&:hover [data-message-actions-trigger]": {
                    opacity: 1,
                    transform: "none",
                },
            }}
        >
            {isFriendAdded ? (
                <FriendAddedSystemMessage />
            ) : (
                <Box
                    sx={{
                        alignItems: isOwn ? "flex-end" : "flex-start",
                        display: "flex",
                        flexDirection: "column",
                        maxWidth: "min(calc(100vw - 72px), 360px)",
                        position: "relative",
                        width: "fit-content",
                    }}
                >
                    {actionLabel && (
                        <MessageActionLabel
                            icon="reply"
                            isOwn={isOwn}
                            label={actionLabel}
                        />
                    )}
                    {hasMessageReply && (
                        <MessageReplyPreview
                            borderRadius={bubbleBorderRadius}
                            isOwn={isOwn}
                            parentMessage={parentMessage}
                            profile={profile}
                        />
                    )}
                    {isPostReply && (
                        <PostQuotePreview
                            activityPost={activityPost}
                            isOwn={isOwn}
                            mb={hasBodyBubble ? "8px" : "0"}
                            message={message}
                            onLoadActivityPost={onLoadActivityPost}
                            onOpenQuotePost={onOpenQuotePost}
                        />
                    )}
                    {hasBodyBubble && (
                        <Box sx={{ maxWidth: "100%", position: "relative" }}>
                            {canReply && !isUnavailable && !isPoke && (
                                <Box
                                    aria-hidden
                                    sx={{
                                        alignItems: "center",
                                        color: "#888888",
                                        display: "flex",
                                        height: "100%",
                                        justifyContent: "center",
                                        left: 0,
                                        opacity: Math.min(swipeOffset / 24, 1),
                                        position: "absolute",
                                        top: 0,
                                        width: 40,
                                        "& svg": { height: 12, width: 16 },
                                    }}
                                >
                                    <ReplyIcon />
                                </Box>
                            )}
                            <Box
                                data-message-bubble
                                tabIndex={isUnavailable ? undefined : 0}
                                onKeyDown={(
                                    event: React.KeyboardEvent<HTMLElement>,
                                ) => {
                                    if (
                                        isMessageInteractiveTarget(event.target)
                                    )
                                        return;
                                    if (
                                        event.key == "ContextMenu" ||
                                        (event.shiftKey && event.key == "F10")
                                    ) {
                                        event.preventDefault();
                                        openActions(
                                            event.currentTarget,
                                            "contextmenu",
                                        );
                                    }
                                }}
                                onContextMenu={handleContextMenu}
                                onPointerCancel={cancelGesture}
                                onPointerDown={handlePointerDown}
                                onPointerMove={handlePointerMove}
                                onPointerUp={handlePointerUp}
                                onTouchEnd={handleTouchEnd}
                                sx={{
                                    bgcolor: isOwn
                                        ? outgoingBubble
                                        : incomingBubble,
                                    borderRadius: bubbleBorderRadius,
                                    "&:focus-visible": {
                                        outline: `2px solid ${green}`,
                                        outlineOffset: 2,
                                    },
                                    color: isOwn
                                        ? outgoingMessageText
                                        : incomingMessageText,
                                    cursor: isUnavailable
                                        ? "default"
                                        : "context-menu",
                                    display: "block",
                                    maxWidth: "100%",
                                    minWidth: message.reaction ? 48 : 0,
                                    ml: 0,
                                    overflow: "visible",
                                    position: "relative",
                                    px: messageBubblePaddingX,
                                    py: messageBubblePaddingY,
                                    textAlign: "left",
                                    touchAction: "pan-y",
                                    transform: `translateX(${swipeOffset}px)`,
                                    transition:
                                        swipeOffset > 0
                                            ? "border-radius 180ms ease-out"
                                            : "transform 160ms ease-out, border-radius 180ms ease-out",
                                    "@media (prefers-reduced-motion: reduce)": {
                                        transition: "none",
                                    },
                                    userSelect: "none",
                                    WebkitTouchCallout: "none",
                                    WebkitUserSelect: "none",
                                    width: "fit-content",
                                    "& *": {
                                        userSelect: "none",
                                        WebkitTouchCallout: "none",
                                        WebkitUserSelect: "none",
                                    },
                                }}
                            >
                                <Box
                                    sx={{
                                        color: isOwn
                                            ? outgoingMessageText
                                            : incomingMessageText,
                                        fontFamily:
                                            '"Inter Variable", Inter, sans-serif',
                                        fontStyle:
                                            isUnavailable || isPoke
                                                ? "italic"
                                                : "normal",
                                        fontSize: 14,
                                        fontWeight: 600,
                                        lineHeight: "21px",
                                        overflowWrap: "anywhere",
                                        whiteSpace: "pre-wrap",
                                    }}
                                >
                                    {isUnavailable ? (
                                        "Message unavailable"
                                    ) : isPoke ? (
                                        pokeText
                                    ) : (
                                        <SpaceMessageText text={message.text} />
                                    )}
                                </Box>
                                {!isUnavailable && message.reaction && (
                                    <Box
                                        ref={reactionRef}
                                        component="span"
                                        role="img"
                                        aria-label={`Reaction: ${emojiName(message.reaction)}`}
                                        sx={{
                                            alignItems: "center",
                                            bottom: -16,
                                            bgcolor: spaceDialogBackground,
                                            border: `2px solid ${spaceAppBackgroundColor}`,
                                            borderRadius: "12px",
                                            fontFamily:
                                                '"Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif',
                                            fontSize: 15,
                                            minHeight: 25,
                                            minWidth: 29,
                                            pt: "2px",
                                            px: "3px",
                                            color: green,
                                            display: "inline-flex",
                                            justifyContent: "center",
                                            lineHeight: 1,
                                            pointerEvents: "none",
                                            position: "absolute",
                                            zIndex: 2,
                                            ...(isOwn
                                                ? { right: 14 }
                                                : { left: 14 }),
                                        }}
                                    >
                                        {message.reaction}
                                    </Box>
                                )}
                                {hasActionsTrigger && (
                                    <MessageActionsTrigger
                                        isOpen={areActionsOpen}
                                        isOwn={isOwn}
                                        onClick={handleActionsTriggerClick}
                                    />
                                )}
                            </Box>
                        </Box>
                    )}
                </Box>
            )}
        </Box>
    );
};

export const MessagesScreen: React.FC<MessagesScreenProps> = ({
    conversations,
    friendsCount,
    isConversationsLoading = false,
    isThreadLoading = false,
    isThreadReadOnly = false,
    isThreadRecipientLoading = false,
    messages,
    onCloseThread,
    onDeleteMessage,
    onOpenSelectedFriendProfile,
    onOpenQuotePost,
    onOpenThread,
    onLoadActivityPost,
    onReplyToMessage,
    onSendMessage,
    onSetMessageReaction,
    profile,
    profileLink,
    selectedFriend,
    threadBackLabel = "Back to messages",
}) => {
    const [messageText, setMessageText] = React.useState("");
    const [messageContextMenu, setMessageContextMenu] =
        React.useState<MessageContextMenuState | null>(null);
    const [reactionPickerMessage, setReactionPickerMessage] =
        React.useState<MessageContextMenuState | null>(null);
    const [reactionError, setReactionError] = React.useState(false);
    const [replyingTo, setReplyingTo] = React.useState<SpaceMessage | null>(
        null,
    );
    const [sendPhase, setSendPhase] = React.useState<"idle" | "sending">(
        "idle",
    );
    const [actionStatus, setActionStatus] = React.useState("");
    const [liveThreadID, setLiveThreadID] = React.useState<string>();
    const [isInviteSharing, setIsInviteSharing] = React.useState(false);
    const [activityPostsByKey, setActivityPostsByKey] = React.useState<
        Record<string, SpaceMessageActivityPost>
    >({});
    const composerRef = React.useRef<HTMLTextAreaElement | null>(null);
    const threadScrollRef = React.useRef<HTMLDivElement | null>(null);
    const stickToThreadBottomRef = React.useRef(true);
    const smoothNextMessageScrollRef = React.useRef(false);
    const bottomScrollFrameRef = React.useRef<number | undefined>(undefined);
    const bottomScrollSecondFrameRef = React.useRef<number | undefined>(
        undefined,
    );
    const composerBlurResetTimeoutRef = React.useRef<number | undefined>(
        undefined,
    );
    const ignoreMessageActionsMouseAwayUntilRef = React.useRef(0);
    const activityPostLoadsInFlightRef = React.useRef<Set<string>>(new Set());
    const prefersReducedMotion = useMediaQuery(
        "(prefers-reduced-motion: reduce)",
    );
    const isThreadOpen = Boolean(selectedFriend);
    const canInteract =
        isThreadOpen && !isThreadReadOnly && !isThreadRecipientLoading;
    const canSend =
        canInteract && messageText.trim().length > 0 && sendPhase == "idle";
    const selectedName = selectedFriend
        ? selectedFriend.fullName.trim() || selectedFriend.username
        : "";
    const selectedThreadID = selectedFriend?.spaceId ?? selectedFriend?.id;
    const isThreadBusy = isThreadLoading || isThreadRecipientLoading;
    React.useEffect(() => {
        setLiveThreadID(isThreadBusy ? undefined : selectedThreadID);
    }, [isThreadBusy, selectedThreadID]);
    const showInviteEmptyState = friendsCount == 0 && Boolean(profileLink);
    const emptyConversationsCopy =
        friendsCount == 0
            ? "No messages yet. Once you add friends, you'll see their replies and messages here."
            : "No messages yet. You'll see your friends' replies and messages here.";
    const previewGenerationRef = React.useRef(0);
    React.useEffect(() => {
        const cancelPreviewLoads = () => {
            previewGenerationRef.current++;
            activityPostLoadsInFlightRef.current.clear();
        };
        const invalidatePreviews = () => {
            cancelPreviewLoads();
            setActivityPostsByKey({});
        };
        const onVisibilityChange = () => {
            if (document.visibilityState == "visible") invalidatePreviews();
        };
        invalidatePreviews();
        window.addEventListener("focus", invalidatePreviews);
        window.addEventListener("online", invalidatePreviews);
        window.addEventListener(spacePostDeletedEvent, invalidatePreviews);
        document.addEventListener("visibilitychange", onVisibilityChange);
        return () => {
            cancelPreviewLoads();
            window.removeEventListener("focus", invalidatePreviews);
            window.removeEventListener("online", invalidatePreviews);
            window.removeEventListener(
                spacePostDeletedEvent,
                invalidatePreviews,
            );
            document.removeEventListener(
                "visibilitychange",
                onVisibilityChange,
            );
        };
    }, [selectedFriend?.id]);
    const loadActivityPost = React.useCallback(
        (post: SpaceMessageActivityPost) => {
            if (!onLoadActivityPost) return;
            const key = postQuoteKey(post);
            const cached = activityPostsByKey[key];
            if (
                (cached && !cached.hasLoadError) ||
                (cached?.retryAt !== undefined &&
                    Date.now() < cached.retryAt) ||
                activityPostLoadsInFlightRef.current.has(key)
            )
                return;
            const generation = previewGenerationRef.current;
            activityPostLoadsInFlightRef.current.add(key);
            const target = {
                spaceId: post.spaceId,
                postId: post.postId,
                objectKey: post.objectKey,
            };
            setActivityPostsByKey((posts) => ({ ...posts, [key]: target }));
            const storePreview = (preview: SpaceMessageActivityPost) => {
                if (generation != previewGenerationRef.current) return;
                setActivityPostsByKey((posts) => ({
                    ...posts,
                    [key]: preview,
                }));
            };
            void onLoadActivityPost(target)
                .then((loadedPost) =>
                    storePreview(
                        loadedPost ?? { ...target, isUnavailable: true },
                    ),
                )
                .catch((error: unknown) => {
                    log.warn("Failed to load message activity post", error);
                    storePreview({ ...target, ...postQuoteErrorState(error) });
                })
                .finally(() => {
                    if (generation == previewGenerationRef.current)
                        activityPostLoadsInFlightRef.current.delete(key);
                });
        },
        [activityPostsByKey, onLoadActivityPost],
    );
    const visibleMessages = React.useMemo(
        () => messages.filter((message) => message.kind != "friend_added"),
        [messages],
    );
    const messageByID = React.useMemo(
        () => new Map(messages.map((message) => [message.id, message])),
        [messages],
    );
    const isContextMessageOwn = Boolean(
        messageContextMenu?.message &&
        isCurrentProfileMessage(messageContextMenu.message, profile),
    );
    const isContextMessagePoke = messageContextMenu?.message.kind == "poke";
    const messageActionsAnchor = React.useMemo(() => {
        if (!messageContextMenu) return null;
        const { anchorEl, anchorOffset } = messageContextMenu;
        if (!anchorOffset) return anchorEl;
        return {
            contextElement: anchorEl,
            getBoundingClientRect: () => {
                const rect = anchorEl.getBoundingClientRect();
                return DOMRect.fromRect({
                    x: rect.left + anchorOffset.x,
                    y: rect.top + anchorOffset.y,
                });
            },
        };
    }, [messageContextMenu]);
    const isMenuBelowBubble =
        messageActionsAnchor instanceof HTMLElement &&
        messageActionsAnchor.hasAttribute("data-message-bubble");

    const sendMessage = () => {
        const text = messageText.trim();
        if (!selectedFriend || !canInteract || !canSend) return;
        const spaceId = selectedFriend.spaceId ?? selectedFriend.id;
        const repliedMessage = replyingTo;
        stickToThreadBottomRef.current = true;
        smoothNextMessageScrollRef.current = true;
        setSendPhase("sending");
        setActionStatus("Sending message");
        setMessageText("");
        setReplyingTo(null);
        const sendPromise = repliedMessage
            ? onReplyToMessage(spaceId, repliedMessage.id, text)
            : onSendMessage(spaceId, text);
        void sendPromise
            .then(() => {
                setSendPhase("idle");
                setActionStatus("Message sent");
            })
            .catch((error: unknown) => {
                smoothNextMessageScrollRef.current = false;
                log.error("Failed to send message", error);
                setMessageText((currentText) => currentText || text);
                setReplyingTo(
                    (currentReplyingTo) => currentReplyingTo ?? repliedMessage,
                );
                setSendPhase("idle");
                setActionStatus(
                    "Couldn't send message. Your draft has been restored. Try again.",
                );
            });
    };

    const canOpenMessageActions = (message: SpaceMessage) =>
        message.kind != "poke" ||
        (canInteract && isCurrentProfileMessage(message, profile));

    const openMessageActions = (
        message: SpaceMessage,
        anchorEl: HTMLElement,
        source: MessageActionsOpenSource,
        anchorOffset?: MessageContextMenuState["anchorOffset"],
    ) => {
        if (!canOpenMessageActions(message)) return;
        if (
            source == "button" &&
            messageContextMenu?.open &&
            messageContextMenu.message.id == message.id
        ) {
            closeMessageActions();
            return;
        }
        ignoreMessageActionsMouseAwayUntilRef.current =
            source == "touch"
                ? Date.now() + messageActionsTouchOpenMouseSuppressMs
                : 0;
        setMessageContextMenu({
            anchorEl,
            anchorOffset,
            message: messageByID.get(message.id) ?? message,
            open: true,
        });
    };

    const closeMessageActions = () =>
        setMessageContextMenu((currentMenu) =>
            currentMenu ? { ...currentMenu, open: false } : null,
        );

    const clearClosedMessageActions = () =>
        setMessageContextMenu((currentMenu) =>
            currentMenu?.open ? currentMenu : null,
        );

    const handleMessageActionsClickAway = (event: MouseEvent | TouchEvent) => {
        if (
            event instanceof MouseEvent &&
            Date.now() < ignoreMessageActionsMouseAwayUntilRef.current
        )
            return;
        if (
            event.target instanceof Element &&
            event.target.closest("[data-message-actions-trigger]")
        )
            return;

        closeMessageActions();
    };

    const handleMessageActionsKeyDown = (
        event: React.KeyboardEvent<HTMLElement>,
    ) => {
        if (event.key != "Escape" && event.key != "Tab") return;
        event.preventDefault();
        event.stopPropagation();
        closeMessageActions();
    };

    const startReply = (message: SpaceMessage) => {
        if (!canInteract) return;
        flushSync(() => {
            closeMessageActions();
            setReplyingTo(messageByID.get(message.id) ?? message);
        });
        composerRef.current?.focus();
    };

    const reactToMessage = (message: SpaceMessage, emoji: string) => {
        if (!canInteract || isCurrentProfileMessage(message, profile)) return;
        closeMessageActions();
        setReactionError(false);
        const current = messageByID.get(message.id) ?? message;
        const reaction = current.reaction == emoji ? undefined : emoji;
        void onSetMessageReaction(message.id, reaction)
            .then(() => {
                setActionStatus(
                    reaction
                        ? `Reacted with ${emojiName(reaction)}`
                        : "Reaction removed",
                );
            })
            .catch((error: unknown) => {
                log.error("Failed to update message reaction", error);
                setReactionError(true);
            });
    };

    const handleMessageAction = (action: "copy" | "delete" | "reply") => {
        const targetMessage = messageContextMenu?.message;
        if (!targetMessage) return;
        if (!canInteract && action != "copy") {
            closeMessageActions();
            return;
        }

        switch (action) {
            case "copy":
                closeMessageActions();
                void copyTextToClipboard(targetMessage.text).catch(
                    (error: unknown) =>
                        log.error("Failed to copy message", error),
                );
                break;
            case "reply":
                startReply(targetMessage);
                break;
            case "delete":
                closeMessageActions();
                void onDeleteMessage(targetMessage.id).catch((error: unknown) =>
                    log.error("Failed to delete message", error),
                );
                if (replyingTo?.id == targetMessage.id) {
                    setReplyingTo(null);
                }
                break;
        }
    };

    const scrollThreadToBottom = React.useCallback(
        (behavior: ScrollBehavior = "auto") => {
            const scroller = threadScrollRef.current;
            if (!scroller) return;

            if (behavior == "smooth") {
                scroller.scrollTo({ behavior, top: scroller.scrollHeight });
                return;
            }

            scroller.scrollTop = scroller.scrollHeight;
        },
        [],
    );

    const scheduleThreadBottomScroll = React.useCallback(
        (behavior: ScrollBehavior = "auto") => {
            if (bottomScrollFrameRef.current != undefined) {
                window.cancelAnimationFrame(bottomScrollFrameRef.current);
            }
            if (bottomScrollSecondFrameRef.current != undefined) {
                window.cancelAnimationFrame(bottomScrollSecondFrameRef.current);
            }

            bottomScrollFrameRef.current = window.requestAnimationFrame(() => {
                bottomScrollFrameRef.current = undefined;
                bottomScrollSecondFrameRef.current =
                    window.requestAnimationFrame(() => {
                        bottomScrollSecondFrameRef.current = undefined;
                        scrollThreadToBottom(behavior);
                    });
            });
        },
        [scrollThreadToBottom],
    );

    const handleThreadScroll = () => {
        const scroller = threadScrollRef.current;
        if (!scroller) return;
        stickToThreadBottomRef.current = isThreadNearBottom(scroller);
        if (messageContextMenu?.open) closeMessageActions();
    };

    const handleComposerFocus = () => {
        const scroller = threadScrollRef.current;
        if (scroller && !isThreadNearBottom(scroller)) return;
        stickToThreadBottomRef.current = true;
        scheduleThreadBottomScroll("smooth");
    };

    const handleComposerBlur = () => {
        if (composerBlurResetTimeoutRef.current != undefined) {
            window.clearTimeout(composerBlurResetTimeoutRef.current);
        }

        composerBlurResetTimeoutRef.current = window.setTimeout(() => {
            composerBlurResetTimeoutRef.current = undefined;
            window.scrollTo({ left: 0, top: 0 });
            document.scrollingElement?.scrollTo({ left: 0, top: 0 });
        }, 300);
    };

    React.useLayoutEffect(() => {
        resizeComposer(composerRef.current);
        if (!selectedThreadID || !stickToThreadBottomRef.current) return;
        if (smoothNextMessageScrollRef.current) return;
        scrollThreadToBottom();
    }, [messageText, replyingTo, scrollThreadToBottom, selectedThreadID]);

    React.useEffect(() => {
        setReplyingTo(null);
        setMessageContextMenu(null);
        setReactionPickerMessage(null);
        setReactionError(false);
        setMessageText("");
        stickToThreadBottomRef.current = true;
        smoothNextMessageScrollRef.current = false;
    }, [selectedThreadID]);

    React.useEffect(() => {
        if (!messageContextMenu?.open) return;

        const latestMessage = messageByID.get(messageContextMenu.message.id);
        if (!latestMessage || latestMessage == messageContextMenu.message)
            return;

        setMessageContextMenu((currentMenu) =>
            currentMenu?.open && currentMenu.message.id == latestMessage.id
                ? { ...currentMenu, message: latestMessage }
                : currentMenu,
        );
    }, [
        messageByID,
        messageContextMenu?.message,
        messageContextMenu?.message.id,
        messageContextMenu?.open,
    ]);

    React.useEffect(() => {
        if (!isThreadReadOnly) return;
        setReplyingTo(null);
        setSendPhase("idle");
        setMessageText("");
    }, [isThreadReadOnly]);

    React.useLayoutEffect(() => {
        if (!selectedThreadID || isThreadBusy) return;
        if (!stickToThreadBottomRef.current) return;
        if (smoothNextMessageScrollRef.current) {
            smoothNextMessageScrollRef.current = false;
            scheduleThreadBottomScroll("smooth");
            return;
        }
        scrollThreadToBottom();
    }, [
        isThreadBusy,
        scheduleThreadBottomScroll,
        scrollThreadToBottom,
        selectedThreadID,
        visibleMessages.length,
    ]);

    React.useEffect(
        () => () => {
            if (bottomScrollFrameRef.current != undefined) {
                window.cancelAnimationFrame(bottomScrollFrameRef.current);
            }
            if (bottomScrollSecondFrameRef.current != undefined) {
                window.cancelAnimationFrame(bottomScrollSecondFrameRef.current);
            }
            if (composerBlurResetTimeoutRef.current != undefined) {
                window.clearTimeout(composerBlurResetTimeoutRef.current);
            }
        },
        [],
    );

    const messageActionMenuItems = [
        !isContextMessagePoke && canInteract ? (
            <MessageActionMenuItem
                key="reply"
                icon={<ReplyIcon />}
                label="Reply"
                onClick={() => handleMessageAction("reply")}
            />
        ) : null,
        !isContextMessagePoke ? (
            <MessageActionMenuItem
                key="copy"
                icon={<CopyIcon />}
                label="Copy"
                onClick={() => handleMessageAction("copy")}
            />
        ) : null,
        canInteract && messageContextMenu?.message && isContextMessageOwn ? (
            <MessageActionMenuItem
                key="delete"
                icon={<DeleteIcon />}
                label="Delete"
                onClick={() => handleMessageAction("delete")}
                tone="danger"
            />
        ) : null,
    ].filter((item): item is React.ReactElement => Boolean(item));

    return (
        <>
            <SpaceLiveStatus>{actionStatus}</SpaceLiveStatus>
            {reactionPickerMessage && (
                <MessageReactionPicker
                    selected={
                        messageByID.get(reactionPickerMessage.message.id)
                            ?.reaction
                    }
                    onSelect={(emoji) =>
                        reactToMessage(reactionPickerMessage.message, emoji)
                    }
                    onClose={() => {
                        reactionPickerMessage.anchorEl.focus();
                        setReactionPickerMessage(null);
                    }}
                />
            )}
            {reactionError && (
                <SpaceActionToast
                    animateEntrance
                    closeLabel="Dismiss reaction error"
                    icon={
                        <HugeiconsIcon
                            icon={Cancel01Icon}
                            size={20}
                            color={dangerColor}
                        />
                    }
                    message="Couldn’t update your reaction. Try again."
                    onClose={() => setReactionError(false)}
                    zIndex={1600}
                />
            )}
            <Box
                component="main"
                sx={{
                    background: spaceAppBackground,
                    color: textBase,
                    display: "grid",
                    height: isThreadOpen
                        ? "var(--space-page-height, 100dvh)"
                        : undefined,
                    minHeight: isThreadOpen
                        ? 0
                        : "var(--space-page-height, 100svh)",
                    overflow: isThreadOpen ? "hidden" : undefined,
                    overflowX: "hidden",
                    placeItems: { xs: "stretch", sm: "start center" },
                }}
            >
                <SpaceSkipLink />
                <Box
                    sx={{
                        bgcolor: "transparent",
                        boxSizing: "border-box",
                        display: isThreadOpen ? "grid" : undefined,
                        gridTemplateRows: isThreadOpen
                            ? isThreadReadOnly
                                ? "56px minmax(0, 1fr)"
                                : "56px minmax(0, 1fr) auto"
                            : undefined,
                        height: isThreadOpen ? "100%" : undefined,
                        minHeight: isThreadOpen
                            ? 0
                            : "var(--space-page-height, 100svh)",
                        mx: "auto",
                        overflow: isThreadOpen ? "hidden" : undefined,
                        position: "relative",
                        width: "100%",
                        "@media (min-width: 600px)": { maxWidth: 390 },
                    }}
                >
                    <Box
                        component="header"
                        sx={{
                            alignItems: "center",
                            display: "grid",
                            gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                            height: 56,
                            px: 2,
                            width: "100%",
                        }}
                    >
                        <Box
                            component={isThreadOpen ? "button" : "span"}
                            type={isThreadOpen ? "button" : undefined}
                            aria-hidden={!isThreadOpen || undefined}
                            aria-label={
                                isThreadOpen ? threadBackLabel : undefined
                            }
                            onClick={isThreadOpen ? onCloseThread : undefined}
                            sx={{
                                alignItems: "center",
                                bgcolor: "transparent",
                                border: 0,
                                color: conversationPrimaryText,
                                cursor: isThreadOpen ? "pointer" : undefined,
                                visibility: isThreadOpen ? "visible" : "hidden",
                                display: "flex",
                                height: spaceTouchTargetSize,
                                justifyContent: "flex-start",
                                ml: "-2px",
                                p: 0,
                                width: spaceTouchTargetSize,
                                "&:focus-visible": {
                                    borderRadius: "50%",
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                            }}
                        >
                            <HugeiconsIcon
                                icon={ArrowLeft02Icon}
                                size={24}
                                strokeWidth={1.8}
                            />
                        </Box>
                        {isThreadOpen && selectedFriend ? (
                            <Box
                                component="h1"
                                sx={{
                                    justifySelf: "center",
                                    m: 0,
                                    minWidth: 0,
                                    overflow: "hidden",
                                    textOverflow: "ellipsis",
                                    whiteSpace: "nowrap",
                                }}
                            >
                                <Box
                                    component="button"
                                    type="button"
                                    aria-label={
                                        !canInteract
                                            ? selectedName || "Conversation"
                                            : selectedName
                                              ? `Open ${selectedName}'s profile`
                                              : "Open friend profile"
                                    }
                                    disabled={!canInteract}
                                    onClick={() =>
                                        canInteract &&
                                        onOpenSelectedFriendProfile(
                                            selectedFriend,
                                        )
                                    }
                                    sx={{
                                        appearance: "none",
                                        alignItems: "center",
                                        bgcolor: "transparent",
                                        border: 0,
                                        color: "inherit",
                                        cursor: canInteract
                                            ? "pointer"
                                            : "default",
                                        display: "flex",
                                        fontFamily:
                                            '"Inter Variable", Inter, sans-serif',
                                        fontSize: 18,
                                        fontWeight: 700,
                                        justifyContent: "center",
                                        lineHeight: "24px",
                                        m: 0,
                                        maxWidth: "100%",
                                        minWidth: 0,
                                        overflow: "hidden",
                                        p: 0,
                                        whiteSpace: "nowrap",
                                        "&:focus-visible": {
                                            borderRadius: "18px",
                                            outline: `2px solid ${green}`,
                                            outlineOffset: 3,
                                        },
                                    }}
                                >
                                    <Box
                                        component="span"
                                        sx={{
                                            minWidth: 0,
                                            overflow: "hidden",
                                            textOverflow: "ellipsis",
                                        }}
                                    >
                                        {firstNameFrom(selectedName)}
                                    </Box>
                                </Box>
                            </Box>
                        ) : (
                            <Box
                                component="h1"
                                sx={{
                                    color: "inherit",
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 18,
                                    fontWeight: 700,
                                    justifySelf: "center",
                                    lineHeight: "24px",
                                    m: 0,
                                    minWidth: 0,
                                    overflow: "hidden",
                                    textOverflow: "ellipsis",
                                    whiteSpace: "nowrap",
                                }}
                            >
                                Messages
                            </Box>
                        )}
                        <Box aria-hidden />
                    </Box>

                    {isThreadOpen && selectedFriend ? (
                        <>
                            <Box
                                id="space-main-content"
                                tabIndex={-1}
                                ref={threadScrollRef}
                                role="log"
                                aria-label={`Messages with ${selectedName}`}
                                aria-busy={isThreadBusy}
                                aria-live={
                                    !isThreadBusy &&
                                    liveThreadID == selectedThreadID
                                        ? "polite"
                                        : "off"
                                }
                                aria-relevant="additions text"
                                onScroll={handleThreadScroll}
                                sx={{
                                    boxSizing: "border-box",
                                    minHeight: 0,
                                    overscrollBehaviorY: "contain",
                                    overflowY: "auto",
                                    overflowX: "hidden",
                                    px: "14px",
                                    py: "12px",
                                }}
                            >
                                {isThreadLoading || isThreadRecipientLoading ? (
                                    <Box
                                        sx={{
                                            alignItems: "center",
                                            display: "flex",
                                            height: "100%",
                                            justifyContent: "center",
                                        }}
                                    >
                                        <SpaceLoadingSpinner ariaLabel="Loading messages" />
                                    </Box>
                                ) : visibleMessages.length == 0 ? (
                                    <Box
                                        sx={{
                                            alignItems: "center",
                                            display: "flex",
                                            height: "100%",
                                            justifyContent: "center",
                                            pointerEvents: "none",
                                            textAlign: "center",
                                        }}
                                    >
                                        <Box
                                            component="p"
                                            sx={{
                                                color: textSecondary,
                                                fontFamily:
                                                    '"Inter Variable", Inter, sans-serif',
                                                fontSize: 14,
                                                fontWeight: 500,
                                                lineHeight: "20px",
                                                m: 0,
                                            }}
                                        >
                                            {isThreadReadOnly
                                                ? "No messages."
                                                : "Say hello!"}
                                        </Box>
                                    </Box>
                                ) : (
                                    <Box
                                        component="ol"
                                        sx={{
                                            display: "flex",
                                            flexDirection: "column",
                                            listStyle: "none",
                                            m: 0,
                                            p: 0,
                                        }}
                                    >
                                        {(() => {
                                            let lastTimeSeparatorMessage:
                                                | SpaceMessage
                                                | undefined;

                                            return visibleMessages.map(
                                                (message, index) => {
                                                    const previousMessage =
                                                        visibleMessages[
                                                            index - 1
                                                        ];
                                                    const nextMessage =
                                                        visibleMessages[
                                                            index + 1
                                                        ];
                                                    const groupsWithPrevious =
                                                        bodyBubblesCanGroup(
                                                            previousMessage,
                                                            message,
                                                        );
                                                    const groupsWithNext =
                                                        bodyBubblesCanGroup(
                                                            message,
                                                            nextMessage,
                                                        );
                                                    const showTimeSeparator =
                                                        shouldShowMessageTimeSeparator(
                                                            lastTimeSeparatorMessage,
                                                            previousMessage,
                                                            message,
                                                        );
                                                    if (showTimeSeparator) {
                                                        lastTimeSeparatorMessage =
                                                            message;
                                                    }

                                                    return (
                                                        <React.Fragment
                                                            key={message.id}
                                                        >
                                                            {showTimeSeparator && (
                                                                <MessageTimeSeparator
                                                                    timestampMs={
                                                                        message.createdAtMs
                                                                    }
                                                                />
                                                            )}
                                                            <MessageBubble
                                                                activityPost={
                                                                    message.quote
                                                                        ? activityPostsByKey[
                                                                              postQuoteKey(
                                                                                  message.quote,
                                                                              )
                                                                          ]
                                                                        : undefined
                                                                }
                                                                areActionsOpen={
                                                                    Boolean(
                                                                        messageContextMenu?.open,
                                                                    ) &&
                                                                    messageContextMenu
                                                                        ?.message
                                                                        .id ==
                                                                        message.id
                                                                }
                                                                canOpenActions={canOpenMessageActions(
                                                                    message,
                                                                )}
                                                                canReply={
                                                                    canInteract
                                                                }
                                                                friendName={
                                                                    selectedName
                                                                }
                                                                groupsWithNext={
                                                                    groupsWithNext
                                                                }
                                                                groupsWithPrevious={
                                                                    groupsWithPrevious
                                                                }
                                                                isHighlighted={
                                                                    messageContextMenu
                                                                        ?.message
                                                                        .id ==
                                                                    message.id
                                                                }
                                                                message={
                                                                    message
                                                                }
                                                                onOpenActions={
                                                                    openMessageActions
                                                                }
                                                                onLoadActivityPost={
                                                                    loadActivityPost
                                                                }
                                                                onOpenQuotePost={
                                                                    onOpenQuotePost
                                                                }
                                                                onReply={
                                                                    startReply
                                                                }
                                                                ownSpaceID={
                                                                    profile.spaceId
                                                                }
                                                                parentMessage={
                                                                    message.replyMessageId
                                                                        ? messageByID.get(
                                                                              message.replyMessageId,
                                                                          )
                                                                        : undefined
                                                                }
                                                                profile={
                                                                    profile
                                                                }
                                                            />
                                                        </React.Fragment>
                                                    );
                                                },
                                            );
                                        })()}
                                    </Box>
                                )}
                            </Box>
                            <Popper
                                anchorEl={messageActionsAnchor}
                                modifiers={[
                                    {
                                        name: "offset",
                                        options: {
                                            offset: [
                                                0,
                                                isMenuBelowBubble &&
                                                messageContextMenu?.message
                                                    .reaction
                                                    ? 24
                                                    : 8,
                                            ],
                                        },
                                    },
                                    {
                                        name: "preventOverflow",
                                        options: {
                                            altAxis: true,
                                            boundary: threadScrollRef.current,
                                            padding: 8,
                                        },
                                    },
                                    {
                                        name: "flip",
                                        options: {
                                            boundary: threadScrollRef.current,
                                            padding: 8,
                                            fallbackPlacements: [
                                                isContextMessageOwn
                                                    ? "top-end"
                                                    : "top-start",
                                            ],
                                            flipVariations: false,
                                        },
                                    },
                                ]}
                                open={Boolean(messageContextMenu?.open)}
                                placement={
                                    isContextMessageOwn
                                        ? "bottom-end"
                                        : "bottom-start"
                                }
                                sx={{ outline: 0, zIndex: 1300 }}
                                transition
                            >
                                {({ TransitionProps, placement }) => (
                                    <ClickAwayListener
                                        mouseEvent="onMouseDown"
                                        touchEvent="onTouchStart"
                                        onClickAway={
                                            handleMessageActionsClickAway
                                        }
                                    >
                                        <Grow
                                            {...(TransitionProps ?? {})}
                                            easing={{
                                                enter: "cubic-bezier(0.18, 0.9, 0.3, 1.18)",
                                                exit: "ease-in",
                                            }}
                                            style={{
                                                transformOrigin: `${
                                                    placement.endsWith("end")
                                                        ? "right"
                                                        : "left"
                                                } ${
                                                    placement.startsWith("top")
                                                        ? "bottom"
                                                        : "top"
                                                }`,
                                            }}
                                            onExited={() => {
                                                TransitionProps?.onExited();
                                                clearClosedMessageActions();
                                            }}
                                            timeout={
                                                prefersReducedMotion
                                                    ? 0
                                                    : messageActionsTransitionDuration
                                            }
                                        >
                                            <Box
                                                key={
                                                    messageContextMenu?.message
                                                        .id
                                                }
                                                onPointerDown={(
                                                    event: React.PointerEvent<HTMLElement>,
                                                ) => {
                                                    if (
                                                        event.target ==
                                                        event.currentTarget
                                                    )
                                                        closeMessageActions();
                                                }}
                                                onKeyDown={(
                                                    event: React.KeyboardEvent<HTMLElement>,
                                                ) => {
                                                    if (event.key == "Escape") {
                                                        closeMessageActions();
                                                        messageContextMenu?.anchorEl.focus();
                                                    }
                                                }}
                                                sx={{
                                                    WebkitTapHighlightColor:
                                                        "transparent",
                                                    display: "flex",
                                                    flexDirection: "column",
                                                    gap: "4px",
                                                    outline: 0,
                                                }}
                                            >
                                                {!isContextMessagePoke &&
                                                    canInteract &&
                                                    !isContextMessageOwn &&
                                                    messageContextMenu && (
                                                        <MessageQuickReactions
                                                            selected={
                                                                messageContextMenu
                                                                    .message
                                                                    .reaction
                                                            }
                                                            onSelect={(emoji) =>
                                                                reactToMessage(
                                                                    messageContextMenu.message,
                                                                    emoji,
                                                                )
                                                            }
                                                            onMore={() => {
                                                                setReactionPickerMessage(
                                                                    messageContextMenu,
                                                                );
                                                                closeMessageActions();
                                                            }}
                                                        />
                                                    )}
                                                <MenuList
                                                    aria-label="Message actions"
                                                    autoFocus={
                                                        isContextMessagePoke ||
                                                        !canInteract ||
                                                        isContextMessageOwn
                                                    }
                                                    onKeyDown={
                                                        handleMessageActionsKeyDown
                                                    }
                                                    sx={{
                                                        alignSelf: "flex-start",
                                                        bgcolor:
                                                            spaceMenuBackground,
                                                        borderRadius: "16px",
                                                        boxShadow:
                                                            "0 0 0 1px rgba(255, 255, 255, 0.08), 0 8px 24px rgba(0, 0, 0, 0.32)",
                                                        minWidth: 132,
                                                        outline: 0,
                                                        p: "4px",
                                                        width: "max-content",
                                                        "&:focus": {
                                                            outline: 0,
                                                        },
                                                        "&:focus-visible": {
                                                            outline: 0,
                                                        },
                                                    }}
                                                    variant="menu"
                                                >
                                                    {messageActionMenuItems}
                                                </MenuList>
                                            </Box>
                                        </Grow>
                                    </ClickAwayListener>
                                )}
                            </Popper>
                            {!isThreadReadOnly && (
                                <Box
                                    sx={{
                                        bgcolor: "transparent",
                                        boxSizing: "border-box",
                                        display: "grid",
                                        gap: "8px",
                                        p: "10px 14px",
                                        width: "100%",
                                    }}
                                >
                                    {replyingTo && (
                                        <Box
                                            sx={{
                                                bgcolor: spaceSurface,
                                                borderLeft: `3px solid ${green}`,
                                                borderRadius: "12px",
                                                boxSizing: "border-box",
                                                display: "grid",
                                                gridTemplateColumns:
                                                    "minmax(0, 1fr)",
                                                maxWidth: "100%",
                                                overflow: "hidden",
                                                p: "9px 40px 9px 12px",
                                                position: "relative",
                                                width: "100%",
                                            }}
                                        >
                                            <Box
                                                sx={{
                                                    maxWidth: "100%",
                                                    minWidth: 0,
                                                    overflow: "hidden",
                                                }}
                                            >
                                                <Box
                                                    sx={{
                                                        color: textSecondary,
                                                        fontFamily:
                                                            '"Inter Variable", Inter, sans-serif',
                                                        fontSize: 12,
                                                        fontWeight: 650,
                                                        lineHeight: "16px",
                                                        overflow: "hidden",
                                                        textOverflow:
                                                            "ellipsis",
                                                        whiteSpace: "nowrap",
                                                    }}
                                                >
                                                    {isCurrentProfileMessage(
                                                        replyingTo,
                                                        profile,
                                                    )
                                                        ? "You"
                                                        : firstNameFrom(
                                                              replyingTo.sender.fullName.trim() ||
                                                                  replyingTo
                                                                      .sender
                                                                      .username ||
                                                                  selectedName,
                                                          )}
                                                </Box>
                                                <Box
                                                    sx={{
                                                        color: textBase,
                                                        fontFamily:
                                                            '"Inter Variable", Inter, sans-serif',
                                                        fontSize: 13,
                                                        fontWeight: 600,
                                                        lineHeight: "18px",
                                                        maxWidth: "100%",
                                                        overflow: "hidden",
                                                        overflowWrap:
                                                            "anywhere",
                                                        textOverflow:
                                                            "ellipsis",
                                                        whiteSpace: "nowrap",
                                                    }}
                                                >
                                                    {truncateMessageText(
                                                        replyingTo.text,
                                                    )}
                                                </Box>
                                            </Box>
                                            <Box
                                                component="button"
                                                type="button"
                                                aria-label="Cancel reply"
                                                onClick={() => {
                                                    setReplyingTo(null);
                                                }}
                                                sx={{
                                                    alignItems: "center",
                                                    bgcolor: "transparent",
                                                    border: 0,
                                                    borderRadius: "50%",
                                                    color: textSecondary,
                                                    cursor: "pointer",
                                                    display: "flex",
                                                    height: spaceTouchTargetSize,
                                                    justifyContent: "center",
                                                    p: 0,
                                                    position: "absolute",
                                                    right: 0,
                                                    top: 0,
                                                    width: spaceTouchTargetSize,
                                                    "&:focus-visible": {
                                                        outline: `2px solid ${green}`,
                                                        outlineOffset: 2,
                                                    },
                                                    "&:hover": {
                                                        color: textBase,
                                                    },
                                                    "& svg": {
                                                        position: "absolute",
                                                        right: 8,
                                                        top: 8,
                                                    },
                                                }}
                                            >
                                                <HugeiconsIcon
                                                    icon={Cancel01Icon}
                                                    size={16}
                                                    strokeWidth={1.8}
                                                />
                                            </Box>
                                        </Box>
                                    )}
                                    <Box
                                        sx={{
                                            alignItems: "flex-end",
                                            display: "flex",
                                            gap: "8px",
                                            width: "100%",
                                        }}
                                    >
                                        <Box
                                            ref={composerRef}
                                            component="textarea"
                                            aria-label={`Message ${selectedName}`}
                                            onChange={(event) => {
                                                const nextText =
                                                    clampSpaceMessageText(
                                                        event.target.value,
                                                    );
                                                event.currentTarget.value =
                                                    nextText;
                                                setMessageText(nextText);
                                                resizeComposer(
                                                    event.currentTarget,
                                                );
                                            }}
                                            onBlur={handleComposerBlur}
                                            onFocus={handleComposerFocus}
                                            placeholder="Message..."
                                            disabled={isThreadRecipientLoading}
                                            rows={1}
                                            value={messageText}
                                            sx={{
                                                bgcolor: composerSurface,
                                                border: 0,
                                                borderRadius: "24px",
                                                boxSizing: "border-box",
                                                color: textBase,
                                                flex: "1 1 auto",
                                                fontFamily:
                                                    '"Inter Variable", Inter, sans-serif',
                                                fontSize: 14,
                                                fontWeight: 600,
                                                lineHeight: "20px",
                                                maxHeight: composerMaxHeight,
                                                minHeight: composerHeight,
                                                minWidth: 0,
                                                outline: 0,
                                                overflow: "hidden",
                                                pb: `${composerPadding}px`,
                                                pl: `${composerPaddingLeft}px`,
                                                pr: `${composerPadding}px`,
                                                pt: `${composerPadding}px`,
                                                resize: "none",
                                                "&::placeholder": {
                                                    color: textSecondary,
                                                },
                                            }}
                                        />
                                        <Box
                                            component="button"
                                            type="button"
                                            aria-label="Send message"
                                            className={
                                                canSend ? "green-bg" : undefined
                                            }
                                            disabled={!canSend}
                                            onClick={sendMessage}
                                            sx={{
                                                alignItems: "center",
                                                bgcolor: canSend
                                                    ? green
                                                    : spaceSurface,
                                                border: 0,
                                                borderRadius: "50%",
                                                color: canSend
                                                    ? spaceOnAccent
                                                    : "#BDBDBD",
                                                cursor: canSend
                                                    ? "pointer"
                                                    : "default",
                                                display: "flex",
                                                flexShrink: 0,
                                                height: composerHeight,
                                                justifyContent: "center",
                                                p: 0,
                                                transition:
                                                    "background-color 180ms ease, color 180ms ease, transform 120ms ease",
                                                width: composerHeight,
                                                "&:active": {
                                                    transform: canSend
                                                        ? "scale(0.96)"
                                                        : "none",
                                                },
                                                "&:focus-visible": {
                                                    outline: `2px solid ${green}`,
                                                    outlineOffset: 2,
                                                },
                                                "&:hover": {
                                                    bgcolor: canSend
                                                        ? "#07AE22"
                                                        : spaceSurface,
                                                },
                                            }}
                                        >
                                            <Box
                                                component="span"
                                                sx={{
                                                    display: "flex",
                                                    transform:
                                                        "translate(-1px, 1px)",
                                                }}
                                            >
                                                <HugeiconsIcon
                                                    icon={Navigation03Icon}
                                                    size={24}
                                                    strokeWidth={1.8}
                                                />
                                            </Box>
                                        </Box>
                                    </Box>
                                </Box>
                            )}
                        </>
                    ) : (
                        <Box
                            component="section"
                            id="space-main-content"
                            aria-label="Messages"
                            tabIndex={-1}
                        >
                            {isConversationsLoading ? (
                                <Box
                                    sx={{
                                        alignItems: "center",
                                        boxSizing: "border-box",
                                        display: "flex",
                                        inset: 0,
                                        justifyContent: "center",
                                        pointerEvents: "none",
                                        position: "absolute",
                                    }}
                                >
                                    <SpaceLoadingSpinner ariaLabel="Loading messages" />
                                </Box>
                            ) : conversations.length == 0 ? (
                                <Box
                                    sx={{
                                        alignItems: "center",
                                        boxSizing: "border-box",
                                        display: "flex",
                                        flexDirection: "column",
                                        gap: "22px",
                                        inset: 0,
                                        justifyContent: "center",
                                        pointerEvents: "none",
                                        position: "absolute",
                                        px: 3,
                                        textAlign: "center",
                                    }}
                                >
                                    <Box
                                        component="p"
                                        sx={{
                                            color: textSecondary,
                                            fontFamily:
                                                '"Inter Variable", Inter, sans-serif',
                                            fontSize: 14,
                                            fontWeight: 500,
                                            lineHeight: "20px",
                                            m: 0,
                                            maxWidth: 260,
                                        }}
                                    >
                                        {emptyConversationsCopy}
                                    </Box>
                                    {showInviteEmptyState && (
                                        <SpaceShareInviteButton
                                            profileLink={profileLink}
                                            sharing={isInviteSharing}
                                            onShareError={(error) =>
                                                log.error(
                                                    "Failed to share space invite",
                                                    error,
                                                )
                                            }
                                            onSharingChange={setIsInviteSharing}
                                        />
                                    )}
                                </Box>
                            ) : (
                                <Box
                                    component="ul"
                                    sx={{
                                        ...spaceActivityListSx,
                                        listStyle: "none",
                                    }}
                                >
                                    {conversations.map((conversation) => (
                                        <ConversationListItem
                                            key={conversationId(conversation)}
                                            activityPost={
                                                conversation.latestActivity.post
                                                    ? activityPostsByKey[
                                                          postQuoteKey(
                                                              conversation
                                                                  .latestActivity
                                                                  .post,
                                                          )
                                                      ]
                                                    : undefined
                                            }
                                            conversation={conversation}
                                            onLoadActivityPost={
                                                loadActivityPost
                                            }
                                            onOpenFriendProfile={
                                                onOpenSelectedFriendProfile
                                            }
                                            onOpenThread={onOpenThread}
                                        />
                                    ))}
                                </Box>
                            )}
                        </Box>
                    )}
                </Box>
            </Box>
        </>
    );
};
