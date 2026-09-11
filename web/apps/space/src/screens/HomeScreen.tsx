import { Cancel01Icon, UserAdd02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { SpaceActionFeedbackIcon } from "components/ActionFeedback";
import { SpaceActionToast } from "components/ActionToast";
import { SpaceAddFriendButton } from "components/AddFriendButton";
import { SpaceAddFriendTile } from "components/AddFriendTile";
import { SpaceAvatarImage } from "components/AvatarImage";
import {
    SpaceFileViewer,
    SpaceViewerPostBackdrop,
    type SpaceViewerPhoto,
    type SpaceViewerPostActionMode,
} from "components/FileViewer";
import { FriendQuickActionsDialog } from "components/FriendQuickActionsDialog";
import { SpaceHomeHeader, spaceHomeHeaderHeight } from "components/HomeHeader";
import { SpaceNewPostButton } from "components/NewPostButton";
import {
    SpacePostBadge,
    SpacePostUnreadBadge,
} from "components/PostUnreadBadge";
import { SpacePWAInstallPrompt } from "components/PWAInstallPrompt";
import { SpaceLoadingSpinner } from "components/RouteFallback";
import type { FriendProfile } from "data/friends";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React, { useState } from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";
import { markSpaceHomePostRead } from "services/home-posts";
import {
    isSpaceContentError,
    type SpaceFriendRequest,
    type SpacePost,
    type SpacePostAssetURLLoader,
} from "services/space";
import {
    spaceAppBackground,
    spaceOnAccent,
    spaceSurface,
    spaceSurfaceHover,
    spaceText,
} from "styles/colors";
import {
    spacePostTileRadius,
    spaceTileAvatarSize,
    spaceTileCircleInset,
    spaceTileCornerStyles,
    spaceTileInnerRadius,
} from "styles/tiles";
import { firstNameFrom } from "utils/display";
import {
    homeTileGap,
    homeTileLayout,
    maximumHomeTileCount,
    minimumHomeTileCanvasHeight,
    type HomeTilePlacement,
} from "utils/home-tile-layout";
import { createLoadedLocalPostPhoto } from "utils/local-post-photo";
import {
    canPreviewSpaceImageFile,
    spaceDefaultCoverImagePath,
    spacePostImageErrorMessage,
    spacePostImageInputAccept,
    spacePostPreviewImageForFile,
    type SpaceDraftPostImage,
} from "utils/post-image";
import { thumbHashDataURLFromBase64 } from "utils/thumbhash";

const green = "#08C225";
const textBase = spaceText;
const avatarFallbackColor = spaceSurfaceHover;
const avatarFallbackTextColor = "#FFFFFF";
const mediaPlaceholderColor = spaceSurface;
const tileBadgeBackground = "rgba(0, 0, 0, 0.22)";
const tileBadgeText = "rgba(255, 255, 255, 0.9)";
const homeHorizontalPadding = "16px";
const postTileMediaLoadRootMargin = "640px 0px";
interface HomeScreenProps {
    latestPosts: SpacePost[];
    unreadPosts: SpacePost[];
    friendRequestSentToastName?: string;
    friendRequests: SpaceFriendRequest[];
    friends: FriendProfile[];
    hasUnreadMessages?: boolean;
    isLatestPostsLoading?: boolean;
    isFriendsLoading?: boolean;
    isFriendRequestsLoading?: boolean;
    isHomeCacheLoading?: boolean;
    showInstallPrompt?: boolean;
    onCreatePost?: (
        image: SpaceDraftPostImage,
        caption: string,
    ) => Promise<void>;
    onLoadFriendAvatar?: (friend: FriendProfile) => Promise<string | null>;
    onLoadPostImage?: SpacePostAssetURLLoader;
    onFriendRequestSentToastClose?: () => void;
    onAcceptFriendRequest?: (requestID: number) => Promise<void>;
    onAddFriend: () => void;
    onDiscardFriendRequest?: (requestID: number) => Promise<void>;
    onOpenFriend?: (
        friendID: string,
        username?: string,
        section?: "latest",
    ) => void;
    onOpenFriendRequests?: () => void;
    onOpenMessages?: () => void;
    onMessageFriend: (friend: FriendProfile) => void;
    onPokeFriend: (friend: FriendProfile) => Promise<void>;
    onOpenProfile?: () => void;
    onReplyToPost?: (
        postSpaceId: string,
        postId: number,
        text: string,
    ) => Promise<void>;
    onSetPostLiked?: (postId: number, liked: boolean) => Promise<void>;
    profile: SetupProfile | null;
    viewerSpaceId?: string;
}

interface DecodedImageState {
    failed?: boolean;
    height?: number;
    ready: boolean;
    src?: string | null;
    width?: number;
}

interface PostTileCanvasSize {
    height: number;
    width: number;
}

interface SelectedHomeViewer {
    avatarUrl?: string | null;
    draftFile?: File;
    draftImageError?: string;
    focusReplyOnOpen?: boolean;
    friend?: FriendProfile;
    isDraftImagePreviewPending?: boolean;
    localObjectUrl?: string;
    photo: SpaceViewerPhoto;
    postIndex?: number;
    postActionMode?: SpaceViewerPostActionMode;
    posts?: SpacePost[];
    sessionId?: symbol;
}

interface AddedFriendToastProps {
    message: string;
    onClose?: () => void;
}

const viewerPhotoForPost = (
    post: SpacePost,
    friend: FriendProfile,
    avatarUrl: string | null | undefined,
    imageUrl: string,
): SpaceViewerPhoto => {
    const displayName = friend.fullName.trim() || friend.username.trim();
    return {
        alt: `${displayName} post`,
        avatarUrl,
        caption: post.caption,
        friendID: post.friendID,
        height: post.height,
        imageUrl,
        name: displayName,
        postId: post.postId,
        spaceId: post.spaceId,
        timestampMs: post.timestampMs,
        username: friend.username,
        viewerLiked: post.viewerLiked,
        width: post.width,
    };
};

const postImageCacheKey = (item: SpacePost) =>
    [
        item.postId,
        item.imageAsset?.spaceId ?? item.spaceId,
        item.imageAsset?.objectKey ?? item.imageUrl ?? "",
    ].join(":");

const friendAvatarCacheKey = (friend: FriendProfile) =>
    [
        friend.spaceId ?? friend.id,
        friend.avatarKeyVersion ?? "",
        friend.avatarObjectID ?? "",
        friend.avatarUpdatedAt ?? "",
        friend.avatarSize ?? "",
    ].join(":");

const useDecodedImage = (
    src?: string | null,
    keepPreviousUntilReady = false,
): DecodedImageState => {
    const [state, setState] = useState<DecodedImageState>({ ready: !src, src });

    React.useEffect(() => {
        if (!src) {
            setState({ ready: true, src });
            return;
        }

        let cancelled = false;
        const image = new Image();

        const finish = () => {
            if (cancelled) return;

            setState({
                height: image.naturalHeight || undefined,
                ready: true,
                src,
                width: image.naturalWidth || undefined,
            });
        };
        const fail = () => {
            if (cancelled) return;
            setState({ failed: true, ready: true, src });
        };
        const decodeLoadedImage = () => {
            if (typeof image.decode != "function") {
                finish();
                return;
            }

            void image.decode().then(finish, fail);
        };

        setState((currentState) =>
            keepPreviousUntilReady && currentState.ready && currentState.src
                ? currentState
                : { ready: false, src },
        );
        image.addEventListener("load", decodeLoadedImage, { once: true });
        image.addEventListener("error", fail, { once: true });
        image.src = src;
        if (image.complete) {
            if (image.naturalWidth) decodeLoadedImage();
            else fail();
        }

        return () => {
            cancelled = true;
            image.removeEventListener("load", decodeLoadedImage);
            image.removeEventListener("error", fail);
        };
    }, [keepPreviousUntilReady, src]);

    if (state.src == src) return state;
    if (keepPreviousUntilReady && src && state.ready && state.src) return state;
    return { ready: !src, src };
};

interface FriendPostTileProps {
    avatarUrl?: string | null;
    friend: FriendProfile;
    imageUrl?: string;
    isAvatarPending: boolean;
    isLoading: boolean;
    isRead: boolean;
    friendRequestDirection?: SpaceFriendRequest["direction"];
    isUnavailable: boolean;
    onLoadAvatar?: () => Promise<string | null | undefined>;
    onLoadImage?: () => Promise<string | undefined>;
    onAcceptFriendRequest?: () => Promise<void>;
    onDiscardFriendRequest?: () => Promise<void>;
    onOpenFriend?: HomeScreenProps["onOpenFriend"];
    onOpenAvatar?: (anchorRect: DOMRect) => void;
    onOpenFriendRequest?: () => void;
    onOpenPosts: (
        friend: FriendProfile,
        posts: SpacePost[],
        photo: SpaceViewerPhoto,
    ) => void;
    isNineTileLayout?: boolean;
    isTwoTileLayout?: boolean;
    placement: HomeTilePlacement;
    posts: SpacePost[];
    showFriendRequestDetails?: boolean;
}

export const FriendPostTile: React.FC<FriendPostTileProps> = ({
    avatarUrl,
    friend,
    friendRequestDirection,
    imageUrl,
    isAvatarPending,
    isLoading,
    isRead,
    isUnavailable,
    onAcceptFriendRequest,
    onDiscardFriendRequest,
    onLoadAvatar,
    onLoadImage,
    onOpenFriend,
    onOpenAvatar,
    onOpenFriendRequest,
    onOpenPosts,
    isNineTileLayout = false,
    isTwoTileLayout = false,
    placement,
    posts,
    showFriendRequestDetails = false,
}) => {
    const rootRef = React.useRef<HTMLLIElement | null>(null);
    const [shouldLoadMedia, setShouldLoadMedia] = useState(Boolean(imageUrl));
    const [friendRequestAction, setFriendRequestAction] = useState<
        "accept" | "discard" | null
    >(null);
    const decodedPhoto = useDecodedImage(imageUrl, true);
    const decodedAvatar = useDecodedImage(
        avatarUrl ?? friend.avatarUrl ?? null,
        true,
    );
    const post = posts[0];
    const isRequestPending = Boolean(friendRequestDirection);
    const isFriendRequestActionBusy = friendRequestAction != null;
    const canOpenFriendRequest =
        friendRequestDirection == "sent" && Boolean(onOpenFriendRequest);
    const thumbHashDataURL = React.useMemo(
        () => thumbHashDataURLFromBase64(post?.thumbHash),
        [post?.thumbHash],
    );
    const displayName = friend.fullName.trim() || friend.username.trim();
    const firstName = firstNameFrom(displayName);
    const initial = firstName.charAt(0).toLocaleUpperCase();
    const postUnavailable = isUnavailable || decodedPhoto.failed;
    const displayImageUrl =
        (decodedPhoto.failed
            ? undefined
            : decodedPhoto.ready
              ? decodedPhoto.src
              : imageUrl) ?? undefined;
    const displayAvatarUrl =
        decodedAvatar.ready && !decodedAvatar.failed
            ? (decodedAvatar.src ?? null)
            : null;
    const isPhotoReady = Boolean(displayImageUrl) && decodedPhoto.ready;
    const canOpenPost = Boolean(post) && !postUnavailable && isPhotoReady;
    const isTileDisabled =
        isLoading ||
        isFriendRequestActionBusy ||
        (isRequestPending && !canOpenFriendRequest) ||
        Boolean(post && !isRead && !postUnavailable && !isPhotoReady);
    const tileSize = Math.min(placement.width, placement.height);
    const tileRadius = Math.min(spacePostTileRadius, tileSize * 0.2);
    const avatarSize = spaceTileAvatarSize(placement, isNineTileLayout);
    const requestActionSize = showFriendRequestDetails
        ? Math.min(44, Math.max(40, tileSize * 0.13))
        : Math.min(40, Math.max(26, tileSize * 0.14));
    const requestUsernameTextSize = isTwoTileLayout
        ? 14
        : showFriendRequestDetails
          ? Math.min(18, Math.max(15, tileSize * 0.05))
          : 11;
    const requestActionTextSize = isTwoTileLayout
        ? 12
        : showFriendRequestDetails
          ? 13
          : Math.min(13, Math.max(10, tileSize * 0.04));
    const requestCloseIconSize = 14;
    const requestButtonGap = 6;
    const stackRequestActions = placement.height >= 176;

    const hasMediaToLoad =
        isAvatarPending || Boolean(post && !postUnavailable && !imageUrl);

    React.useEffect(() => {
        if (!hasMediaToLoad || shouldLoadMedia) return;
        const element = rootRef.current;
        if (!element) return;
        if (
            typeof window == "undefined" ||
            !("IntersectionObserver" in window)
        ) {
            setShouldLoadMedia(true);
            return;
        }

        const observer = new IntersectionObserver(
            (entries) => {
                if (entries.some((entry) => entry.isIntersecting)) {
                    setShouldLoadMedia(true);
                    observer.disconnect();
                }
            },
            { rootMargin: postTileMediaLoadRootMargin },
        );
        observer.observe(element);
        return () => observer.disconnect();
    }, [hasMediaToLoad, shouldLoadMedia]);

    React.useEffect(() => {
        if (!shouldLoadMedia) return;
        if (!imageUrl && !postUnavailable) void onLoadImage?.();
        if (isAvatarPending) void onLoadAvatar?.();
    }, [
        imageUrl,
        isAvatarPending,
        onLoadAvatar,
        onLoadImage,
        postUnavailable,
        shouldLoadMedia,
    ]);

    const updateFriendRequest = (
        action: "accept" | "discard",
        handler?: () => Promise<void>,
    ) => {
        if (isFriendRequestActionBusy || !handler) return;
        setFriendRequestAction(action);
        void handler()
            .catch((error: unknown) =>
                log.error("Failed to update friend request", error),
            )
            .finally(() => setFriendRequestAction(null));
    };

    const openTile = () => {
        if (isRequestPending) {
            if (friendRequestDirection == "sent") onOpenFriendRequest?.();
            return;
        }
        if (!post || postUnavailable) {
            onOpenFriend?.(friend.id, friend.username);
            return;
        }
        if (isRead) {
            onOpenFriend?.(friend.id, friend.username, "latest");
            return;
        }
        if (!canOpenPost || !displayImageUrl) return;

        onOpenPosts(friend, posts, {
            alt: `${displayName} post`,
            avatarUrl: displayAvatarUrl,
            caption: post.caption,
            friendID: post.friendID,
            height: decodedPhoto.height ?? post.height,
            imageUrl: displayImageUrl,
            name: displayName,
            postId: post.postId,
            spaceId: post.spaceId,
            timestampMs: post.timestampMs,
            username: friend.username,
            viewerLiked: post.viewerLiked,
            width: decodedPhoto.width ?? post.width,
        });
    };

    const openAvatar = (event: React.MouseEvent<HTMLButtonElement>) => {
        if (isRequestPending) {
            onOpenFriendRequest?.();
            return;
        }
        onOpenAvatar?.(event.currentTarget.getBoundingClientRect());
    };
    const canOpenAvatar = isRequestPending
        ? canOpenFriendRequest
        : Boolean(onOpenAvatar);

    return (
        <Box
            ref={rootRef}
            component="li"
            sx={{
                ...spaceTileCornerStyles(tileRadius),
                listStyle: "none",
                minWidth: 0,
                position: "absolute",
                transition:
                    "left 420ms ease, top 420ms ease, width 420ms ease, height 420ms ease",
                width: placement.width,
                height: placement.height,
                left: placement.x,
                top: placement.y,
                "@media (prefers-reduced-motion: reduce)": {
                    transition: "none",
                },
            }}
        >
            <Box
                component="button"
                type="button"
                aria-label={
                    isLoading
                        ? `Loading ${firstName}'s latest post`
                        : friendRequestDirection == "received"
                          ? `Review friend request from ${firstName}`
                          : friendRequestDirection == "sent"
                            ? `Manage friend request sent to ${firstName}`
                            : post && !postUnavailable
                              ? posts.length > 1
                                  ? `Open ${posts.length} new posts from ${firstName}`
                                  : isRead
                                    ? `Open ${firstName}'s latest post`
                                    : `Open ${firstName}'s new post`
                              : `Open ${firstName}'s profile`
                }
                disabled={isTileDisabled}
                onClick={openTile}
                sx={{
                    alignItems: "center",
                    appearance: "none",
                    bgcolor:
                        !isLoading && (!post || postUnavailable)
                            ? mediaPlaceholderColor
                            : "transparent",
                    backgroundImage:
                        !isLoading && !post
                            ? `linear-gradient(rgba(0, 0, 0, 0.3), rgba(0, 0, 0, 0.3)), url("${spaceDefaultCoverImagePath}")`
                            : undefined,
                    backgroundPosition: "center",
                    backgroundSize: "cover",
                    border: 0,
                    borderRadius: "inherit",
                    color: textBase,
                    cursor: isTileDisabled ? "default" : "pointer",
                    display: "flex",
                    fontFamily: '"Inter Variable", Inter, sans-serif',
                    height: "100%",
                    justifyContent: "center",
                    overflow: "hidden",
                    p: 0,
                    position: "relative",
                    width: "100%",
                    zIndex: 1,
                }}
            >
                {post && !postUnavailable && (
                    <>
                        {thumbHashDataURL && (
                            <Box
                                component="img"
                                alt=""
                                aria-hidden
                                src={thumbHashDataURL}
                                sx={{
                                    filter: "blur(14px)",
                                    height: "100%",
                                    inset: 0,
                                    objectFit: "cover",
                                    position: "absolute",
                                    transform: "scale(1.08)",
                                    width: "100%",
                                }}
                            />
                        )}
                        {isPhotoReady && (
                            <Box
                                component="img"
                                alt={`${displayName} post`}
                                src={displayImageUrl}
                                sx={{
                                    animation: isRead
                                        ? "none"
                                        : "spaceNewPostImageFade 520ms cubic-bezier(0.16, 1, 0.3, 1) both",
                                    height: "100%",
                                    inset: 0,
                                    objectFit: "cover",
                                    position: "absolute",
                                    width: "100%",
                                    "@keyframes spaceNewPostImageFade": {
                                        from: { opacity: 0 },
                                        to: { opacity: 1 },
                                    },
                                    "@media (prefers-reduced-motion: reduce)": {
                                        animation: "none",
                                    },
                                }}
                            />
                        )}
                    </>
                )}
                {!isLoading &&
                    !post &&
                    friendRequestDirection != "received" &&
                    !(
                        friendRequestDirection == "sent" &&
                        showFriendRequestDetails
                    ) && (
                        <SpacePostBadge
                            backgroundColor={tileBadgeBackground}
                            color={tileBadgeText}
                            placement="center"
                        >
                            {friendRequestDirection == "sent"
                                ? "Pending"
                                : "No posts"}
                        </SpacePostBadge>
                    )}
                {!isLoading &&
                    friendRequestDirection == "sent" &&
                    showFriendRequestDetails && (
                        <Box
                            aria-hidden
                            component="span"
                            title={`@${friend.username}’s posts will appear here`}
                            sx={{
                                bgcolor: tileBadgeBackground,
                                borderRadius: "999px",
                                boxSizing: "border-box",
                                color: tileBadgeText,
                                display: "inline-flex",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 11,
                                fontWeight: 600,
                                left: "50%",
                                lineHeight: "17px",
                                maxWidth:
                                    "calc(100% - 2 * var(--space-tile-padding))",
                                px: "12px",
                                py: "7px",
                                position: "absolute",
                                textAlign: "center",
                                top: "50%",
                                transform: "translate(-50%, -50%)",
                                whiteSpace: "nowrap",
                                width: "fit-content",
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
                                @{friend.username}
                            </Box>
                            <Box component="span" sx={{ flexShrink: 0 }}>
                                ’s posts will appear here
                            </Box>
                        </Box>
                    )}
                {!isLoading && postUnavailable && (
                    <SpacePostBadge
                        backgroundColor={tileBadgeBackground}
                        color={tileBadgeText}
                    >
                        Unavailable
                    </SpacePostBadge>
                )}
                {!isLoading && post && !postUnavailable && !isRead && (
                    <SpacePostUnreadBadge count={posts.length} />
                )}
            </Box>
            {friendRequestDirection != "received" &&
                !isAvatarPending &&
                decodedAvatar.ready && (
                    <Box
                        component="button"
                        type="button"
                        aria-label={
                            friendRequestDirection == "sent"
                                ? `Manage friend request sent to ${firstName}`
                                : `Open actions for ${displayName}`
                        }
                        aria-haspopup={isRequestPending ? undefined : "dialog"}
                        disabled={!canOpenAvatar || isFriendRequestActionBusy}
                        onClick={openAvatar}
                        sx={{
                            appearance: "none",
                            backgroundClip: "padding-box",
                            bgcolor: spaceAppBackground,
                            border: "3px solid rgba(28, 28, 30, 0.75)",
                            borderRadius: "50%",
                            bottom: spaceTileCircleInset(avatarSize),
                            boxSizing: "border-box",
                            cursor: canOpenAvatar ? "pointer" : "default",
                            height: avatarSize,
                            left: spaceTileCircleInset(avatarSize),
                            overflow: "hidden",
                            p: 0,
                            position: "absolute",
                            width: avatarSize,
                            zIndex: 2,
                        }}
                    >
                        {displayAvatarUrl ? (
                            <SpaceAvatarImage
                                aria-hidden
                                src={displayAvatarUrl}
                            />
                        ) : (
                            <Box
                                aria-hidden
                                sx={{
                                    alignItems: "center",
                                    bgcolor: avatarFallbackColor,
                                    color: avatarFallbackTextColor,
                                    display: "flex",
                                    fontSize: 14,
                                    fontWeight: 700,
                                    height: "100%",
                                    justifyContent: "center",
                                    width: "100%",
                                }}
                            >
                                {initial}
                            </Box>
                        )}
                    </Box>
                )}
            {friendRequestDirection == "received" && (
                <Box
                    sx={{
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: `${requestButtonGap}px`,
                        height: "100%",
                        inset: 0,
                        p: "var(--space-tile-padding)",
                        pt: showFriendRequestDetails
                            ? "var(--space-tile-padding)"
                            : `calc(var(--space-tile-padding) + ${requestActionSize + requestButtonGap}px)`,
                        pointerEvents: "none",
                        position: "absolute",
                        width: "100%",
                        zIndex: 2,
                    }}
                >
                    <Box
                        sx={{
                            alignItems: "center",
                            display: "flex",
                            flex: 1,
                            flexDirection: "column",
                            gap: "8px",
                            justifyContent: "center",
                            minHeight: 0,
                        }}
                    >
                        <Box
                            component="span"
                            aria-hidden
                            title={`@${friend.username}`}
                            sx={{
                                bgcolor: tileBadgeBackground,
                                borderRadius: "999px",
                                boxSizing: "border-box",
                                color: tileBadgeText,
                                display: "block",
                                fontFamily: '"Nunito", sans-serif',
                                fontSize: requestUsernameTextSize,
                                fontWeight: 800,
                                height: showFriendRequestDetails
                                    ? undefined
                                    : 24,
                                lineHeight: showFriendRequestDetails
                                    ? "20px"
                                    : "24px",
                                flexShrink: 0,
                                maxWidth: "100%",
                                overflow: "hidden",
                                px: showFriendRequestDetails ? "12px" : "8px",
                                py: showFriendRequestDetails ? "6px" : 0,
                                textOverflow: "ellipsis",
                                textAlign: "center",
                                whiteSpace: "nowrap",
                            }}
                        >
                            @{friend.username}
                        </Box>
                        {showFriendRequestDetails && !isTwoTileLayout && (
                            <Box
                                component="span"
                                aria-hidden
                                sx={{
                                    color: "rgba(255, 255, 255, 0.75)",
                                    fontSize: 13,
                                    fontWeight: 500,
                                    lineHeight: 1.4,
                                    textAlign: "center",
                                }}
                            >
                                sent you a friend request
                            </Box>
                        )}
                    </Box>
                    <Box
                        sx={{
                            display: "flex",
                            flexDirection:
                                showFriendRequestDetails && !stackRequestActions
                                    ? "row"
                                    : "column",
                            flexShrink: 0,
                            gap: `${requestButtonGap}px`,
                            pointerEvents: "auto",
                        }}
                    >
                        <Box
                            className="green-bg"
                            component="button"
                            type="button"
                            aria-label={`Accept friend request from ${displayName}`}
                            disabled={
                                isFriendRequestActionBusy ||
                                !onAcceptFriendRequest
                            }
                            onClick={() =>
                                updateFriendRequest(
                                    "accept",
                                    onAcceptFriendRequest,
                                )
                            }
                            sx={{
                                alignItems: "center",
                                bgcolor: green,
                                border: 0,
                                borderRadius: spaceTileInnerRadius,
                                boxSizing: "border-box",
                                color: spaceOnAccent,
                                cursor: isFriendRequestActionBusy
                                    ? "default"
                                    : "pointer",
                                display: "flex",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: requestActionTextSize,
                                fontWeight: 700,
                                height: requestActionSize,
                                justifyContent: "center",
                                p: 0,
                                width: "100%",
                                "&:disabled": { opacity: 0.55 },
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                                "&:hover": isFriendRequestActionBusy
                                    ? undefined
                                    : { bgcolor: "#07A820" },
                            }}
                        >
                            {friendRequestAction == "accept" ? (
                                <SpaceActionFeedbackIcon
                                    phase="busy"
                                    size={17}
                                />
                            ) : (
                                "Accept"
                            )}
                        </Box>
                        {showFriendRequestDetails && (
                            <Box
                                component="button"
                                type="button"
                                aria-label={`Ignore friend request from ${displayName}`}
                                disabled={
                                    isFriendRequestActionBusy ||
                                    !onDiscardFriendRequest
                                }
                                onClick={() =>
                                    updateFriendRequest(
                                        "discard",
                                        onDiscardFriendRequest,
                                    )
                                }
                                sx={{
                                    alignItems: "center",
                                    bgcolor: "rgba(255, 255, 255, 0.12)",
                                    border: 0,
                                    borderRadius: spaceTileInnerRadius,
                                    boxSizing: "border-box",
                                    color: "rgba(255, 255, 255, 0.85)",
                                    cursor: isFriendRequestActionBusy
                                        ? "default"
                                        : "pointer",
                                    display: "flex",
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: requestActionTextSize,
                                    fontWeight: 600,
                                    height: requestActionSize,
                                    justifyContent: "center",
                                    p: 0,
                                    width: "100%",
                                    "&:disabled": { opacity: 0.55 },
                                    "&:focus-visible": {
                                        outline: `2px solid ${green}`,
                                        outlineOffset: 2,
                                    },
                                    "&:hover": isFriendRequestActionBusy
                                        ? undefined
                                        : {
                                              bgcolor:
                                                  "rgba(255, 255, 255, 0.18)",
                                          },
                                }}
                            >
                                {friendRequestAction == "discard" ? (
                                    <SpaceActionFeedbackIcon
                                        phase="busy"
                                        size={17}
                                    />
                                ) : (
                                    "Ignore"
                                )}
                            </Box>
                        )}
                    </Box>
                    {!showFriendRequestDetails && (
                        <Box
                            component="button"
                            type="button"
                            aria-label={`Ignore friend request from ${displayName}`}
                            disabled={
                                isFriendRequestActionBusy ||
                                !onDiscardFriendRequest
                            }
                            onClick={() =>
                                updateFriendRequest(
                                    "discard",
                                    onDiscardFriendRequest,
                                )
                            }
                            sx={{
                                alignItems: "center",
                                bgcolor: "transparent",
                                border: 0,
                                borderRadius: "50%",
                                color: "rgba(255, 255, 255, 0.65)",
                                cursor: isFriendRequestActionBusy
                                    ? "default"
                                    : "pointer",
                                display: "flex",
                                height: requestActionSize,
                                justifyContent: "center",
                                p: 0,
                                pointerEvents: "auto",
                                position: "absolute",
                                right: "calc(var(--space-tile-padding) / 2)",
                                top: "calc(var(--space-tile-padding) / 2)",
                                width: requestActionSize,
                                "&:disabled": { opacity: 0.55 },
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                                "&:hover": isFriendRequestActionBusy
                                    ? undefined
                                    : { color: "rgba(255, 255, 255, 0.85)" },
                            }}
                        >
                            {friendRequestAction == "discard" ? (
                                <SpaceActionFeedbackIcon
                                    phase="busy"
                                    size={requestCloseIconSize}
                                />
                            ) : (
                                <HugeiconsIcon
                                    icon={Cancel01Icon}
                                    size={requestCloseIconSize}
                                    strokeWidth={2.2}
                                />
                            )}
                        </Box>
                    )}
                </Box>
            )}
        </Box>
    );
};

const AddedFriendToast: React.FC<AddedFriendToastProps> = ({
    message,
    onClose,
}) => (
    <SpaceActionToast
        closeLabel="Dismiss friend request status"
        icon={
            <HugeiconsIcon icon={UserAdd02Icon} size={20} strokeWidth={1.8} />
        }
        message={message}
        onClose={onClose}
    />
);

export const HomeScreen: React.FC<HomeScreenProps> = ({
    latestPosts,
    unreadPosts,
    friendRequestSentToastName,
    friendRequests,
    friends,
    hasUnreadMessages,
    isLatestPostsLoading = false,
    isFriendsLoading = false,
    isFriendRequestsLoading = false,
    isHomeCacheLoading = false,
    showInstallPrompt = false,
    onCreatePost,
    onAcceptFriendRequest,
    onAddFriend,
    onDiscardFriendRequest,
    onLoadFriendAvatar,
    onLoadPostImage,
    onFriendRequestSentToastClose,
    onOpenFriend,
    onOpenFriendRequests,
    onOpenMessages,
    onMessageFriend,
    onPokeFriend,
    onOpenProfile,
    onReplyToPost,
    onSetPostLiked,
    profile,
    viewerSpaceId,
}) => {
    const [selectedViewer, setSelectedViewer] =
        useState<SelectedHomeViewer | null>(null);
    const [selectedContact, setSelectedContact] = useState<{
        anchorRect: DOMRect;
        friend: FriendProfile;
        avatarUrl?: string | null;
    } | null>(null);
    const [openedPostIds, setOpenedPostIds] = useState<Set<number>>(new Set());
    const [postTileCanvasSize, setPostTileCanvasSize] =
        useState<PostTileCanvasSize>({ height: 0, width: 0 });
    const [isDraftPostExitAnimating, setIsDraftPostExitAnimating] =
        useState(false);
    const [isDraftPostExiting, setIsDraftPostExiting] = useState(false);
    const [isPostPhotoOpening, setIsPostPhotoOpening] = useState(false);
    const [loadedFriendAvatarURLsByKey, setLoadedFriendAvatarURLsByKey] =
        useState<Record<string, string | null>>({});
    const [loadedPostImageURLsByKey, setLoadedPostImageURLsByKey] = useState<
        Record<string, string>
    >({});
    const [unavailablePostsByKey, setUnavailablePostsByKey] = useState<
        Record<string, true>
    >({});
    const postTileCanvasRef = React.useRef<HTMLDivElement | null>(null);
    const postInputRef = React.useRef<HTMLInputElement | null>(null);
    const localPostObjectUrlsRef = React.useRef<Set<string>>(new Set());
    const activeLocalPostObjectUrlRef = React.useRef<string | null>(null);
    const avatarLoadsInFlightRef = React.useRef<
        Map<string, Promise<string | null>>
    >(new Map());
    const imageLoadsInFlightRef = React.useRef<
        Map<string, Promise<string | undefined>>
    >(new Map());
    const isPostPhotoButtonDisabled =
        isPostPhotoOpening || !viewerSpaceId || !onCreatePost;
    const selectedPhotoFriendID = selectedViewer?.photo.friendID;
    const selectedPhotoIsOwn =
        Boolean(viewerSpaceId) && selectedPhotoFriendID == viewerSpaceId;
    const latestPostByFriendID = React.useMemo(() => {
        const posts = new Map<string, SpacePost>();
        for (const post of latestPosts) {
            posts.set(post.friendID, post);
            posts.set(post.spaceId, post);
        }
        return posts;
    }, [latestPosts]);
    const unreadPostsByFriendID = React.useMemo(() => {
        const postsByFriendID = new Map<string, SpacePost[]>();
        for (const post of unreadPosts) {
            if (openedPostIds.has(post.postId)) continue;
            for (const friendID of new Set([post.friendID, post.spaceId])) {
                const posts = postsByFriendID.get(friendID) ?? [];
                posts.push(post);
                postsByFriendID.set(friendID, posts);
            }
        }
        for (const posts of postsByFriendID.values()) {
            posts.sort(
                (a, b) => b.timestampMs - a.timestampMs || b.postId - a.postId,
            );
        }
        return postsByFriendID;
    }, [openedPostIds, unreadPosts]);
    const orderedHomeItems = React.useMemo(() => {
        const displayedFriends = friends.slice(0, maximumHomeTileCount);
        const friendIDs = new Set(
            friends.map((friend) => friend.spaceId ?? friend.id),
        );
        return [
            ...displayedFriends.map((friend) => ({
                friend,
                type: "friend" as const,
            })),
            ...friendRequests
                .filter(
                    (request) =>
                        !friendIDs.has(
                            request.friend.spaceId ?? request.friend.id,
                        ),
                )
                .slice(0, maximumHomeTileCount - displayedFriends.length)
                .map((request) => ({ request, type: "request" as const })),
        ].sort((a, b) => {
            const aFriend = a.type == "friend" ? a.friend : a.request.friend;
            const bFriend = b.type == "friend" ? b.friend : b.request.friend;
            return (aFriend.spaceId ?? aFriend.id).localeCompare(
                bFriend.spaceId ?? bFriend.id,
            );
        });
    }, [friendRequests, friends]);
    React.useEffect(() => setOpenedPostIds(new Set()), [viewerSpaceId]);
    React.useEffect(() => {
        const canvas = postTileCanvasRef.current;
        if (!canvas) return;

        const updateSize = () => {
            const { height, width } = canvas.getBoundingClientRect();
            setPostTileCanvasSize({ height, width });
        };
        const observer = new ResizeObserver(updateSize);
        observer.observe(canvas);
        updateSize();
        return () => observer.disconnect();
    }, []);
    const postLayout = homeTileLayout(
        orderedHomeItems.length,
        postTileCanvasSize.width,
        postTileCanvasSize.height,
    );
    const isInstallPromptEnabled =
        showInstallPrompt && !friendRequestSentToastName && !selectedViewer;
    const isHomeItemsLoading = isFriendsLoading || isFriendRequestsLoading;
    const showUnreadIndicator = hasUnreadMessages === true;
    const profileDisplayName =
        profile?.fullName.trim() || profile?.username.trim() || "";
    const revokeLocalPostObjectUrls = React.useCallback(() => {
        localPostObjectUrlsRef.current.forEach((objectUrl) =>
            URL.revokeObjectURL(objectUrl),
        );
        localPostObjectUrlsRef.current.clear();
    }, []);
    const openPostPhotoPicker = () => {
        if (isPostPhotoButtonDisabled) return;

        postInputRef.current?.click();
    };
    const markPostRead = React.useCallback(
        (post: Pick<SpacePost, "postId" | "timestampMs">) => {
            if (!viewerSpaceId) return;
            setOpenedPostIds((current) => new Set(current).add(post.postId));
            void markSpaceHomePostRead(viewerSpaceId, post).catch(
                (error: unknown) =>
                    log.warn("Failed to mark Space post as read", error),
            );
        },
        [viewerSpaceId],
    );
    const openPostPhotos = (
        friend: FriendProfile,
        posts: SpacePost[],
        photo: SpaceViewerPhoto,
    ) => {
        if (photo.postId) {
            markPostRead({
                postId: photo.postId,
                timestampMs: photo.timestampMs,
            });
        }
        const isOwnPost =
            Boolean(viewerSpaceId) && photo.friendID == viewerSpaceId;
        setSelectedViewer({
            avatarUrl: photo.avatarUrl,
            friend,
            photo,
            postIndex: 0,
            postActionMode: isOwnPost ? "hidden" : "like-only",
            posts,
            sessionId: Symbol(),
        });
    };
    const closeSelectedPhoto = () => {
        activeLocalPostObjectUrlRef.current = null;
        setIsDraftPostExitAnimating(false);
        setIsDraftPostExiting(false);
        setSelectedViewer(null);
        revokeLocalPostObjectUrls();
    };
    const { clearBrowserBackState: clearSelectedPhotoHistory } =
        useBrowserBackClose({
            open: Boolean(selectedViewer),
            onClose: () => {
                if (!isDraftPostExiting) closeSelectedPhoto();
            },
            stateKey: "space-home-viewer",
        });
    const loadedPostImageURLFor = React.useCallback(
        (item: SpacePost) =>
            item.imageUrl ?? loadedPostImageURLsByKey[postImageCacheKey(item)],
        [loadedPostImageURLsByKey],
    );
    const loadedFriendAvatarURLFor = React.useCallback(
        (friend: FriendProfile) =>
            friend.avatarUrl ??
            loadedFriendAvatarURLsByKey[friendAvatarCacheKey(friend)],
        [loadedFriendAvatarURLsByKey],
    );
    const loadPostImage = React.useCallback(
        (item: SpacePost) => {
            const loadedImageUrl = loadedPostImageURLFor(item);
            if (loadedImageUrl) return Promise.resolve(loadedImageUrl);
            if (!item.imageAsset || !onLoadPostImage) {
                return Promise.resolve(undefined);
            }

            const cacheKey = postImageCacheKey(item);
            if (unavailablePostsByKey[cacheKey]) {
                return Promise.resolve(undefined);
            }
            const inFlight = imageLoadsInFlightRef.current.get(cacheKey);
            if (inFlight) return inFlight;

            const load = onLoadPostImage(item.imageAsset)
                .then((imageUrl) => {
                    setLoadedPostImageURLsByKey((currentURLs) =>
                        currentURLs[cacheKey] == imageUrl
                            ? currentURLs
                            : { ...currentURLs, [cacheKey]: imageUrl },
                    );
                    return imageUrl;
                })
                .catch((error: unknown) => {
                    log.warn("Failed to load latest post image", error);
                    if (isSpaceContentError(error)) {
                        setUnavailablePostsByKey((current) => ({
                            ...current,
                            [cacheKey]: true,
                        }));
                    }
                    return undefined;
                })
                .finally(() => {
                    imageLoadsInFlightRef.current.delete(cacheKey);
                });
            imageLoadsInFlightRef.current.set(cacheKey, load);
            return load;
        },
        [loadedPostImageURLFor, onLoadPostImage, unavailablePostsByKey],
    );
    const loadFriendAvatar = React.useCallback(
        (friend: FriendProfile) => {
            const loadedAvatarUrl = loadedFriendAvatarURLFor(friend);
            if (loadedAvatarUrl !== undefined) {
                return Promise.resolve(loadedAvatarUrl);
            }
            if (!friend.avatarObjectID || !onLoadFriendAvatar) {
                return Promise.resolve(null);
            }

            const cacheKey = friendAvatarCacheKey(friend);
            const inFlight = avatarLoadsInFlightRef.current.get(cacheKey);
            if (inFlight) return inFlight;

            const load = onLoadFriendAvatar(friend)
                .then((avatarUrl) => {
                    setLoadedFriendAvatarURLsByKey((currentURLs) =>
                        currentURLs[cacheKey] == avatarUrl
                            ? currentURLs
                            : { ...currentURLs, [cacheKey]: avatarUrl },
                    );
                    return avatarUrl;
                })
                .catch((error: unknown) => {
                    log.warn("Failed to load friend avatar", error);
                    setLoadedFriendAvatarURLsByKey((currentURLs) =>
                        currentURLs[cacheKey] === null
                            ? currentURLs
                            : { ...currentURLs, [cacheKey]: null },
                    );
                    return null;
                })
                .finally(() => {
                    avatarLoadsInFlightRef.current.delete(cacheKey);
                });
            avatarLoadsInFlightRef.current.set(cacheKey, load);
            return load;
        },
        [loadedFriendAvatarURLFor, onLoadFriendAvatar],
    );
    const selectedViewerPostIndex = selectedViewer?.postIndex;
    const selectedViewerPosts = selectedViewer?.posts;

    const selectedViewerPhotos = React.useMemo(() => {
        const friend = selectedViewer?.friend;
        if (!selectedViewerPosts || !friend) return undefined;

        return selectedViewerPosts.map((post) =>
            viewerPhotoForPost(
                post,
                friend,
                selectedViewer.avatarUrl,
                loadedPostImageURLFor(post) ??
                    (selectedViewer.photo.postId == post.postId
                        ? selectedViewer.photo.imageUrl
                        : ""),
            ),
        );
    }, [loadedPostImageURLFor, selectedViewer, selectedViewerPosts]);
    const handleSelectedViewerPostIndexChange = React.useCallback(
        (postIndex: number) => {
            const currentViewer = selectedViewer;
            const post = currentViewer?.posts?.[postIndex];
            const friend = currentViewer?.friend;
            if (!post || !friend) return;

            markPostRead(post);
            const updateSelectedViewer = (
                imageUrl: string,
                requireActivePost = false,
            ) => {
                setSelectedViewer((viewer) => {
                    if (
                        !viewer?.posts ||
                        viewer.sessionId !== currentViewer.sessionId ||
                        (requireActivePost &&
                            (viewer.postIndex != postIndex ||
                                viewer.photo.postId != post.postId))
                    ) {
                        return viewer;
                    }
                    return {
                        ...viewer,
                        photo: viewerPhotoForPost(
                            post,
                            friend,
                            viewer.avatarUrl,
                            imageUrl,
                        ),
                        postIndex,
                    };
                });
            };

            const imageUrl = loadedPostImageURLFor(post);
            if (imageUrl) {
                updateSelectedViewer(imageUrl);
                return;
            }

            updateSelectedViewer("");
            void loadPostImage(post).then((loadedImageUrl) => {
                if (loadedImageUrl) {
                    updateSelectedViewer(loadedImageUrl, true);
                }
            });
        },
        [loadPostImage, loadedPostImageURLFor, markPostRead, selectedViewer],
    );
    const setSelectedViewerPostLiked = React.useCallback(
        async (postId: number, liked: boolean) => {
            await onSetPostLiked?.(postId, liked);
            setSelectedViewer((viewer) =>
                viewer
                    ? {
                          ...viewer,
                          photo:
                              viewer.photo.postId == postId
                                  ? { ...viewer.photo, viewerLiked: liked }
                                  : viewer.photo,
                          posts: viewer.posts?.map((post) =>
                              post.postId == postId
                                  ? { ...post, viewerLiked: liked }
                                  : post,
                          ),
                      }
                    : viewer,
            );
        },
        [onSetPostLiked],
    );

    React.useEffect(() => {
        if (!selectedViewerPosts || selectedViewerPostIndex == undefined)
            return;

        for (const offset of [-1, 1]) {
            const adjacentPost =
                selectedViewerPosts[selectedViewerPostIndex + offset];
            if (!adjacentPost || loadedPostImageURLFor(adjacentPost)) continue;
            void loadPostImage(adjacentPost);
        }
    }, [
        loadPostImage,
        loadedPostImageURLFor,
        selectedViewerPostIndex,
        selectedViewerPosts,
    ]);
    const friendPostTileFor = (friend: FriendProfile, index: number) => {
        const placement = postLayout!.friends[index]!;
        const friendID = friend.spaceId ?? friend.id;
        const unreadFriendPosts = (
            unreadPostsByFriendID.get(friendID) ?? []
        ).filter(
            (post) =>
                !post.isUnavailable &&
                !unavailablePostsByKey[postImageCacheKey(post)],
        );
        const latestPost = latestPostByFriendID.get(friendID);
        const posts =
            unreadFriendPosts.length > 0
                ? unreadFriendPosts
                : latestPost
                  ? [latestPost]
                  : [];
        const item = posts[0];
        const imageUrl = item ? loadedPostImageURLFor(item) : undefined;
        const avatarUrl = loadedFriendAvatarURLFor(friend);
        const isAvatarPending = Boolean(
            friend.avatarObjectID && avatarUrl === undefined,
        );
        const isUnavailable = Boolean(
            item &&
            (item.isUnavailable ||
                unavailablePostsByKey[postImageCacheKey(item)]),
        );
        const isRead = unreadFriendPosts.length == 0;
        return (
            <FriendPostTile
                key={`${friend.id}:${item?.postId ?? "empty"}`}
                avatarUrl={avatarUrl}
                friend={friend}
                imageUrl={imageUrl}
                isAvatarPending={isAvatarPending}
                isLoading={isFriendsLoading || (isLatestPostsLoading && !item)}
                isRead={isRead}
                isUnavailable={isUnavailable}
                onLoadAvatar={() => loadFriendAvatar(friend)}
                onLoadImage={
                    item && !imageUrl && !isUnavailable
                        ? () => loadPostImage(item)
                        : undefined
                }
                onOpenFriend={onOpenFriend}
                onOpenAvatar={(anchorRect) =>
                    setSelectedContact({ anchorRect, friend, avatarUrl })
                }
                onOpenPosts={openPostPhotos}
                isNineTileLayout={
                    orderedHomeItems.length == maximumHomeTileCount
                }
                placement={placement}
                posts={posts}
            />
        );
    };
    const friendRequestTileFor = (
        request: SpaceFriendRequest,
        index: number,
    ) => {
        const friend = request.friend;
        const avatarUrl =
            request.direction == "sent"
                ? loadedFriendAvatarURLFor(friend)
                : undefined;
        return (
            <FriendPostTile
                key={`request:${request.requestId}`}
                avatarUrl={avatarUrl}
                friend={friend}
                friendRequestDirection={request.direction}
                isAvatarPending={Boolean(
                    request.direction == "sent" &&
                    friend.avatarObjectID &&
                    avatarUrl === undefined,
                )}
                isLoading={isHomeItemsLoading}
                isRead
                isUnavailable={false}
                onAcceptFriendRequest={
                    request.direction == "received" && onAcceptFriendRequest
                        ? () => onAcceptFriendRequest(request.requestId)
                        : undefined
                }
                onDiscardFriendRequest={
                    request.direction == "received" && onDiscardFriendRequest
                        ? () => onDiscardFriendRequest(request.requestId)
                        : undefined
                }
                onLoadAvatar={
                    request.direction == "sent"
                        ? () => loadFriendAvatar(friend)
                        : undefined
                }
                onOpenFriendRequest={
                    request.direction == "sent"
                        ? onOpenFriendRequests
                        : undefined
                }
                onOpenPosts={openPostPhotos}
                isNineTileLayout={
                    orderedHomeItems.length == maximumHomeTileCount
                }
                isTwoTileLayout={orderedHomeItems.length == 2}
                placement={postLayout!.friends[index]!}
                posts={[]}
                showFriendRequestDetails={orderedHomeItems.length <= 2}
            />
        );
    };

    const prepareSelectedPostPhoto = React.useCallback(
        async (file: File) => {
            if (!profile) return;

            const canShowLocalPreview = canPreviewSpaceImageFile(file);
            if (!canShowLocalPreview) {
                const timestampMs = Date.now();
                const draftKey = `pending-preview-${timestampMs}`;
                activeLocalPostObjectUrlRef.current = draftKey;
                setSelectedViewer({
                    draftFile: file,
                    isDraftImagePreviewPending: true,
                    localObjectUrl: draftKey,
                    photo: {
                        alt: `${profileDisplayName || "You"} post`,
                        avatarUrl: profile.avatarUrl,
                        imageUrl: "",
                        name: profileDisplayName || "You",
                        timestampMs,
                    },
                    postActionMode: "draft-post",
                });

                window.setTimeout(() => {
                    if (activeLocalPostObjectUrlRef.current != draftKey) return;

                    void spacePostPreviewImageForFile(file)
                        .then((preview) => {
                            if (
                                activeLocalPostObjectUrlRef.current != draftKey
                            ) {
                                URL.revokeObjectURL(preview.url);
                                return;
                            }

                            localPostObjectUrlsRef.current.add(preview.url);
                            activeLocalPostObjectUrlRef.current = preview.url;
                            setSelectedViewer((currentViewer) => {
                                if (currentViewer?.localObjectUrl != draftKey)
                                    return currentViewer;

                                return {
                                    ...currentViewer,
                                    isDraftImagePreviewPending: false,
                                    localObjectUrl: preview.url,
                                    photo: {
                                        ...currentViewer.photo,
                                        height: preview.height,
                                        imageUrl: preview.url,
                                        width: preview.width,
                                    },
                                };
                            });
                        })
                        .catch((error: unknown) => {
                            log.error("Failed to prepare post preview", error);
                            const message = spacePostImageErrorMessage(error);
                            setSelectedViewer((currentViewer) => {
                                if (currentViewer?.localObjectUrl != draftKey)
                                    return currentViewer;

                                return {
                                    ...currentViewer,
                                    draftImageError: message,
                                };
                            });
                        });
                }, 0);
                return;
            }

            const localPost = await createLoadedLocalPostPhoto({
                avatarUrl: profile.avatarUrl,
                file,
                name: profileDisplayName || "You",
            });
            localPostObjectUrlsRef.current.add(localPost.objectUrl);
            activeLocalPostObjectUrlRef.current = localPost.objectUrl;
            setSelectedViewer({
                draftFile: file,
                localObjectUrl: localPost.objectUrl,
                photo: localPost.photo,
                postActionMode: "draft-post",
            });
        },
        [profile, profileDisplayName],
    );

    const handlePostPhotoSelect: React.ChangeEventHandler<HTMLInputElement> = (
        event,
    ) => {
        const file = event.target.files?.[0];
        event.target.value = "";
        if (!file) return;

        setIsPostPhotoOpening(true);
        void prepareSelectedPostPhoto(file)
            .catch((error: unknown) => {
                log.error("Failed to open post photo draft", error);
            })
            .finally(() => {
                setIsPostPhotoOpening(false);
            });
    };

    React.useEffect(
        () => () => {
            activeLocalPostObjectUrlRef.current = null;
            revokeLocalPostObjectUrls();
        },
        [revokeLocalPostObjectUrls],
    );

    return (
        <Box
            component="main"
            sx={{
                background: spaceAppBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
                position: "relative",
            }}
        >
            {selectedViewer && (
                <SpaceViewerPostBackdrop exiting={isDraftPostExitAnimating} />
            )}
            <Box
                sx={{
                    bgcolor: "transparent",
                    boxSizing: "border-box",
                    maxWidth: "100%",
                    minHeight: "100svh",
                    minWidth: 0,
                    mx: "auto",
                    overflowX: "hidden",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <SpaceHomeHeader
                    profile={profile}
                    showUnreadIndicator={showUnreadIndicator}
                    onOpenMessages={onOpenMessages}
                    onOpenProfile={onOpenProfile}
                >
                    <Box
                        ref={postInputRef}
                        component="input"
                        type="file"
                        accept={spacePostImageInputAccept}
                        onChange={handlePostPhotoSelect}
                        sx={{ display: "none" }}
                    />
                </SpaceHomeHeader>
                <Box
                    sx={{
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: `${homeTileGap}px`,
                        minHeight: `calc(100svh - ${spaceHomeHeaderHeight}px)`,
                        minWidth: 0,
                        pb: "calc(env(safe-area-inset-bottom) + 16px)",
                        px: homeHorizontalPadding,
                        pt: "4px",
                        width: "100%",
                    }}
                >
                    <Box
                        ref={postTileCanvasRef}
                        sx={{
                            flex: "1 1 auto",
                            minHeight: minimumHomeTileCanvasHeight(
                                orderedHomeItems.length,
                            ),
                            position: "relative",
                            width: "100%",
                        }}
                    >
                        {isHomeItemsLoading ? (
                            <Box
                                sx={{
                                    alignItems: "center",
                                    display: "flex",
                                    height: "100%",
                                    justifyContent: "center",
                                    width: "100%",
                                }}
                            >
                                {!isHomeCacheLoading && (
                                    <SpaceLoadingSpinner ariaLabel="Loading friends and requests" />
                                )}
                            </Box>
                        ) : (
                            postLayout && (
                                <Box
                                    component="ul"
                                    aria-label="Friends and friend requests"
                                    sx={{
                                        inset: 0,
                                        m: 0,
                                        p: 0,
                                        position: "absolute",
                                    }}
                                >
                                    {orderedHomeItems.map((item, index) =>
                                        item.type == "friend"
                                            ? friendPostTileFor(
                                                  item.friend,
                                                  index,
                                              )
                                            : friendRequestTileFor(
                                                  item.request,
                                                  index,
                                              ),
                                    )}
                                    {postLayout.addFriend && (
                                        <SpaceAddFriendTile
                                            placement={postLayout.addFriend}
                                            variant={
                                                postLayout.addFriendVariant
                                            }
                                            onClick={onAddFriend}
                                        />
                                    )}
                                </Box>
                            )
                        )}
                    </Box>
                    <Box
                        sx={{
                            alignItems: "center",
                            display: "flex",
                            gap: `${homeTileGap}px`,
                            justifyContent: "flex-end",
                        }}
                    >
                        {!isHomeItemsLoading &&
                            [1, 2, 4, 6, 8].includes(
                                orderedHomeItems.length,
                            ) && <SpaceAddFriendButton onClick={onAddFriend} />}
                        <SpaceNewPostButton
                            isDisabled={isPostPhotoButtonDisabled}
                            onClick={openPostPhotoPicker}
                        />
                    </Box>
                </Box>
                {selectedContact && (
                    <FriendQuickActionsDialog
                        {...selectedContact}
                        onClose={() => setSelectedContact(null)}
                        onMessage={() =>
                            onMessageFriend(selectedContact.friend)
                        }
                        onPoke={() => onPokeFriend(selectedContact.friend)}
                        onProfile={() =>
                            onOpenFriend?.(
                                selectedContact.friend.id,
                                selectedContact.friend.username,
                            )
                        }
                    />
                )}
                {selectedViewer && (
                    <SpaceFileViewer
                        focusReplyOnOpen={selectedViewer.focusReplyOnOpen}
                        photo={selectedViewer.photo}
                        photos={selectedViewerPhotos}
                        photoIndex={selectedViewerPostIndex}
                        draftPostPreparationError={
                            selectedViewer.draftImageError
                        }
                        isDraftPostPreviewPending={
                            selectedViewer.isDraftImagePreviewPending
                        }
                        postActionMode={selectedViewer.postActionMode}
                        showSequenceProgress={Boolean(
                            selectedViewerPosts &&
                            selectedViewerPosts.length > 1,
                        )}
                        onPhotoIndexChange={
                            selectedViewerPosts
                                ? handleSelectedViewerPostIndexChange
                                : undefined
                        }
                        onClose={closeSelectedPhoto}
                        onOpenProfile={
                            selectedPhotoIsOwn && onOpenProfile
                                ? () => {
                                      void clearSelectedPhotoHistory(
                                          "back",
                                      ).finally(() => {
                                          onOpenProfile();
                                      });
                                  }
                                : selectedPhotoFriendID && onOpenFriend
                                  ? () => {
                                        void clearSelectedPhotoHistory(
                                            "back",
                                        ).finally(() => {
                                            onOpenFriend(
                                                selectedPhotoFriendID,
                                                selectedViewer.photo.username,
                                            );
                                        });
                                    }
                                  : undefined
                        }
                        onSwipeLeft={
                            !selectedViewerPosts ||
                            selectedViewerPostIndex ==
                                selectedViewerPosts.length - 1
                                ? closeSelectedPhoto
                                : undefined
                        }
                        onReplyToPost={
                            !selectedPhotoIsOwn &&
                            selectedViewer.photo.friendID != viewerSpaceId
                                ? onReplyToPost
                                : undefined
                        }
                        onPublishDraftPost={
                            selectedViewer.draftFile && onCreatePost
                                ? (caption, edit) => {
                                      const previewUrl =
                                          selectedViewer.photo.imageUrl;
                                      const publishPromise = onCreatePost(
                                          {
                                              cropArea: edit.cropArea,
                                              file: selectedViewer.draftFile!,
                                              height: edit.height,
                                              previewUrl,
                                              rotationDegrees:
                                                  edit.rotationDegrees,
                                              width: edit.width,
                                          },
                                          caption,
                                      );
                                      localPostObjectUrlsRef.current.delete(
                                          previewUrl,
                                      );
                                      return publishPromise;
                                  }
                                : undefined
                        }
                        onDraftPostExitAnimationStart={() => {
                            setIsDraftPostExitAnimating(true);
                        }}
                        onDraftPostExitStart={() => {
                            setIsDraftPostExiting(true);
                        }}
                        onSetPostLiked={
                            onSetPostLiked
                                ? setSelectedViewerPostLiked
                                : undefined
                        }
                    />
                )}
                {friendRequestSentToastName ? (
                    <AddedFriendToast
                        message={`Friend request sent to @${friendRequestSentToastName}`}
                        onClose={onFriendRequestSentToastClose}
                    />
                ) : (
                    <SpacePWAInstallPrompt enabled={isInstallPromptEnabled} />
                )}
            </Box>
        </Box>
    );
};
