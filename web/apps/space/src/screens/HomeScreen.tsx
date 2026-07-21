import {
    BubbleChatIcon,
    FavouriteIcon,
    MultiplicationSignIcon,
    UserAdd02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Skeleton } from "@mui/material";
import { SpaceAvatarImage } from "components/SpaceAvatarImage";
import {
    SpaceFileViewer,
    SpaceViewerFeedBackdrop,
    type SpaceViewerDraftPostEdit,
    type SpaceViewerPhoto,
    type SpaceViewerPostActionMode,
} from "components/SpaceFileViewer";
import { SpacePostFloatingActionButton } from "components/SpacePostFloatingActionButton";
import {
    spacePostLikeButtonPop,
    spacePostLikeHeartPop,
    spacePostLikePopDurationMs,
    spacePostLikePopTiming,
} from "components/SpacePostLikeAnimation";
import { SpacePWAInstallPrompt } from "components/SpacePWAInstallPrompt";
import { SpaceLoadingSpinner } from "components/SpaceRouteFallback";
import { SpaceShareInviteButton } from "components/SpaceShareInviteButton";
import { useBrowserBackClose } from "hooks/useBrowserBackClose";
import React, { useState } from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";
import type {
    SpacePost,
    SpacePostAssetURLLoader,
    SpacePostAvatarURLLoader,
} from "services/space";
import type { LocalSpaceFeedPost } from "state/spaceAppState";
import { spaceTouchTargetSize } from "styles/touchTargets";
import { createLoadedLocalPostPhoto } from "utils/localPostPhoto";
import { firstNameFrom, formatSpaceDate } from "utils/spaceDisplay";
import {
    canPreviewSpaceImageFile,
    spacePostImageErrorMessage,
    spacePostImageInputAccept,
    spacePostPreviewImageForFile,
} from "utils/spacePostImage";
import { thumbHashDataURLFromBase64 } from "utils/thumbhash";

export const homeBackground = "#F5F5F7";

const green = "#08C225";
const paleGreen = "#E7F6E9";
const feedCardBackground = "#FFFFFF";
const feedActionBackground = "#F7F7F7";
const feedActionBackgroundHover = "#EFEFEF";
const feedSkeletonElementBackground = "#E6E6E6";
const textBase = "#000";
const textSecondary = "#6B6B6B";
const dangerColor = "#F63A3A";
const headerActionSize = spaceTouchTargetSize;
const headerAvatarSize = 28;
const feedAvatarSize = 38;
const headerHeight = 64;
const headerIconSize = 30;
const headerHideStartY = 96;
const headerScrollDelta = 4;
const headerSideWidth = 32;
const feedLikeActionSize = spaceTouchTargetSize;
const feedActionIconSize = 20;
const feedReplyIconSize = 17;
const emptyFeedItemGap = "22px";
const feedHorizontalPadding = "16px";
const minimumFeedPhotoFrameAspectRatio = 3 / 4;
const feedMediaLoadRootMargin = "640px 0px";
const feedLoadMoreRootMargin = "0px 0px 160px 0px";
const feedCaptionTextSx = {
    color: textBase,
    fontFamily: '"Inter Variable", Inter, sans-serif',
    fontSize: 13,
    fontWeight: 600,
    lineHeight: "18px",
    m: 0,
    minWidth: 0,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
};

