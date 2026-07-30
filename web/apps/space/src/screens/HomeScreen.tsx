import {
    BubbleChatIcon,
    FavouriteIcon,
    MultiplicationSignIcon,
    UserAdd02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Skeleton } from "@mui/material";
import { SpaceActionToast } from "components/SpaceActionToast";
import { SpaceAvatarImage } from "components/SpaceAvatarImage";
import {
    SpaceFileViewer,
    SpaceViewerFeedBackdrop,
    type SpaceViewerDraftPostEdit,
    type SpaceViewerPhoto,
    type SpaceViewerPostActionMode,
} from "components/SpaceFileViewer";
import { SpaceInlinePostButton } from "components/SpaceInlinePostButton";
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
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/useBrowserBackClose";
import { useHideOnScrollDirection } from "hooks/useHideOnScrollDirection";
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
const headerSideWidth = 32;
const feedLikeActionSize = spaceTouchTargetSize;
const feedActionIconSize = 20;
const emptyFeedItemGap = "22px";
const feedHorizontalPadding = "16px";
const minimumFeedPhotoFrameAspectRatio = 3 / 4;
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
    color: "#FFFFFF",
    fontFamily: '"Inter Variable", Inter, sans-serif',
    fontSize: 13,
    fontWeight: 650,
    lineHeight: "19px",
    textAlign: "center",
    textWrap: "balance",
} as const;
const feedPhotoCaptionBubbleSx = {
    bgcolor: "rgba(48, 48, 48, 0.86)",
    borderRadius: "10px",
    boxDecorationBreak: "clone",
    px: "8px",
    py: "2px",
    WebkitBoxDecorationBreak: "clone",
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
    showInstallPrompt?: boolean;
    showInviteFriendsToast?: boolean;
    onCreatePost?: (
        image: DraftSpacePostImage,
        caption: string,
    ) => Promise<void>;
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

const FeedPhotoCaption: React.FC<{ caption: string }> = ({ caption }) => {
    const measureContainerRef = React.useRef<HTMLDivElement | null>(null);
    const measureTextRef = React.useRef<HTMLSpanElement | null>(null);
    const [displayCaption, setDisplayCaption] = useState(caption);

    React.useEffect(() => {
        const container = measureContainerRef.current;
        const text = measureTextRef.current;
        if (!container || !text) return;

        const measure = () => {
            const fits = (value: string) => {
                text.textContent = value;
                return text.getClientRects().length <= 2;
            };
            if (fits(caption)) {
                setDisplayCaption(caption);
                return;
            }

            let lower = 0;
            let upper = caption.length;
            while (lower < upper) {
                const middle = Math.ceil((lower + upper) / 2);
                if (fits(`${caption.slice(0, middle).trimEnd()}…`)) {
                    lower = middle;
                } else {
                    upper = middle - 1;
                }
            }

            const prefix = caption.slice(0, lower).trimEnd();
            const lastSpace = prefix.lastIndexOf(" ");
            setDisplayCaption(
                `${lastSpace > 0 ? prefix.slice(0, lastSpace) : prefix}…`,
            );
        };

        measure();
        const observer = new ResizeObserver(measure);
        observer.observe(container);
        return () => observer.disconnect();
    }, [caption]);

    return (
        <>
            <Box
                aria-hidden
                ref={measureContainerRef}
                sx={{
                    ...feedPhotoCaptionTextSx,
                    left: "15%",
                    position: "absolute",
                    top: 0,
                    visibility: "hidden",
                    width: "70%",
                }}
            >
                <Box
                    ref={measureTextRef}
                    component="span"
                    sx={feedPhotoCaptionBubbleSx}
                >
                    {caption}
                </Box>
            </Box>
            <Box
                title={caption}
                sx={{
                    ...feedPhotoCaptionTextSx,
                    bottom: 20,
                    display: "-webkit-box",
                    left: "50%",
                    maxWidth: "70%",
                    pointerEvents: "none",
                    position: "absolute",
                    textShadow: "0 1px 10px rgba(0, 0, 0, 0.74)",
                    transform: "translateX(-50%)",
                    WebkitBoxOrient: "vertical",
                    WebkitLineClamp: 2,
                    width: "max-content",
                    zIndex: 2,
                }}
            >
                <Box component="span" sx={feedPhotoCaptionBubbleSx}>
                    {displayCaption}
                </Box>
            </Box>
        </>
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
    username,
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
    const showFooter = !isOwnPost;
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
    const isPhotoReady = Boolean(displayImageUrl) && decodedPhoto.ready;
    const canOpenPhoto = isPhotoReady && Boolean(onOpenPhoto);
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
        if (!canOpenPhoto || !displayImageUrl) return;

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
                username,
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
            log.error("Failed to update post like", error);
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
        if (!isPhotoReady) return;
        if (!thumbHashDataURL) {
            setShowResolvedPhoto(true);
            return;
        }

        const frameID = window.requestAnimationFrame(() =>
            setShowResolvedPhoto(true),
        );
        return () => window.cancelAnimationFrame(frameID);
    }, [displayImageUrl, isPhotoReady, thumbHashDataURL]);

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
                    disabled={!canOpenPhoto}
                    onClick={() => openPhoto()}
                    sx={{
                        appearance: "none",
                        bgcolor: "transparent",
                        border: 0,
                        cursor: canOpenPhoto ? "pointer" : "default",
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
                    {!thumbHashDataURL && !isPhotoReady && (
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
                    {isPhotoReady && (
                        <Box
                            component="img"
                            alt={`${name} post`}
                            src={displayImageUrl}
                            onLoad={rememberLoadedPhotoDimensions}
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
                            bgcolor: "transparent",
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
                        <Box
                            aria-hidden
                            sx={{
                                bgcolor: "rgba(255, 255, 255, 0.2)",
                                borderRadius: "50%",
                                inset: 0,
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
                                border: "2px solid rgba(255, 255, 255, 0.35)",
                                borderRadius: "50%",
                                inset: -2,
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
                {displayCaption && (
                    <FeedPhotoCaption caption={displayCaption} />
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
                        mt: "8px",
                        px: "4px",
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
                            borderRadius: "22px",
                            color: textSecondary,
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
                                bgcolor: feedActionBackgroundHover,
                            },
                        }}
                    >
                        Reply privately to {firstName}...
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

const InviteFriendsToast: React.FC<InviteFriendsToastProps> = ({
    profileLink,
    sharing,
    onClose,
    onSharingChange,
}) => (
    <SpaceActionToast
        action={
            <SpaceShareInviteButton
                className="green-bg"
                label="Invite"
                profileLink={profileLink}
                sharing={sharing}
                showIcon={false}
                onShareComplete={onClose}
                onShareError={(error) =>
                    log.error("Failed to share space invite", error)
                }
                onSharingChange={onSharingChange}
                sx={{
                    alignItems: "center",
                    bgcolor: green,
                    border: 0,
                    borderRadius: "14px",
                    color: "#FFFFFF",
                    cursor: profileLink && !sharing ? "pointer" : "default",
                    display: "flex",
                    flexShrink: 0,
                    fontFamily: '"Inter Variable", Inter, sans-serif',
                    fontSize: 13,
                    fontWeight: 700,
                    height: 34,
                    justifyContent: "center",
                    lineHeight: "18px",
                    minWidth: 48,
                    px: "17px",
                    transition: "filter 120ms ease",
                    "&:active":
                        profileLink && !sharing
                            ? { filter: "brightness(0.96)" }
                            : undefined,
                    "&:disabled": { opacity: 0.45 },
                    "&:focus-visible": {
                        outline: "2px solid rgba(0 0 0 / 0.72)",
                        outlineOffset: 2,
                    },
                    "&:hover":
                        profileLink && !sharing
                            ? { filter: "brightness(0.98)" }
                            : undefined,
                }}
            />
        }
        animateEntrance
        closeLabel="Close invite prompt"
        icon={
            <HugeiconsIcon icon={UserAdd02Icon} size={24} strokeWidth={1.9} />
        }
        message="Invite friends to your Space"
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
    showInstallPrompt = false,
    showInviteFriendsToast = false,
    onCreatePost,
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
    const [isDraftPostExiting, setIsDraftPostExiting] = useState(false);
    const [isInviteSharing, setIsInviteSharing] = useState(false);
    const [isPostPhotoOpening, setIsPostPhotoOpening] = useState(false);
    const [loadedFeedAvatarURLsByKey, setLoadedFeedAvatarURLsByKey] = useState<
        Record<string, string | null>
    >({});
    const [loadedFeedImageURLsByKey, setLoadedFeedImageURLsByKey] = useState<
        Record<string, string>
    >({});
    const [feedScrollRequest, setFeedScrollRequest] = useState(0);
    const isHeaderTriggered = useHideOnScrollDirection();
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
    const isPostPhotoButtonDisabled =
        isPostPhotoOpening || !viewerSpaceId || !onCreatePost;
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
    const profileDisplayName =
        profile?.fullName.trim() || profile?.username.trim() || "";
    const profileFirstName = profile?.fullName.trim().split(/\s+/)[0];
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
            Boolean(viewerSpaceId) && photo.friendID == viewerSpaceId;
        setSelectedViewer({
            focusReplyOnOpen: isOwnPost ? false : focusReplyOnOpen,
            photo,
            postActionMode: isOwnPost ? "hidden" : "like-only",
        });
    };
    const closeSelectedPhoto = () => {
        activeLocalPostObjectUrlRef.current = null;
        setIsDraftPostExiting(false);
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
                    log.warn("Failed to load feed post image", error);
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
                    Boolean(viewerSpaceId) && item.spaceId == viewerSpaceId
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
                bgcolor: homeBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
                position: "relative",
            }}
        >
            {selectedViewer && (
                <SpaceViewerFeedBackdrop exiting={isDraftPostExiting} />
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
                        background: "transparent",
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
                        "&::before": {
                            WebkitBackdropFilter: "blur(4px)",
                            WebkitMaskImage:
                                "linear-gradient(to bottom, #000 0%, transparent 100%)",
                            backdropFilter: "blur(4px)",
                            background:
                                "linear-gradient(to bottom, rgba(245, 245, 247, 0.8), transparent)",
                            content: '""',
                            height: "calc(100% + 28px)",
                            left: 0,
                            maskImage:
                                "linear-gradient(to bottom, #000 0%, transparent 100%)",
                            pointerEvents: "none",
                            position: "absolute",
                            right: 0,
                            top: 0,
                            zIndex: -1,
                        },
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
                                <Box
                                    key={profile.avatarUrl ?? "default-avatar"}
                                    sx={{
                                        ...avatarFadeSx,
                                        height: "100%",
                                        width: "100%",
                                    }}
                                >
                                    <SpaceAvatarImage
                                        src={profile.avatarUrl}
                                        borderRadius="50%"
                                    />
                                </Box>
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
                        gap: 0,
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
                                src="/images/ducky-camera.svg"
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
                                    maxWidth: 280,
                                }}
                            >
                                Welcome to your space, {profileFirstName}.
                                <br />
                                Share a little moment from your day.
                            </Box>
                            <SpaceInlinePostButton
                                disabled={isPostPhotoButtonDisabled}
                                onClick={openPostPhotoPicker}
                            />
                        </Box>
                    )}
                </Box>
                {hasFeedItems && (
                    <SpacePostFloatingActionButton
                        disabled={isPostPhotoButtonDisabled}
                        onClick={openPostPhotoPicker}
                    />
                )}
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
                                            onOpenFriend(
                                                selectedPhotoFriendID,
                                                selectedViewer.photo.username,
                                            );
                                        });
                                    }
                                  : undefined
                        }
                        onSwipeLeft={closeSelectedPhoto}
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
                        onDraftPostExitStart={() => {
                            setIsDraftPostExiting(true);
                        }}
                        onDraftPostPublished={() => {
                            setFeedScrollRequest((request) => request + 1);
                        }}
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
