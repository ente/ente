import { downloadManager } from "@/public-album/download/services/download-manager";
import {
    getPublicAlbumFeed,
    getPublicAnonProfiles,
    getPublicParticipantsMaskedEmails,
    type PublicFeedComment,
    type PublicFeedReaction,
} from "@/public-album/social/api/public-reaction";
import { useBrowserBackClose } from "@/shared/hooks/useBrowserBackClose";
import CloseIcon from "@mui/icons-material/Close";
import {
    Avatar,
    Box,
    CircularProgress,
    Drawer,
    IconButton,
    Stack,
    styled,
    Typography,
} from "@mui/material";
import { useColorScheme } from "@mui/material/styles";
import { useInterval } from "ente-base/components/utils/hooks";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import type { PublicAlbumsCredentials } from "ente-base/http";
import log from "ente-base/log";
import { getAvatarColor } from "ente-gallery/utils/avatar-colors";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { t } from "i18next";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";

// =============================================================================
// Icons
// =============================================================================

const LikedPhotoIcon: React.FC = () => (
    <svg
        width="17"
        height="15"
        viewBox="0 0 17 15"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M6.99906 13.1537C4.84391 11.5421 0.574219 7.85775 0.574219 4.54219C0.574219 2.35074 2.1824 0.574219 4.39366 0.574219C5.5395 0.574219 6.68533 0.956163 8.21311 2.48394C9.74089 0.956163 10.8867 0.574219 12.0326 0.574219C14.2438 0.574219 15.852 2.35074 15.852 4.54219C15.852 7.85775 11.5823 11.5421 9.42716 13.1537C8.70192 13.696 7.7243 13.696 6.99906 13.1537Z"
            fill="#08C225"
            stroke="#08C225"
            strokeWidth="1.14583"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
    </svg>
);

const CommentedPhotoIcon: React.FC = () => (
    <svg
        width="15"
        height="15"
        viewBox="0 0 15 15"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M7.5 14.25C8.83502 14.25 10.1401 13.8541 11.2501 13.1124C12.3601 12.3707 13.2253 11.3165 13.7362 10.0831C14.2471 8.84971 14.3808 7.49252 14.1203 6.18314C13.8598 4.87377 13.217 3.67104 12.273 2.72703C11.329 1.78303 10.1262 1.14015 8.81686 0.879702C7.50749 0.619252 6.15029 0.752925 4.91689 1.26382C3.68349 1.77471 2.62928 2.63987 1.88758 3.7499C1.14588 4.85994 0.75 6.16498 0.75 7.5C0.75 8.616 1.02 9.66825 1.5 10.5953L0.75 14.25L4.40475 13.5C5.33175 13.98 6.38475 14.25 7.5 14.25Z"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
    </svg>
);

const RepliedCommentIcon: React.FC = () => (
    <svg
        width="12"
        height="9"
        viewBox="0 0 12 9"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M4.2334 0.0849609C4.39661 0.0849817 4.55308 0.151147 4.66797 0.268555C4.78252 0.386006 4.84664 0.544829 4.84668 0.709961C4.84668 0.875074 4.78246 1.03389 4.66797 1.15137L2.1748 3.70215H7.76855C8.41316 3.70215 9.34837 3.88326 10.1738 4.42969L10.3379 4.54297L10.5029 4.67188C11.3155 5.34145 11.918 6.39843 11.918 7.94531C11.9179 8.11049 11.8539 8.26927 11.7393 8.38672C11.6244 8.50422 11.4679 8.57119 11.3047 8.57129C11.1413 8.57129 10.985 8.5043 10.8701 8.38672C10.7553 8.26923 10.6905 8.11066 10.6904 7.94531C10.6904 6.70123 10.1974 5.98489 9.61914 5.55859C9.00926 5.10915 8.25891 4.95312 7.76855 4.95312H2.17578L4.66504 7.50098C4.72518 7.55831 4.77424 7.62756 4.80762 7.7041C4.84094 7.78063 4.85886 7.86362 4.86035 7.94727C4.8618 8.03105 4.84614 8.11459 4.81543 8.19238C4.78472 8.27017 4.73883 8.34087 4.68066 8.40039C4.62251 8.45986 4.55306 8.50745 4.47656 8.53906C4.40013 8.57058 4.31786 8.58645 4.23535 8.58496C4.1528 8.58343 4.07139 8.5646 3.99609 8.53027C3.9207 8.4959 3.85295 8.44634 3.79688 8.38477V8.38379L0.263672 4.76953C0.148973 4.65203 0.0849609 4.49242 0.0849609 4.32715C0.085085 4.16205 0.149084 4.00313 0.263672 3.88574L3.79883 0.268555C3.91373 0.151128 4.07015 0.0849609 4.2334 0.0849609Z"
            fill="currentColor"
            stroke="currentColor"
            strokeWidth="0.166667"
        />
    </svg>
);

