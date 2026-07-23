import CloseIcon from "@mui/icons-material/Close";
import {
    Avatar,
    Box,
    CircularProgress,
    Drawer,
    IconButton,
    Menu,
    MenuItem,
    Stack,
    styled,
    TextField,
    Typography,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import log from "ente-base/log";
import {
    useResolvedContactAvatar,
    useResolvedContactDisplay,
} from "ente-contacts-web";
import { downloadManager } from "ente-gallery/services/download";
import { getAvatarColor } from "ente-gallery/utils/avatar-colors";
import type { EnteFile } from "ente-media/file";
import { getCollectionByID } from "ente-new/photos/services/collection";
import type { CollectionSummaries } from "ente-new/photos/services/collection-summary";
import {
    addComment,
    deleteComment,
    type Comment,
} from "ente-new/photos/services/comment";
import {
    addCommentReaction,
    deleteReaction,
} from "ente-new/photos/services/reaction";
import type { UnifiedReaction } from "ente-new/photos/services/social";
import i18n, { t } from "i18next";
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

const SendIcon: React.FC = () => (
    <svg
        width="18"
        height="16"
        viewBox="0 0 15 13"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M2.03872 4.50697L2.47372 5.26697C2.75072 5.75197 2.88872 5.99397 2.88872 6.25997C2.88872 6.52597 2.75072 6.76797 2.47372 7.25197L2.03872 8.01297C0.800717 10.18 0.181717 11.263 0.663717 11.801C1.14672 12.338 2.29072 11.838 4.57672 10.838L10.8527 8.09197C12.6477 7.30697 13.5457 6.91397 13.5457 6.25997C13.5457 5.60597 12.6477 5.21297 10.8527 4.42797L4.57672 1.68197C2.29072 0.681968 1.14672 0.181968 0.663717 0.718968C0.181717 1.25597 0.800717 2.33897 2.03872 4.50697Z"
            stroke="currentColor"
        />
    </svg>
);

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

interface HeartIconProps {
    filled?: boolean;
    small?: boolean;
}

const HeartIcon: React.FC<HeartIconProps> = ({ filled, small }) => (
    <svg
        width={small ? "13" : "16"}
        height={small ? "11" : "14"}
        viewBox="0 0 16 14"
        fill={filled ? "#08C225" : "none"}
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M6.63749 12.3742C4.66259 10.885 0.75 7.4804 0.75 4.41664C0.75 2.39161 2.22368 0.75 4.25 0.75C5.3 0.75 6.35 1.10294 7.75 2.51469C9.15 1.10294 10.2 0.75 11.25 0.75C13.2763 0.75 14.75 2.39161 14.75 4.41664C14.75 7.4804 10.8374 10.885 8.86251 12.3742C8.19793 12.8753 7.30207 12.8753 6.63749 12.3742Z"
            stroke={filled ? "#08C225" : "currentColor"}
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

const ChevronDownIcon: React.FC = () => (
    <svg
        width="22"
        height="22"
        viewBox="0 0 20 20"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        style={{ marginLeft: -6, transform: "translateY(-2px)" }}
    >
        <path
            d="M10.0007 12.5004L6.46484 8.96544L7.64401 7.78711L10.0007 10.1438L12.3573 7.78711L13.5365 8.96544L10.0007 12.5004Z"
            fill="currentColor"
        />
    </svg>
);

const PersonIcon: React.FC = () => (
    <svg
        width="16"
        height="16"
        viewBox="0 0 24 24"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M12 12C14.21 12 16 10.21 16 8C16 5.79 14.21 4 12 4C9.79 4 8 5.79 8 8C8 10.21 9.79 12 12 12ZM12 14C9.33 14 4 15.34 4 18V20H20V18C20 15.34 14.67 14 12 14Z"
            fill="currentColor"
        />
    </svg>
);

// =============================================================================
// Types
// =============================================================================

/** Collection info for the dropdown. */
interface CollectionInfo {
    id: number;
    name: string;
    commentCount: number;
    coverFile?: EnteFile;
}

// =============================================================================
// Utility Functions
// =============================================================================

const formatTimeAgo = (timestampMicros: number): string => {
    // Server timestamps are in microseconds, convert to milliseconds
    const timestampMs = Math.floor(timestampMicros / 1000);
    const now = Date.now();
    const diff = now - timestampMs;
    const minutes = Math.floor(diff / 60000);
    if (minutes < 1) return t("just_now");
    if (minutes < 60) return t("minutes_ago", { count: minutes });
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return t("hours_ago", { count: hours });
    const days = Math.floor(hours / 24);
    if (days < 7) return t("days_ago", { count: days });

    // For 7+ days, show actual date using locale-aware formatting
    const date = new Date(timestampMs);
    const currentYear = new Date(now).getFullYear();
    const locale = i18n.language;
    if (date.getFullYear() === currentYear) {
        return date.toLocaleDateString(locale, {
            month: "short",
            day: "numeric",
        });
    }
    return date.toLocaleDateString(locale, {
        month: "short",
        day: "numeric",
        year: "numeric",
    });
};

const getParentComment = (
    parentID: string | undefined,
    comments: Comment[],
): Comment | undefined => {
    if (!parentID) return undefined;
    return comments.find((c) => c.id === parentID);
};

/**
 * Truncates comment text to first 100 characters of the first line.
 * Adds "..." if multiline or if first line exceeds 100 chars.
 */
const truncateCommentText = (text: string): string => {
    const lines = text.split("\n");
    const firstLine = lines[0] ?? text;
    const isMultiline = lines.length > 1;
    if (firstLine.length > 100) {
        return firstLine.slice(0, 100) + "...";
    }
    return isMultiline ? firstLine + "..." : firstLine;
};

// =============================================================================
// Shared Comment Components
// =============================================================================

interface CommentHeaderProps {
    userName: string;
    timestamp: number;
    avatarSize?: number;
    isMaskedEmail?: boolean;
    /** Key used for computing avatar color (e.g., anonUserID for anonymous users). */
    avatarColorKey?: string;
    userID?: number;
    email?: string;
    useContactDisplay?: boolean;
}

/**
 * Header component showing avatar, username, and timestamp.
 * Used consistently for both root comments and replies.
 */
const CommentHeader: React.FC<CommentHeaderProps> = ({
    userName,
    timestamp,
    avatarSize = 32,
    isMaskedEmail,
    avatarColorKey,
    userID,
    email,
    useContactDisplay,
}) => {
    const resolved = useResolvedContactAvatar({
        userID: useContactDisplay ? userID : undefined,
        email: useContactDisplay ? email : undefined,
    });
    const displayName = useContactDisplay
        ? resolved.primaryLabel || userName
        : userName;

    return (
        <CommentHeaderContainer>
            <Avatar
                sx={{
                    width: avatarSize,
                    height: avatarSize,
                    fontSize: 14,
                    bgcolor: getAvatarColor(
                        avatarColorKey ?? email ?? userName,
                    ),
                    color: "#fff",
                }}
                src={useContactDisplay ? resolved.avatarURL : undefined}
            >
                {isMaskedEmail ? (
                    <PersonIcon />
                ) : useContactDisplay && resolved.source === "contact" ? (
                    resolved.initial
                ) : (
                    userName[0]?.toUpperCase()
                )}
            </Avatar>
            <UserName>{displayName}</UserName>
            <Separator>•</Separator>
            <Timestamp>{formatTimeAgo(timestamp)}</Timestamp>
        </CommentHeaderContainer>
    );
};

interface QuotedReplyProps {
    parentComment: Comment;
    isOwn: boolean;
    currentUserID?: number;
    userIDToEmail?: Map<number, string>;
    anonUserNames?: Map<string, string>;
    currentAnonUserID?: string;
}

/**
 * Shows the quoted parent comment inside a reply bubble.
 */
const QuotedReply: React.FC<QuotedReplyProps> = ({
    parentComment,
    isOwn,
    currentUserID,
    userIDToEmail,
    anonUserNames,
    currentAnonUserID,
}) => {
    const parentEmail = userIDToEmail?.get(parentComment.userID);
    const shouldResolveParent =
        currentUserID !== undefined &&
        parentComment.userID > 0 &&
        !parentComment.anonUserID &&
        !!parentEmail &&
        !parentEmail.startsWith("*");
    const resolvedParent = useResolvedContactDisplay({
        userID: shouldResolveParent ? parentComment.userID : undefined,
        email: shouldResolveParent ? parentEmail : undefined,
    });

    // Get the author name
    const getAuthorName = (): string => {
        // Check if this is the current user (logged in or anonymous)
        if (parentComment.userID === currentUserID) {
            return t("you");
        }
        if (
            parentComment.anonUserID &&
            parentComment.anonUserID === currentAnonUserID
        ) {
            return t("you");
        }

        // For anonymous users, look up in anonUserNames
        if (parentComment.anonUserID) {
            return (
                anonUserNames?.get(parentComment.anonUserID) ??
                `${t("anonymous")} ${parentComment.anonUserID.slice(-4)}`
            );
        }

        // For registered users, look up email
        return shouldResolveParent
            ? resolvedParent.primaryLabel || parentEmail || t("user")
            : (parentEmail ?? t("user"));
    };

    return (
        <QuotedReplyContainer isOwn={isOwn}>
            <Typography
                sx={(theme) => ({
                    fontWeight: 600,
                    fontSize: 12,
                    color: isOwn ? "rgba(255,255,255,0.9)" : "#666",
                    ...(!isOwn &&
                        theme.applyStyles("dark", {
                            color: "rgba(255, 255, 255, 0.7)",
                        })),
                })}
            >
                {getAuthorName()}
            </Typography>
            {parentComment.isDeleted ? (
                <Typography
                    sx={(theme) => ({
                        fontSize: 12,
                        fontStyle: "italic",
                        color: isOwn ? "rgba(255,255,255,0.8)" : "#888",
                        ...(!isOwn &&
                            theme.applyStyles("dark", {
                                color: "rgba(255, 255, 255, 0.5)",
                            })),
                    })}
                >
                    (deleted)
                </Typography>
            ) : (
                <Typography
                    sx={(theme) => ({
                        fontSize: 12,
                        color: isOwn ? "rgba(255,255,255,0.8)" : "#888",
                        ...(!isOwn &&
                            theme.applyStyles("dark", {
                                color: "rgba(255, 255, 255, 0.5)",
                            })),
                    })}
                >
                    {truncateCommentText(parentComment.text)}
                </Typography>
            )}
        </QuotedReplyContainer>
    );
};

// =============================================================================
// Main Component
// =============================================================================

export interface CommentsSidebarProps extends ModalVisibilityProps {
    /**
     * The file whose comments are being displayed.
     */
    file?: EnteFile;
    /**
     * The currently active collection ID (when viewing from within a collection).
     */
    activeCollectionID?: number;
    /**
     * A mapping from file IDs to the IDs of collections they belong to.
     */
    fileNormalCollectionIDs?: Map<number, number[]>;
    /**
     * Collection summaries indexed by their IDs.
     */
    collectionSummaries?: CollectionSummaries;
    /**
     * The current user's ID.
     */
    currentUserID?: number;
    /**
     * Pre-fetched comments by collection ID.
     */
    prefetchedComments?: Map<number, Comment[]>;
    /**
     * Pre-fetched reactions by collection ID (includes both file and comment reactions).
     */
    prefetchedReactions?: Map<number, UnifiedReaction[]>;
    /**
     * Pre-fetched user ID to email mapping.
     */
    prefetchedUserIDToEmail?: Map<number, string>;
    /**
     * Called when a comment is successfully added. The parent should update its
     * comments state to include this new comment.
     */
    onCommentAdded?: (comment: Comment) => void;
    /**
     * Called when a comment is successfully deleted. The parent should update its
     * comments state to mark this comment as deleted.
     */
    onCommentDeleted?: (collectionID: number, commentID: string) => void;
    /**
     * Called when a comment reaction is added. The parent should update its
     * reactions state to include this new reaction.
     */
    onCommentReactionAdded?: (reaction: UnifiedReaction) => void;
    /**
     * Called when a comment reaction is deleted. The parent should update its
     * reactions state to remove this reaction.
     */
    onCommentReactionDeleted?: (
        collectionID: number,
        reactionID: string,
    ) => void;
    /**
     * If set, the sidebar will scroll to and highlight this comment.
     */
    highlightCommentID?: string;
    /**
     * Map of anonymous user ID to decrypted user name.
     */
    anonUserNames?: Map<string, string>;
}

/**
 * A sidebar panel for displaying and managing comments on a file.
 */
interface ContextMenuState {
    comment: Comment;
    anchorEl: HTMLElement;
    isLiked: boolean;
}

export const CommentsSidebar: React.FC<CommentsSidebarProps> = ({
    open,
    onClose,
    file,
    activeCollectionID,
    fileNormalCollectionIDs,
    collectionSummaries,
    currentUserID,
    prefetchedComments,
    prefetchedReactions,
    prefetchedUserIDToEmail,
    onCommentAdded,
    onCommentDeleted,
    onCommentReactionAdded,
    onCommentReactionDeleted,
    highlightCommentID,
    anonUserNames,
}) => {
    const [commentText, setCommentText] = useState("");
    const [replyingTo, setReplyingTo] = useState<Comment | null>(null);
    const [contextMenu, setContextMenu] = useState<ContextMenuState | null>(
        null,
    );
    const [collectionDropdownOpen, setCollectionDropdownOpen] = useState(false);
    const [comments, setComments] = useState<Comment[]>([]);
    const [loading, setLoading] = useState(false);
    const [sending, setSending] = useState(false);
    const hasLoadedRef = useRef(false);
    const inputRef = useRef<HTMLInputElement>(null);
    const commentsContainerRef = useRef<HTMLDivElement>(null);
    // Ref to preserve isLiked state during context menu close animation
    const contextMenuIsLikedRef = useRef(false);

    // Comments grouped by collection: collectionID -> comments
    const [commentsByCollection, setCommentsByCollection] = useState<
        Map<number, Comment[]>
    >(new Map());

    // Selected collection for viewing comments (when in gallery view)
    const [selectedCollectionID, setSelectedCollectionID] = useState<
        number | undefined
    >(undefined);

    // Thumbnail URLs for each collection's cover file: collectionID -> URL
    const [thumbnailURLs, setThumbnailURLs] = useState<Map<number, string>>(
        new Map(),
    );

    // Comment reactions: commentID -> reactionID (for current user's likes)
    const [likedComments, setLikedComments] = useState<Map<string, string>>(
        new Map(),
    );

    // All reactions by collection: collectionID -> reactions array
    const [reactionsByCollection, setReactionsByCollection] = useState<
        Map<number, UnifiedReaction[]>
    >(new Map());

    // Track whether we've scrolled to the highlight comment for this open
    const hasScrolledToHighlightRef = useRef(false);

    // Focus input when replying to a comment
    useEffect(() => {
        if (replyingTo && inputRef.current) {
            inputRef.current.focus();
        }
    }, [replyingTo]);

    // Reset tracking refs when sidebar closes
    useEffect(() => {
        if (!open) {
            hasScrolledToHighlightRef.current = false;
            hasLoadedRef.current = false;
        }
    }, [open]);

    // Scroll to and highlight the target comment when opening from feed
    useEffect(() => {
        if (
            !open ||
            !highlightCommentID ||
            hasScrolledToHighlightRef.current ||
            !commentsContainerRef.current ||
            loading ||
            comments.length === 0
        ) {
            return;
        }

        let highlightTimeout: ReturnType<typeof setTimeout> | undefined;
        let fadeTimeout: ReturnType<typeof setTimeout> | undefined;
        let cleanupTimeout: ReturnType<typeof setTimeout> | undefined;
        let blinkInterval: ReturnType<typeof setInterval> | undefined;

        // Wait for DOM to update after comments state change
        const initialTimeout = setTimeout(() => {
            const commentWrapper = commentsContainerRef.current?.querySelector(
                `[data-comment-id="${highlightCommentID}"]`,
            );
            if (commentWrapper) {
                hasScrolledToHighlightRef.current = true;

                // Scroll to the comment
                commentWrapper.scrollIntoView({
                    behavior: "smooth",
                    block: "center",
                });

                // Find the bubble element inside the wrapper
                const bubbleElement = commentWrapper.querySelector<HTMLElement>(
                    "[data-comment-bubble]",
                );

                if (bubbleElement) {
                    // Wait for scroll to mostly complete, then apply blink highlight
                    highlightTimeout = setTimeout(() => {
                        const computedStyle = getComputedStyle(bubbleElement);
                        const originalBg = computedStyle.backgroundColor;

                        // Parse the RGB values to create 80% opacity version
                        const rgbMatch = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(
                            originalBg,
                        );
                        if (!rgbMatch) return;

                        const [, r, g, b] = rgbMatch;
                        const dimmedBg = `rgba(${r}, ${g}, ${b}, 0.6)`;

                        bubbleElement.style.transition =
                            "background-color 0.2s ease-in-out";

                        let isDimmed = false;
                        blinkInterval = setInterval(() => {
                            isDimmed = !isDimmed;
                            bubbleElement.style.backgroundColor = isDimmed
                                ? dimmedBg
                                : originalBg;
                        }, 300);

                        // Stop blinking after 1.5 seconds
                        fadeTimeout = setTimeout(() => {
                            if (blinkInterval) clearInterval(blinkInterval);
                            bubbleElement.style.backgroundColor = originalBg;

                            // Clean up transition style
                            cleanupTimeout = setTimeout(() => {
                                bubbleElement.style.transition = "";
                                bubbleElement.style.backgroundColor = "";
                            }, 200);
                        }, 1500);
                    }, 400);
                }
            }
        }, 100);

        return () => {
            clearTimeout(initialTimeout);
            if (highlightTimeout) clearTimeout(highlightTimeout);
            if (fadeTimeout) clearTimeout(fadeTimeout);
            if (cleanupTimeout) clearTimeout(cleanupTimeout);
            if (blinkInterval) clearInterval(blinkInterval);
        };
    }, [open, highlightCommentID, loading, comments]);

    // Reset state when the file changes to avoid showing stale data
    useEffect(() => {
        setSelectedCollectionID(undefined);
        setComments([]);
        setCommentsByCollection(new Map());
        setReactionsByCollection(new Map());
        setLikedComments(new Map());
        hasLoadedRef.current = false;
    }, [file?.id]);

    // Check if opened from a collection context
    const hasCollectionContext =
        activeCollectionID !== undefined && activeCollectionID !== 0;

    // Get all collections the file belongs to
    const fileCollectionIDs = useMemo(() => {
        if (!file) return [];
        return fileNormalCollectionIDs?.get(file.id) ?? [];
    }, [file, fileNormalCollectionIDs]);

    // Build collection info list with comment counts and cover files (shared albums only)
    const collectionsInfo = useMemo((): CollectionInfo[] => {
        return fileCollectionIDs
            .filter((collectionID) =>
                collectionSummaries
                    ?.get(collectionID)
                    ?.attributes.has("shared"),
            )
            .map((collectionID) => {
                const summary = collectionSummaries?.get(collectionID);
                return {
                    id: collectionID,
                    name: summary?.name ?? `Album ${collectionID}`,
                    commentCount:
                        commentsByCollection
                            .get(collectionID)
                            ?.filter((c) => !c.isDeleted).length ?? 0,
                    coverFile: summary?.coverFile,
                };
            });
    }, [fileCollectionIDs, collectionSummaries, commentsByCollection]);

    // Collections sorted by comment count (descending) for dropdown
    const sortedCollectionsInfo = useMemo(() => {
        return [...collectionsInfo].sort(
            (a, b) => b.commentCount - a.commentCount,
        );
    }, [collectionsInfo]);

    // Currently selected collection info
    const selectedCollectionInfo = useMemo(() => {
        const targetID = hasCollectionContext
            ? activeCollectionID
            : selectedCollectionID;
        return (
            collectionsInfo.find((c) => c.id === targetID) ??
            sortedCollectionsInfo[0]
        );
    }, [
        hasCollectionContext,
        activeCollectionID,
        selectedCollectionID,
        collectionsInfo,
        sortedCollectionsInfo,
    ]);

    // Check if the current user can delete a given comment.
    // User can delete if: they authored the comment, OR they are owner/admin of the collection.
    const canDeleteComment = useCallback(
        (comment: Comment): boolean => {
            // Comment author can always delete their own comment
            if (comment.userID === currentUserID) {
                return true;
            }

            // Check if user is owner or admin of the selected collection
            const collectionID = selectedCollectionInfo?.id;
            if (!collectionID || !collectionSummaries) {
                return false;
            }

            const summary = collectionSummaries.get(collectionID);
            if (!summary) {
                return false;
            }

            // User is owner (not sharedIncoming) or admin (sharedIncomingAdmin)
            return (
                !summary.attributes.has("sharedIncoming") ||
                summary.attributes.has("sharedIncomingAdmin")
            );
        },
        [currentUserID, selectedCollectionInfo, collectionSummaries],
    );

    // Load comments and reactions from prefetched data.
    const loadComments = useCallback(() => {
        if (!file || !open || !prefetchedComments) return;

        // Only show loading spinner on initial load, not during polling refresh
        const isInitialLoad = !hasLoadedRef.current;
        if (isInitialLoad) {
            setLoading(true);
        }

        try {
            // Use prefetched data
            setCommentsByCollection(prefetchedComments);
            setReactionsByCollection(prefetchedReactions ?? new Map());

            // Set comments for the currently selected collection
            if (hasCollectionContext && activeCollectionID) {
                const activeComments =
                    prefetchedComments.get(activeCollectionID) ?? [];
                setComments(activeComments);
            } else {
                // For gallery view, only auto-select on initial load.
                // Use functional update to check current selection without
                // adding selectedCollectionID as a dependency.
                setSelectedCollectionID((currentSelection) => {
                    if (currentSelection !== undefined) {
                        // Already have a selection, don't change it.
                        // The useEffect that watches selectedCollectionID will
                        // update the displayed comments.
                        return currentSelection;
                    }

                    // Initial selection: find collection with most comments.
                    // Only consider shared collections (non-shared ones won't appear in the UI).
                    let maxCount = -1;
                    let bestCollectionID: number | undefined;
                    for (const [
                        collectionID,
                        collectionComments,
                    ] of prefetchedComments) {
                        const isShared = collectionSummaries
                            ?.get(collectionID)
                            ?.attributes.has("shared");
                        if (!isShared) continue;

                        const count = collectionComments.filter(
                            (c) => !c.isDeleted,
                        ).length;
                        if (count > maxCount) {
                            maxCount = count;
                            bestCollectionID = collectionID;
                        }
                    }
                    if (bestCollectionID !== undefined) {
                        setComments(
                            prefetchedComments.get(bestCollectionID) ?? [],
                        );
                    }
                    return bestCollectionID;
                });
            }
        } catch (e) {
            log.error("Failed to load comments", e);
        } finally {
            if (isInitialLoad) {
                hasLoadedRef.current = true;
                setLoading(false);
            }
        }
    }, [
        file,
        open,
        prefetchedComments,
        prefetchedReactions,
        hasCollectionContext,
        activeCollectionID,
        collectionSummaries,
    ]);

    // Load comments when the sidebar opens
    useEffect(() => {
        if (open) {
            loadComments();
        }
    }, [open, loadComments]);

    // Set initial selected collection to the one with most comments (gallery view)
    useEffect(() => {
        if (
            open &&
            !hasCollectionContext &&
            selectedCollectionID === undefined &&
            commentsByCollection.size > 0
        ) {
            // Find the collection with the most comments.
            // Only consider shared collections (non-shared ones won't appear in the UI).
            let maxCount = -1;
            let bestCollectionID: number | undefined;
            for (const [
                collectionID,
                collectionComments,
            ] of commentsByCollection) {
                const isShared = collectionSummaries
                    ?.get(collectionID)
                    ?.attributes.has("shared");
                if (!isShared) continue;

                const count = collectionComments.filter(
                    (c) => !c.isDeleted,
                ).length;
                if (count > maxCount) {
                    maxCount = count;
                    bestCollectionID = collectionID;
                }
            }
            if (bestCollectionID !== undefined) {
                setSelectedCollectionID(bestCollectionID);
            }
        }
    }, [
        open,
        hasCollectionContext,
        selectedCollectionID,
        commentsByCollection,
        collectionSummaries,
    ]);

    // Update displayed comments when selected collection changes (gallery view)
    useEffect(() => {
        if (!hasCollectionContext && selectedCollectionID !== undefined) {
            const collectionComments =
                commentsByCollection.get(selectedCollectionID) ?? [];
            setComments(collectionComments);
        }
    }, [hasCollectionContext, selectedCollectionID, commentsByCollection]);

    // Fetch thumbnails for each collection's cover file
    useEffect(() => {
        if (!open || collectionsInfo.length === 0) {
            return;
        }

        let didCancel = false;

        const fetchThumbnails = async () => {
            const urls = new Map<number, string>();
            for (const collection of collectionsInfo) {
                if (collection.coverFile) {
                    try {
                        const url =
                            await downloadManager.renderableThumbnailURL(
                                collection.coverFile,
                            );
                        if (!didCancel && url) {
                            urls.set(collection.id, url);
                        }
                    } catch (e) {
                        log.warn(
                            `Failed to fetch thumbnail for collection ${collection.id}`,
                            e,
                        );
                    }
                }
            }
            if (!didCancel) {
                setThumbnailURLs(urls);
            }
        };

        void fetchThumbnails();

        return () => {
            didCancel = true;
        };
    }, [open, collectionsInfo]);

    // Build liked comments map from reactions when selected collection changes
    useEffect(() => {
        // Don't reset state on close - preserves UI during exit animation
        if (!open) return;
        if (!selectedCollectionInfo) {
            setLikedComments(new Map());
            return;
        }

        const reactions = reactionsByCollection.get(selectedCollectionInfo.id);
        if (!reactions) {
            setLikedComments(new Map());
            return;
        }

        // Find comment reactions that are likes from the current user.
        const newLikedComments = new Map<string, string>();
        for (const reaction of reactions) {
            if (reaction.commentID && reaction.reactionType === "green_heart") {
                if (reaction.userID === currentUserID) {
                    newLikedComments.set(reaction.commentID, reaction.id);
                }
            }
        }
        setLikedComments(newLikedComments);
    }, [open, selectedCollectionInfo, reactionsByCollection, currentUserID]);

    const handleSend = async () => {
        if (!commentText.trim() || !file || !selectedCollectionInfo) return;
        const text = commentText.trim();
        const collectionID = selectedCollectionInfo.id;

        setSending(true);
        try {
            const collection = await getCollectionByID(collectionID);

            const newCommentID = await addComment(
                collectionID,
                file.id,
                text,
                collection.key,
                replyingTo?.id,
            );

            // Add the new comment to local state
            const newComment: Comment = {
                id: newCommentID,
                collectionID,
                fileID: file.id,
                text,
                parentCommentID: replyingTo?.id,
                isDeleted: false,
                userID: currentUserID ?? 0,
                createdAt: Date.now() * 1000, // Microseconds to match server format
                updatedAt: Date.now() * 1000,
            };
            setComments((prev) => [...prev, newComment]);
            setCommentsByCollection((prev) => {
                const next = new Map(prev);
                const existing = next.get(collectionID) ?? [];
                next.set(collectionID, [...existing, newComment]);
                return next;
            });

            setCommentText("");
            setReplyingTo(null);

            // Notify parent to update its comments state
            onCommentAdded?.(newComment);

            // Scroll to bottom after adding comment
            setTimeout(() => {
                if (commentsContainerRef.current) {
                    commentsContainerRef.current.scrollTop = 0;
                }
            }, 0);
        } catch (e) {
            log.error("Failed to add comment", e);
        } finally {
            setSending(false);
        }
    };

    const handleReply = (commentToReply: Comment) => {
        setReplyingTo(commentToReply);
    };

    // Handler for keydown: Enter to send, Shift+Enter for new line
    const handleCommentKeyDown = (e: React.KeyboardEvent) => {
        if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            void handleSend();
        }
    };

    const handleCollectionSelect = (collectionID: number) => {
        setSelectedCollectionID(collectionID);
        setCollectionDropdownOpen(false);
    };

    const handleContextMenu = (
        e: React.MouseEvent,
        targetComment: Comment,
        bubbleElement: HTMLElement,
    ) => {
        const selection = window.getSelection();
        if (selection && selection.toString().length > 0) {
            return;
        }
        e.preventDefault();
        const isLiked = likedComments.has(targetComment.id);
        contextMenuIsLikedRef.current = isLiked;
        setContextMenu({
            comment: targetComment,
            anchorEl: bubbleElement,
            isLiked,
        });
    };

    const handleCloseContextMenu = () => {
        setContextMenu(null);
    };

    const handleLikeComment = async (targetComment: Comment) => {
        if (!selectedCollectionInfo) return;

        const collectionID = selectedCollectionInfo.id;
        const existingReactionID = likedComments.get(targetComment.id);

        try {
            const collection = await getCollectionByID(collectionID);

            if (existingReactionID) {
                await deleteReaction(existingReactionID);
                setLikedComments((prev) => {
                    const next = new Map(prev);
                    next.delete(targetComment.id);
                    return next;
                });
                setReactionsByCollection((prev) => {
                    const next = new Map(prev);
                    const reactions = next.get(collectionID) ?? [];
                    next.set(
                        collectionID,
                        reactions.filter((r) => r.id !== existingReactionID),
                    );
                    return next;
                });
                onCommentReactionDeleted?.(collectionID, existingReactionID);
            } else {
                const reactionID = await addCommentReaction(
                    collectionID,
                    targetComment.id,
                    "green_heart",
                    collection.key,
                    targetComment.fileID,
                );
                const newReaction: UnifiedReaction = {
                    id: reactionID,
                    collectionID,
                    commentID: targetComment.id,
                    reactionType: "green_heart",
                    userID: currentUserID ?? 0,
                    isDeleted: false,
                    createdAt: Date.now() * 1000,
                    updatedAt: Date.now() * 1000,
                };
                setLikedComments((prev) => {
                    const next = new Map(prev);
                    next.set(targetComment.id, reactionID);
                    return next;
                });
                setReactionsByCollection((prev) => {
                    const next = new Map(prev);
                    const reactions = next.get(collectionID) ?? [];
                    next.set(collectionID, [...reactions, newReaction]);
                    return next;
                });
                onCommentReactionAdded?.(newReaction);
            }
        } catch (e) {
            log.error("Failed to toggle comment like", e);
        }
    };

    const handleContextMenuAction = async (
        action: "like" | "reply" | "delete",
    ) => {
        if (!contextMenu || !selectedCollectionInfo) return;
        const targetComment = contextMenu.comment;
        setContextMenu(null);

        switch (action) {
            case "like":
                await handleLikeComment(targetComment);
                break;
            case "reply":
                handleReply(targetComment);
                break;
            case "delete":
                try {
                    await deleteComment(targetComment.id);

                    // Update local state
                    setComments((prev) =>
                        prev.map((c) =>
                            c.id === targetComment.id
                                ? { ...c, isDeleted: true }
                                : c,
                        ),
                    );
                    setCommentsByCollection((prev) => {
                        const next = new Map(prev);
                        const collectionComments =
                            next.get(targetComment.collectionID) ?? [];
                        next.set(
                            targetComment.collectionID,
                            collectionComments.map((c) =>
                                c.id === targetComment.id
                                    ? { ...c, isDeleted: true }
                                    : c,
                            ),
                        );
                        return next;
                    });

                    // Notify parent to update its comments state
                    onCommentDeleted?.(
                        targetComment.collectionID,
                        targetComment.id,
                    );
                } catch (e) {
                    log.error("Failed to delete comment", e);
                }
                break;
        }
    };

    // Filter out deleted comments and sort by timestamp (newest first for column-reverse layout)
    const sortedComments = [...comments]
        .filter((c) => !c.isDeleted)
        .sort((a, b) => b.createdAt - a.createdAt);

    const showOverlay = contextMenu || collectionDropdownOpen;

    return (
        <SidebarDrawer open={open} onClose={onClose} anchor="right">
            <DrawerContentWrapper>
                {showOverlay && (
                    <ContextMenuOverlay
                        onClick={() => {
                            handleCloseContextMenu();
                            setCollectionDropdownOpen(false);
                        }}
                    />
                )}
                <Header>
                    {hasCollectionContext ? (
                        <Typography
                            sx={(theme) => ({
                                color: "#000",
                                fontWeight: 600,
                                ...theme.applyStyles("dark", { color: "#fff" }),
                            })}
                        >
                            {loading
                                ? "Loading..."
                                : `${sortedComments.length} ${t("comments")}`}
                        </Typography>
                    ) : collectionsInfo.length > 1 ? (
                        <Box
                            sx={{
                                position: "relative",
                                zIndex: collectionDropdownOpen ? 12 : "auto",
                            }}
                        >
                            <CollectionDropdownButton
                                onClick={() =>
                                    setCollectionDropdownOpen(
                                        !collectionDropdownOpen,
                                    )
                                }
                            >
                                <Box sx={{ position: "relative" }}>
                                    {selectedCollectionInfo &&
                                    thumbnailURLs.get(
                                        selectedCollectionInfo.id,
                                    ) ? (
                                        <CollectionThumbnail
                                            src={thumbnailURLs.get(
                                                selectedCollectionInfo.id,
                                            )}
                                            alt=""
                                        />
                                    ) : (
                                        <CollectionThumbnailPlaceholder />
                                    )}
                                    <CollectionBadge>
                                        {selectedCollectionInfo?.commentCount ??
                                            0}
                                    </CollectionBadge>
                                </Box>
                                <Typography
                                    sx={(theme) => ({
                                        color: "#000",
                                        fontWeight: 600,
                                        fontSize: 14,
                                        lineHeight: "20px",
                                        marginBottom: "4px",
                                        ...theme.applyStyles("dark", {
                                            color: "#fff",
                                        }),
                                    })}
                                >
                                    {selectedCollectionInfo?.name ?? "Album"}
                                </Typography>
                                <ChevronDownIcon />
                            </CollectionDropdownButton>
                            {collectionDropdownOpen && (
                                <CollectionDropdownMenu>
                                    {sortedCollectionsInfo.map((collection) => (
                                        <CollectionDropdownItem
                                            key={collection.id}
                                            onClick={() =>
                                                handleCollectionSelect(
                                                    collection.id,
                                                )
                                            }
                                        >
                                            <Box sx={{ position: "relative" }}>
                                                {thumbnailURLs.get(
                                                    collection.id,
                                                ) ? (
                                                    <CollectionThumbnail
                                                        src={thumbnailURLs.get(
                                                            collection.id,
                                                        )}
                                                        alt=""
                                                    />
                                                ) : (
                                                    <CollectionThumbnailPlaceholder />
                                                )}
                                                <CollectionBadge>
                                                    {collection.commentCount}
                                                </CollectionBadge>
                                            </Box>
                                            <Typography
                                                sx={(theme) => ({
                                                    color: "#000",
                                                    fontWeight: 600,
                                                    fontSize: 14,
                                                    lineHeight: "20px",
                                                    marginBottom: "4px",
                                                    ...theme.applyStyles(
                                                        "dark",
                                                        { color: "#fff" },
                                                    ),
                                                })}
                                            >
                                                {collection.name}
                                            </Typography>
                                        </CollectionDropdownItem>
                                    ))}
                                </CollectionDropdownMenu>
                            )}
                        </Box>
                    ) : (
                        <Typography
                            sx={(theme) => ({
                                color: "#000",
                                fontWeight: 600,
                                ...theme.applyStyles("dark", { color: "#fff" }),
                            })}
                        >
                            {loading
                                ? "Loading..."
                                : `${sortedComments.length} ${t("comments")}`}
                        </Typography>
                    )}
                    <CloseButton onClick={onClose}>
                        <CloseIcon sx={{ fontSize: 22 }} />
                    </CloseButton>
                </Header>

                <CommentsContainer ref={commentsContainerRef}>
                    {loading ? (
                        <LoadingContainer>
                            <CircularProgress size={32} />
                        </LoadingContainer>
                    ) : sortedComments.length === 0 ? (
                        <EmptyMessage>{t("no_comments_yet")}</EmptyMessage>
                    ) : (
                        sortedComments.map((comment, index) => {
                            const commentIsOwn =
                                comment.userID === currentUserID;

                            // With column-reverse, visual order is reversed from array order
                            // Visual "above" = higher index, visual "below" = lower index
                            const prevComment = sortedComments[index + 1];
                            const nextComment = sortedComments[index - 1];

                            // 10 minutes in microseconds (server timestamps are in microseconds)
                            const GROUP_TIME_THRESHOLD = 10 * 60 * 1000 * 1000;

                            // Comments are in same sequence if same user AND within 10 minutes
                            // For anon users, also check if they have the same anonUserID
                            const isSameUser = (a: Comment, b: Comment) => {
                                if (a.anonUserID && b.anonUserID) {
                                    return a.anonUserID === b.anonUserID;
                                }
                                return a.userID === b.userID;
                            };
                            const isSameSequenceAsPrev =
                                prevComment &&
                                isSameUser(prevComment, comment) &&
                                comment.createdAt - prevComment.createdAt <=
                                    GROUP_TIME_THRESHOLD;
                            const isSameSequenceAsNext =
                                nextComment &&
                                isSameUser(nextComment, comment) &&
                                nextComment.createdAt - comment.createdAt <=
                                    GROUP_TIME_THRESHOLD;

                            const isFirstInSequence = !isSameSequenceAsPrev;
                            const isLastInSequence = !isSameSequenceAsNext;
                            const showHeader =
                                isFirstInSequence && !commentIsOwn;
                            const parentComment = comment.parentCommentID
                                ? getParentComment(
                                      comment.parentCommentID,
                                      comments,
                                  )
                                : undefined;

                            const showOwnTimestamp =
                                commentIsOwn && isFirstInSequence;

                            // Get the display name, avatar color key, and masked email status for the comment author
                            const getCommentAuthorInfo = (): {
                                name: string;
                                avatarColorKey: string;
                                isMaskedEmail: boolean;
                                email?: string;
                                userID?: number;
                                useContactDisplay: boolean;
                            } => {
                                // If anonymous user, check anonUserNames map
                                if (comment.anonUserID) {
                                    const anonName =
                                        anonUserNames?.get(
                                            comment.anonUserID,
                                        ) ??
                                        `${t("anonymous")} ${comment.anonUserID.slice(-4)}`;
                                    return {
                                        name: anonName,
                                        // Use name for avatar color (varying length like mobile emails)
                                        avatarColorKey: anonName,
                                        isMaskedEmail: false,
                                        useContactDisplay: false,
                                    };
                                }
                                // For registered users, use email
                                const emailFromMap =
                                    prefetchedUserIDToEmail?.get(
                                        comment.userID,
                                    );
                                const email = emailFromMap ?? t("user");
                                return {
                                    name: email,
                                    // Use email or userID for avatar color
                                    avatarColorKey: emailFromMap
                                        ? emailFromMap
                                        : String(comment.userID),
                                    isMaskedEmail: email.startsWith("*"),
                                    email: emailFromMap,
                                    userID: comment.userID,
                                    useContactDisplay:
                                        currentUserID !== undefined &&
                                        !email.startsWith("*"),
                                };
                            };

                            const authorInfo = getCommentAuthorInfo();

                            return (
                                <Box key={comment.id}>
                                    {showHeader && (
                                        <CommentHeader
                                            userName={authorInfo.name}
                                            timestamp={comment.createdAt}
                                            isMaskedEmail={
                                                authorInfo.isMaskedEmail
                                            }
                                            avatarColorKey={
                                                authorInfo.avatarColorKey
                                            }
                                            email={authorInfo.email}
                                            userID={authorInfo.userID}
                                            useContactDisplay={
                                                authorInfo.useContactDisplay
                                            }
                                        />
                                    )}
                                    {showOwnTimestamp && (
                                        <OwnTimestamp>
                                            {formatTimeAgo(comment.createdAt)}
                                        </OwnTimestamp>
                                    )}
                                    <CommentBubbleWrapper
                                        data-comment-id={comment.id}
                                        isOwn={commentIsOwn}
                                        isFirstOwn={
                                            !showOwnTimestamp &&
                                            commentIsOwn &&
                                            !!prevComment &&
                                            prevComment.userID !== currentUserID
                                        }
                                        isLastOwn={isLastInSequence}
                                        isHighlighted={
                                            contextMenu?.comment.id ===
                                            comment.id
                                        }
                                    >
                                        <CommentBubbleInner
                                            onContextMenu={(e) => {
                                                const bubbleElement =
                                                    e.currentTarget.querySelector<HTMLElement>(
                                                        "[data-comment-bubble]",
                                                    );
                                                if (bubbleElement) {
                                                    handleContextMenu(
                                                        e,
                                                        comment,
                                                        bubbleElement,
                                                    );
                                                }
                                            }}
                                        >
                                            <CommentBubble
                                                isOwn={commentIsOwn}
                                                data-comment-bubble
                                            >
                                                {parentComment && (
                                                    <QuotedReply
                                                        parentComment={
                                                            parentComment
                                                        }
                                                        isOwn={commentIsOwn}
                                                        currentUserID={
                                                            currentUserID
                                                        }
                                                        userIDToEmail={
                                                            prefetchedUserIDToEmail
                                                        }
                                                        anonUserNames={
                                                            anonUserNames
                                                        }
                                                    />
                                                )}
                                                <CommentText
                                                    isOwn={commentIsOwn}
                                                >
                                                    {comment.text}
                                                </CommentText>
                                            </CommentBubble>
                                        </CommentBubbleInner>
                                    </CommentBubbleWrapper>
                                </Box>
                            );
                        })
                    )}
                    <StyledMenu
                        anchorEl={contextMenu?.anchorEl}
                        open={Boolean(contextMenu)}
                        onClose={handleCloseContextMenu}
                        anchorOrigin={{
                            vertical: "bottom",
                            horizontal: "right",
                        }}
                        transformOrigin={{
                            vertical: "top",
                            horizontal: "right",
                        }}
                    >
                        <StyledMenuItem
                            onClick={() => handleContextMenuAction("like")}
                        >
                            <HeartIcon small />
                            <span>
                                {contextMenuIsLikedRef.current
                                    ? t("unlike")
                                    : t("like")}
                            </span>
                        </StyledMenuItem>
                        <StyledMenuItem
                            onClick={() => handleContextMenuAction("reply")}
                        >
                            <ReplyIcon />
                            <span>{t("reply")}</span>
                        </StyledMenuItem>
                        {contextMenu &&
                            canDeleteComment(contextMenu.comment) && (
                                <StyledMenuItem
                                    onClick={() =>
                                        handleContextMenuAction("delete")
                                    }
                                    sx={(theme) => ({
                                        "&:hover": {
                                            backgroundColor: "#F24F4F",
                                            color: "#fff",
                                        },
                                        ...theme.applyStyles("dark", {
                                            "&:hover": {
                                                backgroundColor: "#C53030",
                                                color: "#fff",
                                            },
                                        }),
                                    })}
                                >
                                    <DeleteIcon />
                                    <span>{t("delete")}</span>
                                </StyledMenuItem>
                            )}
                    </StyledMenu>
                </CommentsContainer>

                <InputContainer>
                    {replyingTo && (
                        <ReplyingToBar>
                            <ReplyingToContent>
                                <Box sx={{ flex: 1, minWidth: 0 }}>
                                    <Typography
                                        sx={(theme) => ({
                                            fontSize: 12,
                                            color: "#666",
                                            ...theme.applyStyles("dark", {
                                                color: "rgba(255, 255, 255, 0.7)",
                                            }),
                                        })}
                                    >
                                        Replying to{" "}
                                        {(() => {
                                            if (replyingTo.anonUserID) {
                                                return (
                                                    anonUserNames?.get(
                                                        replyingTo.anonUserID,
                                                    ) ?? t("user")
                                                );
                                            }
                                            // Regular user
                                            return replyingTo.userID ===
                                                currentUserID
                                                ? t("yourself")
                                                : (prefetchedUserIDToEmail?.get(
                                                      replyingTo.userID,
                                                  ) ?? t("user"));
                                        })()}
                                        ...
                                    </Typography>
                                    <Typography
                                        sx={(theme) => ({
                                            fontSize: 14,
                                            color: "#000",
                                            overflow: "hidden",
                                            textOverflow: "ellipsis",
                                            whiteSpace: "nowrap",
                                            ...theme.applyStyles("dark", {
                                                color: "#fff",
                                            }),
                                        })}
                                    >
                                        {truncateCommentText(replyingTo.text)}
                                    </Typography>
                                </Box>
                                <IconButton
                                    size="small"
                                    onClick={() => {
                                        setReplyingTo(null);
                                        inputRef.current?.focus();
                                    }}
                                    sx={(theme) => ({
                                        color: "#666",
                                        p: 0,
                                        mt: -0.25,
                                        mr: -0.25,
                                        flexShrink: 0,
                                        "&:hover": {
                                            backgroundColor: "transparent",
                                        },
                                        ...theme.applyStyles("dark", {
                                            color: "rgba(255, 255, 255, 0.7)",
                                        }),
                                    })}
                                >
                                    <CloseIcon sx={{ fontSize: 16 }} />
                                </IconButton>
                            </ReplyingToContent>
                        </ReplyingToBar>
                    )}
                    <InputWrapper>
                        <StyledTextField
                            fullWidth
                            multiline
                            minRows={1}
                            autoFocus
                            placeholder={t("say_something_nice_placeholder")}
                            variant="standard"
                            value={commentText}
                            onChange={(e) => setCommentText(e.target.value)}
                            onKeyDown={handleCommentKeyDown}
                            inputRef={inputRef}
                            slotProps={{ htmlInput: { maxLength: 280 } }}
                        />
                    </InputWrapper>
                    <SendButton onClick={handleSend} disabled={sending}>
                        {sending ? (
                            <CircularProgress
                                size={18}
                                sx={{ color: "inherit" }}
                            />
                        ) : (
                            <SendIcon />
                        )}
                    </SendButton>
                </InputContainer>
            </DrawerContentWrapper>
        </SidebarDrawer>
    );
};

// =============================================================================
// Styled Components
// =============================================================================

// Drawer & Layout
const SidebarDrawer = styled(Drawer)(({ theme }) => ({
    "& .MuiDrawer-paper": {
        width: "23vw",
        minWidth: "520px",
        maxWidth: "calc(100% - 32px)",
        height: "calc(100% - 32px)",
        margin: "16px",
        borderRadius: "36px",
        backgroundColor: "#fff",
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
    "& .MuiBackdrop-root": { backgroundColor: "transparent" },
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

// Collection Dropdown
const CollectionDropdownButton = styled(Box)(({ theme }) => ({
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    gap: 14,
    padding: "5px 6px 0px 6px",
    borderRadius: 12,
    backgroundColor: "#F0F0F0",
    cursor: "pointer",
    "&:hover": { backgroundColor: "#E8E8E8" },
    ...theme.applyStyles("dark", {
        backgroundColor: "#363636",
        "&:hover": { backgroundColor: "#404040" },
    }),
}));

const CollectionThumbnail = styled("img")(() => ({
    width: 24,
    height: 24,
    borderRadius: 5,
    objectFit: "cover",
    backgroundColor: "#08C225",
}));

const CollectionBadge = styled(Box)(({ theme }) => ({
    position: "absolute",
    bottom: 4,
    right: -4,
    display: "inline-flex",
    justifyContent: "center",
    alignItems: "center",
    borderRadius: "50%",
    backgroundColor: "#FFF",
    color: "#000",
    fontSize: 10,
    fontWeight: 600,
    lineHeight: 1,
    minWidth: 16,
    minHeight: 16,
    ...theme.applyStyles("dark", { backgroundColor: "#fff", color: "#000" }),
}));

const CollectionThumbnailPlaceholder = styled(Box)(() => ({
    width: 24,
    height: 24,
    borderRadius: 5,
    backgroundColor: "#08C225",
}));

const LoadingContainer = styled(Box)(() => ({
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    height: "100%",
    // Offset for header (marginBottom: 48) + padding diff (32-24=8) = 56, halved
    marginTop: -28,
}));

const EmptyMessage = styled(Typography)(({ theme }) => ({
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    height: "100%",
    // Offset for header (marginBottom: 48) + padding diff (32-24=8) = 56, halved
    marginTop: -28,
    color: "#666",
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.5)" }),
}));

const CollectionDropdownMenu = styled(Box)(({ theme }) => ({
    position: "absolute",
    top: "calc(100% + 8px)",
    left: 0,
    display: "flex",
    flexDirection: "column",
    justifyContent: "center",
    alignItems: "flex-start",
    width: 184,
    padding: 4,
    gap: 4,
    borderRadius: 12,
    border: "1px solid rgba(0, 0, 0, 0.08)",
    backgroundColor: "#F0F0F0",
    zIndex: 12,
    ...theme.applyStyles("dark", {
        border: "1px solid rgba(0, 0, 0, 0.08)",
        backgroundColor: "#363636",
    }),
}));

const CollectionDropdownItem = styled(Box)(({ theme }) => ({
    display: "flex",
    alignItems: "center",
    gap: 14,
    padding: "5px 6px 0px 6px",
    borderRadius: 8,
    cursor: "pointer",
    width: "100%",
    "&:hover": { backgroundColor: "#E8E8E8" },
    ...theme.applyStyles("dark", {
        "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.16)" },
    }),
}));

const CommentsContainer = styled(Box)(({ theme }) => ({
    flex: 1,
    overflow: "auto",
    marginBottom: 16,
    marginRight: -24,
    position: "relative",
    display: "flex",
    flexDirection: "column-reverse",
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

// Comment Header
const CommentHeaderContainer = styled(Box)(() => ({
    display: "flex",
    alignItems: "center",
    gap: 8,
    marginBottom: 12,
}));

const UserName = styled(Typography)(({ theme }) => ({
    fontWeight: 600,
    color: "#000",
    fontSize: 14,
    ...theme.applyStyles("dark", { color: "#fff" }),
}));

const Separator = styled(Typography)(({ theme }) => ({
    color: "#666",
    fontSize: 12,
    marginLeft: -4,
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.7)" }),
}));

const Timestamp = styled(Typography)(({ theme }) => ({
    color: "#666",
    fontSize: 12,
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.7)" }),
}));

const OwnTimestamp = styled(Typography)(({ theme }) => ({
    color: "#666",
    fontSize: 12,
    textAlign: "right",
    marginBottom: 4,
    paddingRight: 52,
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.7)" }),
}));

// Comment Bubbles
const CommentBubbleWrapper = styled(Box, {
    shouldForwardProp: (prop) =>
        !["isOwn", "isFirstOwn", "isLastOwn", "isHighlighted"].includes(
            prop as string,
        ),
})<{
    isOwn: boolean;
    isFirstOwn?: boolean;
    isLastOwn?: boolean;
    isHighlighted?: boolean;
}>(({ isOwn, isFirstOwn, isLastOwn, isHighlighted }) => ({
    display: "flex",
    justifyContent: isOwn ? "flex-end" : "flex-start",
    width: "100%",
    marginTop: isFirstOwn ? 64 : 0,
    marginBottom: isLastOwn ? 48 : 12,
    paddingRight: isOwn ? 52 : 0,
    paddingLeft: isOwn ? 0 : 28,
    position: "relative",
    zIndex: isHighlighted ? 11 : "auto",
}));

const CommentBubbleInner = styled(Box)(() => ({
    position: "relative",
    maxWidth: 320,
}));

const CommentBubble = styled(Box, {
    shouldForwardProp: (prop) => prop !== "isOwn",
})<{ isOwn: boolean }>(({ isOwn, theme }) => ({
    backgroundColor: isOwn ? "#0DAF35" : "#F0F0F0",
    borderRadius: isOwn ? "20px 6px 20px 20px" : "6px 20px 20px 20px",
    padding: "20px 40px 20px 20px",
    width: "fit-content",
    maxWidth: "100%",
    ...(!isOwn && theme.applyStyles("dark", { backgroundColor: "#363636" })),
}));

const CommentText = styled(Typography, {
    shouldForwardProp: (prop) => prop !== "isOwn",
})<{ isOwn: boolean }>(({ isOwn, theme }) => ({
    color: isOwn ? "#fff" : "#000",
    fontSize: 14,
    whiteSpace: "pre-wrap",
    overflowWrap: "break-word",
    ...(!isOwn && theme.applyStyles("dark", { color: "#fff" })),
}));

const QuotedReplyContainer = styled(Box, {
    shouldForwardProp: (prop) => prop !== "isOwn",
})<{ isOwn: boolean }>(({ isOwn, theme }) => ({
    borderLeft: `3px solid ${isOwn ? "rgba(255,255,255,0.5)" : "#ccc"}`,
    paddingLeft: 10,
    marginBottom: 16,
    ...(!isOwn &&
        theme.applyStyles("dark", {
            borderLeft: "3px solid rgba(255, 255, 255, 0.3)",
        })),
}));

// Input Area
const InputContainer = styled(Box)(({ theme }) => ({
    position: "relative",
    backgroundColor: "#F3F3F3",
    borderRadius: "20px",
    margin: "0 -8px -16px -8px",
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255, 255, 255, 0.12)",
    }),
}));

