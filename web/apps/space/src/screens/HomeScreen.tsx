import {
    FavouriteIcon,
    MultiplicationSignIcon,
    UserAdd02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Skeleton } from "@mui/material";
import { visuallyHidden } from "@mui/utils";
import { SpaceActionToast } from "components/ActionToast";
import { SpaceAvatarImage } from "components/AvatarImage";
import { SpaceCaptionText } from "components/CaptionText";
import { SpaceFeedPostButton } from "components/FeedPostButton";
import {
    SpaceFileViewer,
    type SpaceViewerPhoto,
    type SpaceViewerPostActionMode,
} from "components/FileViewer";
import { SpaceHomeHeader } from "components/HomeHeader";
import {
    spacePostLikeButtonPop,
    spacePostLikeHeartPop,
    spacePostLikePopDurationMs,
    spacePostLikePopTiming,
} from "components/post-like-animation";
import { SpacePostPhotoInput } from "components/PostPhotoInput";
import { SpacePostPhotosCounter } from "components/PostPhotosCounter";
import { SpacePostPhotosDots } from "components/PostPhotosDots";
import { SpacePWAInstallPrompt } from "components/PWAInstallPrompt";
import { SpaceLoadingSpinner } from "components/RouteFallback";
import { SpaceShareInviteButton } from "components/ShareInviteButton";
import { SpaceSkipLink } from "components/SkipLink";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React, { useState } from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";
import {
    isSpaceContentError,
    type SpacePost,
    type SpacePostAssetURLLoader,
    type SpacePostAvatarURLLoader,
    type SpacePostPhoto,
} from "services/space";
import type { LocalSpaceFeedPost } from "state/app-state";
import { spaceEmptyStateButtonSx } from "styles/buttons";
import {
    spaceAppBackgroundColor,
    spaceControlBackground,
    spaceControlBackgroundHover,
    spaceSurface,
    spaceSurfaceHover,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { minimumPostPhotoFrameAspectRatio } from "styles/tiles";
import { spaceTouchTargetSize } from "styles/touch-targets";
import { firstNameFrom, formatSpaceDate } from "utils/display";
import { spacePostPhotos, viewerPhotosFromPost } from "utils/post-photos";
import { thumbHashDataURLFromBase64 } from "utils/thumbhash";

const homeBackground = spaceAppBackgroundColor;

const green = "#08C225";
const feedAccentBackground = "#263D2C";
const feedAccentBackgroundHover = "#2C4B32";
const feedActionBackground = "#363639";
const feedActionForeground = "#DEDEDE";
const feedTimestampForeground = "#C8C8C8";
const feedSkeletonElementBackground = spaceSurfaceHover;
const textBase = spaceText;
const textSecondary = spaceTextMuted;
const dangerColor = "#F63A3A";
const feedAvatarSize = 38;
const feedLikeActionSize = spaceTouchTargetSize;
const feedActionIconSize = 20;
const feedHorizontalPadding = "16px";
const feedMediaLoadRootMargin = "640px 0px";
const feedLoadMoreRootMargin = "0px 0px 160px 0px";
const feedRowEnterDurationMs = 460;
const feedRowEnterStaggerMs = 35;
const feedRowEnterTiming = "cubic-bezier(0.2, 0.8, 0.2, 1)";
const avatarFadeSx = {
    "@keyframes spaceAvatarFade": { from: { opacity: 0 }, to: { opacity: 1 } },
    animation: "spaceAvatarFade 320ms cubic-bezier(0.22, 1, 0.36, 1) both",
    "@media (prefers-reduced-motion: reduce)": { animation: "none" },
} as const;
const feedPhotoCaptionTextSx = {
    color: "#E6E6E6",
    fontFamily: '"Inter Variable", Inter, sans-serif',
    fontSize: 13,
    fontWeight: 600,
    lineHeight: "21px",
    textAlign: "center",
    textWrap: "balance",
} as const;
interface HomeScreenProps {
    feedItems: SpacePost[];
    friendRequestSentToastName?: string;
    hasFeedLoadMoreError?: boolean;
    hasMoreFeedItems?: boolean;
    hasUnreadMessages?: boolean;
    isFeedLoading?: boolean;
    isFeedLoadingMore?: boolean;
    localFeedPosts?: LocalSpaceFeedPost[];
    showFirstPostPrompt?: boolean;
    showInstallPrompt?: boolean;
    showInviteFriendsToast?: boolean;
    onAddFriend: () => void;
    onPostPhotoSelect: (files: File[]) => void;
    onDeletePost?: (postId: number) => Promise<void> | void;
    onLoadMoreFeedItems?: () => Promise<void> | void;
    onLoadPostAvatar?: SpacePostAvatarURLLoader;
    onLoadPostImage?: SpacePostAssetURLLoader;
    onFriendRequestSentToastClose?: () => void;
    onInviteFriendsToastClose?: () => void;
    onOpenFriend?: (friendID: string, username?: string) => void;
    onOpenMessages?: () => void;
    onOpenProfile?: () => void;
    onReplyToPost?: (
        postSpaceId: string,
        postId: number,
        text: string,
        objectKey: string,
    ) => Promise<void>;
    onSetPostLiked?: (postId: number, liked: boolean) => Promise<void>;
    onUpdatePostCaption?: (postId: number, caption: string) => Promise<void>;
    profileLink?: string;
    profile: SetupProfile | null;
    viewerSpaceId?: string;
}

interface FeedPhotoDimensions {
    height: number;
    width: number;
}

interface DecodedImageState {
    failed?: boolean;
    height?: number;
    ready: boolean;
    src?: string | null;
    width?: number;
}

interface SelectedHomeViewer {
    photoIndex: number;
    photos: SpaceViewerPhoto[];
    focusReplyOnOpen?: boolean;
    photo: SpaceViewerPhoto;
    postActionMode?: SpaceViewerPostActionMode;
}

type HomeFeedEntry =
    | {
          identity: string;
          item: LocalSpaceFeedPost;
          kind: "local";
          renderKey: string;
      }
    | { identity: string; item: SpacePost; kind: "remote"; renderKey: string };

interface FeedLayoutSnapshot {
    enteringKeys: Set<string>;
    previousTops: Map<string, number>;
}

interface FeedMotionListProps {
    entries: HomeFeedEntry[];
    renderEntry: (entry: HomeFeedEntry) => React.ReactNode;
}

class FeedMotionList extends React.Component<FeedMotionListProps> {
    private animations = new Map<string, Animation>();
    private identityKeys = new Map<string, string>();
    private rowElements = new Map<string, HTMLDivElement>();
    private rowRefs = new Map<
        string,
        (element: HTMLDivElement | null) => void
    >();
    private sourceKeys = new Map<string, string>();

    private stableKeyFor = (entry: HomeFeedEntry) => {
        const stableKey =
            this.identityKeys.get(entry.identity) ??
            this.sourceKeys.get(entry.renderKey) ??
            entry.renderKey;
        this.identityKeys.set(entry.identity, stableKey);
        this.sourceKeys.set(entry.renderKey, stableKey);
        return stableKey;
    };

    private rowRefFor = (key: string) => {
        let rowRef = this.rowRefs.get(key);
        if (!rowRef) {
            rowRef = (element) => {
                if (element) this.rowElements.set(key, element);
                else this.rowElements.delete(key);
            };
            this.rowRefs.set(key, rowRef);
        }
        return rowRef;
    };

    private cancelAnimations = () => {
        this.animations.forEach((animation) => animation.cancel());
        this.animations.clear();
        this.rowElements.forEach((element) => {
            element.style.zIndex = "";
            element.style.willChange = "";
        });
    };

    getSnapshotBeforeUpdate(
        previousProps: FeedMotionListProps,
    ): FeedLayoutSnapshot | null {
        const previousIdentityOrder = previousProps.entries.map(
            (entry) => entry.identity,
        );
        const identityOrder = this.props.entries.map((entry) => entry.identity);
        if (
            previousIdentityOrder.length == identityOrder.length &&
            previousIdentityOrder.every(
                (identity, index) => identity == identityOrder[index],
            )
        )
            return null;

        const previousIdentities = new Set(previousIdentityOrder);
        const addedEntries = this.props.entries.filter(
            (entry) => !previousIdentities.has(entry.identity),
        );
        if (
            previousProps.entries.length == 0 ||
            addedEntries.some((entry) => entry.kind == "local")
        )
            return null;

        const firstRetainedIndex = this.props.entries.findIndex((entry) =>
            previousIdentities.has(entry.identity),
        );
        const enteringKeys = new Set(
            firstRetainedIndex > 0
                ? this.props.entries
                      .slice(0, firstRetainedIndex)
                      .filter((entry) => entry.kind == "remote")
                      .map(this.stableKeyFor)
                : [],
        );
        const previousTops = new Map<string, number>();
        this.rowElements.forEach((element, key) => {
            previousTops.set(key, element.getBoundingClientRect().top);
        });
        return { enteringKeys, previousTops };
    }

    componentDidUpdate(
        _previousProps: FeedMotionListProps,
        _previousState: unknown,
        snapshot: FeedLayoutSnapshot | null,
    ) {
        if (
            !snapshot ||
            window.matchMedia("(prefers-reduced-motion: reduce)").matches
        )
            return;

        this.cancelAnimations();
        let enteringIndex = 0;
        for (const entry of this.props.entries) {
            const key = this.stableKeyFor(entry);
            const element = this.rowElements.get(key);
            if (!element) continue;

            let animation: Animation | undefined;
            if (snapshot.enteringKeys.has(key)) {
                const delay = enteringIndex * feedRowEnterStaggerMs;
                const height = element.getBoundingClientRect().height;
                const paddingBottom =
                    window.getComputedStyle(element).paddingBottom;
                element.style.zIndex = String(3 - enteringIndex++);
                element.style.willChange = "height, padding-bottom, transform";
                animation = element.animate(
                    [
                        {
                            height: "0px",
                            paddingBottom: "0px",
                            transform: `translate3d(0, -${height}px, 0)`,
                        },
                        {
                            height: `${height}px`,
                            paddingBottom,
                            transform: "translate3d(0, 0, 0)",
                        },
                    ],
                    {
                        delay,
                        duration: feedRowEnterDurationMs,
                        easing: feedRowEnterTiming,
                        fill: "both",
                    },
                );
            } else if (snapshot.enteringKeys.size == 0) {
                const previousTop = snapshot.previousTops.get(key);
                if (previousTop == undefined) continue;
                const offsetY =
                    previousTop - element.getBoundingClientRect().top;
                if (!offsetY) continue;
                animation = element.animate(
                    [
                        { transform: `translate3d(0, ${offsetY}px, 0)` },
                        { transform: "translate3d(0, 0, 0)" },
                    ],
                    {
                        duration: feedRowEnterDurationMs,
                        easing: feedRowEnterTiming,
                        fill: "both",
                    },
                );
            }
            if (!animation) continue;

            this.animations.set(key, animation);
            void animation.finished.then(
                () => {
                    if (this.animations.get(key) != animation) return;
                    animation.cancel();
                    this.animations.delete(key);
                    element.style.zIndex = "";
                    element.style.willChange = "";
                },
                () => undefined,
            );
        }
    }

    componentWillUnmount() {
        this.cancelAnimations();
    }

    render() {
        return this.props.entries.map((entry) => {
            const key = this.stableKeyFor(entry);
            return (
                <Box
                    key={key}
                    ref={this.rowRefFor(key)}
                    sx={{
                        boxSizing: "border-box",
                        minWidth: 0,
                        pb: "24px",
                        position: "relative",
                        width: "100%",
                    }}
                >
                    {this.props.renderEntry(entry)}
                </Box>
            );
        });
    }
}

type FeedTimestampStatus = "failed" | "post-limit" | "posted" | "posting";

interface FeedPostPhoto extends SpacePostPhoto {
    isUnavailable?: boolean;
}

type FeedPhotoSource = SpacePostPhoto & Pick<SpacePost, "postId" | "spaceId">;

interface FeedItemProps {
    photoCount?: number;
    photoIndex?: number;
    photos?: FeedPostPhoto[];
    onPhotoIndexChange?: (index: number) => void;
    aspectRatio: number;
    avatarUrl: string | null;
    caption?: string;
    friendID: string;
    imageUrl?: string;
    isAvatarPending: boolean;
    isOwnPost: boolean;
    isUnavailable?: boolean;
    name: string;
    onLoadAvatar?: () => Promise<string | null | undefined>;
    onLoadImage?: (index: number) => Promise<string | undefined>;
    onOpenFriend?: (friendID: string, username?: string) => void;
    onOpenPhoto?: (photo: SpaceViewerPhoto, focusReplyOnOpen?: boolean) => void;
    onOpenProfile?: () => void;
    onSetPostLiked?: (postId: number, liked: boolean) => Promise<void>;
    postId: number;
    spaceId?: string;
    thumbHash?: string;
    timestampStatus?: FeedTimestampStatus;
    timestampMs: number;
    username?: string;
    viewerLiked: boolean;
}

interface AddedFriendToastProps {
    message: string;
    onClose?: () => void;
}

interface InviteFriendsToastProps {
    profileLink?: string;
    sharing: boolean;
    onClose?: () => void;
    onSharingChange: (sharing: boolean) => void;
}

const dimensionsFromAspectRatio = (
    aspectRatio: number,
): FeedPhotoDimensions => {
    const safeAspectRatio =
        Number.isFinite(aspectRatio) && aspectRatio > 0 ? aspectRatio : 1;
    const height = 1000;

    return { height, width: Math.round(safeAspectRatio * height) };
};

const feedPostImageCacheKey = (item: FeedPhotoSource) =>
    [
        item.postId,
        item.imageAsset?.spaceId ?? item.spaceId,
        item.imageAsset?.objectKey ?? item.imageUrl ?? "",
    ].join(":");

const feedPostAvatarCacheKey = (item: SpacePost) =>
    [
        item.spaceId,
        item.avatarKeyVersion ?? "",
        item.avatarObjectID ?? "",
        item.avatarUpdatedAt ?? "",
        item.avatarSize ?? "",
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

const scrollPageToTop = () => {
    const behavior = window.matchMedia("(prefers-reduced-motion: reduce)")
        .matches
        ? "auto"
        : "smooth";
    window.scrollTo({ behavior, top: 0 });
};

const scheduleScrollPageToTop = () => {
    let scrollFrame = 0;
    const closeFrame = window.requestAnimationFrame(() => {
        scrollFrame = window.requestAnimationFrame(scrollPageToTop);
    });
    return () => {
        window.cancelAnimationFrame(closeFrame);
        window.cancelAnimationFrame(scrollFrame);
    };
};

const usePostingDotCount = (isPosting: boolean) => {
    const [dotCount, setDotCount] = useState(1);

    React.useEffect(() => {
        if (!isPosting) {
            setDotCount(1);
            return;
        }

        const intervalID = window.setInterval(() => {
            setDotCount((count) => (count % 3) + 1);
        }, 500);

        return () => window.clearInterval(intervalID);
    }, [isPosting]);

    return dotCount;
};

interface FeedLikeButtonProps {
    isLiked: boolean;
    onClick: () => void;
    popID: number;
}

const FeedLikeButton: React.FC<FeedLikeButtonProps> = ({
    isLiked,
    onClick,
    popID,
}) => {
    const isPopping = isLiked && popID > 0;

    return (
        <Box
            component="button"
            type="button"
            aria-label="Like post"
            aria-pressed={isLiked}
            onClick={onClick}
            sx={{
                alignItems: "center",
                animation: isPopping
                    ? `${spacePostLikeButtonPop} ${spacePostLikePopDurationMs}ms ${spacePostLikePopTiming} both`
                    : undefined,
                appearance: "none",
                bgcolor: isLiked ? feedAccentBackground : feedActionBackground,
                border: 0,
                borderRadius: "50%",
                color: isLiked ? green : feedActionForeground,
                cursor: "pointer",
                display: "inline-flex",
                flexShrink: 0,
                height: feedLikeActionSize,
                justifyContent: "center",
                p: 0,
                position: "relative",
                transition:
                    "background-color 160ms ease, color 120ms ease, transform 120ms ease",
                width: feedLikeActionSize,
                "&:active": { transform: "scale(0.94)" },
                "&:focus-visible": {
                    outline: `2px solid ${green}`,
                    outlineOffset: 2,
                },
                "&:hover": {
                    bgcolor: isLiked
                        ? feedAccentBackgroundHover
                        : spaceControlBackgroundHover,
                },
                "@media (prefers-reduced-motion: reduce)": {
                    animation: "none",
                    transition: "background-color 120ms ease, color 120ms ease",
                },
            }}
        >
            <Box
                key={isPopping ? `heart-${popID}` : "heart"}
                component="span"
                sx={{
                    animation: isPopping
                        ? `${spacePostLikeHeartPop} ${spacePostLikePopDurationMs}ms ${spacePostLikePopTiming} both`
                        : undefined,
                    display: "flex",
                    lineHeight: 0,
                    position: "relative",
                    transformOrigin: "50% 58%",
                    zIndex: 1,
                    "@media (prefers-reduced-motion: reduce)": {
                        animation: "none",
                    },
                }}
            >
                <HugeiconsIcon
                    fill={isLiked ? green : "none"}
                    icon={FavouriteIcon}
                    primaryColor={isLiked ? green : feedActionForeground}
                    size={feedActionIconSize}
                    strokeWidth={2}
                />
            </Box>
        </Box>
    );
};

const FeedPhotoOverlay: React.FC<{
    caption?: string;
    photoIndex: number;
    photoCount: number;
}> = ({ caption, photoIndex, photoCount }) => {
    return (
        <Box
            sx={{
                ...feedPhotoCaptionTextSx,
                bottom: 20,
                display: "grid",
                gap: "16px",
                justifyItems: "center",
                left: "50%",
                maxWidth: "78%",
                pointerEvents: "none",
                position: "absolute",
                transform: "translateX(-50%)",
                width: "max-content",
                zIndex: 2,
            }}
        >
            <SpacePostPhotosDots index={photoIndex} count={photoCount} />
            {caption && (
                <Box title={caption} sx={{ minWidth: 0, width: "100%" }}>
                    <SpaceCaptionText caption={caption} lineClamp={2} />
                </Box>
            )}
        </Box>
    );
};

const FeedPhoto: React.FC<{
    imageUrl?: string;
    isActive: boolean;
    isUnavailable: boolean;
    name: string;
    onLoadImage?: () => Promise<string | undefined>;
    onOpenPhoto?: () => void;
    shouldLoad: boolean;
    thumbHash?: string;
}> = ({
    imageUrl,
    isActive,
    isUnavailable,
    name,
    onLoadImage,
    onOpenPhoto,
    shouldLoad,
    thumbHash,
}) => {
    const decodedPhoto = useDecodedImage(imageUrl, true);
    const isPostUnavailable = isUnavailable || Boolean(decodedPhoto.failed);
    const displayImageUrl = decodedPhoto.src ?? undefined;
    const isPhotoReady = Boolean(displayImageUrl) && decodedPhoto.ready;
    const canOpenPhoto =
        !isPostUnavailable && isPhotoReady && Boolean(onOpenPhoto);
    const [showResolvedPhoto, setShowResolvedPhoto] = useState(false);
    const thumbHashDataURL = React.useMemo(
        () => thumbHashDataURLFromBase64(thumbHash),
        [thumbHash],
    );

    React.useEffect(() => {
        if (shouldLoad && !imageUrl && !isUnavailable) void onLoadImage?.();
    }, [imageUrl, isUnavailable, onLoadImage, shouldLoad]);

    React.useEffect(() => {
        if (!isPhotoReady || showResolvedPhoto) return;
        if (!thumbHashDataURL) {
            setShowResolvedPhoto(true);
            return;
        }
        const frameID = window.requestAnimationFrame(() =>
            setShowResolvedPhoto(true),
        );
        return () => window.cancelAnimationFrame(frameID);
    }, [isPhotoReady, showResolvedPhoto, thumbHashDataURL]);

    return (
        <Box
            component="button"
            type="button"
            aria-label={
                isPostUnavailable ? "Post unavailable" : `Open ${name} photo`
            }
            disabled={!canOpenPhoto}
            tabIndex={isActive ? 0 : -1}
            onClick={onOpenPhoto}
            sx={{
                appearance: "none",
                bgcolor: "transparent",
                border: 0,
                cursor: canOpenPhoto ? "pointer" : "default",
                display: "block",
                height: "100%",
                flex: "0 0 100%",
                scrollSnapAlign: "start",
                scrollSnapStop: "always",
                maxWidth: "100%",
                minWidth: 0,
                overflow: "hidden",
                p: 0,
                position: "relative",
                width: "100%",
                "&:focus-visible": {
                    outline: `2px solid ${green}`,
                    outlineOffset: -2,
                },
            }}
        >
            {!isPostUnavailable && !thumbHashDataURL && !isPhotoReady && (
                <Skeleton
                    variant="rectangular"
                    sx={{
                        bgcolor: feedSkeletonElementBackground,
                        display: "block",
                        height: "100%",
                        transform: "none",
                        width: "100%",
                    }}
                />
            )}
            {!isPostUnavailable && thumbHashDataURL ? (
                <Box
                    component="img"
                    alt=""
                    aria-hidden
                    src={thumbHashDataURL}
                    sx={{
                        display: "block",
                        filter: "blur(14px)",
                        height: "100%",
                        inset: 0,
                        objectFit: "cover",
                        objectPosition: "center",
                        position: "absolute",
                        transform: "scale(1.08)",
                        width: "100%",
                    }}
                />
            ) : null}
            {!isPostUnavailable && isPhotoReady && (
                <Box
                    component="img"
                    alt={`${name} post`}
                    src={displayImageUrl}
                    draggable={false}
                    sx={{
                        display: "block",
                        height: "100%",
                        inset: 0,
                        maxWidth: "100%",
                        minWidth: 0,
                        objectFit: "cover",
                        objectPosition: "center",
                        opacity: showResolvedPhoto ? 1 : 0,
                        position: "absolute",
                        transition: thumbHashDataURL
                            ? "opacity 220ms ease"
                            : "none",
                        width: "100%",
                        zIndex: 1,
                        "@media (prefers-reduced-motion: reduce)": {
                            opacity: 1,
                            transition: "none",
                        },
                    }}
                />
            )}
            {isPostUnavailable && (
                <Box
                    sx={{
                        alignItems: "center",
                        bgcolor: feedSkeletonElementBackground,
                        color: spaceTextMuted,
                        display: "flex",
                        fontSize: 14,
                        fontWeight: 600,
                        height: "100%",
                        justifyContent: "center",
                        width: "100%",
                    }}
                >
                    Post unavailable
                </Box>
            )}
        </Box>
    );
};

const FeedItem: React.FC<FeedItemProps> = ({
    photoCount = 1,
    photoIndex = 0,
    photos,
    onPhotoIndexChange,
    aspectRatio,
    avatarUrl,
    caption,
    friendID,
    imageUrl,
    isAvatarPending,
    isOwnPost,
    isUnavailable = false,
    name,
    onLoadAvatar,
    onLoadImage,
    onOpenFriend,
    onOpenPhoto,
    onOpenProfile,
    onSetPostLiked,
    postId,
    spaceId,
    thumbHash,
    timestampStatus,
    timestampMs,
    username,
    viewerLiked,
}) => {
    const [isLiked, setIsLiked] = useState(viewerLiked);
    const [likePopID, setLikePopID] = useState(0);
    const [shouldLoadMedia, setShouldLoadMedia] = useState(
        !isUnavailable && Boolean(imageUrl) && !isAvatarPending,
    );
    const feedPhotos = photos ?? [{ imageUrl, thumbHash }];
    const activePhoto = feedPhotos[photoIndex]!;
    const carouselRef = React.useRef<HTMLDivElement | null>(null);
    const photoAnimationRef = React.useRef<number | null>(null);
    const swipeRef = React.useRef<{
        pointerID: number;
        index: number;
        startLeft: number;
        x: number;
        y: number;
        dragging: boolean;
    } | null>(null);
    const suppressPhotoClickRef = React.useRef(false);
    const scrollToPhoto = React.useCallback(
        (index: number) => {
            const carousel = carouselRef.current;
            if (!carousel) return;
            if (photoAnimationRef.current != null) {
                cancelAnimationFrame(photoAnimationRef.current);
                photoAnimationRef.current = null;
            }
            const nextIndex = Math.max(
                0,
                Math.min(index, feedPhotos.length - 1),
            );
            const left = nextIndex * carousel.clientWidth;
            const startLeft = carousel.scrollLeft;
            carousel.style.scrollSnapType = "none";
            if (
                Math.abs(startLeft - left) < 1 ||
                window.matchMedia("(prefers-reduced-motion: reduce)").matches
            ) {
                carousel.scrollLeft = left;
                carousel.style.scrollSnapType = "";
                return;
            }
            const startTime = performance.now();
            const animate = (time: number) => {
                const progress = Math.min(1, (time - startTime) / 280);
                carousel.scrollLeft =
                    startLeft + (left - startLeft) * (1 - (1 - progress) ** 3);
                if (progress < 1) {
                    photoAnimationRef.current = requestAnimationFrame(animate);
                } else {
                    photoAnimationRef.current = null;
                    carousel.style.scrollSnapType = "";
                }
            };
            photoAnimationRef.current = requestAnimationFrame(animate);
        },
        [feedPhotos.length],
    );
    const finishPhotoSwipe = (event: React.PointerEvent<HTMLDivElement>) => {
        const swipe = swipeRef.current;
        if (swipe?.pointerID != event.pointerId) return;
        swipeRef.current = null;
        const dx = event.clientX - swipe.x;
        const direction =
            swipe.dragging &&
            event.type != "pointercancel" &&
            Math.abs(dx) >= 40
                ? -Math.sign(dx)
                : 0;
        scrollToPhoto(swipe.index + direction);
    };
    React.useEffect(
        () => () => {
            if (photoAnimationRef.current != null)
                cancelAnimationFrame(photoAnimationRef.current);
        },
        [],
    );
    React.useEffect(() => {
        const carousel = carouselRef.current;
        if (!carousel || feedPhotos.length < 2) return;
        let delta = 0;
        let advanced = false;
        let wheelEndTimeout: ReturnType<typeof setTimeout>;
        const handleWheel = (event: WheelEvent) => {
            if (
                event.ctrlKey ||
                Math.abs(event.deltaX) <= Math.abs(event.deltaY)
            )
                return;
            event.preventDefault();
            clearTimeout(wheelEndTimeout);
            wheelEndTimeout = setTimeout(() => {
                delta = 0;
                advanced = false;
            }, 180);
            if (advanced) return;
            delta += event.deltaX;
            if (Math.abs(delta) < 20) return;
            advanced = true;
            scrollToPhoto(
                Math.round(carousel.scrollLeft / carousel.clientWidth) +
                    Math.sign(delta),
            );
        };
        carousel.addEventListener("wheel", handleWheel, { passive: false });
        return () => {
            clearTimeout(wheelEndTimeout);
            carousel.removeEventListener("wheel", handleWheel);
        };
    }, [feedPhotos.length, scrollToPhoto]);
    React.useEffect(() => {
        const carousel = carouselRef.current;
        if (!carousel) return;
        if (
            Math.round(carousel.scrollLeft / carousel.clientWidth) != photoIndex
        ) {
            if (photoAnimationRef.current != null) {
                cancelAnimationFrame(photoAnimationRef.current);
                photoAnimationRef.current = null;
            }
            carousel.style.scrollSnapType = "";
            carousel.scrollTo({
                left: photoIndex * carousel.clientWidth,
                behavior: "instant",
            });
        }
    }, [photoIndex]);
    const rootRef = React.useRef<HTMLElement | null>(null);
    const firstName = firstNameFrom(name);
    const dateLabel = formatSpaceDate(timestampMs);
    const postingDotCount = usePostingDotCount(timestampStatus == "posting");
    const displayCaption = caption?.trim();
    const canOpenAuthor = isOwnPost
        ? Boolean(onOpenProfile)
        : Boolean(onOpenFriend);
    const authorProfileLabel = isOwnPost
        ? "Open your profile"
        : `Open ${firstName}'s profile`;
    const openAuthor = () => {
        if (isOwnPost) {
            onOpenProfile?.();
            return;
        }
        onOpenFriend?.(friendID, username);
    };
    const decodedPhoto = useDecodedImage(activePhoto.imageUrl);
    const decodedAvatar = useDecodedImage(avatarUrl, true);
    const isPostUnavailable =
        isUnavailable || activePhoto.isUnavailable || decodedPhoto.failed;
    const showFooter = !isOwnPost && !isPostUnavailable;
    const displayImageUrl =
        (decodedPhoto.failed
            ? undefined
            : decodedPhoto.ready
              ? decodedPhoto.src
              : activePhoto.imageUrl) ?? undefined;
    const displayAvatarUrl =
        (decodedAvatar.failed
            ? undefined
            : decodedAvatar.ready
              ? decodedAvatar.src
              : avatarUrl) ?? undefined;
    const isAvatarReady = !isAvatarPending && decodedAvatar.ready;
    const photoDimensions = {
        height:
            decodedPhoto.height ??
            activePhoto.height ??
            dimensionsFromAspectRatio(aspectRatio).height,
        width:
            decodedPhoto.width ??
            activePhoto.width ??
            dimensionsFromAspectRatio(aspectRatio).width,
    };
    const firstPhoto = feedPhotos[0]!;
    const firstPhotoAspectRatio =
        firstPhoto.width && firstPhoto.height
            ? firstPhoto.width / firstPhoto.height
            : aspectRatio;
    const frameAspectRatio = Math.max(
        minimumPostPhotoFrameAspectRatio,
        feedPhotos.length > 1
            ? firstPhotoAspectRatio
            : photoDimensions.width / photoDimensions.height,
    );
    const isPhotoReady = Boolean(displayImageUrl) && decodedPhoto.ready;
    const canOpenPhoto =
        !isPostUnavailable && isPhotoReady && Boolean(onOpenPhoto);
    const openPhoto = (focusReplyOnOpen = false, index = photoIndex) => {
        const selectedPhoto = feedPhotos[index]!;
        if (!selectedPhoto.imageUrl || isUnavailable) return;

        onOpenPhoto?.(
            {
                ...selectedPhoto,
                alt: `${name} post`,
                avatarUrl: displayAvatarUrl ?? null,
                caption,
                friendID,
                height:
                    index == photoIndex
                        ? photoDimensions.height
                        : selectedPhoto.height,
                imageUrl: selectedPhoto.imageUrl,
                name,
                postId,
                postPhotoIndex: index,
                postPhotoCount: photoCount,
                spaceId,
                timestampMs,
                username,
                viewerLiked: isLiked,
                width:
                    index == photoIndex
                        ? photoDimensions.width
                        : selectedPhoto.width,
            },
            focusReplyOnOpen,
        );
    };
    const handleLikeClick = () => {
        if (isOwnPost) return;

        const nextLiked = !isLiked;
        setIsLiked(nextLiked);
        if (nextLiked) setLikePopID((id) => id + 1);
        void onSetPostLiked?.(postId, nextLiked).catch((error: unknown) => {
            log.error("Failed to update post like", error);
            setIsLiked(!nextLiked);
        });
    };

    React.useEffect(() => {
        setIsLiked(viewerLiked);
    }, [viewerLiked]);

    React.useEffect(() => {
        if (isPostUnavailable) return;
        if (shouldLoadMedia) return;
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
            { rootMargin: feedMediaLoadRootMargin },
        );
        observer.observe(element);
        return () => observer.disconnect();
    }, [isPostUnavailable, shouldLoadMedia]);

    React.useEffect(() => {
        if (isPostUnavailable) return;
        if (!shouldLoadMedia) return;

        if (isAvatarPending) {
            void onLoadAvatar?.();
        }
    }, [isAvatarPending, isPostUnavailable, onLoadAvatar, shouldLoadMedia]);

    React.useEffect(() => {
        if (!decodedPhoto.failed) return;
        log.warn(
            `Post ${postId} is unavailable because the browser could not decode its image`,
        );
    }, [decodedPhoto.failed, postId]);

    React.useEffect(() => {
        if (likePopID == 0) return;

        const timeoutID = window.setTimeout(
            () => setLikePopID(0),
            spacePostLikePopDurationMs,
        );
        return () => window.clearTimeout(timeoutID);
    }, [likePopID]);

    return (
        <Box
            ref={rootRef}
            component="article"
            sx={{
                bgcolor: showFooter ? spaceSurface : "transparent",
                borderRadius: "16px",
                boxSizing: "border-box",
                display: "flex",
                flexDirection: "column",
                maxWidth: "100%",
                minWidth: 0,
                width: "100%",
            }}
        >
            <Box
                sx={{
                    aspectRatio: frameAspectRatio,
                    bgcolor: "transparent",
                    borderRadius: showFooter ? "16px 16px 0 0" : "16px",
                    maxWidth: "100%",
                    minWidth: 0,
                    overflow: "hidden",
                    position: "relative",
                    transition: "aspect-ratio 220ms ease",
                    width: "100%",
                    "@media (prefers-reduced-motion: reduce)": {
                        transition: "none",
                    },
                }}
            >
                {photoCount > 1 && (
                    <Box
                        sx={{
                            display: "flex",
                            position: "absolute",
                            right: 16,
                            top: 16,
                            zIndex: 3,
                            pointerEvents: "none",
                        }}
                    >
                        <SpacePostPhotosCounter
                            compact
                            index={photoIndex}
                            count={photoCount}
                        />
                    </Box>
                )}
                <Box
                    ref={carouselRef}
                    role={photoCount > 1 ? "group" : undefined}
                    aria-label={photoCount > 1 ? "Post photos" : undefined}
                    onPointerDown={(event) => {
                        suppressPhotoClickRef.current = false;
                        if (
                            !event.isPrimary ||
                            event.button != 0 ||
                            feedPhotos.length < 2
                        )
                            return;
                        const carousel = event.currentTarget;
                        if (photoAnimationRef.current != null) {
                            cancelAnimationFrame(photoAnimationRef.current);
                            photoAnimationRef.current = null;
                        }
                        const index = Math.round(
                            carousel.scrollLeft / carousel.clientWidth,
                        );
                        swipeRef.current = {
                            pointerID: event.pointerId,
                            index,
                            startLeft: carousel.scrollLeft,
                            x: event.clientX,
                            y: event.clientY,
                            dragging: false,
                        };
                    }}
                    onPointerMove={(event) => {
                        const swipe = swipeRef.current;
                        if (swipe?.pointerID != event.pointerId) return;
                        const dx = event.clientX - swipe.x;
                        const dy = event.clientY - swipe.y;
                        if (!swipe.dragging) {
                            if (Math.max(Math.abs(dx), Math.abs(dy)) < 8)
                                return;
                            if (Math.abs(dy) >= Math.abs(dx)) {
                                swipeRef.current = null;
                                scrollToPhoto(swipe.index);
                                return;
                            }
                            swipe.dragging = true;
                            suppressPhotoClickRef.current = true;
                            event.currentTarget.setPointerCapture(
                                event.pointerId,
                            );
                            event.currentTarget.style.scrollSnapType = "none";
                        }
                        const carousel = event.currentTarget;
                        carousel.scrollLeft = Math.max(
                            (swipe.index - 1) * carousel.clientWidth,
                            Math.min(
                                (swipe.index + 1) * carousel.clientWidth,
                                swipe.startLeft - dx,
                            ),
                        );
                    }}
                    onPointerUp={finishPhotoSwipe}
                    onPointerCancel={finishPhotoSwipe}
                    onClickCapture={(event) => {
                        if (!suppressPhotoClickRef.current || event.detail == 0)
                            return;
                        suppressPhotoClickRef.current = false;
                        event.preventDefault();
                        event.stopPropagation();
                    }}
                    onScroll={(event) => {
                        const carousel = event.currentTarget;
                        const index = Math.round(
                            carousel.scrollLeft / carousel.clientWidth,
                        );
                        if (index != photoIndex) onPhotoIndexChange?.(index);
                    }}
                    onKeyDown={(event) => {
                        if (
                            event.key != "ArrowLeft" &&
                            event.key != "ArrowRight"
                        )
                            return;
                        event.preventDefault();
                        const index = Math.max(
                            0,
                            Math.min(
                                photoIndex +
                                    (event.key == "ArrowLeft" ? -1 : 1),
                                feedPhotos.length - 1,
                            ),
                        );
                        (
                            event.currentTarget.children[index] as HTMLElement
                        ).focus({ preventScroll: true });
                        scrollToPhoto(index);
                    }}
                    sx={{
                        display: "flex",
                        height: "100%",
                        overflowX: "hidden",
                        overscrollBehaviorX: "contain",
                        scrollSnapType: "x mandatory",
                        scrollbarWidth: "none",
                        touchAction: "pan-y pinch-zoom",
                        userSelect: "none",
                        "&::-webkit-scrollbar": { display: "none" },
                    }}
                >
                    {feedPhotos.map((photo, index) => (
                        <FeedPhoto
                            key={index}
                            imageUrl={photo.imageUrl}
                            isActive={index == photoIndex}
                            isUnavailable={
                                isUnavailable || Boolean(photo.isUnavailable)
                            }
                            name={name}
                            onLoadImage={
                                onLoadImage
                                    ? () => onLoadImage(index)
                                    : undefined
                            }
                            onOpenPhoto={
                                onOpenPhoto
                                    ? () => openPhoto(false, index)
                                    : undefined
                            }
                            shouldLoad={
                                shouldLoadMedia &&
                                Math.abs(index - photoIndex) <= 1
                            }
                            thumbHash={photo.thumbHash}
                        />
                    ))}
                </Box>
                <Box
                    aria-hidden
                    sx={{
                        background:
                            "linear-gradient(180deg, rgba(0, 0, 0, 0.78), rgba(0, 0, 0, 0))",
                        filter: "blur(12px)",
                        height: 100,
                        left: -12,
                        pointerEvents: "none",
                        position: "absolute",
                        right: -12,
                        top: -12,
                        zIndex: 1,
                    }}
                />
                <Box
                    sx={{
                        alignItems: "center",
                        boxSizing: "border-box",
                        color: "#FFFFFF",
                        display: "grid",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        gap: "8px",
                        gridTemplateColumns: `${feedAvatarSize}px minmax(0, 1fr)`,
                        left: 12,
                        lineHeight: "20px",
                        minHeight: 32,
                        pointerEvents: "none",
                        position: "absolute",
                        right: photoCount > 1 ? 68 : 12,
                        top: 12,
                        zIndex: 2,
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label={authorProfileLabel}
                        onClick={openAuthor}
                        sx={{
                            alignItems: "center",
                            appearance: "none",
                            bgcolor: "transparent",
                            border: 0,
                            borderRadius: "50%",
                            cursor: canOpenAuthor ? "pointer" : "default",
                            display: "flex",
                            flexShrink: 0,
                            height: spaceTouchTargetSize,
                            justifyContent: "center",
                            mx: `${(feedAvatarSize - spaceTouchTargetSize) / 2}px`,
                            overflow: "visible",
                            p: 0,
                            pointerEvents: "auto",
                            position: "relative",
                            width: spaceTouchTargetSize,
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <Box
                            aria-hidden
                            sx={{
                                bgcolor: "rgba(255, 255, 255, 0.2)",
                                borderRadius: "50%",
                                height: feedAvatarSize,
                                width: feedAvatarSize,
                                position: "absolute",
                                zIndex: 0,
                            }}
                        />
                        {isAvatarReady ? (
                            <Box
                                key={displayAvatarUrl ?? "default-avatar"}
                                sx={{
                                    ...avatarFadeSx,
                                    borderRadius: "50%",
                                    height: feedAvatarSize,
                                    overflow: "hidden",
                                    position: "relative",
                                    width: feedAvatarSize,
                                    zIndex: 1,
                                }}
                            >
                                <SpaceAvatarImage
                                    src={displayAvatarUrl}
                                    borderRadius="50%"
                                />
                            </Box>
                        ) : null}
                        <Box
                            aria-hidden
                            sx={{
                                border: "1px solid rgba(255, 255, 255, 0.16)",
                                borderRadius: "50%",
                                boxShadow: "0 1px 4px rgba(0, 0, 0, 0.24)",
                                height: feedAvatarSize,
                                width: feedAvatarSize,
                                pointerEvents: "none",
                                position: "absolute",
                                zIndex: 2,
                            }}
                        />
                    </Box>
                    <Box sx={{ minWidth: 0 }}>
                        <Box
                            component="button"
                            type="button"
                            aria-label={authorProfileLabel}
                            onClick={openAuthor}
                            sx={{
                                appearance: "none",
                                bgcolor: "transparent",
                                border: 0,
                                color: "inherit",
                                cursor: canOpenAuthor ? "pointer" : "default",
                                display: "block",
                                fontFamily: "inherit",
                                fontSize: 14,
                                fontWeight: 650,
                                lineHeight: "18px",
                                maxWidth: "100%",
                                minWidth: 0,
                                overflow: "hidden",
                                p: 0,
                                pointerEvents: "auto",
                                textAlign: "left",
                                textOverflow: "ellipsis",
                                whiteSpace: "nowrap",
                                "&:focus-visible": {
                                    borderRadius: "4px",
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                            }}
                        >
                            {firstName}
                        </Box>
                        {timestampStatus ? (
                            <Box
                                component="span"
                                role="status"
                                aria-label={
                                    timestampStatus == "posting"
                                        ? "Posting"
                                        : timestampStatus == "post-limit"
                                          ? "Post limit reached. Please contact support."
                                          : timestampStatus == "failed"
                                            ? "Failed"
                                            : "Posted"
                                }
                                sx={{
                                    alignItems: "center",
                                    color:
                                        timestampStatus == "failed" ||
                                        timestampStatus == "post-limit"
                                            ? dangerColor
                                            : feedTimestampForeground,
                                    display: "flex",
                                    fontSize: 12,
                                    fontWeight: 500,
                                    lineHeight: "16px",
                                    minHeight: 16,
                                    whiteSpace:
                                        timestampStatus == "post-limit"
                                            ? "normal"
                                            : "nowrap",
                                }}
                            >
                                {timestampStatus == "posted" ? (
                                    <Box component="span">Posted</Box>
                                ) : timestampStatus == "post-limit" ? (
                                    <Box component="span">
                                        Post limit reached. Please contact
                                        support.
                                    </Box>
                                ) : timestampStatus == "failed" ? (
                                    <Box component="span">Failed</Box>
                                ) : (
                                    <>
                                        <Box component="span">Posting</Box>
                                        <Box
                                            component="span"
                                            aria-hidden
                                            sx={{
                                                display: "inline-block",
                                                textAlign: "left",
                                                width: 12,
                                            }}
                                        >
                                            {".".repeat(postingDotCount)}
                                        </Box>
                                    </>
                                )}
                            </Box>
                        ) : (
                            <Box
                                component="time"
                                dateTime={new Date(timestampMs).toISOString()}
                                sx={{
                                    alignItems: "center",
                                    color: feedTimestampForeground,
                                    display: "flex",
                                    fontSize: 12,
                                    fontWeight: 500,
                                    height: 16,
                                    lineHeight: "16px",
                                    whiteSpace: "nowrap",
                                }}
                            >
                                {dateLabel}
                            </Box>
                        )}
                    </Box>
                </Box>
                {(photoCount > 1 || (!isPostUnavailable && displayCaption)) && (
                    <FeedPhotoOverlay
                        caption={isPostUnavailable ? undefined : displayCaption}
                        photoIndex={photoIndex}
                        photoCount={photoCount}
                    />
                )}
            </Box>
            {showFooter && (
                <Box
                    sx={{
                        alignItems: "center",
                        boxSizing: "border-box",
                        display: "grid",
                        gap: "6px",
                        gridTemplateColumns: "minmax(0, 1fr) auto",
                        minHeight: feedLikeActionSize,
                        p: "8px",
                        width: "100%",
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label={`Reply privately to ${firstName}'s post`}
                        disabled={!canOpenPhoto}
                        onClick={() => openPhoto(true)}
                        sx={{
                            appearance: "none",
                            bgcolor: feedActionBackground,
                            border: 0,
                            borderRadius: "12px",
                            color: "#C4C4C8",
                            cursor: canOpenPhoto ? "pointer" : "default",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 500,
                            height: feedLikeActionSize,
                            lineHeight: "20px",
                            minWidth: 0,
                            overflow: "hidden",
                            px: "16px",
                            textAlign: "left",
                            textOverflow: "ellipsis",
                            transition:
                                "background-color 120ms ease, transform 120ms ease",
                            whiteSpace: "nowrap",
                            "&:active": {
                                transform: canOpenPhoto
                                    ? "scale(0.99)"
                                    : undefined,
                            },
                            "&:disabled": { color: textSecondary },
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                            "&:not(:disabled):hover": {
                                bgcolor: spaceControlBackgroundHover,
                                color: textBase,
                            },
                        }}
                    >
                        Reply...
                    </Box>
                    <FeedLikeButton
                        isLiked={isLiked}
                        onClick={handleLikeClick}
                        popID={likePopID}
                    />
                </Box>
            )}
        </Box>
    );
};

const AddedFriendToast: React.FC<AddedFriendToastProps> = ({
    message,
    onClose,
}) => (
    <Box
        sx={{
            boxSizing: "border-box",
            left: "50%",
            px: feedHorizontalPadding,
            pointerEvents: "none",
            position: "fixed",
            top: "calc(env(safe-area-inset-top) + 12px)",
            transform: "translateX(-50%)",
            width: "100%",
            zIndex: 20,
            "@media (min-width: 600px)": { maxWidth: 390 },
        }}
    >
        <Box
            role="status"
            aria-live="polite"
            sx={{
                alignItems: "center",
                bgcolor: spaceSurface,
                borderRadius: "22px",
                boxShadow: "0 12px 32px rgba(0, 0, 0, 0.18)",
                boxSizing: "border-box",
                color: textBase,
                display: "flex",
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 14,
                fontWeight: 650,
                gap: "10px",
                lineHeight: "20px",
                minHeight: spaceTouchTargetSize,
                pointerEvents: "auto",
                pl: "16px",
                pr: "6px",
                py: 0,
                width: "100%",
            }}
        >
            <Box component="span" sx={{ display: "flex", flexShrink: 0 }}>
                <HugeiconsIcon
                    icon={UserAdd02Icon}
                    size={20}
                    strokeWidth={1.8}
                />
            </Box>
            <Box
                component="span"
                sx={{
                    flex: "1 1 auto",
                    minWidth: 0,
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                }}
            >
                {message}
            </Box>
            <Box
                component="button"
                type="button"
                aria-label="Close"
                onClick={onClose}
                sx={{
                    alignItems: "center",
                    appearance: "none",
                    bgcolor: "transparent",
                    border: 0,
                    color: textBase,
                    cursor: onClose ? "pointer" : "default",
                    display: "flex",
                    flexShrink: 0,
                    height: spaceTouchTargetSize,
                    justifyContent: "center",
                    opacity: 0.9,
                    p: 0,
                    width: spaceTouchTargetSize,
                    "&:focus-visible": {
                        outline: `2px solid ${spaceText}`,
                        outlineOffset: 2,
                    },
                }}
            >
                <HugeiconsIcon
                    icon={MultiplicationSignIcon}
                    size={16}
                    strokeWidth={2}
                />
            </Box>
        </Box>
    </Box>
);

const InviteFriendsToast: React.FC<InviteFriendsToastProps> = ({
    profileLink,
    sharing,
    onClose,
    onSharingChange,
}) => (
    <SpaceActionToast
        action={
            <SpaceShareInviteButton
                profileLink={profileLink}
                sharing={sharing}
                variant="toast"
                onShareError={(error) =>
                    log.error("Failed to share space invite", error)
                }
                onSharingChange={onSharingChange}
            />
        }
        animateEntrance
        closeLabel="Close invite prompt"
        icon={
            <HugeiconsIcon icon={UserAdd02Icon} size={20} strokeWidth={1.9} />
        }
        message="Invite your friends"
        onClose={onClose}
    />
);

export const HomeScreen: React.FC<HomeScreenProps> = ({
    feedItems,
    friendRequestSentToastName,
    hasFeedLoadMoreError = false,
    hasMoreFeedItems = false,
    hasUnreadMessages,
    isFeedLoading = false,
    isFeedLoadingMore = false,
    localFeedPosts = [],
    showFirstPostPrompt = false,
    showInstallPrompt = false,
    showInviteFriendsToast = false,
    onAddFriend,
    onPostPhotoSelect,
    onDeletePost,
    onLoadMoreFeedItems,
    onLoadPostAvatar,
    onLoadPostImage,
    onFriendRequestSentToastClose,
    onInviteFriendsToastClose,
    onOpenFriend,
    onOpenMessages,
    onOpenProfile,
    onReplyToPost,
    onSetPostLiked,
    onUpdatePostCaption,
    profile,
    profileLink,
    viewerSpaceId,
}) => {
    const [selectedViewer, setSelectedViewer] =
        useState<SelectedHomeViewer | null>(null);
    const [feedPhotoIndices, setFeedPhotoIndices] = useState<
        Record<number, number>
    >({});
    const [isInviteSharing, setIsInviteSharing] = useState(false);
    const [loadedFeedAvatarURLsByKey, setLoadedFeedAvatarURLsByKey] = useState<
        Record<string, string | null>
    >({});
    const [loadedFeedImageURLsByKey, setLoadedFeedImageURLsByKey] = useState<
        Record<string, string>
    >({});
    const [unavailableFeedPostsByKey, setUnavailableFeedPostsByKey] = useState<
        Record<string, true>
    >({});
    const newestLocalPostID = localFeedPosts[0]?.id;
    const postInputRef = React.useRef<HTMLInputElement | null>(null);
    const feedLoadMoreRef = React.useRef<HTMLDivElement | null>(null);
    const feedAvatarLoadsInFlightRef = React.useRef<
        Map<string, Promise<string | null>>
    >(new Map());
    const feedImageLoadsRef = React.useRef<
        Map<string, Promise<string | undefined>>
    >(new Map());
    const selectedPhotoFriendID = selectedViewer?.photo.friendID;
    const selectedPhotoIsOwn =
        Boolean(viewerSpaceId) && selectedPhotoFriendID == viewerSpaceId;
    const desiredFeedEntries = React.useMemo<HomeFeedEntry[]>(() => {
        const localResolvedPostIds = new Set(
            localFeedPosts
                .filter(
                    (item) => item.status == "posted" || item.status == "ready",
                )
                .map((item) => item.post.postId),
        );
        return [
            ...localFeedPosts.map(
                (item): HomeFeedEntry => ({
                    identity:
                        item.status == "posted" || item.status == "ready"
                            ? `post:${item.post.postId}`
                            : `local:${item.id}`,
                    item,
                    kind: "local",
                    renderKey: `local:${item.id}`,
                }),
            ),
            ...feedItems
                .filter((item) => !localResolvedPostIds.has(item.postId))
                .map(
                    (item): HomeFeedEntry => ({
                        identity: `post:${item.postId}`,
                        item,
                        kind: "remote",
                        renderKey: `post:${item.postId}`,
                    }),
                ),
        ];
    }, [feedItems, localFeedPosts]);
    const hasFeedItems = desiredFeedEntries.length > 0;
    const isEmptyFeedLoading = !hasFeedItems && isFeedLoading;
    const showFeedCards = hasFeedItems;
    const isInstallPromptEnabled =
        showInstallPrompt &&
        !friendRequestSentToastName &&
        !showInviteFriendsToast &&
        !selectedViewer;
    const showUnreadIndicator = hasUnreadMessages === true;
    const openPostPhotoPicker = () => {
        postInputRef.current?.click();
    };
    const openFeedPhoto = (
        post: SpacePost,
        photo: SpaceViewerPhoto,
        focusReplyOnOpen = false,
    ) => {
        const isOwnPost =
            Boolean(viewerSpaceId) && photo.friendID == viewerSpaceId;
        const photoIndex = photo.postPhotoIndex ?? 0;
        const photos = viewerPhotosFromPost({
            ...post,
            avatarUrl: photo.avatarUrl,
            viewerLiked: photo.viewerLiked,
        });
        photos[photoIndex] = { ...photos[photoIndex]!, ...photo };
        setSelectedViewer({
            photoIndex,
            photos,
            focusReplyOnOpen: isOwnPost ? false : focusReplyOnOpen,
            photo,
            postActionMode: isOwnPost ? "hidden" : "like-only",
        });
    };
    const closeSelectedPhoto = () => {
        setSelectedViewer(null);
    };
    const { clearBrowserBackState: clearSelectedPhotoHistory } =
        useBrowserBackClose({
            open: Boolean(selectedViewer),
            onClose: () => {
                closeSelectedPhoto();
            },
            stateKey: "space-feed-viewer",
        });
    const deleteSelectedPost = async () => {
        const postId = selectedViewer?.photo.postId;
        if (!postId || !onDeletePost) return;

        await onDeletePost(postId);
    };
    const loadedFeedImageURLFor = React.useCallback(
        (item: FeedPhotoSource) =>
            item.imageUrl ??
            loadedFeedImageURLsByKey[feedPostImageCacheKey(item)],
        [loadedFeedImageURLsByKey],
    );
    const loadedFeedAvatarURLFor = React.useCallback(
        (item: SpacePost) => {
            if (item.avatarUrl) return item.avatarUrl;
            if (!item.avatarObjectID) return null;
            return loadedFeedAvatarURLsByKey[feedPostAvatarCacheKey(item)];
        },
        [loadedFeedAvatarURLsByKey],
    );
    const loadFeedPostImage = React.useCallback(
        (item: FeedPhotoSource) => {
            const loadedImageUrl = loadedFeedImageURLFor(item);
            if (loadedImageUrl) return Promise.resolve(loadedImageUrl);
            if (!item.imageAsset || !onLoadPostImage) {
                return Promise.resolve(undefined);
            }

            const cacheKey = feedPostImageCacheKey(item);
            if (unavailableFeedPostsByKey[cacheKey]) {
                return Promise.resolve(undefined);
            }
            const existingLoad = feedImageLoadsRef.current.get(cacheKey);
            if (existingLoad) return existingLoad;

            const load = onLoadPostImage(item.imageAsset)
                .then((imageUrl) => {
                    setLoadedFeedImageURLsByKey((currentURLs) =>
                        currentURLs[cacheKey] == imageUrl
                            ? currentURLs
                            : { ...currentURLs, [cacheKey]: imageUrl },
                    );
                    return imageUrl;
                })
                .catch((error: unknown) => {
                    feedImageLoadsRef.current.delete(cacheKey);
                    log.warn("Failed to load feed post image", error);
                    if (isSpaceContentError(error)) {
                        setUnavailableFeedPostsByKey((current) => ({
                            ...current,
                            [cacheKey]: true,
                        }));
                    }
                    return undefined;
                });
            feedImageLoadsRef.current.set(cacheKey, load);
            return load;
        },
        [loadedFeedImageURLFor, onLoadPostImage, unavailableFeedPostsByKey],
    );
    const loadFeedPostAvatar = React.useCallback(
        (item: SpacePost) => {
            const loadedAvatarUrl = loadedFeedAvatarURLFor(item);
            if (loadedAvatarUrl !== undefined) {
                return Promise.resolve(loadedAvatarUrl);
            }
            if (!item.avatarObjectID || !onLoadPostAvatar) {
                return Promise.resolve(null);
            }

            const cacheKey = feedPostAvatarCacheKey(item);
            const inFlight = feedAvatarLoadsInFlightRef.current.get(cacheKey);
            if (inFlight) return inFlight;

            const load = onLoadPostAvatar(item)
                .then((avatarUrl) => {
                    setLoadedFeedAvatarURLsByKey((currentURLs) =>
                        currentURLs[cacheKey] == avatarUrl
                            ? currentURLs
                            : { ...currentURLs, [cacheKey]: avatarUrl },
                    );
                    return avatarUrl;
                })
                .catch((error: unknown) => {
                    log.warn("Failed to load feed avatar", error);
                    setLoadedFeedAvatarURLsByKey((currentURLs) =>
                        currentURLs[cacheKey] === null
                            ? currentURLs
                            : { ...currentURLs, [cacheKey]: null },
                    );
                    return null;
                })
                .finally(() => {
                    feedAvatarLoadsInFlightRef.current.delete(cacheKey);
                });
            feedAvatarLoadsInFlightRef.current.set(cacheKey, load);
            return load;
        },
        [loadedFeedAvatarURLFor, onLoadPostAvatar],
    );
    const feedItemFor = (
        item: SpacePost,
        key: React.Key,
        timestampStatus?: FeedTimestampStatus,
    ) => {
        const postPhotos = spacePostPhotos(item).map((photo, index) => ({
            ...photo,
            postId: item.postId,
            spaceId: item.spaceId,
            imageUrl:
                photo.imageUrl ?? (index == 0 ? item.imageUrl : undefined),
        }));
        const photos = postPhotos.map((photo) => ({
            ...photo,
            imageUrl: loadedFeedImageURLFor(photo),
            isUnavailable: Boolean(
                unavailableFeedPostsByKey[feedPostImageCacheKey(photo)],
            ),
        }));
        const imageUrl = photos[0]?.imageUrl;
        const avatarUrl = loadedFeedAvatarURLFor(item);
        const isAvatarPending = !item.isUnavailable && avatarUrl === undefined;
        const isUnavailable =
            Boolean(item.isUnavailable) ||
            Boolean(unavailableFeedPostsByKey[feedPostImageCacheKey(item)]);
        return (
            <FeedItem
                key={key}
                aspectRatio={
                    item.width && item.height ? item.width / item.height : 1
                }
                avatarUrl={avatarUrl ?? null}
                caption={item.caption}
                friendID={item.friendID}
                imageUrl={imageUrl}
                isAvatarPending={isAvatarPending}
                isOwnPost={
                    Boolean(viewerSpaceId) && item.spaceId == viewerSpaceId
                }
                isUnavailable={isUnavailable}
                name={item.name}
                onLoadAvatar={
                    isAvatarPending && !isUnavailable
                        ? () => loadFeedPostAvatar(item)
                        : undefined
                }
                onLoadImage={(index) => loadFeedPostImage(postPhotos[index]!)}
                onOpenFriend={onOpenFriend}
                onOpenPhoto={(photo, focusReply) =>
                    openFeedPhoto({ ...item, photos }, photo, focusReply)
                }
                onOpenProfile={onOpenProfile}
                onSetPostLiked={onSetPostLiked}
                photos={photos}
                photoCount={photos.length}
                photoIndex={feedPhotoIndices[item.postId] ?? 0}
                onPhotoIndexChange={(index) =>
                    setFeedPhotoIndices((current) => ({
                        ...current,
                        [item.postId]: index,
                    }))
                }
                postId={item.postId}
                spaceId={item.spaceId}
                thumbHash={item.thumbHash}
                timestampStatus={timestampStatus}
                timestampMs={item.timestampMs}
                username={item.username}
                viewerLiked={item.viewerLiked}
            />
        );
    };
    const localFeedItemFor = (item: LocalSpaceFeedPost) => {
        if (item.status == "posted" || item.status == "ready") {
            return feedItemFor(
                item.post,
                item.id,
                item.status == "posted" ? "posted" : undefined,
            );
        }

        return (
            <FeedItem
                key={item.id}
                aspectRatio={
                    item.width && item.height ? item.width / item.height : 1
                }
                avatarUrl={item.avatarUrl ?? null}
                caption={item.caption}
                friendID={item.friendID}
                imageUrl={item.imageUrl}
                isAvatarPending={false}
                isOwnPost
                name={item.name}
                onOpenProfile={onOpenProfile}
                photoCount={item.photoCount}
                postId={0}
                timestampStatus={
                    item.status == "failed"
                        ? item.reason == "post-limit"
                            ? "post-limit"
                            : "failed"
                        : "posting"
                }
                timestampMs={item.timestampMs}
                viewerLiked={false}
            />
        );
    };

    React.useEffect(() => {
        if (!newestLocalPostID) return;

        return scheduleScrollPageToTop();
    }, [newestLocalPostID]);

    React.useEffect(() => {
        if (
            hasFeedLoadMoreError ||
            !hasMoreFeedItems ||
            isFeedLoadingMore ||
            !onLoadMoreFeedItems
        ) {
            return;
        }

        const element = feedLoadMoreRef.current;
        if (!element) return;

        let didRequestLoad = false;
        const loadMore = () => {
            if (didRequestLoad) return;

            didRequestLoad = true;
            void Promise.resolve(onLoadMoreFeedItems()).catch(
                (error: unknown) => {
                    log.error("Failed to load more space feed", error);
                },
            );
        };

        if (
            typeof window == "undefined" ||
            !("IntersectionObserver" in window)
        ) {
            loadMore();
            return;
        }

        const observer = new IntersectionObserver(
            (entries) => {
                if (entries.some((entry) => entry.isIntersecting)) loadMore();
            },
            { rootMargin: feedLoadMoreRootMargin },
        );
        observer.observe(element);
        return () => observer.disconnect();
    }, [
        hasFeedLoadMoreError,
        hasMoreFeedItems,
        isFeedLoadingMore,
        onLoadMoreFeedItems,
    ]);

    return (
        <Box
            component="main"
            sx={{
                bgcolor: homeBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
                position: "relative",
            }}
        >
            <SpaceSkipLink />
            {hasFeedItems && (
                <Box component="h1" sx={visuallyHidden}>
                    Home
                </Box>
            )}
            <Box
                sx={{
                    bgcolor: homeBackground,
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
                    <SpacePostPhotoInput
                        inputRef={postInputRef}
                        onSelect={onPostPhotoSelect}
                    />
                </SpaceHomeHeader>
                <Box
                    component="section"
                    id="space-main-content"
                    aria-label="Feed"
                    tabIndex={-1}
                    sx={{
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: 0,
                        justifyContent: showFeedCards ? "flex-start" : "center",
                        minHeight: "calc(100svh - 64px)",
                        minWidth: 0,
                        pb: "calc(env(safe-area-inset-bottom) + 112px)",
                        px: feedHorizontalPadding,
                        pt: showFeedCards ? "16px" : "8px",
                        width: "100%",
                    }}
                >
                    {hasFeedItems ? (
                        <>
                            <FeedMotionList
                                entries={desiredFeedEntries}
                                renderEntry={(entry) =>
                                    entry.kind == "local"
                                        ? localFeedItemFor(entry.item)
                                        : feedItemFor(
                                              entry.item,
                                              entry.item.postId,
                                          )
                                }
                            />
                            {hasMoreFeedItems && onLoadMoreFeedItems && (
                                <Box
                                    ref={feedLoadMoreRef}
                                    aria-live="polite"
                                    sx={{
                                        alignItems: "center",
                                        alignSelf: "center",
                                        display: "flex",
                                        height: 48,
                                        justifyContent: "center",
                                        mb: 0,
                                        mt: "12px",
                                        width: "100%",
                                    }}
                                >
                                    {hasFeedLoadMoreError ? (
                                        <Box
                                            component="button"
                                            type="button"
                                            aria-label="Retry loading posts"
                                            onClick={onLoadMoreFeedItems}
                                            sx={{
                                                alignItems: "center",
                                                appearance: "none",
                                                bgcolor: spaceControlBackground,
                                                border: 0,
                                                borderRadius: "18px",
                                                color: "#DEDEDE",
                                                cursor: "pointer",
                                                display: "inline-flex",
                                                fontFamily:
                                                    '"Inter Variable", Inter, sans-serif',
                                                fontSize: 13,
                                                fontWeight: 600,
                                                height: spaceTouchTargetSize,
                                                justifyContent: "center",
                                                lineHeight: "18px",
                                                minWidth: 116,
                                                px: "18px",
                                                whiteSpace: "nowrap",
                                                "&:focus-visible": {
                                                    outline: `2px solid ${green}`,
                                                    outlineOffset: 2,
                                                },
                                                "&:hover": {
                                                    bgcolor:
                                                        spaceControlBackgroundHover,
                                                },
                                            }}
                                        >
                                            Retry
                                        </Box>
                                    ) : (
                                        <SpaceLoadingSpinner
                                            ariaLabel="Loading more posts"
                                            size={22}
                                        />
                                    )}
                                </Box>
                            )}
                        </>
                    ) : isEmptyFeedLoading ? (
                        <Box
                            sx={{
                                alignItems: "center",
                                display: "flex",
                                justifyContent: "center",
                                width: "100%",
                            }}
                        >
                            <SpaceLoadingSpinner ariaLabel="Loading posts" />
                        </Box>
                    ) : (
                        <Box
                            className="green-bg"
                            sx={{
                                alignItems: "center",
                                bgcolor: green,
                                borderRadius: "24px",
                                boxSizing: "border-box",
                                color: "#FFFFFF",
                                display: "flex",
                                flexDirection: "column",
                                height: "calc(100svh - 184px - env(safe-area-inset-bottom))",
                                minHeight: 360,
                                overflow: "hidden",
                                px: "24px",
                                pt: "72px",
                                pb: "16px",
                                textAlign: "center",
                                width: "100%",
                                "@media (max-height: 720px)": { pt: "32px" },
                            }}
                        >
                            <Box
                                component="h1"
                                sx={{
                                    fontFamily:
                                        '"Nunito", "Inter Variable", sans-serif',
                                    fontSize: 25,
                                    fontWeight: 800,
                                    lineHeight: "30px",
                                    m: 0,
                                    maxWidth: 260,
                                    textWrap: "balance",
                                }}
                            >
                                Invite your friends and family
                            </Box>
                            <Box
                                component="p"
                                sx={{
                                    color: "rgba(255, 255, 255, 0.84)",
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 15,
                                    fontWeight: 500,
                                    lineHeight: "21px",
                                    m: 0,
                                    mt: "10px",
                                    maxWidth: 250,
                                    textWrap: "balance",
                                }}
                            >
                                Keep up with each other through
                                <br />
                                everyday photos.
                            </Box>
                            <Box
                                component="button"
                                type="button"
                                aria-haspopup="dialog"
                                disabled={!profile}
                                onClick={onAddFriend}
                                sx={{
                                    ...spaceEmptyStateButtonSx,
                                    bgcolor: "#FFFFFF",
                                    color: homeBackground,
                                    flexShrink: 0,
                                    mt: "24px",
                                    "&:focus-visible": {
                                        outline: `2px solid ${textBase}`,
                                        outlineOffset: 2,
                                    },
                                    "&:hover:not(:disabled)": {
                                        bgcolor: textBase,
                                    },
                                }}
                            >
                                <HugeiconsIcon
                                    icon={UserAdd02Icon}
                                    size={18}
                                    strokeWidth={1.8}
                                />
                                Add friend
                            </Box>
                            <Box sx={{ flexGrow: 1, minHeight: "32px" }} />
                            <Box
                                component="img"
                                alt=""
                                src="/images/ducky-space.svg"
                                sx={{
                                    display: "block",
                                    height: "auto",
                                    maxWidth: 300,
                                    minHeight: 0,
                                    objectFit: "contain",
                                    width: "100%",
                                    "@media (max-height: 720px)": {
                                        maxWidth: 228,
                                    },
                                }}
                            />
                        </Box>
                    )}
                </Box>
                <SpaceFeedPostButton
                    onClick={openPostPhotoPicker}
                    showFirstPostPrompt={showFirstPostPrompt}
                />
                {selectedViewer && (
                    <SpaceFileViewer
                        closeOnSwipePastEnd
                        focusReplyOnOpen={selectedViewer.focusReplyOnOpen}
                        photo={selectedViewer.photo}
                        photos={selectedViewer.photos}
                        photoIndex={selectedViewer.photoIndex}
                        onPhotoIndexChange={(index) => {
                            setSelectedViewer((current) =>
                                current
                                    ? { ...current, photoIndex: index }
                                    : null,
                            );
                            setFeedPhotoIndices((current) => ({
                                ...current,
                                [selectedViewer.photo.postId!]: index,
                            }));
                        }}
                        onLoadPhoto={onLoadPostImage}
                        postActionMode={selectedViewer.postActionMode}
                        onClose={closeSelectedPhoto}
                        onOpenProfile={
                            selectedPhotoIsOwn && onOpenProfile
                                ? () => {
                                      void clearSelectedPhotoHistory(
                                          "back",
                                      ).finally(() => {
                                          closeSelectedPhoto();
                                          onOpenProfile();
                                      });
                                  }
                                : selectedPhotoFriendID && onOpenFriend
                                  ? () => {
                                        void clearSelectedPhotoHistory(
                                            "back",
                                        ).finally(() => {
                                            closeSelectedPhoto();
                                            onOpenFriend(
                                                selectedPhotoFriendID,
                                                selectedViewer.photo.username,
                                            );
                                        });
                                    }
                                  : undefined
                        }
                        onReplyToPost={
                            !selectedPhotoIsOwn &&
                            selectedViewer.photo.friendID != viewerSpaceId
                                ? onReplyToPost
                                : undefined
                        }
                        onDeletePost={
                            selectedPhotoIsOwn &&
                            selectedViewer.photo.postId &&
                            onDeletePost
                                ? deleteSelectedPost
                                : undefined
                        }
                        onSetPostLiked={onSetPostLiked}
                        onUpdatePostCaption={
                            selectedPhotoIsOwn ? onUpdatePostCaption : undefined
                        }
                    />
                )}
                {friendRequestSentToastName ? (
                    <AddedFriendToast
                        message={`Friend request sent to @${friendRequestSentToastName}`}
                        onClose={onFriendRequestSentToastClose}
                    />
                ) : showInviteFriendsToast ? (
                    <InviteFriendsToast
                        profileLink={profileLink}
                        sharing={isInviteSharing}
                        onClose={onInviteFriendsToastClose}
                        onSharingChange={setIsInviteSharing}
                    />
                ) : (
                    <SpacePWAInstallPrompt enabled={isInstallPromptEnabled} />
                )}
            </Box>
        </Box>
    );
};