const LikedCommentIcon: React.FC<{ heartStroke?: string }> = ({
    heartStroke = "white",
}) => (
    <svg
        width="22"
        height="21"
        viewBox="0 0 22 21"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M9.16797 16.043C10.5277 16.043 11.8569 15.6398 12.9875 14.8843C14.1181 14.1289 14.9993 13.0552 15.5196 11.7989C16.04 10.5427 16.1761 9.16035 15.9109 7.82673C15.6456 6.49311 14.9908 5.2681 14.0293 4.30661C13.0678 3.34513 11.8428 2.69035 10.5092 2.42507C9.17559 2.1598 7.79326 2.29595 6.53702 2.8163C5.28078 3.33665 4.20705 4.21784 3.45162 5.34843C2.69618 6.47901 2.29297 7.80823 2.29297 9.16797C2.29297 10.3046 2.56797 11.3764 3.05686 12.3205L2.29297 16.043L6.0154 15.2791C6.95957 15.768 8.03207 16.043 9.16797 16.043Z"
            stroke="currentColor"
            strokeWidth="1.52778"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
        <path
            d="M17.3555 10.0986C18.9264 10.0987 20.0537 11.3666 20.0537 12.8887C20.0536 14.0427 19.3203 15.2043 18.4863 16.1631C17.6399 17.1362 16.6287 17.9692 15.9541 18.4736C15.3852 18.899 14.6148 18.899 14.0459 18.4736C13.3713 17.9692 12.3601 17.1362 11.5137 16.1631C10.6797 15.2043 9.94638 14.0427 9.94629 12.8887C9.94629 11.3666 11.0736 10.0986 12.6445 10.0986C13.3933 10.0986 14.1193 10.34 15 11.1455C15.8807 10.34 16.6067 10.0986 17.3555 10.0986Z"
            stroke={heartStroke}
            strokeWidth="0.685221"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
        <path
            d="M14.2513 18.1992C12.9222 17.2053 10.2891 14.9332 10.2891 12.8885C10.2891 11.537 11.2808 10.4414 12.6445 10.4414C13.3511 10.4414 14.0578 10.677 15 11.6191C15.9421 10.677 16.6488 10.4414 17.3554 10.4414C18.7191 10.4414 19.7109 11.537 19.7109 12.8885C19.7109 14.9332 17.0777 17.2053 15.7487 18.1992C15.3014 18.5336 14.6985 18.5336 14.2513 18.1992Z"
            fill="#08C225"
            stroke="#08C225"
            strokeWidth="0.685221"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
    </svg>
);

// =============================================================================
// Types
// =============================================================================

/**
 * Information about a feed item click for navigation purposes.
 */
export interface PublicFeedItemClickInfo {
    /** The type of feed item. */
    type: PublicFeedItem["type"];
    /** The file ID to navigate to. */
    fileID: number;
    /**
     * The comment ID to highlight (for comment-related items).
     * For `replied_comment`, this is the reply's comment ID.
     * For `liked_comment`, this is the target comment ID.
     */
    commentID?: string;
    /**
     * Snapshot of resolved anonymous display names from the feed.
     * This lets the viewer open with stable names instead of briefly falling
     * back to anonymous placeholders before its own profile fetch completes.
     */
    anonUserNames?: Map<string, string>;
}

export interface PublicFeedSidebarProps extends ModalVisibilityProps {
    /**
     * The files in the album, used to display thumbnails and determine file type.
     */
    files?: EnteFile[];
    /**
     * Public album credentials for API access.
     */
    credentials: PublicAlbumsCredentials;
    /**
     * The decrypted collection key (base64 encoded).
     */
    collectionKey: string;
    /**
     * Called when a feed item is clicked for navigation.
     */
    onItemClick?: (info: PublicFeedItemClickInfo) => void;
    /**
     * Called after the drawer finishes its close transition.
     */
    onExited?: () => void;
}