const ReplyingToBar = styled(Box)(() => ({ padding: "12px 12px 0 12px" }));

const ReplyingToContent = styled(Box)(({ theme }) => ({
    display: "flex",
    alignItems: "flex-start",
    gap: 8,
    backgroundColor: "rgba(0, 0, 0, 0.06)",
    borderRadius: 12,
    padding: "10px 10px 10px 12px",
    borderLeft: "4px solid #ccc",
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255, 255, 255, 0.08)",
        borderLeft: "4px solid rgba(255, 255, 255, 0.3)",
    }),
}));

const InputWrapper = styled(Box)(({ theme }) => ({
    padding: "8px 48px 8px 16px",
    maxHeight: "300px",
    overflow: "auto",
    "&::-webkit-scrollbar": { width: "8px" },
    "&::-webkit-scrollbar-track": { background: "transparent" },
    "&::-webkit-scrollbar-thumb": {
        background: "rgba(0, 0, 0, 0.3)",
        borderRadius: "4px",
    },
    "&::-webkit-scrollbar-thumb:hover": { background: "rgba(0, 0, 0, 0.5)" },
    scrollbarWidth: "thin",
    scrollbarColor: "rgba(0, 0, 0, 0.3) transparent",
    ...theme.applyStyles("dark", {
        "&::-webkit-scrollbar-thumb": {
            background: "rgba(255, 255, 255, 0.3)",
        },
        "&::-webkit-scrollbar-thumb:hover": {
            background: "rgba(255, 255, 255, 0.5)",
        },
        scrollbarColor: "rgba(255, 255, 255, 0.3) transparent",
    }),
}));

