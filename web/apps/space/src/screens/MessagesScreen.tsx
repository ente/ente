import {
    ArrowLeft02Icon,
    Cancel01Icon,
    FavouriteIcon,
    ImageDelete02Icon,
    Navigation03Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    ClickAwayListener,
    Grow,
    MenuItem,
    MenuList,
    Popper,
} from "@mui/material";
import { SpaceAvatarImage } from "components/SpaceAvatarImage";
import { SpaceLoadingSpinner } from "components/SpaceRouteFallback";
import { SpaceShareInviteButton } from "components/SpaceShareInviteButton";
import { formatTimeAgo } from "ente-base/date";
import React from "react";
import { flushSync } from "react-dom";
import type { SetupProfile } from "screens/SetupProfileScreen";
import type {
    SpaceMessage,
    SpaceMessageActivityPost,
    SpaceMessageConversation,
    SpaceMessageQuote,
} from "services/space";
import { spaceTouchTargetSize } from "styles/touchTargets";
import { firstNameFrom } from "utils/spaceDisplay";
import { clampSpaceMessageText } from "utils/spaceMessageLimits";

export const messagesBackground = "#FFFFFF";

const green = "#08C225";
const textBase = "#000000";
const textSecondary = "#777777";
const lightSurface = "#F2F2F2";
const lightSurfaceHover = "#E8E8E8";
const composerSurface = "#FFFFFF";
const composerBorder = "#DEDEDE";
const outgoingBubble = "#0DAF35";
const incomingBubble = lightSurface;
const outgoingMessageText = "#FFFFFF";
const incomingMessageText = "#111111";
const outgoingQuoteBubble = "#9EDFAE";
const incomingQuoteBubble = "#FAFAFA";
const incomingQuoteText = "#BDBDBD";
const outgoingQuoteText = "#FFFFFF";
const quoteRule = "#EEEEEE";
const dangerColor = "#F63A3A";
const composerHeight = 48;
const composerMaxHeight = 112;
const messageBubblePaddingX = "16px";
const messageBubblePaddingY = "14px";
const composerPadding = 14;
const composerPaddingLeft = 18;
const postQuoteThumbnailSize = 164;
const threadBottomThresholdPx = 96;
const messageGroupTimeThresholdMs = 10 * 60 * 1000;
const messageTimeSeparatorThresholdMs = 60 * 60 * 1000;
const messageLongPressMs = 520;
const messageLongPressMoveTolerancePx = 10;
const messageActionsTouchOpenMouseSuppressMs = 900;
const dayMs = 24 * 60 * 60 * 1000;

interface MessagesScreenProps {
    conversations: SpaceMessageConversation[];
    friendsCount?: number;
    isConversationsLoading?: boolean;
    isThreadLoading?: boolean;
    isThreadReadOnly?: boolean;
    isThreadRecipientLoading?: boolean;
    messages: SpaceMessage[];
    onBack?: () => void;
    onCloseThread: () => void;
    onConfirmFriendRequest: (
        conversation: SpaceMessageConversation,
    ) => Promise<void>;
    onDeleteMessage: (messageId: string) => Promise<void>;
    onDeleteFriendRequest: (
        conversation: SpaceMessageConversation,
    ) => Promise<void>;
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
    onSetMessageLiked: (messageId: string, liked: boolean) => Promise<void>;
    profileLink?: string;
    newConversationIds?: string[];
    profile: SetupProfile;
    selectedFriend?: SpaceMessageConversation["friend"];
    threadBackLabel?: string;
}

interface MessageContextMenuState {
    anchorEl: HTMLElement;
    message: SpaceMessage;
    open: boolean;
}

type MessageActionsOpenSource = "contextmenu" | "touch";

interface ConversationSection {
    items: SpaceMessageConversation[];
    title: string;
}

const microsForTimestamp = (timestampMs: number) => timestampMs * 1000;

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

const Avatar: React.FC<{ avatarUrl?: string | null; size: number }> = ({
    avatarUrl,
    size,
}) => (
    <Box
        sx={{
            alignItems: "center",
            borderRadius: "50%",
            display: "flex",
            flexShrink: 0,
            height: size,
            justifyContent: "center",
            overflow: "hidden",
            width: size,
        }}
    >
        <SpaceAvatarImage src={avatarUrl} />
    </Box>
);

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
    if (activity.type == "empty") {
        return "You're now friends. Say hello!";
    }
    if (activity.type == "friend_request") {
        return "Sent you a friend request";
    }
    if (activity.type == "friend_added") {
        return "You're now friends. Say hello!";
    }
    if (activity.type == "post_like") {
        return activity.outgoing ? "You liked a post" : "Liked your post";
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
                ? `You liked "${text}"`
                : `Liked "${text}"`
            : activity.outgoing
              ? "You liked a message"
              : "Liked a message";
    }
    if (text) {
        return activity.outgoing ? `You: ${text}` : text;
    }

    return activity.outgoing ? "You sent a message" : "Message";
};

const ConversationPreviewLine: React.FC<{
    conversation: SpaceMessageConversation;
}> = ({ conversation }) => {
    const previewLineSx = {
        color: textSecondary,
        fontFamily: '"Inter Variable", Inter, sans-serif',
        fontSize: 13,
        fontWeight: 500,
        lineHeight: "18px",
        minWidth: 0,
        overflow: "hidden",
        textOverflow: "ellipsis",
        whiteSpace: "nowrap",
    };

    return <Box sx={previewLineSx}>{conversationPreview(conversation)}</Box>;
};