/** A user who performed an action in the feed. */
interface FeedUser {
    userID: number;
    anonUserID?: string;
    userName: string;
    /** Email/identifier used for avatar color. */
    email: string;
}

/** Base interface for all feed items. */
interface BaseFeedItem {
    /** Unique identifier for this feed item (for React keys). */
    id: string;
    /** Timestamp of the most recent action in this item. */
    timestamp: number;
}

/** Someone liked a photo/video (grouped by file). */
interface LikedFileFeedItem extends BaseFeedItem {
    type: "liked_photo" | "liked_video";
    fileID: number;
    thumbnailURL?: string;
    users: FeedUser[];
}

/** Someone commented on a photo/video. */
interface CommentedFileFeedItem extends BaseFeedItem {
    type: "commented_photo" | "commented_video";
    fileID: number;
    /** The ID of the comment for navigation. */
    commentID: string;
    thumbnailURL?: string;
    user: FeedUser;
}

/** Someone replied to a comment. */
interface RepliedCommentFeedItem extends BaseFeedItem {
    type: "replied_comment";
    /** The parent comment ID. */
    parentCommentID: string;
    /** The ID of the reply for navigation. */
    replyID: string;
    fileID?: number;
    thumbnailURL?: string;
    user: FeedUser;
}

/** Someone liked a comment (grouped by comment, includes reply likes). */
interface LikedCommentFeedItem extends BaseFeedItem {
    type: "liked_comment";
    commentID: string;
    fileID?: number;
    thumbnailURL?: string;
    users: FeedUser[];
}

type PublicFeedItem =
    | LikedFileFeedItem
    | CommentedFileFeedItem
    | RepliedCommentFeedItem
    | LikedCommentFeedItem;

/** Thumbnail URL cache for files. */
type ThumbnailCache = Map<number, string>;

/** File type cache for determining photo vs video. */
type FileTypeCache = Map<number, number>;

// =============================================================================
// Utility Functions
// =============================================================================

/**
 * Get the display name for a user.
 * For anonymous users, uses their entered name from userName.
 * Falls back to "Anonymous" only if userName is empty.
 */
const getUserDisplayName = (
    userID: number,
    userName: string,
    anonUserID?: string,
): string => {
    if (userID === -1 || userID === 0 || anonUserID) {
        return userName || t("anonymous");
    }
    return userName;
};

/**
 * Process feed items from public album data.
 *
 * For public albums, we show ALL actions from everyone:
 * - X liked a photo/video
 * - A liked a comment (includes reply likes)
 * - M commented on a photo/video
 * - C replied to a comment
 */