const StyledTextField = styled(TextField)(({ theme }) => ({
    "& .MuiInput-root": { "&::before, &::after": { display: "none" } },
    "& .MuiInputBase-input": {
        padding: 0,
        color: "#000",
        "&::placeholder": { color: "#999", opacity: 1 },
    },
    ...theme.applyStyles("dark", {
        "& .MuiInputBase-input": {
            color: "#fff",
            "&::placeholder": { color: "rgba(255, 255, 255, 0.5)" },
        },
    }),
}));

const SendButton = styled(IconButton)(({ theme }) => ({
    position: "absolute",
    right: 12,
    bottom: 8.5,
    color: "rgba(0, 0, 0, 0.8)",
    width: 42,
    height: 42,
    "&:hover": { backgroundColor: "rgba(0, 0, 0, 0.1)" },
    ...theme.applyStyles("dark", {
        color: "rgba(255, 255, 255, 0.8)",
        "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.1)" },
    }),
}));

// Context Menu
const ContextMenuOverlay = styled(Box)(() => ({
    position: "absolute",
    top: -25,
    left: -25,
    right: -25,
    bottom: -33,
    backgroundColor: "rgba(0, 0, 0, 0.6)",
    zIndex: 10,
    borderRadius: "36px",
    "@media (max-width: 450px)": { borderRadius: 0 },
}));

const StyledMenu = styled(Menu)(({ theme }) => ({
    "& .MuiPaper-root": {
        backgroundColor: "#fff",
        borderRadius: "12px",
        boxShadow: "0 4px 16px rgba(0, 0, 0, 0.15)",
        minWidth: "140px",
        marginTop: "4px",
    },
    "& .MuiList-root": { padding: "6px" },
    ...theme.applyStyles("dark", {
        "& .MuiPaper-root": {
            backgroundColor: "#2b2b2b",
            boxShadow: "0 4px 16px rgba(0, 0, 0, 0.5)",
        },
    }),
}));

const StyledMenuItem = styled(MenuItem)(({ theme }) => ({
    display: "flex",
    alignItems: "center",
    gap: 10,
    padding: "8px 12px",
    borderRadius: 8,
    color: "#131313",
    fontSize: 14,
    "&:hover": { backgroundColor: "#F5F5F5" },
    ...theme.applyStyles("dark", {
        color: "#fff",
        "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.12)" },
    }),
}));