const FeedReplyIcon: React.FC = () => (
    <svg
        width={feedReplyIconSize}
        height={feedReplyIconSize}
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

interface HomeScreenProps {
    feedItems: SpacePost[];
    friendRequestSentToastName?: string;
    friendsCount: number;
    hasFeedLoadMoreError?: boolean;
    hasMoreFeedItems?: boolean;
    hasUnreadMessages?: boolean;
    isFeedLoading?: boolean;
    isFeedLoadingMore?: boolean;
    isFriendsLoading?: boolean;
    localFeedPosts?: LocalSpaceFeedPost[];
    showInstallPrompt?: boolean;
    onCreatePost?: (
        image: DraftSpacePostImage,
        caption: string,
    ) => Promise<void>;
    onDeletePost?: (postId: number) => Promise<void> | void;
    onLoadMoreFeedItems?: () => Promise<void> | void;
    onLoadPostAvatar?: SpacePostAvatarURLLoader;
    onLoadPostImage?: SpacePostAssetURLLoader;
    onFriendRequestSentToastClose?: () => void;
    onOpenFriend?: (friendID: string) => void;
    onOpenMessages?: () => void;
    onOpenProfile?: () => void;
    onReplyToPost?: (
        postSpaceId: string,
        postId: number,
        text: string,
    ) => Promise<void>;
    onSetPostLiked?: (postId: number, liked: boolean) => Promise<void>;
    profileLink?: string;
    profile: SetupProfile | null;
}

interface FeedPhotoDimensions {
    height: number;
    width: number;
}

interface LoadedFeedPhotoDimensions extends FeedPhotoDimensions {
    src: string;
}

interface DecodedImageState {
    height?: number;
    ready: boolean;
    src?: string | null;
    width?: number;
}

interface SelectedHomeViewer {
    draftFile?: File;
    draftImageError?: string;
    focusReplyOnOpen?: boolean;
    isDraftImagePreviewPending?: boolean;
    localObjectUrl?: string;
    photo: SpaceViewerPhoto;
    postActionMode?: SpaceViewerPostActionMode;
}

interface DraftSpacePostImage {
    cropArea?: SpaceViewerDraftPostEdit["cropArea"];
    file: File;
    height?: number;
    previewUrl?: string;
    rotationDegrees?: number;
    width?: number;
}

type FeedTimestampStatus = "failed" | "post-limit" | "posted" | "posting";

interface FeedItemProps {
    aspectRatio: number;
    avatarUrl: string | null;
    caption?: string;
    friendID: string;
    imageUrl?: string;
    isAvatarPending: boolean;
    isOwnPost: boolean;
    name: string;
    onLoadAvatar?: () => Promise<string | null | undefined>;
    onLoadImage?: () => Promise<string | undefined>;
    onOpenFriend?: (friendID: string) => void;
    onOpenPhoto?: (photo: SpaceViewerPhoto, focusReplyOnOpen?: boolean) => void;
    onOpenProfile?: () => void;
    onSetPostLiked?: (postId: number, liked: boolean) => Promise<void>;
    postId: number;
    spaceId?: string;
    thumbHash?: string;
    timestampStatus?: FeedTimestampStatus;
    timestampMs: number;
    viewerLiked: boolean;
}

interface FeedSkeletonItemProps {
    aspectRatio: string;
    isOwnPost?: boolean;
    pb?: string;
    rootRef?: React.Ref<HTMLElement>;
    showFooter?: boolean;
    thumbHashDataURL?: string;
}

interface AddedFriendToastProps {
    message: string;
    onClose?: () => void;
}

const dimensionsFromAspectRatio = (
    aspectRatio: number,
): FeedPhotoDimensions => {
    const safeAspectRatio =
        Number.isFinite(aspectRatio) && aspectRatio > 0 ? aspectRatio : 1;
    const height = 1000;

    return { height, width: Math.round(safeAspectRatio * height) };
};

const feedPhotoFrameDimensionsFor = (
    dimensions: FeedPhotoDimensions,
): FeedPhotoDimensions =>
    dimensions.width / dimensions.height < minimumFeedPhotoFrameAspectRatio
        ? { height: 4, width: 3 }
        : dimensions;

const feedPostImageCacheKey = (item: SpacePost) =>
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
        const decodeLoadedImage = () => {
            if (typeof image.decode != "function") {
                finish();
                return;
            }

            void image.decode().then(finish, finish);
        };

        setState((currentState) =>
            keepPreviousUntilReady && currentState.ready && currentState.src
                ? currentState
                : { ready: false, src },
        );
        image.addEventListener("load", decodeLoadedImage, { once: true });
        image.addEventListener("error", finish, { once: true });
        image.src = src;
        if (image.complete) decodeLoadedImage();

        return () => {
            cancelled = true;
            image.removeEventListener("load", decodeLoadedImage);
            image.removeEventListener("error", finish);
        };
    }, [keepPreviousUntilReady, src]);

    if (state.src == src) return state;
    if (keepPreviousUntilReady && src && state.ready && state.src) return state;
    return { ready: !src, src };
};

const pageScrollY = () =>
    Math.max(
        0,
        window.scrollY ||
            document.scrollingElement?.scrollTop ||
            document.documentElement.scrollTop ||
            document.body.scrollTop ||
            0,
    );

const scrollPageToTop = () => {
    const scrollOptions: ScrollToOptions = { behavior: "auto", top: 0 };
    document.scrollingElement?.scrollTo(scrollOptions);
    window.scrollTo(scrollOptions);
};

const scheduleScrollPageToTop = () => {
    const timeoutID = window.setTimeout(scrollPageToTop, 0);
    return () => window.clearTimeout(timeoutID);
};

const useHideHeaderOnScrollDirection = () => {
    const [isHidden, setIsHidden] = useState(false);
    const lastScrollYRef = React.useRef(0);
    const frameRef = React.useRef<number | null>(null);

    React.useEffect(() => {
        lastScrollYRef.current = pageScrollY();

        const updateVisibility = () => {
            frameRef.current = null;
            const nextScrollY = pageScrollY();
            const delta = nextScrollY - lastScrollYRef.current;
            lastScrollYRef.current = nextScrollY;

            if (nextScrollY <= headerHideStartY) {
                setIsHidden(false);
                return;
            }

            if (delta > headerScrollDelta) {
                setIsHidden(true);
                return;
            }

            if (delta < -1) setIsHidden(false);
        };

        const scheduleUpdate = () => {
            if (frameRef.current != null) return;
            frameRef.current = window.requestAnimationFrame(updateVisibility);
        };

        window.addEventListener("scroll", scheduleUpdate, { passive: true });
        document.addEventListener("scroll", scheduleUpdate, { passive: true });
        return () => {
            window.removeEventListener("scroll", scheduleUpdate);
            document.removeEventListener("scroll", scheduleUpdate);
            if (frameRef.current != null) {
                window.cancelAnimationFrame(frameRef.current);
            }
        };
    }, []);

    return isHidden;
};