const processFeedItems = (
    comments: PublicFeedComment[],
    reactions: PublicFeedReaction[],
    thumbnailCache: ThumbnailCache,
    fileTypeCache: FileTypeCache,
    maskedEmails: Map<number, string>,
    anonUserNames: Map<string, string>,
): PublicFeedItem[] => {
    const feedItems: PublicFeedItem[] = [];

    // Build a map from commentID to fileID for looking up comment likes
    const commentFileIDMap = new Map<string, number>();
    for (const c of comments) {
        if (c.fileID) {
            commentFileIDMap.set(c.id, c.fileID);
        }
    }

    // Helper to get display name for a user
    const getUserName = (userID: number, anonUserID?: string): string => {
        if (anonUserID) {
            return (
                anonUserNames.get(anonUserID) ??
                `${t("anonymous")} ${anonUserID.slice(-4)}`
            );
        }
        return maskedEmails.get(userID) ?? t("unknown_user");
    };

    // Helper to get avatar color key
    const getAvatarColorKey = (userID: number, anonUserID?: string): string => {
        if (anonUserID) {
            return anonUserNames.get(anonUserID) ?? anonUserID;
        }
        return maskedEmails.get(userID) ?? String(userID);
    };

    // Helper to get thumbnail URL from cache
    const getThumbnailURL = (fileID: number | undefined): string | undefined =>
        fileID ? thumbnailCache.get(fileID) : undefined;

    // Helper to determine if file is video
    const isVideo = (fileID: number | undefined): boolean => {
        if (!fileID) return false;
        const fileType = fileTypeCache.get(fileID);
        return fileType === FileType.video;
    };

    // 1. Process comments - categorize as "commented_photo/video" or "replied_comment"
    for (const c of comments) {
        if (c.isDeleted) continue;

        const displayName = getUserName(c.userID, c.anonUserID);
        const avatarColorKey = getAvatarColorKey(c.userID, c.anonUserID);

        if (c.isReply && c.parentCommentID) {
            // This is a reply to a comment
            feedItems.push({
                id: `replied_comment_${c.id}`,
                type: "replied_comment",
                parentCommentID: c.parentCommentID,
                replyID: c.id,
                fileID: c.fileID,
                thumbnailURL: getThumbnailURL(c.fileID),
                timestamp: c.createdAt,
                user: {
                    userID: c.userID,
                    anonUserID: c.anonUserID,
                    userName: displayName,
                    email: avatarColorKey,
                },
            });
        } else if (c.fileID) {
            // This is a comment on a photo/video
            const fileIsVideo = isVideo(c.fileID);
            feedItems.push({
                id: `commented_file_${c.id}`,
                type: fileIsVideo ? "commented_video" : "commented_photo",
                fileID: c.fileID,
                commentID: c.id,
                thumbnailURL: getThumbnailURL(c.fileID),
                timestamp: c.createdAt,
                user: {
                    userID: c.userID,
                    anonUserID: c.anonUserID,
                    userName: displayName,
                    email: avatarColorKey,
                },
            });
        }
    }

    // 2. Process reactions - group by file or comment
    // Group file likes by fileID
    const fileLikes = new Map<
        number,
        { users: FeedUser[]; latestTimestamp: number; isVideo: boolean }
    >();
    // Group comment likes by commentID (includes reply likes)
    const commentLikes = new Map<
        string,
        { users: FeedUser[]; latestTimestamp: number; fileID?: number }
    >();

    for (const r of reactions) {
        if (r.isDeleted) continue;

        const userName = getUserName(r.userID, r.anonUserID);
        const email = getAvatarColorKey(r.userID, r.anonUserID);
        const user: FeedUser = {
            userID: r.userID,
            anonUserID: r.anonUserID,
            userName,
            email,
        };

        if (r.fileID && !r.commentID) {
            // Reaction on a file (photo/video)
            const fileID = r.fileID;
            const existing = fileLikes.get(fileID);
            if (existing) {
                existing.users.push(user);
                if (r.createdAt > existing.latestTimestamp) {
                    existing.latestTimestamp = r.createdAt;
                    // Move most recent user to front
                    existing.users.pop();
                    existing.users.unshift(user);
                }
            } else {
                fileLikes.set(fileID, {
                    users: [user],
                    latestTimestamp: r.createdAt,
                    isVideo: isVideo(fileID),
                });
            }
        } else if (r.commentID) {
            // Reaction on a comment (treat reply likes as comment likes)
            const commentID = r.commentID;
            // Look up fileID from comment if not present in reaction
            const fileID = r.fileID || commentFileIDMap.get(commentID);
            const existing = commentLikes.get(commentID);
            if (existing) {
                existing.users.push(user);
                if (r.createdAt > existing.latestTimestamp) {
                    existing.latestTimestamp = r.createdAt;
                    existing.users.pop();
                    existing.users.unshift(user);
                }
            } else {
                commentLikes.set(commentID, {
                    users: [user],
                    latestTimestamp: r.createdAt,
                    fileID,
                });
            }
        }
    }

    // Add grouped file likes to feed
    for (const [fileID, data] of fileLikes) {
        feedItems.push({
            id: `liked_file_${fileID}`,
            type: data.isVideo ? "liked_video" : "liked_photo",
            fileID,
            thumbnailURL: getThumbnailURL(fileID),
            timestamp: data.latestTimestamp,
            users: data.users,
        });
    }

    // Add grouped comment likes to feed (includes reply likes)
    for (const [commentID, data] of commentLikes) {
        feedItems.push({
            id: `liked_comment_${commentID}`,
            type: "liked_comment",
            commentID,
            fileID: data.fileID,
            thumbnailURL: getThumbnailURL(data.fileID),
            timestamp: data.latestTimestamp,
            users: data.users,
        });
    }

    // Sort by timestamp (newest first)
    return feedItems.sort((a, b) => b.timestamp - a.timestamp);
};

/**
 * Get the action text for a feed item.
 */
