import { ArrowLeft02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    CircularProgress,
    ClickAwayListener,
    Dialog,
    Grow,
    Popper,
    Slide,
    useMediaQuery,
} from "@mui/material";
import { keyframes } from "@mui/material/styles";
import { SpaceAvatarImage } from "components/AvatarImage";
import { SpaceBottomSheetTransition } from "components/BottomSheetTransition";
import { SpaceCommentComposer } from "components/CommentComposer";
import {
    CopyIcon,
    DeleteIcon,
    MessageActionMenuItem,
    MessageActionMenuList,
    ReplyIcon,
} from "components/MessageActionMenu";
import {
    MessageQuickReactions,
    MessageReactionPicker,
} from "components/MessageReactionPicker";
import { ReplyComposerPreview } from "components/ReplyComposerPreview";
import { emojiName } from "data/emojis";
import type { FriendProfile } from "data/friends";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import { flushSync } from "react-dom";
import {
    createCurrentComment,
    deleteCurrentComment,
    loadCurrentComments,
    loadCurrentFriendAvatarURL,
    markCurrentNotificationItemsRead,
    removeCurrentCommentReaction,
    setCurrentCommentReaction,
    type SpaceComment,
} from "services/space";
import {
    spaceControlBackgroundHover,
    spaceDialogBackground,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import {
    commentReactionGroups,
    commentThreads,
    groupCommentReactions,
    isEmojiOnlyComment,
    validateCommentReplyTarget,
    type CommentDraft,
} from "utils/comments";
import { firstNameFrom, formatSpaceDate } from "utils/display";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const messageActionsTransitionDuration = { enter: 300, exit: 100 };

const reactionPop = keyframes`
    from { transform: scale(0.85); }
    60% { transform: scale(1.15); }
    to { transform: scale(1); }
`;

const commentEnter = keyframes`
    from { opacity: 0; transform: translateY(6px); }
    to { opacity: 1; transform: translateY(0); }
`;

const textActionSx = {
    appearance: "none",
    bgcolor: "transparent",
    border: 0,
    borderRadius: "8px",
    color: spaceTextMuted,
    cursor: "pointer",
    font: "inherit",
    fontSize: 12,
    fontWeight: 500,
    minHeight: 32,
    p: 0,
    "&:hover": { color: spaceText },
    "&:disabled": { cursor: "default", opacity: 0.4 },
    "&:focus-visible": { outline: "2px solid #08C225", outlineOffset: 3 },
} as const;

const CommentIdentity: React.FC<{
    actor: FriendProfile;
    viewer: string;
    inline?: boolean;
}> = ({ actor, viewer, inline = false }) => {
    const router = useSpaceRouter();
    const [avatar, setAvatar] = React.useState<string | null>(null);
    React.useEffect(() => {
        let active = true;
        setAvatar(null);
        if (actor.avatarObjectID)
            void loadCurrentFriendAvatarURL(actor, viewer)
                .then((url) => {
                    if (active) setAvatar(url);
                })
                .catch(() => {
                    if (active) setAvatar(null);
                });
        return () => {
            active = false;
        };
    }, [actor, viewer]);
    return (
        <Box
            component="button"
            type="button"
            onClick={() =>
                void router.push(
                    spaceRoutes.friendPage,
                    spaceRoutes.friend(actor.username),
                )
            }
            sx={{
                ...textActionSx,
                alignItems: "center",
                display: inline ? "inline-flex" : "flex",
                fontSize: inline ? 13 : 14,
                fontWeight: 600,
                minHeight: inline ? 0 : 24,
                lineHeight: inline ? "18px" : "20px",
                color: spaceText,
                p: 0,
                minWidth: 0,
                overflowWrap: "anywhere",
                textAlign: "left",
                textTransform: "none",
                gap: 1,
            }}
        >
            <Box
                component="span"
                sx={{
                    display: "block",
                    width: 32,
                    height: 32,
                    flexShrink: 0,
                    ...(inline
                        ? { position: "absolute", left: 0, top: 0 }
                        : {}),
                }}
            >
                <SpaceAvatarImage
                    src={avatar ?? undefined}
                    alt=""
                    borderRadius="50%"
                />
            </Box>
            {(inline ? firstNameFrom(actor.fullName) : actor.fullName) ||
                `@${actor.username}`}
        </Box>
    );
};

const CommentRow: React.FC<{
    comment: SpaceComment;
    recipient?: SpaceComment;
    viewer: string;
    highlighted: boolean;
    disabled: boolean;
    ownReaction: string | undefined;
    onReact: (emoji: string) => void;
    onReply: () => void;
    onOpenReactions: () => void;
    onOpenActions: (
        anchor: HTMLElement,
        source: "touch" | "contextmenu",
    ) => void;
}> = ({
    comment,
    recipient,
    viewer,
    highlighted,
    disabled,
    ownReaction,
    onReact,
    onReply,
    onOpenReactions,
    onOpenActions,
}) => {
    const timer = React.useRef<number | undefined>(undefined);
    const start = React.useRef<
        | {
              pointerId: number;
              x: number;
              y: number;
              canReply: boolean;
              active: boolean;
              thresholdPx: number;
              maxOffsetPx: number;
              resistancePx: number;
          }
        | undefined
    >(undefined);
    const didOpen = React.useRef(false);
    const didSwipe = React.useRef(false);
    const [swipeOffset, setSwipeOffset] = React.useState(0);
    const canOpenActions = !disabled && !comment.deleted;
    const reactions = commentReactionGroups(comment.reactions, ownReaction);
    const reactionColumns = Math.min(reactions.length, 6);
    const largeEmoji =
        !comment.parentId && isEmojiOnlyComment(comment.text ?? "");
    const previousReaction = React.useRef(ownReaction);
    const [poppingReaction, setPoppingReaction] = React.useState<string>();
    React.useEffect(() => {
        if (ownReaction && ownReaction != previousReaction.current)
            setPoppingReaction(ownReaction);
        previousReaction.current = ownReaction;
    }, [ownReaction]);
    const clearLongPress = React.useCallback(() => {
        window.clearTimeout(timer.current);
        timer.current = undefined;
    }, []);
    React.useEffect(() => clearLongPress, [clearLongPress]);
    const cancelGesture = () => {
        clearLongPress();
        start.current = undefined;
        setSwipeOffset(0);
    };
    const openContextAction = (
        anchor: HTMLElement,
        source: "touch" | "contextmenu",
    ) => {
        cancelGesture();
        window.getSelection()?.removeAllRanges();
        if (anchor.hasAttribute("data-comment-reaction")) onOpenReactions();
        else onOpenActions(anchor, source);
    };
    const isInteractiveTarget = (target: EventTarget | null) =>
        target instanceof Element && Boolean(target.closest("a, button"));
    const reactionTarget = (target: EventTarget | null) =>
        target instanceof Element
            ? target.closest<HTMLElement>("[data-comment-reaction]")
            : null;
    return (
        <Box
            component="article"
            id={`comment-${comment.commentId}`}
            data-comment-id={comment.commentId}
            data-comment-highlighted={highlighted || undefined}
            tabIndex={canOpenActions ? 0 : undefined}
            aria-label={`Comment by ${comment.author ? firstNameFrom(comment.author.fullName) || `@${comment.author.username}` : "deleted account"}`}
            aria-haspopup={canOpenActions ? "menu" : undefined}
            onContextMenu={(event) => {
                const reaction = reactionTarget(event.target);
                if (
                    !canOpenActions ||
                    (isInteractiveTarget(event.target) && !reaction)
                )
                    return;
                event.preventDefault();
                event.stopPropagation();
                if (didOpen.current) return;
                const source = start.current ? "touch" : "contextmenu";
                didOpen.current = source == "touch";
                openContextAction(reaction ?? event.currentTarget, source);
            }}
            onKeyDown={(event) => {
                didOpen.current = false;
                didSwipe.current = false;
                const reaction = reactionTarget(event.target);
                if (
                    !canOpenActions ||
                    (isInteractiveTarget(event.target) && !reaction)
                )
                    return;
                if (
                    event.key == "ContextMenu" ||
                    (event.shiftKey && event.key == "F10") ||
                    (!reaction && (event.key == "Enter" || event.key == " "))
                ) {
                    event.preventDefault();
                    openContextAction(
                        reaction ?? event.currentTarget,
                        "contextmenu",
                    );
                }
            }}
            onPointerDown={(event) => {
                cancelGesture();
                didOpen.current = false;
                didSwipe.current = false;
                const reaction = reactionTarget(event.target);
                if (
                    !canOpenActions ||
                    !event.isPrimary ||
                    event.button != 0 ||
                    (event.pointerType != "touch" &&
                        isInteractiveTarget(event.target) &&
                        !reaction)
                )
                    return;
                const rect = event.currentTarget.getBoundingClientRect();
                const availableRightPx = Math.max(
                    0,
                    Math.min(window.innerWidth - 8, rect.right + 8) -
                        event.clientX,
                );
                const resistancePx = rect.width * 0.42;
                start.current = {
                    pointerId: event.pointerId,
                    x: event.clientX,
                    y: event.clientY,
                    canReply: event.pointerType == "touch",
                    active: false,
                    thresholdPx: Math.min(
                        64,
                        Math.max(20, availableRightPx * 0.65),
                        availableRightPx,
                    ),
                    maxOffsetPx:
                        resistancePx *
                        Math.log1p(availableRightPx / resistancePx),
                    resistancePx,
                };
                if (isInteractiveTarget(event.target) && !reaction) return;
                const anchor = reaction ?? event.currentTarget;
                anchor.setPointerCapture(event.pointerId);
                timer.current = window.setTimeout(() => {
                    didOpen.current = true;
                    openContextAction(anchor, "touch");
                }, 520);
            }}
            onPointerMove={(event) => {
                const gesture = start.current;
                if (gesture?.pointerId != event.pointerId) return;
                const dx = event.clientX - gesture.x;
                const dy = event.clientY - gesture.y;
                if (Math.hypot(dx, dy) > 10) clearLongPress();
                if (!gesture.canReply || !canOpenActions) return;
                if (!gesture.active) {
                    if (
                        (Math.abs(dy) > 10 && Math.abs(dy) >= Math.abs(dx)) ||
                        dx < -10
                    ) {
                        cancelGesture();
                        return;
                    }
                    if (dx <= 10 || dx <= Math.abs(dy) * 1.2) return;
                    gesture.active = true;
                    didSwipe.current = true;
                    event.currentTarget.setPointerCapture(event.pointerId);
                }
                setSwipeOffset(
                    Math.min(
                        gesture.maxOffsetPx,
                        gesture.resistancePx *
                            Math.log1p(Math.max(dx, 0) / gesture.resistancePx),
                    ),
                );
            }}
            onPointerUp={(event) => {
                const gesture = start.current;
                if (gesture && gesture.pointerId != event.pointerId) return;
                cancelGesture();
                if (didOpen.current) {
                    event.preventDefault();
                    event.stopPropagation();
                    return;
                }
                if (!gesture?.active || !canOpenActions) return;
                const dx = event.clientX - gesture.x;
                const dy = event.clientY - gesture.y;
                if (dx < gesture.thresholdPx || dx <= Math.abs(dy) * 1.2)
                    return;
                if (event.cancelable) event.preventDefault();
                event.stopPropagation();
                onReply();
            }}
            onPointerCancel={cancelGesture}
            onTouchEnd={(event) => {
                if (!didOpen.current && !didSwipe.current) return;
                if (event.cancelable) event.preventDefault();
                event.stopPropagation();
            }}
            onClickCapture={(event) => {
                if (!didOpen.current && !didSwipe.current) return;
                event.preventDefault();
                event.stopPropagation();
                didOpen.current = false;
                didSwipe.current = false;
            }}
            sx={{
                bgcolor: highlighted
                    ? spaceControlBackgroundHover
                    : "transparent",
                transition: "background-color 400ms ease-out",
                animation: highlighted
                    ? `${commentEnter} 240ms ease-out`
                    : undefined,
                position: "relative",
                py: 0.75,
                px: 2,
                flexShrink: 0,
                cursor: canOpenActions ? "context-menu" : "default",
                touchAction: "pan-y",
                userSelect: "none",
                WebkitTouchCallout: "none",
                WebkitUserSelect: "none",
                "&:focus-visible": {
                    outline: "2px solid #08C225",
                    outlineOffset: 2,
                },
                "@media (prefers-reduced-motion: reduce)": {
                    transition: "none",
                    animation: "none",
                },
            }}
        >
            {canOpenActions && (
                <Box
                    aria-hidden
                    sx={{
                        alignItems: "center",
                        color: "#888888",
                        display: "flex",
                        height: "100%",
                        justifyContent: "center",
                        left: comment.parentId ? 56 : 16,
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
                sx={{
                    position: "relative",
                    pl: 5,
                    ml: comment.parentId ? 5 : 0,
                    containerType: "inline-size",
                    transform: `translateX(${swipeOffset}px)`,
                    transition:
                        swipeOffset > 0 ? "none" : "transform 160ms ease-out",
                    "@media (prefers-reduced-motion: reduce)": {
                        transition: "none",
                    },
                }}
            >
                <Box
                    sx={{
                        display: "flex",
                        alignItems: "baseline",
                        flexWrap: "wrap",
                        columnGap: 1,
                        rowGap: 0.25,
                        lineHeight: "18px",
                    }}
                >
                    {comment.author ? (
                        <CommentIdentity
                            actor={comment.author}
                            viewer={viewer}
                            inline
                        />
                    ) : (
                        <Box
                            component="span"
                            sx={{
                                fontSize: 13,
                                fontWeight: 600,
                                color: spaceText,
                            }}
                        >
                            Deleted account
                        </Box>
                    )}
                    <Box
                        component="time"
                        dateTime={comment.createdAt}
                        sx={{
                            color: spaceTextMuted,
                            fontSize: 11,
                            fontWeight: 400,
                            whiteSpace: "nowrap",
                        }}
                    >
                        {formatSpaceDate(Date.parse(comment.createdAt)).replace(
                            / ago$/,
                            "",
                        )}
                    </Box>
                </Box>
                <Box
                    sx={{
                        whiteSpace: "pre-wrap",
                        overflowWrap: "anywhere",
                        fontSize: largeEmoji ? 30 : 13,
                        fontWeight: 400,
                        lineHeight: largeEmoji ? "40px" : "18px",
                        color: spaceText,
                    }}
                >
                    {recipient?.author && !recipient.deleted && (
                        <Box
                            component="span"
                            sx={{ color: spaceTextMuted, fontSize: 13 }}
                        >
                            {`@${recipient.author.username} `}
                        </Box>
                    )}
                    {comment.text ?? "Comment unavailable"}
                </Box>
                {!comment.deleted && reactions.length > 0 && (
                    <Box
                        sx={{
                            alignItems: "center",
                            display: "grid",
                            gridTemplateColumns: `repeat(${reactionColumns}, max-content)`,
                            columnGap: 0.5,
                            mt: 0.25,
                            "@container (max-width: 260px)": {
                                columnGap: 0.25,
                            },
                            "@container (max-width: 224px)": {
                                gridTemplateColumns: `repeat(${Math.min(reactionColumns, 5)}, max-content)`,
                            },
                        }}
                    >
                        {reactions.map(({ emoji, count, isOwn }) => (
                            <Box
                                component="button"
                                type="button"
                                key={emoji}
                                data-comment-reaction
                                aria-label={`${isOwn ? "Remove" : "Add"} ${emojiName(emoji)} reaction, ${count} ${count == 1 ? "reaction" : "reactions"}`}
                                aria-pressed={isOwn}
                                disabled={
                                    disabled || comment.text === undefined
                                }
                                onClick={() => onReact(emoji)}
                                onAnimationEnd={() =>
                                    setPoppingReaction(undefined)
                                }
                                sx={{
                                    ...textActionSx,
                                    alignItems: "center",
                                    borderRadius: "999px",
                                    display: "flex",
                                    justifyContent: "center",
                                    minHeight: 28,
                                    "&:hover > span": {
                                        bgcolor: spaceControlBackgroundHover,
                                    },
                                    "&:disabled": { cursor: "default" },
                                    "&:active > span": {
                                        transform: "scale(0.94)",
                                    },
                                }}
                            >
                                <Box
                                    component="span"
                                    aria-hidden
                                    sx={{
                                        alignItems: "center",
                                        bgcolor: isOwn ? "#28462F" : "#333333",
                                        borderRadius: "999px",
                                        display: "flex",
                                        gap: 0.5,
                                        height: 24,
                                        px: 0.75,
                                        transition: "transform 180ms ease-out",
                                        "@container (max-width: 260px)": {
                                            px: 0.5,
                                        },
                                        animation:
                                            poppingReaction == emoji
                                                ? `${reactionPop} 240ms ease-out`
                                                : undefined,
                                        "@media (prefers-reduced-motion: reduce)":
                                            {
                                                animation: "none",
                                                transition: "none",
                                            },
                                    }}
                                >
                                    <Box component="span" sx={{ fontSize: 16 }}>
                                        {emoji}
                                    </Box>
                                    <Box
                                        component="span"
                                        sx={{
                                            color: isOwn
                                                ? "#A1D5AB"
                                                : "#C2C2C2",
                                            fontVariantNumeric: "tabular-nums",
                                        }}
                                    >
                                        {count}
                                    </Box>
                                </Box>
                            </Box>
                        ))}
                    </Box>
                )}
            </Box>
        </Box>
    );
};

export const PostComments: React.FC<{
    container: () => HTMLElement | null;
    autoFocus?: boolean;
    targetCommentId?: string;
    viewer: string;
    postId: number;
    owner: string;
    draft: CommentDraft;
    setDraft: React.Dispatch<React.SetStateAction<CommentDraft>>;
    onClose: () => void;
}> = ({
    container,
    autoFocus,
    targetCommentId,
    viewer,
    postId,
    owner,
    draft,
    setDraft,
    onClose,
}) => {
    const prefersReducedMotion = useMediaQuery(
        "(prefers-reduced-motion: reduce)",
    );
    const [comments, setComments] = React.useState<SpaceComment[]>([]);
    const threads = commentThreads(comments);
    const [loading, setLoading] = React.useState(true);
    const [error, setError] = React.useState<string>();
    const [mutationError, setMutationError] = React.useState<string>();
    const [open, setOpen] = React.useState(true);
    const [entered, setEntered] = React.useState(false);
    const [highlightedCommentId, setHighlightedCommentId] =
        React.useState<string>();
    const handledTarget = React.useRef<string>(undefined);
    const submittedCommentId = React.useRef<string>(undefined);
    const dialogContainer = React.useRef<HTMLDivElement>(null);
    const list = React.useRef<HTMLDivElement>(null);
    const acknowledged = React.useRef(new Set<string>());
    const [action, setAction] = React.useState<
        | {
              type: "menu";
              commentId: string;
              anchor: HTMLElement;
              open: boolean;
          }
        | { type: "react"; commentId: string }
        | { type: "reactions"; commentId: string; open: boolean }
    >();
    const ignoreMouseAwayUntil = React.useRef(0);
    const menuPointerTarget = React.useRef<Element | null>(null);
    const reactionsPointerTarget = React.useRef<Element | null>(null);
    const actionAnchor = React.useMemo(() => {
        if (action?.type != "menu") return undefined;
        return {
            contextElement: action.anchor,
            getBoundingClientRect: () => {
                const rect = action.anchor.getBoundingClientRect();
                const bounds = list.current!.getBoundingClientRect();
                const top = Math.max(rect.top, bounds.top);
                return DOMRect.fromRect({
                    x: rect.left,
                    y: top,
                    width: rect.width,
                    height: Math.max(
                        0,
                        Math.min(rect.bottom, bounds.bottom) - top,
                    ),
                });
            },
        };
    }, [action]);
    const dragStart = React.useRef<number | undefined>(undefined);
    const [isDragging, setIsDragging] = React.useState(false);
    const [dragOffset, setDragOffset] = React.useState(0);
    const dragged = React.useRef(false);
    const { replyTarget } = draft;
    const reply = comments.find(
        (comment) =>
            replyTarget?.status == "selected" &&
            comment.commentId == replyTarget.commentId,
    );
    const [mutating, setMutating] = React.useState(false);
    const [optimisticReaction, setOptimisticReaction] = React.useState<{
        commentId: string;
        emoji: string | undefined;
    }>();
    const busy = mutating || Boolean(draft.sending);
    const selectedComment = comments.find(
        (comment) => comment.commentId == action?.commentId && !comment.deleted,
    );
    const reactionList =
        action?.type == "reactions" ? selectedComment : undefined;
    const generation = React.useRef(0);
    const input = React.useRef<HTMLTextAreaElement>(null);
    useBrowserBackClose({
        open,
        onClose: () => setOpen(false),
        stateKey: "space-post-comments",
    });
    const refresh = React.useCallback(async () => {
        const current = ++generation.current;
        try {
            const items = await loadCurrentComments(viewer, owner, postId);
            if (current != generation.current) return;
            setComments(items);
            setError(undefined);
            setMutationError(undefined);
            setDraft((value) => ({
                ...value,
                replyTarget: validateCommentReplyTarget(
                    value.replyTarget,
                    items,
                ),
            }));
        } catch {
            if (current != generation.current) return;
            setComments([]);
            setAction(undefined);
            setError(
                "Discussion unavailable. Access may have changed or the post may have been deleted.",
            );
        } finally {
            if (current == generation.current) setLoading(false);
        }
    }, [viewer, owner, postId, setDraft]);
    React.useEffect(() => {
        if (draft.sending) return;
        const requestGeneration = generation;
        void refresh();
        return () => {
            requestGeneration.current++;
        };
    }, [refresh, draft.sending]);
    React.useLayoutEffect(() => {
        if (
            loading ||
            !targetCommentId ||
            handledTarget.current == targetCommentId
        )
            return;
        const container = list.current;
        const target = Array.from(
            container?.querySelectorAll<HTMLElement>("[data-comment-id]") ?? [],
        ).find((row) => row.dataset.commentId == targetCommentId);
        handledTarget.current = targetCommentId;
        if (!container || !target) return;
        const bounds = target.getBoundingClientRect();
        container.scrollTo({
            top:
                container.scrollTop +
                bounds.top -
                container.getBoundingClientRect().top -
                Math.max(12, (container.clientHeight - bounds.height) / 2),
            behavior: "instant",
        });
        setHighlightedCommentId(targetCommentId);
    }, [comments, loading, targetCommentId]);
    React.useLayoutEffect(() => {
        const container = list.current;
        if (
            !container ||
            !open ||
            reactionList ||
            !comments.some(
                (comment) => comment.commentId == submittedCommentId.current,
            )
        )
            return;
        const target = Array.from(
            container.querySelectorAll<HTMLElement>("[data-comment-id]"),
        ).find((row) => row.dataset.commentId == submittedCommentId.current);
        if (!target) return;
        setHighlightedCommentId(submittedCommentId.current);
        submittedCommentId.current = undefined;
        container.scrollTo({
            top:
                container.scrollTop +
                target.getBoundingClientRect().top -
                container.getBoundingClientRect().top -
                Math.max(
                    12,
                    (container.clientHeight - target.clientHeight) / 2,
                ),
            behavior: prefersReducedMotion ? "instant" : "smooth",
        });
    }, [comments, open, prefersReducedMotion, reactionList]);
    React.useEffect(() => {
        if (!highlightedCommentId) return;
        const timer = window.setTimeout(
            () => setHighlightedCommentId(undefined),
            1800,
        );
        return () => window.clearTimeout(timer);
    }, [highlightedCommentId]);
    React.useEffect(() => {
        const container = list.current;
        if (!container || !entered || loading || !open || action) return;
        const notifications = new Map(
            comments
                .filter(
                    (comment) => !comment.deleted && comment.text !== undefined,
                )
                .map((comment) => [
                    comment.commentId,
                    comment.unreadNotificationIds,
                ]),
        );
        const acknowledge = async (ids: string[]) => {
            for (let offset = 0; offset < ids.length; offset += 100) {
                const batch = ids
                    .slice(offset, offset + 100)
                    .filter((id) => !acknowledged.current.has(id));
                if (batch.length == 0) continue;
                batch.forEach((id) => acknowledged.current.add(id));
                try {
                    await markCurrentNotificationItemsRead(viewer, batch);
                } catch (error) {
                    batch.forEach((id) => acknowledged.current.delete(id));
                    log.warn(
                        "Failed to acknowledge comment notifications",
                        error,
                    );
                }
            }
        };
        let observer: IntersectionObserver | undefined;
        const observe = () => {
            observer?.disconnect();
            if (
                document.visibilityState != "visible" ||
                container.clientHeight == 0
            )
                return;
            const rows = Array.from(
                container.querySelectorAll<HTMLElement>("[data-comment-id]"),
            );
            const threshold = [
                ...new Set(
                    rows.map((row) =>
                        Math.min(
                            0.5,
                            container.clientHeight /
                                (2 * row.getBoundingClientRect().height),
                        ),
                    ),
                ),
            ];
            observer = new IntersectionObserver(
                (entries) => {
                    if (
                        document.visibilityState != "visible" ||
                        container.clientHeight == 0
                    )
                        return;
                    const ids = entries
                        .filter(
                            (entry) =>
                                entry.isIntersecting &&
                                entry.intersectionRect.height >=
                                    Math.min(
                                        entry.boundingClientRect.height,
                                        container.clientHeight,
                                    ) /
                                        2,
                        )
                        .flatMap(
                            (entry) =>
                                notifications.get(
                                    (entry.target as HTMLElement).dataset
                                        .commentId!,
                                ) ?? [],
                        );
                    if (ids.length > 0) void acknowledge(ids);
                },
                { root: container, threshold },
            );
            rows.forEach((row) => observer!.observe(row));
        };
        observe();
        const resize = new ResizeObserver(observe);
        resize.observe(container);
        document.addEventListener("visibilitychange", observe);
        return () => {
            observer?.disconnect();
            resize.disconnect();
            document.removeEventListener("visibilitychange", observe);
        };
    }, [action, comments, entered, loading, open, viewer]);
    const mutate = async (action: () => Promise<void>) => {
        setMutating(true);
        setMutationError(undefined);
        try {
            await action();
            await refresh();
        } catch {
            await refresh();
            setMutationError("Couldn't save your change. Please try again.");
        } finally {
            setMutating(false);
        }
    };
    const react = (comment: SpaceComment, emoji: string) => {
        if (busy) return;
        const nextEmoji = comment.reactions.some(
            (item) => item.isOwn && item.emoji == emoji,
        )
            ? undefined
            : emoji;
        setOptimisticReaction({
            commentId: comment.commentId,
            emoji: nextEmoji,
        });
        void mutate(() =>
            setCurrentCommentReaction(
                viewer,
                owner,
                postId,
                comment.commentId,
                nextEmoji,
            ),
        ).finally(() => setOptimisticReaction(undefined));
    };
    const closeActions = () =>
        setAction((current) =>
            current?.type == "menu" ? { ...current, open: false } : current,
        );
    const closeReactions = () =>
        setAction((current) =>
            current?.type == "reactions"
                ? { ...current, open: false }
                : current,
        );
    const replyTo = (comment: SpaceComment) => {
        flushSync(() => {
            closeActions();
            setDraft((value) => ({
                ...value,
                replyTarget: {
                    status: "selected",
                    commentId: comment.commentId,
                },
            }));
        });
        input.current?.focus({ preventScroll: true });
    };
    const renderComment = (comment: SpaceComment) => (
        <CommentRow
            key={comment.commentId}
            comment={comment}
            recipient={comments.find(
                (item) => item.commentId == comment.replyToId,
            )}
            viewer={viewer}
            highlighted={highlightedCommentId == comment.commentId}
            disabled={busy}
            ownReaction={
                optimisticReaction?.commentId == comment.commentId
                    ? optimisticReaction.emoji
                    : comment.reactions.find((reaction) => reaction.isOwn)
                          ?.emoji
            }
            onReact={(emoji) => react(comment, emoji)}
            onReply={() => replyTo(comment)}
            onOpenReactions={() => {
                reactionsPointerTarget.current = null;
                setAction({
                    type: "reactions",
                    commentId: comment.commentId,
                    open: true,
                });
            }}
            onOpenActions={(anchor, source) => {
                menuPointerTarget.current = null;
                ignoreMouseAwayUntil.current =
                    source == "touch" ? Date.now() + 900 : 0;
                setAction({
                    type: "menu",
                    commentId: comment.commentId,
                    anchor,
                    open: true,
                });
            }}
        />
    );
    return (
        <Dialog
            container={container}
            open={open}
            onClose={() => setOpen(false)}
            maxWidth={false}
            aria-label={reactionList ? "Reactions" : "Comments"}
            slots={
                prefersReducedMotion
                    ? undefined
                    : { transition: SpaceBottomSheetTransition }
            }
            transitionDuration={prefersReducedMotion ? 0 : undefined}
            sx={{
                "--space-dialog-backdrop": "rgba(0 0 0 / 0.64)",
                "& .MuiDialog-container": {
                    alignItems: "flex-end",
                    pb: "var(--space-keyboard-inset, 0px)",
                },
            }}
            slotProps={{
                container: { ref: dialogContainer },
                paper: {
                    style: {
                        maxHeight:
                            "calc(100dvh - var(--space-keyboard-inset, 0px) - env(safe-area-inset-top) - 16px)",
                        translate: `0 ${dragOffset}px`,
                        transition:
                            isDragging || prefersReducedMotion
                                ? "none"
                                : "translate 160ms ease-out",
                    },
                    sx: {
                        bgcolor: spaceDialogBackground,
                        color: spaceText,
                        borderRadius: "28px 28px 0 0",
                        boxShadow: "none",
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        height: "min(72dvh, 640px)",
                        m: 0,
                        maxWidth: { xs: "none", sm: 480 },
                        overflow: "hidden",
                        width: "100%",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                    },
                },
                transition: {
                    onEntered: () => setEntered(true),
                    onExited: onClose,
                },
            }}
        >
            <Box
                component="button"
                type="button"
                aria-label="Close comments"
                onClick={(event) => {
                    if (event.detail == 0 || !dragged.current) setOpen(false);
                    dragged.current = false;
                }}
                onPointerDown={(event) => {
                    if (event.button != 0) return;
                    dragStart.current = event.clientY;
                    dragged.current = false;
                    setIsDragging(true);
                    event.currentTarget.setPointerCapture(event.pointerId);
                }}
                onPointerMove={(event) => {
                    if (dragStart.current != undefined) {
                        if (Math.abs(event.clientY - dragStart.current) > 4)
                            dragged.current = true;
                        setDragOffset(
                            Math.max(0, event.clientY - dragStart.current),
                        );
                    }
                }}
                onPointerUp={(event) => {
                    if (dragStart.current == undefined) return;
                    const distance = event.clientY - dragStart.current;
                    dragStart.current = undefined;
                    setIsDragging(false);
                    if (distance > 80) setOpen(false);
                    else setDragOffset(0);
                }}
                onPointerCancel={() => {
                    dragStart.current = undefined;
                    dragged.current = true;
                    setIsDragging(false);
                    setDragOffset(0);
                }}
                sx={{
                    ...textActionSx,
                    alignItems: "center",
                    cursor: isDragging ? "grabbing" : "grab",
                    display: "flex",
                    justifyContent: "center",
                    minHeight: 24,
                    flexShrink: 0,
                    touchAction: "none",
                    width: "100%",
                    "&:focus-visible": {
                        outline: "2px solid #08C225",
                        outlineOffset: -2,
                    },
                }}
            >
                <Box
                    component="span"
                    sx={{
                        bgcolor: "#686868",
                        borderRadius: "999px",
                        height: 4,
                        width: 32,
                    }}
                />
            </Box>
            <Box
                inert={Boolean(reactionList)}
                aria-hidden={Boolean(reactionList)}
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    flex: 1,
                    minHeight: 0,
                }}
            >
                <Box
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        px: 2,
                        pb: 2,
                        flexShrink: 0,
                        position: "relative",
                    }}
                >
                    <Box
                        component="h2"
                        sx={{
                            fontSize: 16,
                            fontWeight: 600,
                            lineHeight: "24px",
                            m: 0,
                        }}
                    >
                        Comments
                    </Box>
                </Box>
                <Box
                    ref={list}
                    sx={{
                        py: 0.5,
                        display: "flex",
                        flexDirection: "column",
                        overflowX: "hidden",
                        overflowY: "auto",
                        overscrollBehavior: "contain",
                        flex: "1 1 auto",
                        minHeight: 0,
                    }}
                >
                    <>
                        {!loading &&
                            !error &&
                            targetCommentId &&
                            !comments.some(
                                (comment) =>
                                    comment.commentId == targetCommentId &&
                                    !comment.deleted,
                            ) && (
                                <Box
                                    role="status"
                                    sx={{
                                        px: 2,
                                        py: 2,
                                        color: spaceTextMuted,
                                        fontSize: 13,
                                    }}
                                >
                                    This comment is no longer available.
                                </Box>
                            )}
                        {loading && (
                            <Box
                                sx={{
                                    alignItems: "center",
                                    display: "flex",
                                    flex: "1 1 auto",
                                    justifyContent: "center",
                                    py: 3,
                                }}
                            >
                                <CircularProgress
                                    size={20}
                                    sx={{ color: spaceTextMuted }}
                                />
                            </Box>
                        )}
                        {!loading && !error && threads.length == 0 && (
                            <Box
                                sx={{
                                    display: "flex",
                                    flexDirection: "column",
                                    flex: "1 1 auto",
                                    justifyContent: "center",
                                    gap: 0.75,
                                    px: 2,
                                    py: 3,
                                    textAlign: "center",
                                }}
                            >
                                <Box
                                    component="p"
                                    sx={{ m: 0, fontSize: 15, fontWeight: 600 }}
                                >
                                    No comments yet
                                </Box>
                                <Box
                                    component="p"
                                    sx={{
                                        m: 0,
                                        color: spaceTextMuted,
                                        fontSize: 13,
                                    }}
                                >
                                    Be the first to comment
                                </Box>
                            </Box>
                        )}
                        {threads.map(({ comment, replies }, index) => (
                            <Box
                                key={comment.commentId}
                                sx={{
                                    flexShrink: 0,
                                    py: 0.5,
                                    mt: index > 0 ? 0.75 : 0,
                                }}
                            >
                                {renderComment(comment)}
                                {replies.length > 0 && (
                                    <Box
                                        sx={{
                                            display: "flex",
                                            flexDirection: "column",
                                            gap: 0.25,
                                            mt: 0.25,
                                        }}
                                    >
                                        {replies.map(renderComment)}
                                    </Box>
                                )}
                            </Box>
                        ))}
                        {(error || mutationError) && (
                            <Box
                                role="alert"
                                sx={{
                                    px: 2,
                                    py: 2,
                                    color: spaceTextMuted,
                                    fontSize: 13,
                                }}
                            >
                                {error || mutationError}{" "}
                                <Box
                                    component="button"
                                    type="button"
                                    onClick={() => void refresh()}
                                    sx={textActionSx}
                                >
                                    Refresh
                                </Box>
                            </Box>
                        )}
                    </>
                </Box>
                <Box
                    sx={{
                        display: "grid",
                        gap: "8px",
                        px: 2,
                        pt: 1,
                        pb: "max(16px, env(safe-area-inset-bottom))",
                        flexShrink: 0,
                    }}
                >
                    {replyTarget && (
                        <ReplyComposerPreview
                            tone="neutral"
                            name={
                                replyTarget.status == "unavailable"
                                    ? "Comment unavailable"
                                    : reply?.author?.spaceId == viewer
                                      ? "You"
                                      : reply?.author
                                        ? firstNameFrom(
                                              reply.author.fullName,
                                          ) || `@${reply.author.username}`
                                        : reply
                                          ? "Deleted account"
                                          : "Replying…"
                            }
                            text={
                                replyTarget.status == "unavailable"
                                    ? "This comment or its thread is no longer available."
                                    : loading && !reply
                                      ? "Loading comment…"
                                      : (reply?.text ?? "Comment unavailable")
                            }
                            cancelLabel={
                                replyTarget.status == "unavailable"
                                    ? "Comment instead"
                                    : "Cancel reply"
                            }
                            onCancel={() =>
                                setDraft((value) => ({
                                    ...value,
                                    replyTarget: undefined,
                                }))
                            }
                        />
                    )}
                    <SpaceCommentComposer
                        autoFocus={autoFocus}
                        inputRef={input}
                        text={draft.text}
                        onTextChange={(text) =>
                            setDraft((value) => ({ ...value, text }))
                        }
                        disabled={
                            busy ||
                            Boolean(error) ||
                            replyTarget?.status == "unavailable"
                        }
                        sendDisabled={loading}
                        placeholder={replyTarget ? "Reply…" : "Add a comment…"}
                        onSend={async (text) => {
                            const replyToId =
                                replyTarget?.status == "selected"
                                    ? replyTarget.commentId
                                    : undefined;
                            const submission =
                                draft.pendingSubmission?.text == text &&
                                draft.pendingSubmission.replyToId == replyToId
                                    ? draft.pendingSubmission
                                    : {
                                          commentId: crypto.randomUUID(),
                                          text,
                                          replyToId,
                                      };
                            setDraft((value) => ({
                                ...value,
                                pendingSubmission: submission,
                                sending: true,
                            }));
                            try {
                                await createCurrentComment(
                                    viewer,
                                    owner,
                                    postId,
                                    submission.commentId,
                                    submission.replyToId,
                                    submission.text,
                                );
                                submittedCommentId.current =
                                    submission.commentId;
                                setDraft({ text: "", sending: true });
                            } finally {
                                setDraft((value) => ({
                                    ...value,
                                    sending: false,
                                }));
                            }
                        }}
                    />
                </Box>
            </Box>
            <Slide
                direction="up"
                in={action?.type == "reactions" && action.open}
                timeout={prefersReducedMotion ? 0 : 240}
                easing="cubic-bezier(0.22, 1, 0.36, 1)"
                mountOnEnter
                unmountOnExit
                onExited={() =>
                    setAction((current) =>
                        current?.type == "reactions" ? undefined : current,
                    )
                }
            >
                <Box
                    onPointerDownCapture={(event) => {
                        reactionsPointerTarget.current =
                            event.target instanceof Element
                                ? event.target.closest("button")
                                : null;
                    }}
                    onPointerCancel={() => {
                        reactionsPointerTarget.current = null;
                    }}
                    onClickCapture={(event) => {
                        const target =
                            event.target instanceof Element
                                ? event.target.closest("button")
                                : null;
                        if (
                            event.detail &&
                            (!target ||
                                target != reactionsPointerTarget.current)
                        ) {
                            event.preventDefault();
                            event.stopPropagation();
                        }
                        reactionsPointerTarget.current = null;
                    }}
                    sx={{
                        position: "absolute",
                        inset: "24px 0 0",
                        bgcolor: spaceDialogBackground,
                        display: "flex",
                        flexDirection: "column",
                        zIndex: 1,
                    }}
                >
                    <Box
                        sx={{
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            px: 2,
                            pb: 2,
                            flexShrink: 0,
                            position: "relative",
                        }}
                    >
                        <Box
                            component="button"
                            type="button"
                            aria-label="Back to comments"
                            onClick={closeReactions}
                            sx={{
                                ...textActionSx,
                                position: "absolute",
                                left: 16,
                                display: "flex",
                                alignItems: "center",
                            }}
                        >
                            <HugeiconsIcon
                                icon={ArrowLeft02Icon}
                                size={20}
                                strokeWidth={1.8}
                            />
                        </Box>
                        <Box
                            component="h2"
                            sx={{
                                fontSize: 16,
                                fontWeight: 600,
                                lineHeight: "24px",
                                m: 0,
                            }}
                        >
                            Reactions
                        </Box>
                    </Box>
                    <Box
                        sx={{
                            overflowY: "auto",
                            overscrollBehavior: "contain",
                            display: "flex",
                            flexDirection: "column",
                            flex: 1,
                            minHeight: 0,
                            py: 0.5,
                        }}
                    >
                        {reactionList && (
                            <>
                                {reactionList.reactions.length == 0 && (
                                    <Box
                                        role="status"
                                        sx={{
                                            alignItems: "center",
                                            color: spaceTextMuted,
                                            display: "flex",
                                            flex: "1 1 auto",
                                            fontSize: 13,
                                            justifyContent: "center",
                                            px: 2,
                                            py: 3,
                                        }}
                                    >
                                        No reactions yet
                                    </Box>
                                )}
                                {groupCommentReactions(
                                    reactionList.reactions,
                                ).map((reaction) => (
                                    <Box
                                        key={reaction.actor.id}
                                        sx={{
                                            display: "flex",
                                            alignItems: "center",
                                            gap: 1.5,
                                            px: 2,
                                            py: 1.5,
                                            flexShrink: 0,
                                        }}
                                    >
                                        <CommentIdentity
                                            actor={reaction.actor}
                                            viewer={viewer}
                                        />
                                        <Box
                                            sx={{
                                                ml: "auto",
                                                display: "flex",
                                                alignItems: "center",
                                                gap: 1.5,
                                                flexShrink: 0,
                                            }}
                                        >
                                            {(reaction.isOwn ||
                                                viewer == owner) && (
                                                <Box
                                                    component="button"
                                                    type="button"
                                                    disabled={busy}
                                                    sx={{
                                                        ...textActionSx,
                                                        bgcolor: "#383838",
                                                        borderRadius: "999px",
                                                        color: spaceText,
                                                        minHeight: 28,
                                                        px: 1.5,
                                                        "&:hover": {
                                                            bgcolor: "#484848",
                                                        },
                                                        "&:active": {
                                                            bgcolor: "#505050",
                                                        },
                                                    }}
                                                    onClick={() =>
                                                        void mutate(() =>
                                                            removeCurrentCommentReaction(
                                                                viewer,
                                                                postId,
                                                                reactionList.commentId,
                                                                reaction.actor
                                                                    .spaceId!,
                                                            ),
                                                        )
                                                    }
                                                >
                                                    Remove
                                                </Box>
                                            )}
                                            <Box sx={{ fontSize: 22 }}>
                                                {reaction.emoji}
                                            </Box>
                                        </Box>
                                    </Box>
                                ))}
                            </>
                        )}
                    </Box>
                </Box>
            </Slide>
            {action?.type == "react" && selectedComment && (
                <MessageReactionPicker
                    label="React to comment"
                    selected={
                        selectedComment.reactions.find((item) => item.isOwn)
                            ?.emoji
                    }
                    onClose={() => setAction(undefined)}
                    onSelect={(emoji) => react(selectedComment, emoji)}
                />
            )}
            <Popper
                anchorEl={actionAnchor}
                open={
                    open &&
                    action?.type == "menu" &&
                    action.open &&
                    Boolean(selectedComment)
                }
                placement="bottom-start"
                container={() => dialogContainer.current}
                transition
                modifiers={[
                    { name: "offset", options: { offset: [16, 8] } },
                    {
                        name: "preventOverflow",
                        options: {
                            altAxis: false,
                            boundary: dialogContainer.current,
                            padding: 8,
                        },
                    },
                    {
                        name: "flip",
                        options: {
                            boundary: dialogContainer.current,
                            padding: 8,
                            fallbackPlacements: ["top-start"],
                            flipVariations: false,
                        },
                    },
                ]}
                sx={{ outline: 0, zIndex: 1500 }}
            >
                {({ TransitionProps, placement }) => (
                    <ClickAwayListener
                        mouseEvent="onMouseDown"
                        touchEvent="onTouchStart"
                        onClickAway={(event) => {
                            if (
                                event instanceof MouseEvent &&
                                Date.now() < ignoreMouseAwayUntil.current
                            )
                                return;
                            closeActions();
                        }}
                    >
                        <Grow
                            {...(TransitionProps ?? {})}
                            easing={{
                                enter: "cubic-bezier(0.18, 0.9, 0.3, 1.18)",
                                exit: "ease-in",
                            }}
                            style={{
                                transformOrigin: `left ${placement.startsWith("top") ? "bottom" : "top"}`,
                            }}
                            timeout={
                                prefersReducedMotion
                                    ? 0
                                    : messageActionsTransitionDuration
                            }
                            onExited={() => {
                                TransitionProps?.onExited();
                                setAction((current) =>
                                    current?.type == "menu" && !current.open
                                        ? undefined
                                        : current,
                                );
                            }}
                        >
                            <Box
                                inert={!TransitionProps?.in || busy}
                                onPointerDownCapture={(event) => {
                                    menuPointerTarget.current =
                                        event.target instanceof Element
                                            ? event.target.closest(
                                                  "button, [role=menuitem]",
                                              )
                                            : null;
                                }}
                                onPointerCancel={() => {
                                    menuPointerTarget.current = null;
                                }}
                                onClickCapture={(event) => {
                                    const target =
                                        event.target instanceof Element
                                            ? event.target.closest(
                                                  "button, [role=menuitem]",
                                              )
                                            : null;
                                    if (
                                        event.detail &&
                                        (!target ||
                                            target != menuPointerTarget.current)
                                    ) {
                                        event.preventDefault();
                                        event.stopPropagation();
                                    }
                                    menuPointerTarget.current = null;
                                }}
                                onKeyDown={(
                                    event: React.KeyboardEvent<HTMLElement>,
                                ) => {
                                    if (event.key != "Escape") return;
                                    event.preventDefault();
                                    event.stopPropagation();
                                    closeActions();
                                    if (action?.type == "menu")
                                        action.anchor.focus({
                                            preventScroll: true,
                                        });
                                }}
                                sx={{
                                    WebkitTapHighlightColor: "transparent",
                                    display: "flex",
                                    flexDirection: "column",
                                    gap: "8px",
                                    outline: 0,
                                    position: "relative",
                                    "& > [role=group], & > [role=menu]": {
                                        bgcolor: "#383838",
                                        boxShadow: "none",
                                        position: "relative",
                                    },
                                    "& > [role=group] > button": {
                                        "&:hover, &[aria-pressed=true]": {
                                            bgcolor: "#505050",
                                        },
                                        "&:active": { bgcolor: "#606060" },
                                    },
                                }}
                            >
                                <Box
                                    component="button"
                                    type="button"
                                    aria-label="Close comment actions"
                                    tabIndex={-1}
                                    onClick={closeActions}
                                    sx={{
                                        position: "absolute",
                                        inset: 0,
                                        bgcolor: "transparent",
                                        border: 0,
                                        p: 0,
                                        cursor: "pointer",
                                    }}
                                />
                                {selectedComment?.text !== undefined && (
                                    <MessageQuickReactions
                                        label="React to comment"
                                        selected={
                                            selectedComment.reactions.find(
                                                (item) => item.isOwn,
                                            )?.emoji
                                        }
                                        onSelect={(emoji) => {
                                            closeActions();
                                            react(selectedComment, emoji);
                                        }}
                                        onMore={() =>
                                            setAction({
                                                type: "react",
                                                commentId:
                                                    selectedComment.commentId,
                                            })
                                        }
                                    />
                                )}
                                <MessageActionMenuList
                                    aria-label="Comment actions"
                                    onKeyDown={(event) => {
                                        if (event.key != "Tab") return;
                                        event.preventDefault();
                                        closeActions();
                                        if (action?.type == "menu")
                                            action.anchor.focus({
                                                preventScroll: true,
                                            });
                                    }}
                                    autoFocus={
                                        selectedComment?.text === undefined
                                    }
                                    variant="menu"
                                >
                                    {selectedComment && (
                                        <MessageActionMenuItem
                                            icon={<ReplyIcon />}
                                            label="Reply"
                                            onClick={() =>
                                                replyTo(selectedComment)
                                            }
                                        />
                                    )}
                                    {selectedComment?.text !== undefined && (
                                        <MessageActionMenuItem
                                            icon={<CopyIcon />}
                                            label="Copy"
                                            onClick={() => {
                                                closeActions();
                                                void navigator.clipboard
                                                    .writeText(
                                                        selectedComment.text!,
                                                    )
                                                    .catch((error: unknown) =>
                                                        log.error(
                                                            "Failed to copy comment",
                                                            error,
                                                        ),
                                                    );
                                            }}
                                        />
                                    )}
                                    {selectedComment?.canDelete && (
                                        <MessageActionMenuItem
                                            icon={<DeleteIcon />}
                                            label="Delete"
                                            tone="danger"
                                            onClick={() => {
                                                closeActions();
                                                void mutate(() =>
                                                    deleteCurrentComment(
                                                        viewer,
                                                        postId,
                                                        selectedComment.commentId,
                                                    ),
                                                );
                                            }}
                                        />
                                    )}
                                </MessageActionMenuList>
                            </Box>
                        </Grow>
                    </ClickAwayListener>
                )}
            </Popper>
        </Dialog>
    );
};