const FeedSkeletonItem: React.FC<FeedSkeletonItemProps> = ({
    aspectRatio,
    isOwnPost = false,
    pb = "8px",
    rootRef,
    showFooter = true,
    thumbHashDataURL,
}) => (
    <Box
        ref={rootRef}
        component="article"
        aria-hidden
        sx={{
            bgcolor: feedCardBackground,
            borderRadius: "17px",
            boxSizing: "border-box",
            display: "flex",
            flexDirection: "column",
            maxWidth: "100%",
            minWidth: 0,
            overflow: "hidden",
            pb,
            pl: "5px",
            pr: "5px",
            pt: "5px",
            width: "100%",
        }}
    >
        <Box
            sx={{
                aspectRatio,
                borderRadius: "13px",
                maxWidth: "100%",
                minWidth: 0,
                overflow: "hidden",
                position: "relative",
                width: "100%",
            }}
        >
            {thumbHashDataURL ? (
                <Box
                    component="img"
                    alt=""
                    aria-hidden
                    src={thumbHashDataURL}
                    sx={{
                        display: "block",
                        filter: "blur(14px)",
                        height: "100%",
                        objectFit: "cover",
                        objectPosition: "center",
                        transform: "scale(1.08)",
                        width: "100%",
                    }}
                />
            ) : (
                <Skeleton
                    variant="rectangular"
                    sx={{
                        aspectRatio,
                        bgcolor: feedSkeletonElementBackground,
                        display: "block",
                        height: "100%",
                        transform: "none",
                        width: "100%",
                    }}
                />
            )}
            <Box
                sx={{
                    alignItems: "center",
                    display: "grid",
                    gap: "8px",
                    gridTemplateColumns: `${feedAvatarSize}px minmax(0, 1fr)`,
                    left: 12,
                    position: "absolute",
                    right: 12,
                    top: 12,
                }}
            >
                <Skeleton
                    variant="circular"
                    sx={{
                        bgcolor: "rgba(255, 255, 255, 0.72)",
                        height: feedAvatarSize,
                        transform: "none",
                        width: feedAvatarSize,
                    }}
                />
                <Box sx={{ minWidth: 0 }}>
                    <Skeleton
                        variant="rectangular"
                        sx={{
                            bgcolor: "rgba(255, 255, 255, 0.72)",
                            borderRadius: "999px",
                            height: 10,
                            mb: "5px",
                            transform: "none",
                            width: 72,
                        }}
                    />
                    <Skeleton
                        variant="rectangular"
                        sx={{
                            bgcolor: "rgba(255, 255, 255, 0.56)",
                            borderRadius: "999px",
                            height: 8,
                            transform: "none",
                            width: 42,
                        }}
                    />
                </Box>
            </Box>
        </Box>
        {showFooter && (
            <Box
                sx={{
                    alignItems: "center",
                    boxSizing: "border-box",
                    display: "grid",
                    gap: "8px",
                    gridTemplateColumns: isOwnPost
                        ? "minmax(0, 1fr)"
                        : "minmax(0, 1fr) auto",
                    minHeight: feedLikeActionSize,
                    mt: "8px",
                    pl: "9px",
                    width: "100%",
                }}
            >
                <Skeleton
                    variant="rectangular"
                    sx={{
                        bgcolor: feedActionBackground,
                        borderRadius: "999px",
                        height: 12,
                        maxWidth: 176,
                        transform: "none",
                        width: "60%",
                    }}
                />
                {!isOwnPost && (
                    <Box
                        sx={{
                            alignItems: "center",
                            display: "flex",
                            gap: "6px",
                            justifyContent: "flex-end",
                        }}
                    >
                        <Skeleton
                            variant="circular"
                            sx={{
                                bgcolor: feedActionBackground,
                                height: feedLikeActionSize,
                                transform: "none",
                                width: feedLikeActionSize,
                            }}
                        />
                        <Skeleton
                            variant="circular"
                            sx={{
                                bgcolor: feedActionBackground,
                                height: feedLikeActionSize,
                                mr: "9px",
                                transform: "none",
                                width: feedLikeActionSize,
                            }}
                        />
                    </Box>
                )}
            </Box>
        )}
    </Box>
);

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
            aria-label={isLiked ? "Unlike post" : "Like post"}
            aria-pressed={isLiked}
            onClick={onClick}
            sx={{
                alignItems: "center",
                animation: isPopping
                    ? `${spacePostLikeButtonPop} ${spacePostLikePopDurationMs}ms ${spacePostLikePopTiming} both`
                    : undefined,
                appearance: "none",
                bgcolor: isLiked ? paleGreen : feedActionBackground,
                border: 0,
                borderRadius: "50%",
                color: isLiked ? green : textBase,
                cursor: "pointer",
                display: "inline-flex",
                flexShrink: 0,
                height: feedLikeActionSize,
                justifyContent: "center",
                mr: "9px",
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
                    bgcolor: isLiked ? "#DFF3E2" : feedActionBackgroundHover,
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
                    primaryColor={isLiked ? green : textBase}
                    size={feedActionIconSize}
                    strokeWidth={2}
                />
            </Box>
        </Box>
    );
};