const getActionText = (item: PublicFeedItem): string => {
    switch (item.type) {
        case "liked_photo":
            return t("liked_a_photo");
        case "liked_video":
            return t("liked_a_video");
        case "commented_photo":
            return t("commented_on_a_photo");
        case "commented_video":
            return t("commented_on_a_video");
        case "replied_comment":
            return t("replied_to_a_comment");
        case "liked_comment":
            return t("liked_a_comment");
    }
};

/**
 * Get the users string for display (e.g., "John and 2 others").
 */
const getUsersDisplayText = (users: FeedUser[]): string => {
    if (users.length === 0) return "";
    const firstName = getUserDisplayName(
        users[0]!.userID,
        users[0]!.userName,
        users[0]!.anonUserID,
    );
    if (users.length === 1) {
        return firstName;
    }
    const othersCount = users.length - 1;
    return `${firstName} and ${othersCount} ${othersCount === 1 ? "other" : "others"}`;
};

/**
 * Get the icon component for a feed item type.
 */
const getFeedIcon = (
    type: PublicFeedItem["type"],
    heartStroke: string,
): React.ReactNode => {
    switch (type) {
        case "liked_photo":
        case "liked_video":
            return <LikedPhotoIcon />;
        case "commented_photo":
        case "commented_video":
            return <CommentedPhotoIcon />;
        case "replied_comment":
            return <RepliedCommentIcon />;
        case "liked_comment":
            return <LikedCommentIcon heartStroke={heartStroke} />;
    }
};

// =============================================================================
// Feed Item Row Component
// =============================================================================

interface FeedItemRowProps {
    item: PublicFeedItem;
    onClick?: () => void;
}

/**
 * Get the users array from a feed item.
 */
const getFeedItemUsers = (item: PublicFeedItem): FeedUser[] => {
    switch (item.type) {
        case "commented_photo":
        case "commented_video":
        case "replied_comment":
            return [item.user];
        case "liked_photo":
        case "liked_video":
        case "liked_comment":
            return item.users;
    }
};

/**
 * A single row in the feed showing an action.
 */
const FeedItemRow: React.FC<FeedItemRowProps> = ({ item, onClick }) => {
    const { mode, systemMode } = useColorScheme();
    const users = getFeedItemUsers(item);

    const displayText = getUsersDisplayText(users);
    const actionText = getActionText(item);
    const resolvedMode = mode === "system" ? systemMode : mode;
    const heartStroke = resolvedMode === "dark" ? "#1b1b1b" : "white";

    return (
        <FeedItemContainer onClick={onClick}>
            <IconContainer>{getFeedIcon(item.type, heartStroke)}</IconContainer>
            <FeedItemContent>
                <AvatarStack>
                    {users.slice(0, 3).map((user, index) => {
                        const displayName = getUserDisplayName(
                            user.userID,
                            user.userName,
                            user.anonUserID,
                        );
                        return (
                            <StyledAvatar
                                key={`${user.userID}-${user.anonUserID ?? index}`}
                                sx={{
                                    zIndex: users.length - index,
                                    bgcolor: getAvatarColor(user.email),
                                    color: "#fff",
                                }}
                            >
                                {displayName[0]?.toUpperCase() ?? "A"}
                            </StyledAvatar>
                        );
                    })}
                </AvatarStack>
                <UserNameText>{displayText}</UserNameText>
                <ActionText>{actionText}</ActionText>
            </FeedItemContent>
            {item.thumbnailURL && (
                <ThumbnailImage src={item.thumbnailURL} alt="" />
            )}
        </FeedItemContainer>
    );
};

// =============================================================================
// Main Component
// =============================================================================

/**
 * Extracts navigation info from a feed item for click handling.
 */
const getFeedItemClickInfo = (
    item: PublicFeedItem,
    anonUserNames: Map<string, string>,
): PublicFeedItemClickInfo => {
    const clickInfoBase = { anonUserNames: new Map(anonUserNames) };

    switch (item.type) {
        case "liked_photo":
        case "liked_video":
            return { ...clickInfoBase, type: item.type, fileID: item.fileID };
        case "commented_photo":
        case "commented_video":
            return {
                ...clickInfoBase,
                type: item.type,
                fileID: item.fileID,
                commentID: item.commentID,
            };
        case "replied_comment":
            return {
                ...clickInfoBase,
                type: item.type,
                fileID: item.fileID!,
                commentID: item.replyID,
            };
        case "liked_comment":
            return {
                ...clickInfoBase,
                type: item.type,
                fileID: item.fileID!,
                commentID: item.commentID,
            };
    }
};