const conversationId = (conversation: SpaceMessageConversation) =>
    conversation.latestActivity.type == "friend_request"
        ? conversation.latestActivity.id
        : (conversation.friend.spaceId ?? conversation.friend.id);

const activityPostKey = (post: SpaceMessageActivityPost) =>
    `${post.spaceId}:${post.postId}`;

const conversationTimeSections = (
    conversations: SpaceMessageConversation[],
    newConversationIds: string[],
) => {
    const newIds = new Set(newConversationIds);
    const now = Date.now();
    const today = new Date(now);
    const startOfTodayMs = new Date(
        today.getFullYear(),
        today.getMonth(),
        today.getDate(),
    ).getTime();
    const startOfYesterdayMs = new Date(
        today.getFullYear(),
        today.getMonth(),
        today.getDate() - 1,
    ).getTime();
    const sections: ConversationSection[] = [
        { title: "New", items: [] },
        { title: "Today", items: [] },
        { title: "Yesterday", items: [] },
        { title: "Last 7 days", items: [] },
        { title: "Last 30 days", items: [] },
        { title: "Older", items: [] },
    ];

    for (const conversation of conversations) {
        if (newIds.has(conversationId(conversation))) {
            sections[0]!.items.push(conversation);
            continue;
        }

        const activity = conversation.latestActivity;
        if (activity.createdAtMs >= startOfTodayMs) {
            sections[1]!.items.push(conversation);
            continue;
        }
        if (activity.createdAtMs >= startOfYesterdayMs) {
            sections[2]!.items.push(conversation);
            continue;
        }

        const ageMs = Math.max(0, now - activity.createdAtMs);
        if (ageMs <= 7 * dayMs) {
            sections[3]!.items.push(conversation);
            continue;
        }
        if (ageMs <= 30 * dayMs) {
            sections[4]!.items.push(conversation);
            continue;
        }
        sections[5]!.items.push(conversation);
    }
    return sections;
};

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
            py: "14px",
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
    onConfirmFriendRequest: (
        conversation: SpaceMessageConversation,
    ) => Promise<void>;
    onDeleteFriendRequest: (
        conversation: SpaceMessageConversation,
    ) => Promise<void>;
    onLoadActivityPost?: (post: SpaceMessageActivityPost) => void;
    onOpenFriendProfile: (friend: SpaceMessageConversation["friend"]) => void;
    onOpenThread: (conversation: SpaceMessageConversation) => void;
}> = ({
    activityPost,
    conversation,
    onConfirmFriendRequest,
    onDeleteFriendRequest,
    onLoadActivityPost,
    onOpenFriendProfile,
    onOpenThread,
}) => {
    const name =
        conversation.friend.fullName.trim() || conversation.friend.username;
    const timestampLabel = formatTimeAgo(
        microsForTimestamp(conversation.latestActivity.createdAtMs),
    );
    const isFriendRequest =
        conversation.latestActivity.type == "friend_request";
    const post = conversation.latestActivity.post;
    const postThumbnailUrl = (activityPost ?? post)?.imageUrl;
    const unreadCount = conversation.unreadCount;
    React.useEffect(() => {
        if (
            !post ||
            post.isDeleted ||
            post.imageUrl ||
            activityPost?.imageUrl
        ) {
            return;
        }
        onLoadActivityPost?.(post);
    }, [
        activityPost?.imageUrl,
        onLoadActivityPost,
        post,
        post?.imageUrl,
        post?.isDeleted,
    ]);
    const confirmFriendRequest = () => {
        void onConfirmFriendRequest(conversation).catch((error: unknown) =>
            console.error("Failed to confirm friend request", error),
        );
    };
    const deleteFriendRequest = () => {
        void onDeleteFriendRequest(conversation).catch((error: unknown) =>
            console.error("Failed to delete friend request", error),
        );
    };

    return (
        <Box component="li" sx={{ listStyle: "none" }}>
            <Box
                sx={{
                    alignItems: "center",
                    borderRadius: "8px",
                    color: textBase,
                    display: "grid",
                    gap: "10px",
                    gridTemplateColumns: isFriendRequest
                        ? "44px minmax(0, 1fr) auto"
                        : "44px minmax(0, 1fr)",
                    minHeight: 64,
                    p: "8px 0",
                    textAlign: "left",
                    width: "100%",
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
                    {isFriendRequest ? (
                        <Avatar
                            avatarUrl={conversation.friend.avatarUrl}
                            size={44}
                        />
                    ) : (
                        <Box
                            component="button"
                            type="button"
                            aria-label={`Open ${name}'s profile`}
                            onClick={() =>
                                onOpenFriendProfile(conversation.friend)
                            }
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
                    )}
                    {unreadCount > 0 && !isFriendRequest && (
                        <Box
                            aria-label={`${unreadCount} unread update${unreadCount == 1 ? "" : "s"}`}
                            component="span"
                            sx={{
                                alignItems: "center",
                                bgcolor: dangerColor,
                                borderRadius: "8px",
                                boxShadow: `0 0 0 2px ${messagesBackground}`,
                                color: "#FFFFFF",
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
                    component={isFriendRequest ? "div" : "button"}
                    type={isFriendRequest ? undefined : "button"}
                    aria-label={
                        isFriendRequest
                            ? undefined
                            : `Open conversation with ${name}`
                    }
                    onClick={
                        isFriendRequest
                            ? undefined
                            : () => onOpenThread(conversation)
                    }
                    sx={{
                        alignItems: "center",
                        appearance: "none",
                        bgcolor: "transparent",
                        border: 0,
                        color: "inherit",
                        cursor: isFriendRequest ? "default" : "pointer",
                        display: "grid",
                        gap: "10px",
                        gridColumn: isFriendRequest ? undefined : "2 / -1",
                        gridTemplateColumns: postThumbnailUrl
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
                        <Box
                            sx={{
                                alignItems: "center",
                                display: "flex",
                                gap: "4px",
                                minWidth: 0,
                            }}
                        >
                            <Box
                                sx={{
                                    flex: "0 1 auto",
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 14,
                                    fontWeight: 700,
                                    lineHeight: "20px",
                                    minWidth: 0,
                                    overflow: "hidden",
                                    textOverflow: "ellipsis",
                                    whiteSpace: "nowrap",
                                }}
                            >
                                {firstNameFrom(name)}
                            </Box>
                            <Box
                                aria-hidden
                                component="span"
                                sx={{
                                    color: textSecondary,
                                    flexShrink: 0,
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 12,
                                    fontWeight: 600,
                                    lineHeight: "16px",
                                }}
                            >
                                &middot;
                            </Box>
                            <Box
                                component="time"
                                dateTime={new Date(
                                    conversation.latestActivity.createdAtMs,
                                ).toISOString()}
                                sx={{
                                    color: textSecondary,
                                    flexShrink: 0,
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 12,
                                    fontWeight: 600,
                                    lineHeight: "16px",
                                    whiteSpace: "nowrap",
                                }}
                            >
                                {timestampLabel}
                            </Box>
                        </Box>
                        <ConversationPreviewLine conversation={conversation} />
                    </Box>
                    {postThumbnailUrl && (
                        <Box
                            component="img"
                            alt=""
                            src={postThumbnailUrl}
                            sx={{
                                borderRadius: "6px",
                                display: "block",
                                height: 44,
                                objectFit: "cover",
                                objectPosition: "center",
                                width: 44,
                            }}
                        />
                    )}
                </Box>
                {isFriendRequest && (
                    <Box sx={{ display: "flex", flexShrink: 0, gap: "6px" }}>
                        <Box
                            component="button"
                            type="button"
                            onClick={confirmFriendRequest}
                            sx={{
                                bgcolor: green,
                                border: 0,
                                borderRadius: "12px",
                                color: "white",
                                cursor: "pointer",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 12,
                                fontWeight: 700,
                                height: 34,
                                px: "12px",
                                "&:hover": { bgcolor: "#07A820" },
                            }}
                        >
                            Accept
                        </Box>
                        <Box
                            component="button"
                            type="button"
                            aria-label={`Dismiss friend request from ${name}`}
                            onClick={deleteFriendRequest}
                            sx={{
                                alignItems: "center",
                                bgcolor: "transparent",
                                border: 0,
                                borderRadius: "50%",
                                color: textBase,
                                cursor: "pointer",
                                display: "flex",
                                height: 34,
                                justifyContent: "center",
                                p: 0,
                                width: 34,
                                "&:hover": { bgcolor: "#F1F1F1" },
                            }}
                        >
                            <HugeiconsIcon
                                icon={Cancel01Icon}
                                size={18}
                                strokeWidth={2}
                            />
                        </Box>
                    </Box>
                )}
            </Box>
        </Box>
    );
};

const ConversationSection: React.FC<{
    activityPostsByKey: Record<string, SpaceMessageActivityPost>;
    onConfirmFriendRequest: (
        conversation: SpaceMessageConversation,
    ) => Promise<void>;
    onDeleteFriendRequest: (
        conversation: SpaceMessageConversation,
    ) => Promise<void>;
    onLoadActivityPost?: (post: SpaceMessageActivityPost) => void;
    onOpenFriendProfile: (friend: SpaceMessageConversation["friend"]) => void;
    onOpenThread: (conversation: SpaceMessageConversation) => void;
    section: ConversationSection;
}> = ({
    activityPostsByKey,
    onConfirmFriendRequest,
    onDeleteFriendRequest,
    onLoadActivityPost,
    onOpenFriendProfile,
    onOpenThread,
    section,
}) => {
    if (section.items.length == 0) return null;

    return (
        <Box component="section" sx={{ mb: "10px" }}>
            <Box
                component="h2"
                sx={{
                    color: textSecondary,
                    fontFamily: '"Inter Variable", Inter, sans-serif',
                    fontSize: 13,
                    fontWeight: 700,
                    lineHeight: "18px",
                    m: 0,
                    pb: "4px",
                    pt: "12px",
                }}
            >
                {section.title}
            </Box>
            <Box component="ul" sx={{ listStyle: "none", m: 0, p: 0 }}>
                {section.items.map((conversation) => (
                    <ConversationListItem
                        key={conversationId(conversation)}
                        activityPost={
                            conversation.latestActivity.post
                                ? activityPostsByKey[
                                      activityPostKey(
                                          conversation.latestActivity.post,
                                      )
                                  ]
                                : undefined
                        }
                        conversation={conversation}
                        onConfirmFriendRequest={onConfirmFriendRequest}
                        onDeleteFriendRequest={onDeleteFriendRequest}
                        onLoadActivityPost={onLoadActivityPost}
                        onOpenFriendProfile={onOpenFriendProfile}
                        onOpenThread={onOpenThread}
                    />
                ))}
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
    if (first.kind == "post_like" || first.kind == "friend_added") return false;
    if (second.kind != "regular" || second.replyMessageId) return false;
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

const HeartIcon: React.FC<{ filled?: boolean; small?: boolean }> = ({
    filled,
    small,
}) => (
    <svg
        width={small ? "13" : "16"}
        height={small ? "11" : "14"}
        viewBox="0 0 16 14"
        fill={filled ? green : "none"}
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M6.63749 12.3742C4.66259 10.885 0.75 7.4804 0.75 4.41664C0.75 2.39161 2.22368 0.75 4.25 0.75C5.3 0.75 6.35 1.10294 7.75 2.51469C9.15 1.10294 10.2 0.75 11.25 0.75C13.2763 0.75 14.75 2.39161 14.75 4.41664C14.75 7.4804 10.8374 10.885 8.86251 12.3742C8.19793 12.8753 7.30207 12.8753 6.63749 12.3742Z"
            stroke={filled ? green : "currentColor"}
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
    </svg>
);

const MessageLikeHeartIcon: React.FC = () => (
    <svg
        width="17"
        height="15"
        viewBox="-2 -2 20 18"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M6.63749 12.3742C4.66259 10.885 0.75 7.4804 0.75 4.41664C0.75 2.39161 2.22368 0.75 4.25 0.75C5.3 0.75 6.35 1.10294 7.75 2.51469C9.15 1.10294 10.2 0.75 11.25 0.75C13.2763 0.75 14.75 2.39161 14.75 4.41664C14.75 7.4804 10.8374 10.885 8.86251 12.3742C8.19793 12.8753 7.30207 12.8753 6.63749 12.3742Z"
            fill={green}
            stroke={messagesBackground}
            strokeWidth="4"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
        <path
            d="M6.63749 12.3742C4.66259 10.885 0.75 7.4804 0.75 4.41664C0.75 2.39161 2.22368 0.75 4.25 0.75C5.3 0.75 6.35 1.10294 7.75 2.51469C9.15 1.10294 10.2 0.75 11.25 0.75C13.2763 0.75 14.75 2.39161 14.75 4.41664C14.75 7.4804 10.8374 10.885 8.86251 12.3742C8.19793 12.8753 7.30207 12.8753 6.63749 12.3742Z"
            fill={green}
            stroke={green}
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
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

const messageActionsPopperModifiers = [
    { name: "offset", options: { offset: [0, 6] } },
    { name: "preventOverflow", options: { padding: 14 } },
    { name: "flip", options: { padding: 14 } },
];
const messageActionsTransitionDuration = { enter: 140, exit: 100 };

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
                    tone == "danger" ? "rgba(246, 58, 58, 0.14)" : lightSurface,
                outline: 0,
            },
            "&:focus": { outline: 0 },
            "&:focus-visible": { outline: 0 },
            "&:hover": {
                bgcolor:
                    tone == "danger" ? "rgba(246, 58, 58, 0.14)" : lightSurface,
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
            bgcolor: lightSurface,
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
}> = ({ children, isOwn, mb = "8px" }) => (
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
                bgcolor: quoteRule,
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
        <QuoteFrame isOwn={isOwn}>
            <Box
                sx={{
                    bgcolor: parentIsOwn
                        ? outgoingQuoteBubble
                        : incomingQuoteBubble,
                    borderRadius,
                    color: parentIsOwn ? outgoingQuoteText : incomingQuoteText,
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
                    : truncateMessageText(parentMessage.text)}
            </Box>
        </QuoteFrame>
    );
};

const PostQuotePreview: React.FC<{
    isOwn: boolean;
    message: SpaceMessage;
    mb?: string;
    onOpenQuotePost: (quote: SpaceMessageQuote) => void;
}> = ({ isOwn, message, mb, onOpenQuotePost }) => {
    const quote = message.quote;
    const isUnavailable = !quote || quote.isUnavailable || !quote.imageUrl;
    const canOpen = Boolean(quote && !isUnavailable);

    return (
        <QuoteFrame isOwn={isOwn} mb={mb}>
            <Box
                component={canOpen ? "button" : "div"}
                type={canOpen ? "button" : undefined}
                aria-label={canOpen ? "Open quoted post" : undefined}
                onClick={(event: React.MouseEvent) => {
                    if (!quote || !canOpen) return;
                    event.stopPropagation();
                    onOpenQuotePost(quote);
                }}
                sx={{
                    appearance: "none",
                    bgcolor: "transparent",
                    border: 0,
                    borderRadius: "10px",
                    color: "inherit",
                    cursor: canOpen ? "pointer" : "default",
                    display: "inline-flex",
                    font: "inherit",
                    p: 0,
                    "&:focus-visible": {
                        outline: `2px solid ${green}`,
                        outlineOffset: 2,
                    },
                }}
            >
                {isUnavailable ? (
                    <Box
                        role="img"
                        aria-label="Deleted post"
                        sx={{
                            alignItems: "center",
                            bgcolor: incomingQuoteBubble,
                            borderRadius: "10px",
                            color: incomingQuoteText,
                            display: "flex",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 12,
                            fontWeight: 700,
                            height: postQuoteThumbnailSize,
                            justifyContent: "center",
                            lineHeight: "16px",
                            textAlign: "center",
                            width: postQuoteThumbnailSize,
                            px: "12px",
                        }}
                    >
                        <HugeiconsIcon
                            icon={ImageDelete02Icon}
                            size={28}
                            strokeWidth={1.5}
                        />
                    </Box>
                ) : (
                    <Box
                        component="img"
                        alt=""
                        src={quote.imageUrl}
                        sx={{
                            borderRadius: "8px",
                            display: "block",
                            height: postQuoteThumbnailSize,
                            objectFit: "cover",
                            objectPosition: "center",
                            width: postQuoteThumbnailSize,
                        }}
                    />
                )}
            </Box>
        </QuoteFrame>
    );
};

const isMessageLongPressIgnoredTarget = (target: EventTarget | null) =>
    target instanceof Element && Boolean(target.closest("button"));

const MessageBubble: React.FC<{
    groupsWithNext: boolean;
    groupsWithPrevious: boolean;
    isHighlighted: boolean;
    message: SpaceMessage;
    onOpenActions: (
        message: SpaceMessage,
        anchorEl: HTMLElement,
        source: MessageActionsOpenSource,
    ) => void;
    onOpenQuotePost: (quote: SpaceMessageQuote) => void;
    ownSpaceID?: string;
    parentMessage?: SpaceMessage;
    profile: SetupProfile;
}> = ({
    groupsWithNext,
    groupsWithPrevious,
    isHighlighted,
    message,
    onOpenActions,
    onOpenQuotePost,
    ownSpaceID,
    parentMessage,
    profile,
}) => {
    const isOwn = message.sender.spaceId == ownSpaceID;
    const bubbleBorderRadius = isOwn
        ? `20px ${groupsWithPrevious ? "6px" : "20px"} ${groupsWithNext ? "6px" : "20px"} 20px`
        : `${groupsWithPrevious ? "6px" : "20px"} 20px 20px ${groupsWithNext ? "6px" : "20px"}`;
    const isSyntheticPostLike = message.kind == "post_like";
    const isFriendAdded = message.kind == "friend_added";
    const isPostReply = message.kind == "post_reply";
    const isSystemMessage = isSyntheticPostLike || isFriendAdded;
    const hasMessageReply = Boolean(message.replyMessageId);
    const actionLabel = isSyntheticPostLike
        ? isOwn
            ? "You liked a post"
            : "Liked your post"
        : isPostReply
          ? isOwn
              ? "You replied to a post"
              : "Replied to your post"
          : hasMessageReply
            ? isOwn
                ? "You replied"
                : "Replied to you"
            : undefined;
    const hasBodyBubble = !isSystemMessage;
    const rowAlignItems = isFriendAdded
        ? "center"
        : isOwn
          ? "flex-end"
          : "flex-start";
    const longPressTimerRef = React.useRef<number | undefined>(undefined);
    const longPressStartRef = React.useRef<
        { x: number; y: number } | undefined
    >(undefined);
    const didOpenLongPressRef = React.useRef(false);

    const clearLongPressTimer = React.useCallback(() => {
        if (longPressTimerRef.current == undefined) return;
        window.clearTimeout(longPressTimerRef.current);
        longPressTimerRef.current = undefined;
    }, []);

    const cancelLongPress = React.useCallback(() => {
        clearLongPressTimer();
        longPressStartRef.current = undefined;
        didOpenLongPressRef.current = false;
    }, [clearLongPressTimer]);

    const openActions = React.useCallback(
        (bubbleElement: HTMLElement, source: MessageActionsOpenSource) => {
            if (isSystemMessage) return;
            clearLongPressTimer();
            longPressStartRef.current = undefined;
            window.getSelection()?.removeAllRanges();
            onOpenActions(message, bubbleElement, source);
        },
        [clearLongPressTimer, isSystemMessage, message, onOpenActions],
    );

    const handleContextMenu = (event: React.MouseEvent<HTMLElement>) => {
        if (isSystemMessage) return;
        event.preventDefault();
        event.stopPropagation();
        openActions(event.currentTarget, "contextmenu");
    };

    const handleTouchStart = (event: React.TouchEvent<HTMLElement>) => {
        if (isSystemMessage) {
            cancelLongPress();
            return;
        }
        if (
            event.touches.length != 1 ||
            isMessageLongPressIgnoredTarget(event.target)
        ) {
            cancelLongPress();
            return;
        }

        const touch = event.touches[0]!;
        const bubbleElement = event.currentTarget;
        clearLongPressTimer();
        didOpenLongPressRef.current = false;
        longPressStartRef.current = { x: touch.clientX, y: touch.clientY };
        longPressTimerRef.current = window.setTimeout(() => {
            longPressTimerRef.current = undefined;
            didOpenLongPressRef.current = true;
            openActions(bubbleElement, "touch");
        }, messageLongPressMs);
    };

    const handleTouchMove = (event: React.TouchEvent<HTMLElement>) => {
        const start = longPressStartRef.current;
        const touch = event.touches[0];
        if (!start || !touch) return;

        if (
            Math.hypot(touch.clientX - start.x, touch.clientY - start.y) >
            messageLongPressMoveTolerancePx
        ) {
            cancelLongPress();
        }
    };

    const handleTouchEnd = (event: React.TouchEvent<HTMLElement>) => {
        clearLongPressTimer();
        longPressStartRef.current = undefined;
        if (!didOpenLongPressRef.current) return;

        if (event.cancelable) event.preventDefault();
        event.stopPropagation();
        didOpenLongPressRef.current = false;
    };

    React.useEffect(() => cancelLongPress, [cancelLongPress]);

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
                width: "100%",
                zIndex: isHighlighted ? 3 : message.liked ? 1 : "auto",
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
                            icon={isSyntheticPostLike ? "like" : "reply"}
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
                    {(isPostReply || isSyntheticPostLike) && (
                        <PostQuotePreview
                            isOwn={isOwn}
                            mb={hasBodyBubble ? "8px" : "0"}
                            message={message}
                            onOpenQuotePost={onOpenQuotePost}
                        />
                    )}
                    {hasBodyBubble && (
                        <Box
                            data-message-bubble
                            onContextMenu={handleContextMenu}
                            onTouchCancel={cancelLongPress}
                            onTouchEnd={handleTouchEnd}
                            onTouchMove={handleTouchMove}
                            onTouchStart={handleTouchStart}
                            sx={{
                                bgcolor: isOwn
                                    ? outgoingBubble
                                    : incomingBubble,
                                borderRadius: bubbleBorderRadius,
                                color: isOwn
                                    ? outgoingMessageText
                                    : incomingMessageText,
                                cursor: "context-menu",
                                display: "block",
                                maxWidth: "100%",
                                minWidth: 0,
                                ml: 0,
                                overflow: "visible",
                                position: "relative",
                                px: messageBubblePaddingX,
                                py: messageBubblePaddingY,
                                textAlign: "left",
                                touchAction: "pan-y",
                                userSelect: "none",
                                WebkitTouchCallout: "none",
                                WebkitUserSelect: "none",
                                width: "fit-content",
                                "& *": {
                                    userSelect: "none",
                                    WebkitTouchCallout: "none",
                                    WebkitUserSelect: "none",
                                },
                                "&:hover": {
                                    bgcolor: isOwn
                                        ? outgoingBubble
                                        : lightSurfaceHover,
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
                                    fontSize: 14,
                                    fontWeight: 600,
                                    lineHeight: "21px",
                                    overflowWrap: "anywhere",
                                    whiteSpace: "pre-wrap",
                                }}
                            >
                                {message.text}
                            </Box>
                            {message.liked && (
                                <Box
                                    component="span"
                                    role="img"
                                    aria-label="Liked"
                                    sx={{
                                        alignItems: "center",
                                        bottom: -5,
                                        color: green,
                                        display: "inline-flex",
                                        justifyContent: "center",
                                        lineHeight: 0,
                                        pointerEvents: "none",
                                        position: "absolute",
                                        zIndex: 2,
                                        ...(isOwn
                                            ? { left: -2 }
                                            : { right: -2 }),
                                    }}
                                >
                                    <MessageLikeHeartIcon />
                                </Box>
                            )}
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
    newConversationIds = [],
    onBack,
    onCloseThread,
    onConfirmFriendRequest,
    onDeleteMessage,
    onDeleteFriendRequest,
    onOpenSelectedFriendProfile,
    onOpenQuotePost,
    onOpenThread,
    onLoadActivityPost,
    onReplyToMessage,
    onSendMessage,
    onSetMessageLiked,
    profile,
    profileLink,
    selectedFriend,
    threadBackLabel = "Back to messages",
}) => {
    const [messageText, setMessageText] = React.useState("");
    const [messageContextMenu, setMessageContextMenu] =
        React.useState<MessageContextMenuState | null>(null);
    const [replyingTo, setReplyingTo] = React.useState<SpaceMessage | null>(
        null,
    );
    const [sendPhase, setSendPhase] = React.useState<"idle" | "sending">(
        "idle",
    );
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
    const isThreadOpen = Boolean(selectedFriend);
    const canInteract =
        isThreadOpen && !isThreadReadOnly && !isThreadRecipientLoading;
    const canSend =
        canInteract && messageText.trim().length > 0 && sendPhase == "idle";
    const selectedName = selectedFriend
        ? selectedFriend.fullName.trim() || selectedFriend.username
        : "";
    const showInviteEmptyState = friendsCount == 0 && Boolean(profileLink);
    const emptyConversationsCopy =
        friendsCount == 0
            ? "No messages yet. Once you add friends, you'll see their likes, replies and messages here."
            : "No messages yet. You'll see your friends' likes, replies and messages here.";
    const conversationSections = React.useMemo(
        () => conversationTimeSections(conversations, newConversationIds),
        [conversations, newConversationIds],
    );
    const loadActivityPost = React.useCallback(
        (post: SpaceMessageActivityPost) => {
            if (!onLoadActivityPost) return;
            const key = activityPostKey(post);
            if (
                activityPostsByKey[key] ||
                activityPostLoadsInFlightRef.current.has(key)
            ) {
                return;
            }
            activityPostLoadsInFlightRef.current.add(key);
            void onLoadActivityPost(post)
                .then((loadedPost) => {
                    if (!loadedPost) return;
                    setActivityPostsByKey((currentPosts) =>
                        currentPosts[key]
                            ? currentPosts
                            : { ...currentPosts, [key]: loadedPost },
                    );
                })
                .catch((error: unknown) => {
                    console.warn("Failed to load message activity post", error);
                })
                .finally(() => {
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
    const isContextMessageLiked = Boolean(
        messageContextMenu?.message.viewerLiked,
    );
    const isContextMessageOwn = Boolean(
        messageContextMenu?.message &&
        isCurrentProfileMessage(messageContextMenu.message, profile),
    );

    const sendMessage = () => {
        const text = messageText.trim();
        if (!selectedFriend || !canInteract || !canSend) return;
        const spaceId = selectedFriend.spaceId ?? selectedFriend.id;
        const repliedMessage = replyingTo;
        stickToThreadBottomRef.current = true;
        smoothNextMessageScrollRef.current = true;
        setSendPhase("sending");
        setMessageText("");
        setReplyingTo(null);
        const sendPromise = repliedMessage
            ? onReplyToMessage(spaceId, repliedMessage.id, text)
            : onSendMessage(spaceId, text);
        void sendPromise
            .then(() => {
                setSendPhase("idle");
            })
            .catch((error: unknown) => {
                smoothNextMessageScrollRef.current = false;
                console.error("Failed to send message", error);
                setMessageText((currentText) => currentText || text);
                setReplyingTo(
                    (currentReplyingTo) => currentReplyingTo ?? repliedMessage,
                );
                setSendPhase("idle");
            });
    };

    const openMessageActions = (
        message: SpaceMessage,
        anchorEl: HTMLElement,
        source: MessageActionsOpenSource,
    ) => {
        ignoreMessageActionsMouseAwayUntilRef.current =
            source == "touch"
                ? Date.now() + messageActionsTouchOpenMouseSuppressMs
                : 0;
        setMessageContextMenu({
            anchorEl,
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

    const handleMessageAction = (
        action: "copy" | "delete" | "like" | "reply",
    ) => {
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
                        console.error("Failed to copy message", error),
                );
                break;
            case "like":
                closeMessageActions();
                if (isCurrentProfileMessage(targetMessage, profile)) return;
                void onSetMessageLiked(
                    targetMessage.id,
                    !targetMessage.viewerLiked,
                ).catch((error: unknown) =>
                    console.error("Failed to update message like", error),
                );
                break;
            case "reply":
                flushSync(() => {
                    closeMessageActions();
                    setReplyingTo(targetMessage);
                });
                composerRef.current?.focus();
                break;
            case "delete":
                closeMessageActions();
                void onDeleteMessage(targetMessage.id).catch((error: unknown) =>
                    console.error("Failed to delete message", error),
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
        if (!selectedFriend || !stickToThreadBottomRef.current) return;
        if (smoothNextMessageScrollRef.current) return;
        scrollThreadToBottom();
    }, [messageText, replyingTo, scrollThreadToBottom, selectedFriend]);

    React.useEffect(() => {
        setReplyingTo(null);
        setMessageContextMenu(null);
        setMessageText("");
        stickToThreadBottomRef.current = true;
        smoothNextMessageScrollRef.current = false;
    }, [selectedFriend]);

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
        if (!selectedFriend || isThreadLoading) return;
        if (!stickToThreadBottomRef.current) return;
        if (smoothNextMessageScrollRef.current) {
            smoothNextMessageScrollRef.current = false;
            scheduleThreadBottomScroll("smooth");
            return;
        }
        scrollThreadToBottom();
    }, [
        isThreadLoading,
        scheduleThreadBottomScroll,
        scrollThreadToBottom,
        selectedFriend,
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
        canInteract && !isContextMessageOwn ? (
            <MessageActionMenuItem
                key="like"
                icon={<HeartIcon small />}
                label={isContextMessageLiked ? "Unlike" : "Like"}
                onClick={() => handleMessageAction("like")}
            />
        ) : null,
        canInteract ? (
            <MessageActionMenuItem
                key="reply"
                icon={<ReplyIcon />}
                label="Reply"
                onClick={() => handleMessageAction("reply")}
            />
        ) : null,
        <MessageActionMenuItem
            key="copy"
            icon={<CopyIcon />}
            label="Copy"
            onClick={() => handleMessageAction("copy")}
        />,
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
            <Box
                component="main"
                sx={{
                    bgcolor: messagesBackground,
                    color: textBase,
                    display: "grid",
                    height: isThreadOpen ? "100dvh" : undefined,
                    minHeight: isThreadOpen ? 0 : "100svh",
                    overflow: isThreadOpen ? "hidden" : undefined,
                    overflowX: "hidden",
                    placeItems: { xs: "stretch", sm: "start center" },
                }}
            >
                <Box
                    sx={{
                        bgcolor: "inherit",
                        boxSizing: "border-box",
                        display: isThreadOpen ? "grid" : undefined,
                        gridTemplateRows: isThreadOpen
                            ? isThreadReadOnly
                                ? "56px minmax(0, 1fr)"
                                : "56px minmax(0, 1fr) auto"
                            : undefined,
                        height: isThreadOpen ? "100%" : undefined,
                        minHeight: isThreadOpen ? 0 : "100svh",
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
                            component="button"
                            type="button"
                            aria-label={isThreadOpen ? threadBackLabel : "Back"}
                            onClick={isThreadOpen ? onCloseThread : onBack}
                            sx={{
                                alignItems: "center",
                                bgcolor: "transparent",
                                border: 0,
                                color: "inherit",
                                cursor:
                                    isThreadOpen || onBack
                                        ? "pointer"
                                        : "default",
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
                                ref={threadScrollRef}
                                onScroll={handleThreadScroll}
                                sx={{
                                    boxSizing: "border-box",
                                    minHeight: 0,
                                    overscrollBehaviorY: "contain",
                                    overflowY: "auto",
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
                                                fontWeight: 650,
                                                lineHeight: "20px",
                                                m: 0,
                                            }}
                                        >
                                            {isThreadReadOnly
                                                ? "No messages"
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
                                                                onOpenQuotePost={
                                                                    onOpenQuotePost
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
                                anchorEl={messageContextMenu?.anchorEl ?? null}
                                modifiers={messageActionsPopperModifiers}
                                open={Boolean(messageContextMenu?.open)}
                                placement="bottom-end"
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
                                            style={{
                                                transformOrigin:
                                                    placement.startsWith("top")
                                                        ? "right bottom"
                                                        : "right top",
                                            }}
                                            onExited={() => {
                                                TransitionProps?.onExited();
                                                clearClosedMessageActions();
                                            }}
                                            timeout={
                                                messageActionsTransitionDuration
                                            }
                                        >
                                            <Box
                                                sx={{
                                                    WebkitTapHighlightColor:
                                                        "transparent",
                                                    bgcolor: messagesBackground,
                                                    borderRadius: "16px",
                                                    boxShadow:
                                                        "0 14px 40px rgba(0, 0, 0, 0.14)",
                                                    minWidth: 132,
                                                    outline: 0,
                                                    p: "4px",
                                                }}
                                            >
                                                <MenuList
                                                    autoFocus
                                                    autoFocusItem
                                                    onKeyDown={
                                                        handleMessageActionsKeyDown
                                                    }
                                                    sx={{
                                                        outline: 0,
                                                        p: 0,
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
                                        bgcolor: messagesBackground,
                                        boxSizing: "border-box",
                                        display: "grid",
                                        gap: "8px",
                                        p: "10px 14px calc(10px + env(safe-area-inset-bottom))",
                                        width: "100%",
                                    }}
                                >
                                    {replyingTo && (
                                        <Box
                                            sx={{
                                                bgcolor: lightSurface,
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
                                                border: `1px solid ${composerBorder}`,
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
                                                "&:focus": {
                                                    borderColor: green,
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
                                                    : lightSurfaceHover,
                                                border: 0,
                                                borderRadius: "50%",
                                                color: canSend
                                                    ? "#FFFFFF"
                                                    : textSecondary,
                                                cursor: canSend
                                                    ? "pointer"
                                                    : "default",
                                                display: "flex",
                                                flexShrink: 0,
                                                height: composerHeight,
                                                justifyContent: "center",
                                                opacity: canSend ? 1 : 0.42,
                                                p: 0,
                                                transition:
                                                    "background-color 180ms ease, color 180ms ease, opacity 180ms ease, transform 120ms ease",
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
                                                        : lightSurfaceHover,
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
                        <>
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
                                                console.error(
                                                    "Failed to share space invite",
                                                    error,
                                                )
                                            }
                                            onSharingChange={setIsInviteSharing}
                                            sx={{
                                                alignItems: "center",
                                                bgcolor: "#F2F2F2",
                                                border: 0,
                                                borderRadius: "18px",
                                                color: textBase,
                                                cursor:
                                                    profileLink &&
                                                    !isInviteSharing
                                                        ? "pointer"
                                                        : "default",
                                                display: "inline-flex",
                                                fontFamily:
                                                    '"Inter Variable", Inter, sans-serif',
                                                fontSize: 13,
                                                fontWeight: 600,
                                                gap: "6px",
                                                height: spaceTouchTargetSize,
                                                justifyContent: "center",
                                                lineHeight: "18px",
                                                pointerEvents: "auto",
                                                px: "14px",
                                                whiteSpace: "nowrap",
                                                "&:disabled": { opacity: 0.45 },
                                                "&:focus-visible": {
                                                    outline: `2px solid ${green}`,
                                                    outlineOffset: 2,
                                                },
                                                "&:hover":
                                                    profileLink &&
                                                    !isInviteSharing
                                                        ? { bgcolor: "#E8E8E8" }
                                                        : undefined,
                                            }}
                                        />
                                    )}
                                </Box>
                            ) : (
                                <Box
                                    sx={{
                                        boxSizing: "border-box",
                                        m: 0,
                                        p: "6px 16px 28px",
                                    }}
                                >
                                    {conversationSections.map((section) => (
                                        <ConversationSection
                                            key={section.title}
                                            activityPostsByKey={
                                                activityPostsByKey
                                            }
                                            onConfirmFriendRequest={
                                                onConfirmFriendRequest
                                            }
                                            onDeleteFriendRequest={
                                                onDeleteFriendRequest
                                            }
                                            onLoadActivityPost={
                                                loadActivityPost
                                            }
                                            onOpenFriendProfile={
                                                onOpenSelectedFriendProfile
                                            }
                                            onOpenThread={onOpenThread}
                                            section={section}
                                        />
                                    ))}
                                </Box>
                            )}
                        </>
                    )}
                </Box>
            </Box>
        </>
    );
};
