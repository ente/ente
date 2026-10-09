import {
    ArrowLeft02Icon,
    Cancel01Icon,
    FavouriteIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import {
    SpaceActivityAvatar,
    SpaceActivityIdentity,
    SpaceActivitySection,
} from "components/ActivityList";
import { SpaceFriendRequestCanceledToast } from "components/FriendRequestCanceledToast";
import { SpacePageMeta } from "components/PageMeta";
import { SpacePostPhotoInput } from "components/PostPhotoInput";
import { SpacePostPreviewThumbnail } from "components/PostPreviewThumbnail";
import { SpaceRouteFallback } from "components/RouteFallback";
import { SpaceShareInviteButton } from "components/ShareInviteButton";
import { SpaceSkipLink } from "components/SkipLink";
import log from "ente-base/log";
import React from "react";
import { spaceInviteURL } from "services/invite";
import {
    confirmCurrentFriendRequest,
    deleteCurrentFriendRequest,
    loadCurrentFriendAvatarURL,
    loadCurrentNotifications,
    loadCurrentPostPreview,
    loadCurrentSpaceFriendsCount,
    markCurrentNotificationItemsRead,
    type SpaceNotification,
    type SpacePostPreview,
} from "services/space";
import { useSpaceAppState } from "state/app-state";
import {
    spaceActivityListSx,
    spaceActivityPreviewSx,
    spaceActivityRowSx,
} from "styles/activity-list";
import { spaceEmptyStateButtonSx } from "styles/buttons";
import {
    spaceAppBackgroundColor,
    spaceControlBackground,
    spaceControlBackgroundHover,
    spaceOnAccent,
    spaceSurfaceHover,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { groupSpaceActivities } from "utils/activity-sections";
import { isFriendRequestCanceledError } from "utils/friend-errors";
import { spacePostDeletedEvent } from "utils/post-events";
import { postQuoteErrorState } from "utils/post-quote";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

const NotificationAvatar: React.FC<{
    actor: SpaceNotification["actors"][number];
    spaceId: string;
}> = ({ actor, spaceId }) => {
    const [avatarURL, setAvatarURL] = React.useState<string | null | undefined>(
        actor.avatarUrl ?? undefined,
    );
    const hasAvatar = Boolean(actor.avatarObjectID && actor.avatarKeyVersion);
    React.useEffect(() => {
        if (actor.avatarUrl || !hasAvatar) return;
        let cancelled = false;
        void loadCurrentFriendAvatarURL(actor, spaceId)
            .catch((error: unknown) => {
                log.warn("Failed to load notification avatar", error);
                return null;
            })
            .then((url) => {
                if (!cancelled) setAvatarURL(url);
            });
        return () => {
            cancelled = true;
        };
    }, [actor, hasAvatar, spaceId]);
    return (
        <SpaceActivityAvatar
            avatarUrl={actor.avatarUrl || avatarURL}
            loading={hasAvatar && !actor.avatarUrl && avatarURL === undefined}
            size={44}
        />
    );
};

const actorName = (actor: SpaceNotification["actors"][number]) =>
    actor.fullName.trim() || actor.username;

const NotificationRow: React.FC<{
    group: SpaceNotification;
    spaceId: string;
    loadPostPreview: (postId: number) => Promise<SpacePostPreview | undefined>;
    onPostSomething: () => void;
    showPostSomething: boolean;
    isOpeningPost: boolean;
    onFriendRequest: (
        group: SpaceNotification,
        accept: boolean,
    ) => Promise<void>;
}> = ({
    group,
    spaceId,
    loadPostPreview,
    onFriendRequest,
    onPostSomething,
    showPostSomething,
    isOpeningPost,
}) => {
    const router = useSpaceRouter();
    const rowRef = React.useRef<HTMLDivElement>(null);
    const [preview, setPreview] = React.useState<SpacePostPreview>();
    const actor = group.actors[0]!;
    const otherCount = group.actorCount - 1;
    const isFriendRequest = group.kind == "friend_request";
    const isPostLike = group.kind == "post_like";
    const [isRequestPending, setIsRequestPending] = React.useState(false);
    const [requestError, setRequestError] = React.useState<string>();
    const actOnRequest = async (accept: boolean) => {
        setIsRequestPending(true);
        setRequestError(undefined);
        try {
            await onFriendRequest(group, accept);
        } catch (error) {
            log.error("Failed to update friend request", error);
            setRequestError(
                accept
                    ? "Couldn't accept request. Try again."
                    : "Couldn't dismiss request. Try again.",
            );
            setIsRequestPending(false);
        }
    };
    React.useEffect(() => {
        if (group.postId === undefined) return;
        const postId = group.postId;
        let cancelled = false;
        const observer = new IntersectionObserver(
            (entries) => {
                if (!entries.some((entry) => entry.isIntersecting)) return;
                observer.disconnect();
                void loadPostPreview(postId).then((post) => {
                    if (!cancelled) setPreview(post);
                });
            },
            { rootMargin: "200px 0px" },
        );
        if (rowRef.current) observer.observe(rowRef.current);
        return () => {
            cancelled = true;
            observer.disconnect();
        };
    }, [group.postId, loadPostPreview]);

    return (
        <Box component="li" sx={{ listStyle: "none" }}>
            <Box
                ref={rowRef}
                data-notification-id={group.id}
                sx={{
                    ...spaceActivityRowSx,
                    gridTemplateColumns:
                        isFriendRequest || showPostSomething
                            ? "44px minmax(0, 1fr) auto"
                            : "44px minmax(0, 1fr)",
                    "&:has(> [data-space-row-action]:hover), &:has(> [data-space-row-action]:active)":
                        { bgcolor: "transparent" },
                    ...(isFriendRequest && {
                        "&:hover, &:active": { bgcolor: "transparent" },
                    }),
                }}
            >
                <Box
                    component={isFriendRequest ? "div" : "button"}
                    type={isFriendRequest ? undefined : "button"}
                    aria-label={
                        isFriendRequest
                            ? undefined
                            : `Open ${actorName(actor)}'s profile`
                    }
                    onClick={
                        isFriendRequest
                            ? undefined
                            : () =>
                                  void router.push(
                                      spaceRoutes.friendPage,
                                      spaceRoutes.friend(actor.username),
                                  )
                    }
                    sx={{
                        appearance: "none",
                        bgcolor: "transparent",
                        border: 0,
                        borderRadius: "50%",
                        cursor: isFriendRequest ? "default" : "pointer",
                        display: "block",
                        height: 44,
                        p: 0,
                        width: 44,
                        "&:focus-visible": {
                            outline: "2px solid #08C225",
                            outlineOffset: 2,
                        },
                    }}
                >
                    <NotificationAvatar
                        key={`${actor.id}:${actor.avatarObjectID}:${actor.avatarKeyVersion}`}
                        actor={actor}
                        spaceId={spaceId}
                    />
                </Box>
                <Box
                    component={isFriendRequest ? "div" : "button"}
                    type={isFriendRequest ? undefined : "button"}
                    onClick={
                        isFriendRequest
                            ? undefined
                            : () => {
                                  if (isPostLike)
                                      void router.push(
                                          spaceRoutes.post(
                                              spaceId,
                                              group.postId!,
                                          ),
                                      );
                                  else
                                      void router.push(
                                          spaceRoutes.friendPage,
                                          spaceRoutes.friend(actor.username),
                                      );
                              }
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
                        gridTemplateColumns: isPostLike
                            ? "minmax(0, 1fr) 44px"
                            : "minmax(0, 1fr)",
                        minWidth: 0,
                        p: 0,
                        textAlign: "left",
                        width: "100%",
                        "&:focus-visible": {
                            borderRadius: "8px",
                            outline: "2px solid #08C225",
                            outlineOffset: 2,
                        },
                    }}
                >
                    <Box sx={{ minWidth: 0 }}>
                        <SpaceActivityIdentity
                            name={
                                <>
                                    {isFriendRequest
                                        ? `@${actor.username}`
                                        : actorName(actor)}
                                    {otherCount > 0 && (
                                        <>
                                            <Box
                                                component="span"
                                                sx={{ fontWeight: 400 }}
                                            >
                                                {" and "}
                                            </Box>
                                            {otherCount == 1
                                                ? actorName(group.actors[1]!)
                                                : `${otherCount} others`}
                                        </>
                                    )}
                                </>
                            }
                            createdAtMs={group.createdAtMs}
                        />
                        <Box sx={spaceActivityPreviewSx}>
                            {isPostLike
                                ? "Liked your post"
                                : isFriendRequest
                                  ? "Sent you a friend request"
                                  : group.kind == "poke"
                                    ? "Poked you"
                                    : "You're now friends"}
                        </Box>
                    </Box>
                    {isPostLike && (
                        <Box
                            sx={{ position: "relative", width: 44, height: 44 }}
                        >
                            <SpacePostPreviewThumbnail post={preview} />
                            <Box
                                component="span"
                                aria-hidden
                                sx={{
                                    alignItems: "center",
                                    bottom: -5,
                                    display: "inline-flex",
                                    height: 16,
                                    justifyContent: "center",
                                    pointerEvents: "none",
                                    position: "absolute",
                                    right: -5,
                                    width: 16,
                                    zIndex: 1,
                                }}
                            >
                                <HugeiconsIcon
                                    absoluteStrokeWidth
                                    color={spaceAppBackgroundColor}
                                    fill="#08C225"
                                    icon={FavouriteIcon}
                                    size={14}
                                    strokeWidth={1.25}
                                />
                            </Box>
                        </Box>
                    )}
                </Box>
                {showPostSomething && (
                    <Box
                        className="green-bg"
                        component="button"
                        type="button"
                        data-space-row-action
                        disabled={isOpeningPost}
                        onClick={onPostSomething}
                        sx={{
                            bgcolor: "#08C225",
                            border: 0,
                            borderRadius: "16px",
                            color: spaceOnAccent,
                            cursor: "pointer",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 12,
                            fontWeight: 700,
                            height: 36,
                            px: "12px",
                            whiteSpace: "nowrap",
                            "&:focus-visible": {
                                outline: "2px solid #08C225",
                                outlineOffset: 2,
                            },
                            "&:hover": { bgcolor: "#07A820" },
                        }}
                    >
                        Post a photo
                    </Box>
                )}
                {isFriendRequest && (
                    <Box
                        sx={{
                            display: "flex",
                            flexShrink: 0,
                            gap: "4px",
                            mr: "-6px",
                        }}
                    >
                        <Box
                            className="green-bg"
                            component="button"
                            type="button"
                            disabled={isRequestPending}
                            onClick={() => void actOnRequest(true)}
                            sx={{
                                bgcolor: "#08C225",
                                border: 0,
                                borderRadius: "12px",
                                color: spaceOnAccent,
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
                            aria-label={`Dismiss friend request from ${actor.username}`}
                            disabled={isRequestPending}
                            onClick={() => void actOnRequest(false)}
                            sx={{
                                alignItems: "center",
                                bgcolor: "transparent",
                                border: 0,
                                borderRadius: "50%",
                                color: spaceText,
                                cursor: "pointer",
                                display: "flex",
                                height: 34,
                                justifyContent: "center",
                                p: 0,
                                width: 34,
                                "&:hover": { bgcolor: spaceSurfaceHover },
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
                {requestError && (
                    <Box
                        role="alert"
                        sx={{
                            ...spaceActivityPreviewSx,
                            gridColumn: "2 / -1",
                            whiteSpace: "normal",
                        }}
                    >
                        {requestError}
                    </Box>
                )}
            </Box>
        </Box>
    );
};

const NotificationLoadingDots = () => (
    <Box
        role="status"
        aria-label="Loading more notifications"
        sx={{
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
            gap: "5px",
            height: 48,
        }}
    >
        {[0, 1, 2].map((index) => (
            <Box
                key={index}
                component="span"
                aria-hidden
                sx={{
                    width: 5,
                    height: 5,
                    borderRadius: "50%",
                    bgcolor: "#08C225",
                    animation: "spaceNotificationDot 1.2s ease-in-out infinite",
                    animationDelay: `${index * 0.15}s`,
                    "@keyframes spaceNotificationDot": {
                        "0%, 60%, 100%": {
                            opacity: 0.3,
                            transform: "translateY(0)",
                        },
                        "30%": { opacity: 1, transform: "translateY(-3px)" },
                    },
                    "@media (prefers-reduced-motion: reduce)": {
                        animation: "none",
                    },
                }}
            />
        ))}
    </Box>
);

const NotificationRetry = ({
    message,
    onRetry,
    fullPage = false,
}: {
    message: string;
    onRetry: () => void;
    fullPage?: boolean;
}) => (
    <Box
        role="alert"
        sx={{
            alignItems: "center",
            display: "flex",
            flexDirection: "column",
            gap: fullPage ? "22px" : "12px",
            justifyContent: "center",
            minHeight: fullPage
                ? "calc(var(--space-page-height, 100svh) - 90px - env(safe-area-inset-top) - env(safe-area-inset-bottom))"
                : undefined,
            px: 3,
            py: fullPage ? 0 : 2,
            textAlign: "center",
        }}
    >
        <Box
            component="p"
            sx={{
                color: spaceTextMuted,
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 14,
                fontWeight: 500,
                lineHeight: "20px",
                m: 0,
                maxWidth: 260,
            }}
        >
            {message}
        </Box>
        <Box
            component="button"
            type="button"
            onClick={onRetry}
            sx={{
                ...spaceEmptyStateButtonSx,
                bgcolor: spaceControlBackground,
                color: "#DEDEDE",
                fontSize: 13,
                minWidth: 116,
                px: "18px",
                "&:hover:not(:disabled)": {
                    bgcolor: spaceControlBackgroundHover,
                },
            }}
        >
            Retry
        </Box>
    </Box>
);

const NotificationsFeed: React.FC<{ spaceId: string; profileLink: string }> = ({
    spaceId,
    profileLink,
}) => {
    const { pendingPostPhotoFiles, setPendingPostPhotoFiles, postPublication } =
        useSpaceAppState();
    const postInputRef = React.useRef<HTMLInputElement>(null);
    const [latestPostCreatedAtMs, setLatestPostCreatedAtMs] = React.useState<
        number | null
    >();
    const [items, setItems] = React.useState<SpaceNotification[]>([]);
    const [cursor, setCursor] = React.useState<string>();
    const [newIDs, setNewIDs] = React.useState(new Set<string>());
    const [loading, setLoading] = React.useState<
        "refresh" | "more" | undefined
    >("refresh");
    const [loadError, setLoadError] = React.useState<"refresh" | "more">();
    const [failedReadIDs, setFailedReadIDs] = React.useState<string[]>([]);
    const [refresh, setRefresh] = React.useState(0);
    const [showFriendRequestCanceledToast, setShowFriendRequestCanceledToast] =
        React.useState(false);
    const [friendsCount, setFriendsCount] = React.useState<number>();
    const [isInviteSharing, setIsInviteSharing] = React.useState(false);
    const showInviteEmptyState = friendsCount == 0 && Boolean(profileLink);
    const emptyNotificationsCopy =
        friendsCount == 0
            ? "No notifications yet. Once you add friends, you'll see their likes and comments here."
            : "No notifications yet. You'll see likes, comments and friend requests here.";
    const handleFriendRequest = async (
        group: SpaceNotification,
        accept: boolean,
    ) => {
        try {
            if (accept) {
                await confirmCurrentFriendRequest(
                    spaceId,
                    group.friendRequestId!,
                );
                window.location.reload();
                return;
            } else
                await deleteCurrentFriendRequest(
                    spaceId,
                    group.friendRequestId!,
                );
        } catch (error) {
            if (!isFriendRequestCanceledError(error)) throw error;
            setShowFriendRequestCanceledToast(true);
        }
        setItems((current) => current.filter((item) => item.id != group.id));
        setRefresh((current) => current + 1);
    };
    React.useEffect(() => {
        if (postPublication?.phase == "posted")
            setRefresh((current) => current + 1);
    }, [postPublication?.phase]);
    const listRef = React.useRef<HTMLDivElement>(null);
    const postPreviews = React.useRef({
        generation: refresh,
        items: new Map<number, Promise<SpacePostPreview | undefined>>(),
    });
    const loadMoreRef = React.useRef<HTMLDivElement>(null);
    const loadingMore = React.useRef(false);
    const attemptedReadIDs = React.useRef(new Set<string>());
    const readIDs = React.useRef(new Set<string>());
    const loadedPageCount = React.useRef(1);
    const mounted = React.useRef(true);
    const loadGeneration = React.useRef(0);

    const loadPostPreview = React.useCallback(
        (postId: number) => {
            if (postPreviews.current.generation != refresh) {
                postPreviews.current = {
                    generation: refresh,
                    items: new Map(),
                };
            }
            let preview = postPreviews.current.items.get(postId);
            if (!preview) {
                const target = { spaceId, postId };
                preview = loadCurrentPostPreview(target, spaceId)
                    .then((post) => post ?? { ...target, isUnavailable: true })
                    .catch((error: unknown) => {
                        log.warn("Failed to load notification post", error);
                        return { ...target, ...postQuoteErrorState(error) };
                    });
                postPreviews.current.items.set(postId, preview);
            }
            return preview;
        },
        [spaceId, refresh],
    );

    const sections = React.useMemo(
        () =>
            groupSpaceActivities(items, (group) => ({
                createdAtMs: group.createdAtMs,
                isNew: newIDs.has(group.id),
            })).filter((section) => section.items.length > 0),
        [items, newIDs],
    );

    React.useEffect(() => {
        mounted.current = true;
        return () => {
            mounted.current = false;
        };
    }, []);

    React.useEffect(() => {
        loadGeneration.current++;
        loadingMore.current = false;
        readIDs.current.forEach((id) => attemptedReadIDs.current.delete(id));
        readIDs.current.clear();
        let cancelled = false;
        setLoading("refresh");
        setLoadError(undefined);
        const reloadPages = async () => {
            const page = await loadCurrentNotifications(spaceId);
            let pageCount = 1;
            while (
                !cancelled &&
                page.nextCursor &&
                pageCount < loadedPageCount.current
            ) {
                const nextPage = await loadCurrentNotifications(
                    spaceId,
                    page.nextCursor,
                );
                page.items.push(...nextPage.items);
                page.nextCursor = nextPage.nextCursor;
                pageCount++;
            }
            return {
                ...page,
                friendsCount:
                    page.items.length == 0
                        ? await loadCurrentSpaceFriendsCount(spaceId)
                        : undefined,
                items: [
                    ...new Map(
                        page.items.map((item) => [
                            `${item.kind}:${item.postId ?? item.id}`,
                            item,
                        ]),
                    ).values(),
                ],
                pageCount,
            };
        };
        void reloadPages()
            .then((page) => {
                if (cancelled) return;
                loadedPageCount.current = page.pageCount;
                setFriendsCount(page.friendsCount);
                setLatestPostCreatedAtMs(page.latestPostCreatedAtMs);
                setItems(
                    page.items.map((item) => ({
                        ...item,
                        read:
                            item.read ||
                            item.notificationIds.every((id) =>
                                readIDs.current.has(id),
                            ),
                    })),
                );
                setNewIDs(
                    (current) =>
                        new Set([
                            ...current,
                            ...page.items
                                .filter((item) => !item.read)
                                .map((item) => item.id),
                        ]),
                );
                setCursor(page.nextCursor);
                setFailedReadIDs((current) =>
                    current.filter((id) =>
                        page.items.some(
                            (item) =>
                                item.notificationIds.includes(id) && !item.read,
                        ),
                    ),
                );
            })
            .catch((error: unknown) => {
                log.error("Failed to load notifications", error);
                if (!cancelled) setLoadError("refresh");
            })
            .finally(() => {
                if (!cancelled) setLoading(undefined);
            });
        return () => {
            cancelled = true;
        };
    }, [spaceId, refresh]);

    React.useEffect(() => {
        const reload = () => {
            if (document.visibilityState == "visible")
                setRefresh((value) => value + 1);
        };
        window.addEventListener("focus", reload);
        window.addEventListener("online", reload);
        window.addEventListener(spacePostDeletedEvent, reload);
        document.addEventListener("visibilitychange", reload);
        return () => {
            window.removeEventListener("focus", reload);
            window.removeEventListener("online", reload);
            window.removeEventListener(spacePostDeletedEvent, reload);
            document.removeEventListener("visibilitychange", reload);
        };
    }, []);

    const markRead = React.useCallback(
        async (ids: string[]) => {
            ids.forEach((id) => attemptedReadIDs.current.add(id));
            try {
                for (let offset = 0; offset < ids.length; offset += 100) {
                    await markCurrentNotificationItemsRead(
                        spaceId,
                        ids.slice(offset, offset + 100),
                    );
                }
                if (!mounted.current) return;
                ids.forEach((id) => readIDs.current.add(id));
                setItems((current) =>
                    current.map((item) =>
                        item.notificationIds.every((id) =>
                            readIDs.current.has(id),
                        )
                            ? { ...item, read: true }
                            : item,
                    ),
                );
                setFailedReadIDs((current) =>
                    current.filter((id) => !ids.includes(id)),
                );
            } catch (error) {
                log.error("Failed to mark notifications read", error);
                if (mounted.current)
                    setFailedReadIDs((current) => [
                        ...new Set([...current, ...ids]),
                    ]);
            }
        },
        [spaceId],
    );

    React.useEffect(() => {
        const unreadGroups = new Map(
            items
                .filter((item) => !item.read)
                .map((item) => [item.id, item.notificationIds]),
        );
        const observer = new IntersectionObserver(
            (entries) => {
                if (document.visibilityState != "visible") return;
                const ids = entries
                    .filter(
                        (entry) =>
                            entry.isIntersecting &&
                            entry.intersectionRatio >= 0.5,
                    )
                    .map(
                        (entry) =>
                            (entry.target as HTMLElement).dataset
                                .notificationId!,
                    )
                    .flatMap((id) => unreadGroups.get(id) ?? [])
                    .filter((id) => !attemptedReadIDs.current.has(id));
                if (ids.length > 0) void markRead(ids);
            },
            { threshold: 0.5 },
        );
        const observeVisibleRows = () => {
            observer.disconnect();
            if (document.visibilityState != "visible") return;
            listRef.current
                ?.querySelectorAll("[data-notification-id]")
                .forEach((row) => observer.observe(row));
        };
        observeVisibleRows();
        document.addEventListener("visibilitychange", observeVisibleRows);
        return () => {
            observer.disconnect();
            document.removeEventListener(
                "visibilitychange",
                observeVisibleRows,
            );
        };
    }, [items, markRead]);

    const loadMore = React.useCallback(async () => {
        if (!cursor || loading || loadingMore.current) return;
        loadingMore.current = true;
        const generation = loadGeneration.current;
        setLoading(window.scrollY > 0 ? "more" : "refresh");
        setLoadError(undefined);
        try {
            const page = await loadCurrentNotifications(spaceId, cursor);
            if (!mounted.current || generation != loadGeneration.current)
                return;
            loadedPageCount.current++;
            setItems((current) => [
                ...current,
                ...page.items.filter(
                    (item) =>
                        !current.some(
                            (existing) =>
                                existing.kind == item.kind &&
                                (existing.postId ?? existing.id) ==
                                    (item.postId ?? item.id),
                        ),
                ),
            ]);
            setNewIDs(
                (current) =>
                    new Set([
                        ...current,
                        ...page.items
                            .filter((item) => !item.read)
                            .map((item) => item.id),
                    ]),
            );
            setCursor(page.nextCursor);
        } catch (error) {
            log.error("Failed to load more notifications", error);
            if (mounted.current && generation == loadGeneration.current)
                setLoadError("more");
        } finally {
            if (mounted.current && generation == loadGeneration.current) {
                loadingMore.current = false;
                setLoading(undefined);
            }
        }
    }, [cursor, loading, spaceId]);

    React.useEffect(() => {
        const sentinel = loadMoreRef.current;
        if (!sentinel || !cursor || loading || loadError) return;
        const observer = new IntersectionObserver(
            (entries) => {
                if (entries.some((entry) => entry.isIntersecting))
                    void loadMore();
            },
            { rootMargin: "300px 0px" },
        );
        observer.observe(sentinel);
        return () => observer.disconnect();
    }, [cursor, loading, loadError, loadMore]);

    return (
        <>
            <SpacePostPhotoInput
                inputRef={postInputRef}
                onSelect={setPendingPostPhotoFiles}
            />
            {showFriendRequestCanceledToast && (
                <SpaceFriendRequestCanceledToast
                    onClose={() => setShowFriendRequestCanceledToast(false)}
                />
            )}
            {failedReadIDs.length > 0 && (
                <NotificationRetry
                    message="Couldn't mark notifications as read."
                    onRetry={() => void markRead(failedReadIDs)}
                />
            )}
            <Box ref={listRef}>
                {sections.map((section) => (
                    <SpaceActivitySection
                        key={section.title}
                        title={section.title}
                    >
                        {section.items.map((group) => (
                            <NotificationRow
                                key={`${group.kind}:${group.postId ?? group.id}`}
                                group={group}
                                spaceId={spaceId}
                                loadPostPreview={loadPostPreview}
                                onFriendRequest={handleFriendRequest}
                                onPostSomething={() =>
                                    postInputRef.current?.click()
                                }
                                isOpeningPost={Boolean(pendingPostPhotoFiles)}
                                showPostSomething={
                                    group.kind == "poke" &&
                                    latestPostCreatedAtMs !== undefined &&
                                    (latestPostCreatedAtMs === null ||
                                        latestPostCreatedAtMs <
                                            group.createdAtMs)
                                }
                            />
                        ))}
                    </SpaceActivitySection>
                ))}
            </Box>
            {!loading && !loadError && items.length == 0 && (
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
                            color: spaceTextMuted,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 500,
                            lineHeight: "20px",
                            m: 0,
                            maxWidth: 260,
                        }}
                    >
                        {emptyNotificationsCopy}
                    </Box>
                    {showInviteEmptyState && (
                        <SpaceShareInviteButton
                            profileLink={profileLink}
                            sharing={isInviteSharing}
                            onShareError={(error) =>
                                log.error("Failed to share space invite", error)
                            }
                            onSharingChange={setIsInviteSharing}
                        />
                    )}
                </Box>
            )}
            {loadError && (
                <NotificationRetry
                    fullPage={items.length == 0}
                    message={
                        loadError == "more"
                            ? "Couldn't load more notifications."
                            : items.length > 0
                              ? "Couldn't refresh notifications."
                              : "Couldn't load notifications."
                    }
                    onRetry={() =>
                        loadError == "more"
                            ? void loadMore()
                            : setRefresh((value) => value + 1)
                    }
                />
            )}
            {cursor && (
                <Box ref={loadMoreRef} sx={{ minHeight: 48 }}>
                    {loading == "more" && <NotificationLoadingDots />}
                </Box>
            )}
        </>
    );
};

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const { profile, profileLoadStatus, profileLoadError } = useSpaceAppState();
    React.useEffect(() => {
        if (profileLoadStatus == "ready" && !profile)
            void router.replace(spaceRoutes.onboarding);
    }, [profile, profileLoadStatus, router]);

    if (profileLoadStatus != "ready" || !profile?.spaceId) {
        return (
            <SpaceRouteFallback
                background={spaceAppBackgroundColor}
                message={profileLoadError}
            />
        );
    }

    return (
        <>
            <SpacePageMeta themeColor={spaceAppBackgroundColor} />
            <SpaceSkipLink />
            <Box
                sx={{
                    bgcolor: spaceAppBackgroundColor,
                    color: spaceText,
                    minHeight: "var(--space-page-height, 100dvh)",
                    pt: "env(safe-area-inset-top)",
                    pb: "env(safe-area-inset-bottom)",
                }}
            >
                <Box
                    sx={{
                        width: "100%",
                        mx: "auto",
                        minHeight:
                            "calc(var(--space-page-height, 100svh) - env(safe-area-inset-top) - env(safe-area-inset-bottom))",
                        position: "relative",
                        "@media (min-width: 600px)": { maxWidth: 390 },
                    }}
                >
                    <Box
                        component="header"
                        sx={{
                            display: "grid",
                            alignItems: "center",
                            gridTemplateColumns: "44px 1fr 44px",
                            height: 56,
                            px: 2,
                        }}
                    >
                        <Box
                            component="button"
                            type="button"
                            aria-label="Back"
                            onClick={() => void router.back(spaceRoutes.home)}
                            sx={{
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "flex-start",
                                width: 44,
                                height: 44,
                                border: 0,
                                borderRadius: "50%",
                                bgcolor: "transparent",
                                ml: "-2px",
                                p: 0,
                                color: spaceText,
                                cursor: "pointer",
                                "&:focus-visible": {
                                    outline: "2px solid #08C225",
                                },
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
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 18,
                                fontWeight: 700,
                                lineHeight: "24px",
                                justifySelf: "center",
                                m: 0,
                            }}
                        >
                            Notifications
                        </Box>
                    </Box>
                    <Box
                        component="main"
                        id="space-main-content"
                        tabIndex={-1}
                        sx={spaceActivityListSx}
                    >
                        <NotificationsFeed
                            key={profile.spaceId}
                            spaceId={profile.spaceId}
                            profileLink={spaceInviteURL({
                                spaceUsername: profile.username,
                            })}
                        />
                    </Box>
                </Box>
            </Box>
        </>
    );
};

export default Page;