/**
 * A sidebar panel for displaying the activity feed for a public album.
 */
export const PublicFeedSidebar: React.FC<PublicFeedSidebarProps> = ({
    open,
    onClose,
    files = [],
    credentials,
    collectionKey,
    onItemClick,
    onExited,
}) => {
    const { clearBrowserBackState } = useBrowserBackClose({
        open,
        onClose,
        stateKey: "__entePublicFeedSidebarBackState",
    });

    const [thumbnailCache, setThumbnailCache] = useState<ThumbnailCache>(
        new Map(),
    );
    const [fileTypeCache, setFileTypeCache] = useState<FileTypeCache>(
        new Map(),
    );
    const [comments, setComments] = useState<PublicFeedComment[]>([]);
    const [reactions, setReactions] = useState<PublicFeedReaction[]>([]);
    const [maskedEmails, setMaskedEmails] = useState<Map<number, string>>(
        new Map(),
    );
    const [anonUserNames, setAnonUserNames] = useState<Map<string, string>>(
        new Map(),
    );
    const [isLoading, setIsLoading] = useState(false);
    const thumbnailCacheRef = useRef(thumbnailCache);
    const thumbnailLoadsInFlightRef = useRef<Set<number>>(new Set());
    const canSetThumbnailCacheRef = useRef(open);

    useEffect(() => {
        thumbnailCacheRef.current = thumbnailCache;
    }, [thumbnailCache]);

    useEffect(() => {
        canSetThumbnailCacheRef.current = open;
    }, [open]);

    useEffect(
        () => () => {
            canSetThumbnailCacheRef.current = false;
        },
        [],
    );

    // Build file type cache from files
    useEffect(() => {
        if (!open) return;

        const cache = new Map<number, number>();
        for (const file of files) {
            cache.set(file.id, file.metadata.fileType);
        }
        setFileTypeCache(cache);
    }, [open, files]);

    // Load thumbnails for active feed items in parallel and show each one as
    // soon as it is ready instead of waiting for the entire batch to finish.
    useEffect(() => {
        if (!open || (comments.length === 0 && reactions.length === 0)) return;

        const fileIDsWithActivity = new Set<number>();

        for (const c of comments) {
            if (!c.fileID) continue;
            fileIDsWithActivity.add(c.fileID);
        }

        for (const r of reactions) {
            fileIDsWithActivity.add(r.fileID);
        }

        const filesToLoad = files.filter(
            (file) =>
                fileIDsWithActivity.has(file.id) &&
                !thumbnailCacheRef.current.has(file.id) &&
                !thumbnailLoadsInFlightRef.current.has(file.id),
        );

        if (filesToLoad.length === 0) return;

        for (const file of filesToLoad) {
            thumbnailLoadsInFlightRef.current.add(file.id);
        }

        void Promise.allSettled(
            filesToLoad.map(async (file) => {
                try {
                    const url =
                        await downloadManager.renderableThumbnailURL(file);
                    if (!url || !canSetThumbnailCacheRef.current) return;

                    setThumbnailCache((prev) => {
                        if (prev.get(file.id) === url) return prev;

                        const next = new Map(prev);
                        next.set(file.id, url);
                        thumbnailCacheRef.current = next;
                        return next;
                    });
                } catch (e) {
                    log.warn(
                        `Failed to fetch feed thumbnail for file ${file.id}`,
                        e,
                    );
                } finally {
                    thumbnailLoadsInFlightRef.current.delete(file.id);
                }
            }),
        );
    }, [open, comments, reactions, files]);

    // Polling interval for refreshing feed data (5 seconds)
    const FEED_REFRESH_INTERVAL_MS = 5_000;

    // Refresh social data (used for periodic refresh - excludes masked emails)
    const refreshSocialData = useCallback(async () => {
        try {
            const [feedData, anonProfiles] = await Promise.all([
                getPublicAlbumFeed(credentials, collectionKey),
                getPublicAnonProfiles(credentials, collectionKey),
            ]);
            setComments(feedData.comments);
            setReactions(feedData.reactions);
            setAnonUserNames(anonProfiles);
            // Note: Masked emails for registered participants are fetched only
            // on initial load since they rarely change during a session.
        } catch (e) {
            log.error("Failed to refresh public album feed", e);
        }
    }, [credentials, collectionKey]);

    // Initial fetch when sidebar opens (includes masked emails)
    useEffect(() => {
        if (!open) return;

        const fetchInitialData = async () => {
            try {
                const [feedData, anonProfiles, participantEmails] =
                    await Promise.all([
                        getPublicAlbumFeed(credentials, collectionKey),
                        getPublicAnonProfiles(credentials, collectionKey),
                        getPublicParticipantsMaskedEmails(credentials),
                    ]);
                setComments(feedData.comments);
                setReactions(feedData.reactions);
                setAnonUserNames(anonProfiles);
                setMaskedEmails(participantEmails);
            } catch (e) {
                log.error("Failed to fetch public album feed", e);
            }
        };

        setIsLoading(true);
        void fetchInitialData().finally(() => setIsLoading(false));
    }, [open, credentials, collectionKey]);

    // Periodic refresh while sidebar is open
    useInterval(
        refreshSocialData,
        open && !isLoading ? FEED_REFRESH_INTERVAL_MS : null,
    );

    const feedItems = useMemo(
        () =>
            processFeedItems(
                comments,
                reactions,
                thumbnailCache,
                fileTypeCache,
                maskedEmails,
                anonUserNames,
            ),
        [
            comments,
            reactions,
            thumbnailCache,
            fileTypeCache,
            maskedEmails,
            anonUserNames,
        ],
    );

    return (
        <SidebarDrawer
            open={open}
            onClose={onClose}
            anchor="right"
            slotProps={{ transition: { onExited } }}
        >
            <DrawerContentWrapper>
                <Header>
                    <Typography
                        sx={(theme) => ({
                            color: "#000",
                            fontWeight: 600,
                            ...theme.applyStyles("dark", { color: "#fff" }),
                        })}
                    >
                        {t("activity")}
                    </Typography>
                    <CloseButton onClick={onClose}>
                        <CloseIcon sx={{ fontSize: 22 }} />
                    </CloseButton>
                </Header>

                <ContentContainer>
                    {isLoading ? (
                        <LoadingContainer>
                            <CircularProgress size={24} />
                        </LoadingContainer>
                    ) : feedItems.length === 0 ? (
                        <EmptyStateText>{t("no_activity_yet")}</EmptyStateText>
                    ) : (
                        feedItems.map((item) => (
                            <FeedItemRow
                                key={item.id}
                                item={item}
                                onClick={
                                    onItemClick
                                        ? () => {
                                              const info = getFeedItemClickInfo(
                                                  item,
                                                  anonUserNames,
                                              );
                                              void clearBrowserBackState(
                                                  "back",
                                              ).then(() => onItemClick(info));
                                          }
                                        : undefined
                                }
                            />
                        ))
                    )}
                </ContentContainer>
            </DrawerContentWrapper>
        </SidebarDrawer>
    );
};