const FeedItem: React.FC<FeedItemProps> = ({
    aspectRatio,
    avatarUrl,
    caption,
    friendID,
    imageUrl,
    isAvatarPending,
    isOwnPost,
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
    viewerLiked,
}) => {
    const [isLiked, setIsLiked] = useState(viewerLiked);
    const [likePopID, setLikePopID] = useState(0);
    const [shouldLoadMedia, setShouldLoadMedia] = useState(
        Boolean(imageUrl) && !isAvatarPending,
    );
    const rootRef = React.useRef<HTMLElement | null>(null);
    const firstName = firstNameFrom(name);
    const dateLabel = formatSpaceDate(timestampMs);
    const postingDotCount = usePostingDotCount(timestampStatus == "posting");
    const displayCaption = caption?.trim();
    const thumbHashDataURL = React.useMemo(
        () => thumbHashDataURLFromBase64(thumbHash),
        [thumbHash],
    );
    const showFooter = !isOwnPost || Boolean(displayCaption);
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
        onOpenFriend?.(friendID);
    };
    const [loadedPhotoDimensions, setLoadedPhotoDimensions] =
        useState<LoadedFeedPhotoDimensions | null>(null);
    const decodedPhoto = useDecodedImage(imageUrl, true);
    const decodedAvatar = useDecodedImage(avatarUrl, true);
    const displayImageUrl =
        (decodedPhoto.ready ? decodedPhoto.src : imageUrl) ?? undefined;
    const displayAvatarUrl =
        (decodedAvatar.ready ? decodedAvatar.src : avatarUrl) ?? undefined;
    const isAvatarReady = !isAvatarPending && decodedAvatar.ready;
    const photoDimensions =
        loadedPhotoDimensions && loadedPhotoDimensions.src == displayImageUrl
            ? loadedPhotoDimensions
            : dimensionsFromAspectRatio(aspectRatio);
    const feedPhotoFrameDimensions =
        feedPhotoFrameDimensionsFor(photoDimensions);
    const isFeedItemReady =
        Boolean(displayImageUrl) && decodedPhoto.ready && isAvatarReady;
    const [showResolvedPhoto, setShowResolvedPhoto] = useState(false);
    const decodedPhotoHeight = decodedPhoto.height;
    const decodedPhotoSrc = decodedPhoto.src;
    const decodedPhotoWidth = decodedPhoto.width;
    const rememberLoadedPhotoDimensions: React.ReactEventHandler<
        HTMLImageElement
    > = ({ currentTarget }) => {
        if (!displayImageUrl) return;
        const { naturalHeight, naturalWidth } = currentTarget;
        if (!naturalHeight || !naturalWidth) return;

        setLoadedPhotoDimensions((currentDimensions) => {
            if (
                currentDimensions?.height == naturalHeight &&
                currentDimensions.src == displayImageUrl &&
                currentDimensions.width == naturalWidth
            ) {
                return currentDimensions;
            }

            return {
                height: naturalHeight,
                src: displayImageUrl,
                width: naturalWidth,
            };
        });
    };
    const openPhoto = (focusReplyOnOpen = false) => {
        if (!displayImageUrl) return;

        onOpenPhoto?.(
            {
                alt: `${name} post`,
                avatarUrl: displayAvatarUrl ?? null,
                caption,
                friendID,
                height: photoDimensions.height,
                imageUrl: displayImageUrl,
                name,
                postId,
                spaceId,
                timestampMs,
                viewerLiked: isLiked,
                width: photoDimensions.width,
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
            console.error("Failed to update post like", error);
            setIsLiked(!nextLiked);
        });
    };

    React.useEffect(() => {
        setIsLiked(viewerLiked);
    }, [viewerLiked]);

    React.useEffect(() => {
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
    }, [shouldLoadMedia]);

    React.useEffect(() => {
        if (!shouldLoadMedia) return;

        if (!imageUrl) {
            void onLoadImage?.();
        }
        if (isAvatarPending) {
            void onLoadAvatar?.();
        }
    }, [imageUrl, isAvatarPending, onLoadAvatar, onLoadImage, shouldLoadMedia]);

    React.useEffect(() => {
        if (!decodedPhotoHeight || !decodedPhotoWidth) return;
        if (!decodedPhotoSrc) return;

        setLoadedPhotoDimensions((currentDimensions) => {
            if (
                currentDimensions?.height == decodedPhotoHeight &&
                currentDimensions.src == decodedPhotoSrc &&
                currentDimensions.width == decodedPhotoWidth
            ) {
                return currentDimensions;
            }

            return {
                height: decodedPhotoHeight,
                src: decodedPhotoSrc,
                width: decodedPhotoWidth,
            };
        });
    }, [decodedPhotoHeight, decodedPhotoSrc, decodedPhotoWidth]);

    React.useEffect(() => {
        if (likePopID == 0) return;

        const timeoutID = window.setTimeout(
            () => setLikePopID(0),
            spacePostLikePopDurationMs,
        );
        return () => window.clearTimeout(timeoutID);
    }, [likePopID]);

    React.useEffect(() => {
        setShowResolvedPhoto(false);
        if (!isFeedItemReady) return;
        if (!thumbHashDataURL) {
            setShowResolvedPhoto(true);
            return;
        }

        const frameID = window.requestAnimationFrame(() =>
            setShowResolvedPhoto(true),
        );
        return () => window.cancelAnimationFrame(frameID);
    }, [displayImageUrl, isFeedItemReady, thumbHashDataURL]);

    if (!isFeedItemReady) {
        return (
            <FeedSkeletonItem
                aspectRatio={`${feedPhotoFrameDimensions.width} / ${feedPhotoFrameDimensions.height}`}
                isOwnPost={isOwnPost}
                pb={isOwnPost ? "5px" : "8px"}
                rootRef={rootRef}
                showFooter={showFooter}
                thumbHashDataURL={thumbHashDataURL}
            />
        );
    }

    return (
        <Box
            ref={rootRef}
            component="article"
            sx={{
                bgcolor: feedCardBackground,
                borderRadius: "17px",
                boxSizing: "border-box",
                display: "flex",
                flexDirection: "column",
                maxWidth: "100%",
                minWidth: 0,
                overflow: "hidden",
                pl: "5px",
                pb: isOwnPost ? "5px" : "8px",
                pr: "5px",
                pt: "5px",
                width: "100%",
            }}
        >
            <Box
                sx={{
                    aspectRatio: `${feedPhotoFrameDimensions.width} / ${feedPhotoFrameDimensions.height}`,
                    bgcolor: "transparent",
                    borderRadius: "13px",
                    maxWidth: "100%",
                    minWidth: 0,
                    overflow: "hidden",
                    position: "relative",
                    width: "100%",
                }}
            >
                <Box
                    component="button"
                    type="button"
                    aria-label={`Open ${name} photo`}
                    onClick={() => openPhoto()}
                    sx={{
                        appearance: "none",
                        bgcolor: "transparent",
                        border: 0,
                        cursor: onOpenPhoto ? "pointer" : "default",
                        display: "block",
                        height: "100%",
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
                    {thumbHashDataURL ? (
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
                    <Box
                        component="img"
                        alt={`${name} post`}
                        src={displayImageUrl}
                        onLoad={rememberLoadedPhotoDimensions}
                        sx={{
                            display: "block",
                            height: "100%",
                            maxWidth: "100%",
                            minWidth: 0,
                            objectFit: "cover",
                            objectPosition: "center",
                            opacity: showResolvedPhoto ? 1 : 0,
                            position: "relative",
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
                </Box>
                <Box
                    aria-hidden
                    sx={{
                        background:
                            "linear-gradient(180deg, rgba(0, 0, 0, 0.62) 0%, rgba(0, 0, 0, 0.48) 24%, rgba(0, 0, 0, 0.3) 48%, rgba(0, 0, 0, 0.14) 72%, rgba(0, 0, 0, 0) 100%)",
                        height: 72,
                        left: 0,
                        pointerEvents: "none",
                        position: "absolute",
                        right: 0,
                        top: 0,
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
                        right: 12,
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
                            bgcolor: feedSkeletonElementBackground,
                            border: 0,
                            borderRadius: "50%",
                            cursor: canOpenAuthor ? "pointer" : "default",
                            display: "flex",
                            flexShrink: 0,
                            height: feedAvatarSize,
                            justifyContent: "center",
                            overflow: "visible",
                            p: 0,
                            pointerEvents: "auto",
                            position: "relative",
                            width: feedAvatarSize,
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <SpaceAvatarImage
                            src={displayAvatarUrl}
                            borderRadius="50%"
                        />
                        <Box
                            aria-hidden
                            sx={{
                                border: "2px solid rgba(255, 255, 255, 0.35)",
                                borderRadius: "50%",
                                inset: -2,
                                pointerEvents: "none",
                                position: "absolute",
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
                                            : "rgba(255, 255, 255, 0.86)",
                                    display: "flex",
                                    fontSize: 12,
                                    fontWeight: 500,
                                    height: 16,
                                    lineHeight: "16px",
                                    minWidth: "10ch",
                                    whiteSpace: "nowrap",
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
                                    color: "rgba(255, 255, 255, 0.86)",
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
            </Box>
            {showFooter && (
                <Box
                    sx={{
                        alignItems: "center",
                        boxSizing: "border-box",
                        display: "grid",
                        gap: "8px",
                        gridTemplateColumns: isOwnPost
                            ? "minmax(0, 1fr)"
                            : "minmax(0, 1fr) auto",
                        minHeight: feedLikeActionSize,
                        mt: "8px",
                        pl: "9px",
                        width: "100%",
                    }}
                >
                    {displayCaption ? (
                        <Box
                            component="button"
                            type="button"
                            aria-label={`Open ${name} post`}
                            disabled={!onOpenPhoto}
                            onClick={() => openPhoto()}
                            title={displayCaption}
                            sx={{
                                ...feedCaptionTextSx,
                                appearance: "none",
                                bgcolor: "transparent",
                                border: 0,
                                cursor: onOpenPhoto ? "pointer" : "default",
                                display: "block",
                                p: 0,
                                textAlign: "left",
                                width: "100%",
                                "&:disabled": { color: textBase },
                                "&:focus-visible": {
                                    borderRadius: "4px",
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                            }}
                        >
                            {displayCaption}
                        </Box>
                    ) : (
                        <Box component="p" sx={feedCaptionTextSx} />
                    )}
                    {!isOwnPost && (
                        <Box
                            sx={{
                                alignItems: "center",
                                display: "flex",
                                gap: "6px",
                                justifyContent: "flex-end",
                            }}
                        >
                            <Box
                                component="button"
                                type="button"
                                aria-label={`Reply to ${firstName}'s post`}
                                onClick={() => openPhoto(true)}
                                sx={{
                                    alignItems: "center",
                                    appearance: "none",
                                    bgcolor: feedActionBackground,
                                    border: 0,
                                    borderRadius: "50%",
                                    color: textBase,
                                    cursor: "pointer",
                                    display: "inline-flex",
                                    height: feedLikeActionSize,
                                    justifyContent: "center",
                                    p: 0,
                                    flexShrink: 0,
                                    transition:
                                        "color 120ms ease, transform 120ms ease",
                                    width: feedLikeActionSize,
                                    "&:focus-visible": {
                                        outline: `2px solid ${green}`,
                                        outlineOffset: 2,
                                    },
                                    "&:hover": {
                                        bgcolor: feedActionBackgroundHover,
                                    },
                                }}
                            >
                                <FeedReplyIcon />
                            </Box>
                            <FeedLikeButton
                                isLiked={isLiked}
                                onClick={handleLikeClick}
                                popID={likePopID}
                            />
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
    <Box
        sx={{
            boxSizing: "border-box",
            left: "50%",
            px: feedHorizontalPadding,
            pointerEvents: "none",
            position: "fixed",
            top: "calc(env(safe-area-inset-top) + 10px)",
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
                bgcolor: "#FFFFFF",
                borderRadius: "18px",
                boxShadow: "0 12px 32px rgba(0, 0, 0, 0.18)",
                boxSizing: "border-box",
                color: textBase,
                display: "flex",
                fontFamily: '"Inter Variable", Inter, sans-serif',
                fontSize: 14,
                fontWeight: 650,
                gap: "10px",
                lineHeight: "20px",
                minHeight: 50,
                pointerEvents: "auto",
                pl: "16px",
                pr: "6px",
                py: "3px",
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
                        outline: "2px solid rgba(0 0 0 / 0.72)",
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

export const HomeScreen: React.FC<HomeScreenProps> = ({
    feedItems,
    friendRequestSentToastName,
    friendsCount,
    hasFeedLoadMoreError = false,
    hasMoreFeedItems = false,
    hasUnreadMessages,
    isFeedLoading = false,
    isFeedLoadingMore = false,
    isFriendsLoading = false,
    localFeedPosts = [],
    showInstallPrompt = false,
    onCreatePost,
    onDeletePost,
    onLoadMoreFeedItems,
    onLoadPostAvatar,
    onLoadPostImage,
    onFriendRequestSentToastClose,
    onOpenFriend,
    onOpenMessages,
    onOpenProfile,
    onReplyToPost,
    onSetPostLiked,
    profile,
    profileLink,
}) => {
    const [selectedViewer, setSelectedViewer] =
        useState<SelectedHomeViewer | null>(null);
    const [isInviteSharing, setIsInviteSharing] = useState(false);
    const [isPostPhotoOpening, setIsPostPhotoOpening] = useState(false);
    const [loadedFeedAvatarURLsByKey, setLoadedFeedAvatarURLsByKey] = useState<
        Record<string, string | null>
    >({});
    const [loadedFeedImageURLsByKey, setLoadedFeedImageURLsByKey] = useState<
        Record<string, string>
    >({});
    const [feedScrollRequest, setFeedScrollRequest] = useState(0);
    const isHeaderTriggered = useHideHeaderOnScrollDirection();
    const [isHeaderFocused, setIsHeaderFocused] = useState(false);
    const isHeaderHidden = isHeaderTriggered && !isHeaderFocused;
    const postInputRef = React.useRef<HTMLInputElement | null>(null);
    const feedLoadMoreRef = React.useRef<HTMLDivElement | null>(null);
    const localPostObjectUrlsRef = React.useRef<Set<string>>(new Set());
    const activeLocalPostObjectUrlRef = React.useRef<string | null>(null);
    const feedAvatarLoadsInFlightRef = React.useRef<
        Map<string, Promise<string | null>>
    >(new Map());
    const feedImageLoadsInFlightRef = React.useRef<
        Map<string, Promise<string | undefined>>
    >(new Map());
    const profileSpaceId = profile?.spaceId;
    const isPostPhotoButtonDisabled =
        isPostPhotoOpening || !profileSpaceId || !onCreatePost;
    const selectedPhotoFriendID = selectedViewer?.photo.friendID;
    const selectedPhotoIsOwn =
        Boolean(profileSpaceId) && selectedPhotoFriendID == profileSpaceId;
    const localResolvedPostIds = new Set(
        localFeedPosts
            .filter((item) => item.status == "posted" || item.status == "ready")
            .map((item) => item.post.postId),
    );
    const remoteFeedItems = feedItems.filter(
        (item) => !localResolvedPostIds.has(item.postId),
    );
    const hasFeedItems =
        localFeedPosts.length > 0 || remoteFeedItems.length > 0;
    const isEmptyFeedLoading = !hasFeedItems && isFeedLoading;
    const showFeedCards = hasFeedItems;
    const isInstallPromptEnabled =
        showInstallPrompt && !friendRequestSentToastName && !selectedViewer;
    const showUnreadIndicator = hasUnreadMessages === true;
    const hasLoadedNoFriends = !isFriendsLoading && friendsCount == 0;
    const emptyFeedMessage = hasLoadedNoFriends
        ? "When you add friends, their posts will appear here."
        : "When your friends share posts, they'll appear here.";
    const profileDisplayName =
        profile?.fullName.trim() || profile?.username.trim() || "";
    const revokeLocalPostObjectUrls = React.useCallback(() => {
        localPostObjectUrlsRef.current.forEach((objectUrl) =>
            URL.revokeObjectURL(objectUrl),
        );
        localPostObjectUrlsRef.current.clear();
    }, []);
    const releaseLocalPostObjectUrl = React.useCallback((objectUrl: string) => {
        localPostObjectUrlsRef.current.delete(objectUrl);
    }, []);

    const openPostPhotoPicker = () => {
        if (isPostPhotoButtonDisabled) return;

        postInputRef.current?.click();
    };
    const openFeedPhoto = (
        photo: SpaceViewerPhoto,
        focusReplyOnOpen = false,
    ) => {
        const isOwnPost =
            Boolean(profileSpaceId) && photo.friendID == profileSpaceId;
        setSelectedViewer({
            focusReplyOnOpen: isOwnPost ? false : focusReplyOnOpen,
            photo,
            postActionMode: isOwnPost ? "hidden" : "like-only",
        });
    };
    const closeSelectedPhoto = () => {
        activeLocalPostObjectUrlRef.current = null;
        setSelectedViewer(null);
        revokeLocalPostObjectUrls();
    };
    const { clearBrowserBackState: clearSelectedPhotoHistory } =
        useBrowserBackClose({
            open: Boolean(selectedViewer),
            onClose: closeSelectedPhoto,
            stateKey: "space-feed-viewer",
        });
    const deleteSelectedPost = async () => {
        const postId = selectedViewer?.photo.postId;
        if (!postId || !onDeletePost) return;

        await onDeletePost(postId);
    };
    const loadedFeedImageURLFor = React.useCallback(
        (item: SpacePost) =>
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
        (item: SpacePost) => {
            const loadedImageUrl = loadedFeedImageURLFor(item);
            if (loadedImageUrl) return Promise.resolve(loadedImageUrl);
            if (!item.imageAsset || !onLoadPostImage) {
                return Promise.resolve(undefined);
            }

            const cacheKey = feedPostImageCacheKey(item);
            const inFlight = feedImageLoadsInFlightRef.current.get(cacheKey);
            if (inFlight) return inFlight;

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
                    console.warn("Failed to load feed post image", error);
                    return undefined;
                })
                .finally(() => {
                    feedImageLoadsInFlightRef.current.delete(cacheKey);
                });
            feedImageLoadsInFlightRef.current.set(cacheKey, load);
            return load;
        },
        [loadedFeedImageURLFor, onLoadPostImage],
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
                    console.warn("Failed to load feed avatar", error);
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
        const imageUrl = loadedFeedImageURLFor(item);
        const avatarUrl = loadedFeedAvatarURLFor(item);
        const isAvatarPending = avatarUrl === undefined;
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
                    Boolean(profileSpaceId) && item.spaceId == profileSpaceId
                }
                name={item.name}
                onLoadAvatar={
                    isAvatarPending ? () => loadFeedPostAvatar(item) : undefined
                }
                onLoadImage={
                    imageUrl ? undefined : () => loadFeedPostImage(item)
                }
                onOpenFriend={onOpenFriend}
                onOpenPhoto={openFeedPhoto}
                onOpenProfile={onOpenProfile}
                onSetPostLiked={onSetPostLiked}
                postId={item.postId}
                spaceId={item.spaceId}
                thumbHash={item.thumbHash}
                timestampStatus={timestampStatus}
                timestampMs={item.timestampMs}
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
        if (feedScrollRequest == 0) return;

        return scheduleScrollPageToTop();
    }, [feedScrollRequest]);

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
                    console.error("Failed to load more space feed", error);
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

    const prepareSelectedPostPhoto = async (file: File) => {
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
                        if (activeLocalPostObjectUrlRef.current != draftKey) {
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
                        console.error("Failed to prepare post preview", error);
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
    };

    const handlePostPhotoSelect: React.ChangeEventHandler<HTMLInputElement> = (
        event,
    ) => {
        const file = event.target.files?.[0];
        event.target.value = "";
        if (!file) return;

        setIsPostPhotoOpening(true);
        void prepareSelectedPostPhoto(file)
            .catch((error: unknown) => {
                console.error("Failed to open post photo draft", error);
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
                bgcolor: homeBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
                position: "relative",
            }}
        >
            {selectedViewer && <SpaceViewerFeedBackdrop />}
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
                <Box
                    component="header"
                    onFocusCapture={() => setIsHeaderFocused(true)}
                    onBlurCapture={(event) => {
                        const nextFocus = event.relatedTarget;
                        if (
                            nextFocus instanceof Node &&
                            event.currentTarget.contains(nextFocus)
                        )
                            return;

                        setIsHeaderFocused(false);
                    }}
                    sx={{
                        alignItems: "center",
                        bgcolor: homeBackground,
                        boxSizing: "border-box",
                        display: "grid",
                        gap: "12px",
                        gridTemplateColumns: `${headerSideWidth}px minmax(0, 1fr) ${headerSideWidth}px`,
                        height: headerHeight,
                        left: "50%",
                        maxWidth: "100%",
                        pb: 2,
                        position: "fixed",
                        pt: 1.5,
                        px: 2,
                        top: 0,
                        transform: isHeaderHidden
                            ? "translate(-50%, calc(-100% - 4px))"
                            : "translate(-50%, 0)",
                        transition: "transform 180ms ease",
                        width: "100%",
                        zIndex: 4,
                        "@media (min-width: 600px)": { maxWidth: 390 },
                        "@media (prefers-reduced-motion: reduce)": {
                            transition: "none",
                        },
                    }}
                >
                    <Box
                        ref={postInputRef}
                        component="input"
                        type="file"
                        accept={spacePostImageInputAccept}
                        onChange={handlePostPhotoSelect}
                        sx={{ display: "none" }}
                    />
                    <Box
                        component="button"
                        type="button"
                        aria-label="Open profile"
                        onClick={onOpenProfile}
                        sx={{
                            appearance: "none",
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            borderRadius: "50%",
                            boxSizing: "border-box",
                            color: green,
                            cursor: onOpenProfile ? "pointer" : "default",
                            display: "flex",
                            height: headerActionSize,
                            justifyContent: "center",
                            lineHeight: 0,
                            ml: "-6px",
                            overflow: "hidden",
                            p: 0,
                            placeSelf: "center start",
                            width: headerActionSize,
                            "&:focus-visible": {
                                borderRadius: "50%",
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <Box
                            sx={{
                                alignItems: "center",
                                bgcolor: feedSkeletonElementBackground,
                                borderRadius: "50%",
                                display: "flex",
                                height: headerAvatarSize,
                                justifyContent: "center",
                                overflow: "hidden",
                                width: headerAvatarSize,
                            }}
                        >
                            {profile &&
                            (profile.avatarUrl || !profile.avatarObjectID) ? (
                                <SpaceAvatarImage
                                    src={profile.avatarUrl}
                                    borderRadius="50%"
                                />
                            ) : (
                                <Skeleton
                                    variant="circular"
                                    sx={{
                                        bgcolor: feedSkeletonElementBackground,
                                        height: "100%",
                                        transform: "none",
                                        width: "100%",
                                    }}
                                />
                            )}
                        </Box>
                    </Box>
                    <Box
                        sx={{
                            alignSelf: "center",
                            color: textBase,
                            justifySelf: "center",
                            lineHeight: 0,
                            minWidth: 0,
                            overflow: "visible",
                            placeSelf: "center",
                            width: 61,
                        }}
                    >
                        <Box
                            component="img"
                            alt="Space"
                            src="/images/space.svg"
                            sx={{
                                display: "block",
                                filter: "invert(1)",
                                height: 18,
                                width: "auto",
                            }}
                        />
                    </Box>
                    <Box
                        component="button"
                        type="button"
                        aria-label={
                            showUnreadIndicator
                                ? "Open messages with unread activity"
                                : "Open messages"
                        }
                        onClick={onOpenMessages}
                        sx={{
                            appearance: "none",
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            boxSizing: "border-box",
                            color: textBase,
                            cursor: onOpenMessages ? "pointer" : "default",
                            display: "flex",
                            fontSize: 0,
                            height: headerActionSize,
                            justifyContent: "center",
                            justifySelf: "end",
                            lineHeight: 0,
                            mr: "-6px",
                            p: 0,
                            position: "relative",
                            width: headerActionSize,
                            "& svg": { display: "block" },
                            "&:focus-visible": {
                                borderRadius: "50%",
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <HugeiconsIcon
                            icon={BubbleChatIcon}
                            size={headerIconSize}
                            strokeWidth={1.5}
                        />
                        {showUnreadIndicator && (
                            <Box
                                aria-hidden
                                sx={{
                                    "@keyframes spaceUnreadBadgePing": {
                                        "75%, 100%": {
                                            opacity: 0,
                                            transform: "scale(2.5)",
                                        },
                                    },
                                    "@media (prefers-reduced-motion: reduce)": {
                                        "&::after": { display: "none" },
                                    },
                                    bgcolor: dangerColor,
                                    border: `2px solid ${homeBackground}`,
                                    borderRadius: "50%",
                                    height: 13,
                                    position: "absolute",
                                    right: 7,
                                    top: 7,
                                    width: 13,
                                    zIndex: 0,
                                    "&::after": {
                                        animation:
                                            "spaceUnreadBadgePing 1.25s cubic-bezier(0, 0, 0.2, 1) 1",
                                        bgcolor: dangerColor,
                                        borderRadius: "50%",
                                        content: '""',
                                        inset: 0,
                                        opacity: 0.75,
                                        pointerEvents: "none",
                                        position: "absolute",
                                        zIndex: -1,
                                    },
                                }}
                            />
                        )}
                    </Box>
                </Box>
                <Box aria-hidden sx={{ height: headerHeight }} />
                <Box
                    sx={{
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: showFeedCards ? "24px" : 0,
                        justifyContent: showFeedCards ? "flex-start" : "center",
                        minHeight: "calc(100svh - 64px)",
                        minWidth: 0,
                        pb: showFeedCards
                            ? "calc(env(safe-area-inset-bottom) + 112px)"
                            : "56px",
                        px: showFeedCards ? feedHorizontalPadding : 0,
                        pt: showFeedCards ? "4px" : 0,
                        width: "100%",
                    }}
                >
                    {hasFeedItems ? (
                        <>
                            {localFeedPosts.map(localFeedItemFor)}
                            {remoteFeedItems.map((item) =>
                                feedItemFor(item, item.postId),
                            )}
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
                                                bgcolor: paleGreen,
                                                border: 0,
                                                borderRadius: "18px",
                                                color: green,
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
                                                    bgcolor: "#DDF1E1",
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
                            sx={{
                                alignItems: "center",
                                display: "flex",
                                flexDirection: "column",
                                justifyContent: "center",
                                px: 3,
                                textAlign: "center",
                                width: "100%",
                            }}
                        >
                            <Box
                                component="img"
                                alt=""
                                src="/images/ducky-space.svg"
                                sx={{
                                    display: "block",
                                    height: "auto",
                                    width: 220,
                                    "@media (max-width: 340px)": { width: 196 },
                                }}
                            />
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
                                    mt: emptyFeedItemGap,
                                    maxWidth: 220,
                                }}
                            >
                                {emptyFeedMessage}
                            </Box>
                            {hasLoadedNoFriends && (
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
                                        bgcolor: "#E8E8E8",
                                        border: 0,
                                        borderRadius: "18px",
                                        color: textBase,
                                        cursor:
                                            profileLink && !isInviteSharing
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
                                        mt: emptyFeedItemGap,
                                        px: "14px",
                                        whiteSpace: "nowrap",
                                        "&:disabled": { opacity: 0.45 },
                                        "&:focus-visible": {
                                            outline: `2px solid ${green}`,
                                            outlineOffset: 2,
                                        },
                                        "&:hover":
                                            profileLink && !isInviteSharing
                                                ? { bgcolor: "#DEDEDE" }
                                                : undefined,
                                    }}
                                />
                            )}
                        </Box>
                    )}
                </Box>
                <SpacePostFloatingActionButton
                    disabled={isPostPhotoButtonDisabled}
                    onClick={openPostPhotoPicker}
                />
                {selectedViewer && (
                    <SpaceFileViewer
                        focusReplyOnOpen={selectedViewer.focusReplyOnOpen}
                        photo={selectedViewer.photo}
                        draftPostPreparationError={
                            selectedViewer.draftImageError
                        }
                        isDraftPostPreviewPending={
                            selectedViewer.isDraftImagePreviewPending
                        }
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
                                            onOpenFriend(selectedPhotoFriendID);
                                        });
                                    }
                                  : undefined
                        }
                        onSwipeLeft={closeSelectedPhoto}
                        onReplyToPost={
                            !selectedPhotoIsOwn &&
                            selectedViewer.photo.friendID != profileSpaceId
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
                                      releaseLocalPostObjectUrl(previewUrl);
                                      return publishPromise;
                                  }
                                : undefined
                        }
                        onDraftPostPublished={() =>
                            setFeedScrollRequest((request) => request + 1)
                        }
                        onSetPostLiked={onSetPostLiked}
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