// =============================================================================
// Styled Components
// =============================================================================

// Drawer & Layout
const SidebarDrawer = styled(Drawer)(({ theme }) => ({
    zIndex: 2100, // Above TripLayout nav buttons (z-index: 2000)
    "& .MuiDrawer-paper": {
        width: "23vw",
        minWidth: "520px",
        maxWidth: "calc(100% - 32px)",
        height: "calc(100% - 32px)",
        margin: "16px",
        borderRadius: "36px",
        backgroundColor: "#FAFAFA",
        padding: "24px 24px 32px 24px",
        boxShadow: "none",
        border: "1px solid #E0E0E0",
        display: "flex",
        flexDirection: "column",
        overflow: "visible",
        "@media (max-width: 450px)": {
            width: "100%",
            minWidth: "unset",
            maxWidth: "100%",
            height: "100%",
            margin: 0,
            borderRadius: 0,
        },
        ...theme.applyStyles("dark", {
            backgroundColor: "#1b1b1b",
            border: "1px solid rgba(255, 255, 255, 0.18)",
        }),
    },
    "& .MuiBackdrop-root": { backgroundColor: "rgba(0, 0, 0, 0.65)" },
}));

const DrawerContentWrapper = styled(Box)(() => ({
    position: "relative",
    display: "flex",
    flexDirection: "column",
    flex: 1,
    minHeight: 0,
}));

const Header = styled(Stack)(() => ({
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginBottom: 48,
}));

const CloseButton = styled(IconButton)(({ theme }) => ({
    backgroundColor: "#F5F5F7",
    color: "#000",
    padding: "8px",
    "&:hover": { backgroundColor: "#E5E5E7" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255, 255, 255, 0.12)",
        color: "#fff",
        "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.16)" },
    }),
}));

const ContentContainer = styled(Box)(({ theme }) => ({
    flex: 1,
    overflow: "auto",
    marginRight: -24,
    paddingRight: 24,
    "&::-webkit-scrollbar": { width: "6px" },
    "&::-webkit-scrollbar-track": { background: "transparent" },
    "&::-webkit-scrollbar-thumb": {
        background: "rgba(0, 0, 0, 0.2)",
        borderRadius: "3px",
    },
    scrollbarWidth: "thin",
    scrollbarColor: "rgba(0, 0, 0, 0.2) transparent",
    ...theme.applyStyles("dark", {
        "&::-webkit-scrollbar-thumb": {
            background: "rgba(255, 255, 255, 0.2)",
        },
        scrollbarColor: "rgba(255, 255, 255, 0.2) transparent",
    }),
}));

// Feed Item Components
const FeedItemContainer = styled(Box)(({ theme }) => ({
    display: "flex",
    alignItems: "flex-start",
    gap: 12,
    marginBottom: 40,
    cursor: "pointer",
    position: "relative",
    "&:not(:last-child)::before": {
        content: '""',
        position: "absolute",
        left: 16,
        top: 33,
        bottom: -40,
        width: 2,
        backgroundImage:
            "repeating-linear-gradient(to bottom, #E6E6E6 0px, #E6E6E6 8px, transparent 8px, transparent 16px)",
        borderRadius: 1,
        ...theme.applyStyles("dark", {
            backgroundImage:
                "repeating-linear-gradient(to bottom, rgba(255, 255, 255, 0.18) 0px, rgba(255, 255, 255, 0.18) 8px, transparent 8px, transparent 16px)",
        }),
    },
    "&:last-child": { marginBottom: 0 },
}));

const IconContainer = styled(Box)(({ theme }) => ({
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    width: 33,
    height: 33,
    flexShrink: 0,
    backgroundColor: "#fff",
    borderRadius: "50%",
    position: "relative",
    zIndex: 1,
    ...theme.applyStyles("dark", { backgroundColor: "#2a2a2a" }),
}));

const FeedItemContent = styled(Box)(() => ({
    display: "flex",
    flexDirection: "column",
    gap: 4,
    flex: 1,
    minWidth: 0,
}));

const AvatarStack = styled(Box)(() => ({
    display: "flex",
    flexDirection: "row",
    alignItems: "center",
}));

const StyledAvatar = styled(Avatar)(({ theme }) => ({
    width: 32,
    height: 32,
    fontSize: 14,
    fontWeight: 600,
    border: "2px solid #FAFAFA",
    marginLeft: -8,
    "&:first-of-type": { marginLeft: 0 },
    ...theme.applyStyles("dark", { border: "2px solid #1b1b1b" }),
}));

const UserNameText = styled(Typography)(({ theme }) => ({
    fontWeight: 600,
    fontSize: 14,
    color: "#000",
    whiteSpace: "nowrap",
    overflow: "hidden",
    textOverflow: "ellipsis",
    ...theme.applyStyles("dark", { color: "#fff" }),
}));

const ActionText = styled(Typography)(({ theme }) => ({
    fontSize: 13,
    color: "#666",
    whiteSpace: "nowrap",
    overflow: "hidden",
    textOverflow: "ellipsis",
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.7)" }),
}));

const ThumbnailImage = styled("img")(() => ({
    width: 76,
    height: 76,
    borderRadius: 8,
    objectFit: "cover",
    flexShrink: 0,
}));

const LoadingContainer = styled(Box)(() => ({
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    height: "100%",
    // Offset for header (marginBottom: 48) + padding diff (32-24=8) = 56, halved
    marginTop: -28,
}));

const EmptyStateText = styled(Typography)(({ theme }) => ({
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    height: "100%",
    // Offset for header (marginBottom: 48) + padding diff (32-24=8) = 56, halved
    marginTop: -28,
    color: "#666",
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.6)" }),
}));
