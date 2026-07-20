import {
    AddSquareIcon,
    ArrowLeft02Icon,
    Menu01Icon,
    MultiplicationSignIcon,
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
import { SpaceLoadingSpinner } from "components/SpaceRouteFallback";
import { SpaceShareIcon } from "components/SpaceShareInviteButton";
import { useBrowserBackClose } from "hooks/useBrowserBackClose";
import React, { useState } from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";
import type { SpacePostAsset } from "services/space";
import { spaceTouchTargetSize } from "styles/touchTargets";
import { createLoadedLocalPostPhoto } from "utils/localPostPhoto";
import { firstNameFrom } from "utils/spaceDisplay";
import {
    canPreviewSpaceImageFile,
    spaceDefaultCoverImagePath,
    spacePostImageErrorMessage,
    spacePostImageInputAccept,
    spacePostPreviewImageForFile,
} from "utils/spacePostImage";
import { thumbHashDataURLFromBase64 } from "utils/thumbhash";

export const profileBackground = "#FFFFFF";

const green = "#08C225";
const textBase = "#000";
const textStrong = "#303030";
const textSoft = "#777777";
const coverForeground = "#FFFFFF";
const profileCoverBackground = "#1F1F1F";
const profileCoverTopShadow =
    "linear-gradient(180deg, rgba(0, 0, 0, 0.26) 0%, rgba(0, 0, 0, 0.18) 36%, rgba(0, 0, 0, 0.08) 72%, rgba(0, 0, 0, 0) 100%)";
const profileCoverSkeletonBackground = "#E6E6E6";
const profileHeaderHeight = 56;
const profileAvatarTopOffset = 54;
const profileAvatarSize = 120;
const profileCoverHeight =
    profileHeaderHeight + profileAvatarTopOffset + profileAvatarSize / 2;
const photoMasonryGap = "3px";
const profileHorizontalPadding = "16px";
const photoMasonryPlaceholderBackground = "#F2F2F2";
const photoMasonryRadius = "12px";
const photoMasonryLoadRootMargin = "800px 0px";
const profileToastTransition = "opacity 160ms ease, transform 160ms ease";
interface ProfilePhotoDimensions {
    height: number;
    width: number;
}

const photoAspectRatio = ({ height, width }: ProfilePhotoDimensions): number =>
    height > 0 && width > 0 ? width / height : 1;

export interface ProfilePostItem {
    avatarUrl?: string | null;
    caption?: string;
    friendID?: string;
    height?: number;
    id: string;
    imageAsset?: SpacePostAsset;
    imageUrl?: string;
    name?: string;
    postId?: number;
    spaceId?: string;
    timestampMs: number;
    thumbHash?: string;
    viewerLiked?: boolean;
    width?: number;
}

export interface ProfilePostGroup {
    items: ProfilePostItem[];
    label: string;
}

interface SelectedProfilePost {
    draftFile?: File;
    draftImageError?: string;
    id: string;
    isDraftImagePreviewPending?: boolean;
    localObjectUrl?: string;
    photo: SpaceViewerPhoto;
    postIndex?: number;
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

interface PostMasonryTile {
    aspectRatio: number;
    dimensions: ProfilePhotoDimensions;
    index: number;
    item: ProfilePostItem;
}

interface PostMasonryRow {
    aspectRatio: number;
    tiles: PostMasonryTile[];
}

interface ProfileToastProps {
    message: string;
    open: boolean;
    onClose?: () => void;
    onExited?: () => void;
}

interface ProfileToastState {
    message: string;
    open: boolean;
}

const buildPostMasonryRows = (
    items: ProfilePostItem[],
    loadedDimensionsByID: Record<string, ProfilePhotoDimensions>,
): PostMasonryRow[] => {
    const tiles = items.map((item, index) => {
        const dimensions = loadedDimensionsByID[item.id] ?? {
            height: item.height ?? 1,
            width: item.width ?? 1,
        };
        return {
            aspectRatio: Math.max(0.1, photoAspectRatio(dimensions)),
            dimensions,
            index,
            item,
        };
    });
    const rows = new Array<PostMasonryRow>();
    let nextTileIndex = 0;

    while (nextTileIndex < tiles.length) {
        const rowSize = preferredPostMasonryRowSize(
            tiles.length - nextTileIndex,
        );
        const rowTiles = tiles.slice(nextTileIndex, nextTileIndex + rowSize);
        rows.push({
            aspectRatio: rowTiles.reduce(
                (aspectRatio, tile) => aspectRatio + tile.aspectRatio,
                0,
            ),
            tiles: rowTiles,
        });
        nextTileIndex += rowSize;
    }

    return rows;
};

const preferredPostMasonryRowSize = (remainingTiles: number) => {
    if (remainingTiles <= 3) return remainingTiles;
    if (remainingTiles == 4 || remainingTiles == 5) return 2;
    return remainingTiles % 2 == 0 ? 2 : 3;
};

const profilePostImageCacheKey = (item: ProfilePostItem) =>
    [item.id, item.imageAsset?.objectKey ?? item.imageUrl ?? ""].join(":");

const ProfileStatsSkeleton: React.FC = () => (
    <Box
        role="status"
        aria-label="Loading profile stats"
        sx={{
            alignItems: "center",
            alignSelf: "center",
            display: "inline-flex",
            gap: "8px",
            height: 20,
            lineHeight: "20px",
            mt: "2px",
        }}
    >
        <Skeleton
            variant="rectangular"
            sx={{
                bgcolor: photoMasonryPlaceholderBackground,
                borderRadius: "999px",
                height: 18,
                transform: "none",
                width: 56,
            }}
        />
        <Box
            aria-hidden
            sx={{
                bgcolor: textSoft,
                borderRadius: "50%",
                height: 3,
                opacity: 0.45,
                width: 3,
            }}
        />
        <Skeleton
            variant="rectangular"
            sx={{
                bgcolor: photoMasonryPlaceholderBackground,
                borderRadius: "999px",
                height: 18,
                transform: "none",
                width: 68,
            }}
        />
    </Box>
);

const ProfilePostLoadingIndicator: React.FC = () => (
    <Box
        sx={{
            alignItems: "center",
            bottom: 0,
            display: "flex",
            insetInline: 0,
            justifyContent: "center",
            pointerEvents: "none",
            position: "absolute",
            top: `${profileCoverHeight}px`,
            width: "100%",
        }}
    >
        <SpaceLoadingSpinner ariaLabel="Loading posts" />
    </Box>
);

interface ProfilePostTileProps {
    aspectRatio: number;
    dimensions: ProfilePhotoDimensions;
    displayName: string;
    groupLabel: string;
    imageUrl?: string;
    index: number;
    isSingleItemRow: boolean;
    item: ProfilePostItem;
    onLoadImage: () => Promise<string | undefined>;
    onOpen: (imageUrl: string) => void;
    onRememberDimensions: (itemID: string, image: HTMLImageElement) => void;
}

const ProfilePostTile: React.FC<ProfilePostTileProps> = ({
    aspectRatio,
    dimensions,
    displayName,
    groupLabel,
    imageUrl,
    index,
    isSingleItemRow,
    item,
    onLoadImage,
    onOpen,
    onRememberDimensions,
}) => {
    const [shouldLoad, setShouldLoad] = React.useState(Boolean(imageUrl));
    const [readyImageUrl, setReadyImageUrl] = React.useState<string>();
    const tileRef = React.useRef<HTMLButtonElement | null>(null);
    const thumbHashDataURL = React.useMemo(
        () => thumbHashDataURLFromBase64(item.thumbHash),
        [item.thumbHash],
    );
    const isCurrentImageReady = Boolean(imageUrl && readyImageUrl == imageUrl);

    React.useEffect(() => {
        if (imageUrl) setShouldLoad(true);
    }, [imageUrl]);

    React.useEffect(() => {
        if (shouldLoad || imageUrl) return;
        const element = tileRef.current;
        if (!element) return;
        if (
            typeof window == "undefined" ||
            !("IntersectionObserver" in window)
        ) {
            setShouldLoad(true);
            return;
        }

        const observer = new IntersectionObserver(
            (entries) => {
                if (entries.some((entry) => entry.isIntersecting)) {
                    setShouldLoad(true);
                    observer.disconnect();
                }
            },
            { rootMargin: photoMasonryLoadRootMargin },
        );
        observer.observe(element);
        return () => observer.disconnect();
    }, [imageUrl, shouldLoad]);

    React.useEffect(() => {
        if (!shouldLoad || imageUrl) return;
        void onLoadImage().catch((error: unknown) => {
            console.warn("Failed to load profile post image", error);
        });
    }, [imageUrl, onLoadImage, shouldLoad]);

    return (
        <Box
            ref={tileRef}
            component="button"
            type="button"
            aria-label={`Open ${displayName} post ${index + 1}`}
            disabled={!imageUrl}
            onClick={() => {
                if (imageUrl) onOpen(imageUrl);
            }}
            sx={{
                appearance: "none",
                aspectRatio: isSingleItemRow
                    ? `${dimensions.width} / ${dimensions.height}`
                    : undefined,
                bgcolor: photoMasonryPlaceholderBackground,
                border: 0,
                cursor: imageUrl ? "pointer" : "default",
                display: "block",
                flex: isSingleItemRow ? "0 0 100%" : `${aspectRatio} 1 0`,
                height: isSingleItemRow ? "auto" : "100%",
                minWidth: 0,
                opacity: 1,
                overflow: "hidden",
                p: 0,
                position: "relative",
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
            {imageUrl ? (
                <Box
                    component="img"
                    alt={`${groupLabel} post ${index + 1}`}
                    onLoad={(event) => {
                        setReadyImageUrl(imageUrl);
                        onRememberDimensions(item.id, event.currentTarget);
                    }}
                    src={imageUrl}
                    sx={{
                        display: "block",
                        height: "100%",
                        inset: 0,
                        objectFit: "cover",
                        objectPosition: "center",
                        opacity:
                            isCurrentImageReady || !thumbHashDataURL ? 1 : 0,
                        position: "absolute",
                        transition: thumbHashDataURL
                            ? "opacity 220ms ease"
                            : "none",
                        width: "100%",
                        "@media (prefers-reduced-motion: reduce)": {
                            opacity: 1,
                            transition: "none",
                        },
                    }}
                />
            ) : null}
        </Box>
    );
};

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

const ProfileToast: React.FC<ProfileToastProps> = ({
    message,
    open,
    onClose,
    onExited,
}) => (
    <Box
        onTransitionEnd={(event) => {
            if (event.currentTarget != event.target || open) return;
            onExited?.();
        }}
        sx={{
            boxSizing: "border-box",
            left: "50%",
            opacity: open ? 1 : 0,
            px: profileHorizontalPadding,
            pointerEvents: "none",
            position: "fixed",
            top: "calc(env(safe-area-inset-top) + 10px)",
            transform: open
                ? "translateX(-50%) translateY(0)"
                : "translateX(-50%) translateY(-8px)",
            transition: profileToastTransition,
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
                <CopyIcon />
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

interface ProfileScreenProps {
    friendsCount?: number;
    headerVariant?: "friend" | "owner";
    isCoverLoading?: boolean;
    isPostsLoading?: boolean;
    isStatsLoading?: boolean;
    showPostLoadingIndicator?: boolean;
    onBack?: () => void;
    onCreatePost?: (
        image: DraftSpacePostImage,
        caption: string,
    ) => Promise<void>;
    onDeletePost?: (postId: number) => Promise<void> | void;
    onDraftPostPublished?: () => void;
    onOpenFriends?: () => void;
    onOpenProfileCover?: () => void;
    onOpenProfilePhoto?: () => void;
    onOpenSettings?: () => void;
    onLoadPostImage?: (asset: SpacePostAsset) => Promise<string>;
    onReplyToPost?: (
        postSpaceId: string,
        postId: number,
        text: string,
    ) => Promise<void>;
    onSetPostLiked?: (postId: number, liked: boolean) => Promise<void>;
    postGroups?: ProfilePostGroup[];
    profile: SetupProfile;
    profileLink?: string;
}

export const ProfileScreen: React.FC<ProfileScreenProps> = ({
    friendsCount = 0,
    headerVariant = "owner",
    isCoverLoading = false,
    isPostsLoading = false,
    isStatsLoading = false,
    onBack,
    onCreatePost,
    onDeletePost,
    onDraftPostPublished,
    onOpenFriends,
    onOpenProfileCover,
    onOpenProfilePhoto,
    onOpenSettings,
    onLoadPostImage,
    onReplyToPost,
    onSetPostLiked,
    postGroups = [],
    profile,
    profileLink,
    showPostLoadingIndicator,
}) => {
    const [selectedPost, setSelectedPost] =
        useState<SelectedProfilePost | null>(null);
    const [isPostPhotoOpening, setIsPostPhotoOpening] = useState(false);
    const [deletedPostIDs, setDeletedPostIDs] = useState<Set<string>>(
        () => new Set(),
    );
    const [profileShareToast, setProfileShareToast] =
        useState<ProfileToastState | null>(null);
    const [loadedPhotoDimensionsByID, setLoadedPhotoDimensionsByID] = useState<
        Record<string, ProfilePhotoDimensions>
    >({});
    const [loadedPostImageURLsByKey, setLoadedPostImageURLsByKey] = useState<
        Record<string, string>
    >({});
    const [loadedCoverUrl, setLoadedCoverUrl] = useState<string | null>(null);
    const postInputRef = React.useRef<HTMLInputElement | null>(null);
    const postImageLoadsInFlightRef = React.useRef<
        Map<string, Promise<string | undefined>>
    >(new Map());
    const localPostObjectUrlsRef = React.useRef<Set<string>>(new Set());
    const activeLocalPostObjectUrlRef = React.useRef<string | null>(null);
    const profileShareToastTimeoutRef = React.useRef<number | undefined>(
        undefined,
    );
    const profileShareToastFrameRef = React.useRef<number | undefined>(
        undefined,
    );
    const isOwnerProfile = headerVariant == "owner";
    const isFriendProfile = headerVariant == "friend";
    const displayName = profile.fullName.trim() || profile.username.trim();
    const coverUrl = profile.coverUrl ?? null;
    const isCoverURLPending = Boolean(profile.coverObjectID && !coverUrl);
    const coverImageUrl = coverUrl
        ? coverUrl
        : isCoverURLPending
          ? undefined
          : spaceDefaultCoverImagePath;
    const firstName = firstNameFrom(displayName);
    const visiblePostGroups = postGroups
        .map((group) => ({
            ...group,
            items: group.items.filter((item) => !deletedPostIDs.has(item.id)),
        }))
        .filter((group) => group.items.length > 0);
    const visiblePostItems = visiblePostGroups.flatMap((group) => group.items);
    const visiblePostIndexByID = new Map(
        visiblePostItems.map((item, index) => [item.id, index]),
    );
    const postsSharedCount = visiblePostGroups.reduce(
        (count, group) => count + group.items.length,
        0,
    );
    const canOpenFriends = isOwnerProfile && Boolean(onOpenFriends);
    const canOpenProfileCover = isOwnerProfile && Boolean(onOpenProfileCover);
    const canOpenProfilePhoto = Boolean(onOpenProfilePhoto);
    const hasProfilePosts = postsSharedCount > 0;
    const shouldShowPostLoadingIndicator =
        isPostsLoading && (showPostLoadingIndicator ?? true);
    const isCoverImageLoading = Boolean(
        coverImageUrl && loadedCoverUrl != coverImageUrl,
    );
    const shouldShowCoverSkeleton =
        isCoverLoading || isCoverURLPending || isCoverImageLoading;
    const selectedPostActionMode: SpaceViewerPostActionMode = isOwnerProfile
        ? "hidden"
        : "like-only";

    const clearProfileShareToastTimers = React.useCallback(() => {
        if (profileShareToastTimeoutRef.current !== undefined) {
            window.clearTimeout(profileShareToastTimeoutRef.current);
            profileShareToastTimeoutRef.current = undefined;
        }
        if (profileShareToastFrameRef.current !== undefined) {
            window.cancelAnimationFrame(profileShareToastFrameRef.current);
            profileShareToastFrameRef.current = undefined;
        }
    }, []);

    const hideProfileShareToast = React.useCallback(() => {
        clearProfileShareToastTimers();
        setProfileShareToast((currentToast) =>
            currentToast ? { ...currentToast, open: false } : currentToast,
        );
    }, [clearProfileShareToastTimers]);

    const showProfileShareToast = React.useCallback(
        (message: string) => {
            clearProfileShareToastTimers();
            setProfileShareToast({ message, open: false });
            profileShareToastFrameRef.current = window.requestAnimationFrame(
                () => {
                    setProfileShareToast((currentToast) =>
                        currentToast
                            ? { ...currentToast, open: true }
                            : currentToast,
                    );
                    profileShareToastFrameRef.current = undefined;
                },
            );
            profileShareToastTimeoutRef.current = window.setTimeout(() => {
                profileShareToastTimeoutRef.current = undefined;
                hideProfileShareToast();
            }, 1800);
        },
        [clearProfileShareToastTimers, hideProfileShareToast],
    );

    const clearClosedProfileShareToast = React.useCallback(() => {
        setProfileShareToast((currentToast) =>
            currentToast?.open ? currentToast : null,
        );
    }, []);

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
        if (isPostPhotoOpening) return;

        postInputRef.current?.click();
    };
    const closeSelectedPost = () => {
        activeLocalPostObjectUrlRef.current = null;
        setSelectedPost(null);
        revokeLocalPostObjectUrls();
    };
    const { clearBrowserBackState: clearSelectedPostHistory } =
        useBrowserBackClose({
            open: Boolean(selectedPost),
            onClose: closeSelectedPost,
            stateKey: "space-profile-viewer",
        });
    const rememberLoadedPhotoDimensions = (
        itemID: string,
        image: HTMLImageElement,
    ) => {
        const { naturalHeight, naturalWidth } = image;
        if (naturalHeight <= 0 || naturalWidth <= 0) return;

        setLoadedPhotoDimensionsByID((currentDimensions) => {
            const current = currentDimensions[itemID];
            if (
                current?.height == naturalHeight &&
                current.width == naturalWidth
            )
                return currentDimensions;

            return {
                ...currentDimensions,
                [itemID]: { height: naturalHeight, width: naturalWidth },
            };
        });
    };

    const loadedPostImageURLFor = React.useCallback(
        (item: ProfilePostItem) =>
            item.imageUrl ??
            loadedPostImageURLsByKey[profilePostImageCacheKey(item)],
        [loadedPostImageURLsByKey],
    );

    const loadPostImage = React.useCallback(
        (item: ProfilePostItem) => {
            const loadedImageUrl = loadedPostImageURLFor(item);
            if (loadedImageUrl) return Promise.resolve(loadedImageUrl);
            if (!item.imageAsset || !onLoadPostImage) {
                return Promise.resolve(undefined);
            }

            const cacheKey = profilePostImageCacheKey(item);
            const inFlight = postImageLoadsInFlightRef.current.get(cacheKey);
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
                    console.warn("Failed to load profile post image", error);
                    return undefined;
                })
                .finally(() => {
                    postImageLoadsInFlightRef.current.delete(cacheKey);
                });
            postImageLoadsInFlightRef.current.set(cacheKey, load);
            return load;
        },
        [loadedPostImageURLFor, onLoadPostImage],
    );

    const dimensionsForPost = React.useCallback(
        (item: ProfilePostItem): ProfilePhotoDimensions =>
            loadedPhotoDimensionsByID[item.id] ?? {
                height: item.height ?? 1,
                width: item.width ?? 1,
            },
        [loadedPhotoDimensionsByID],
    );

    const selectedPostForItem = React.useCallback(
        (
            item: ProfilePostItem,
            postIndex: number,
            imageUrl: string,
        ): SelectedProfilePost => {
            const dimensions = dimensionsForPost(item);
            return {
                id: item.id,
                photo: {
                    alt: `${displayName} post ${postIndex + 1}`,
                    avatarUrl: profile.avatarUrl,
                    caption: item.caption,
                    height: dimensions.height,
                    imageUrl,
                    name: displayName,
                    postId: item.postId,
                    spaceId: item.spaceId,
                    timestampMs: item.timestampMs,
                    viewerLiked: item.viewerLiked,
                    width: dimensions.width,
                },
                postIndex,
            };
        },
        [dimensionsForPost, displayName, profile.avatarUrl],
    );

    const profileViewerPhotos = React.useMemo(
        () =>
            visiblePostItems.map((item, index) => {
                const dimensions = dimensionsForPost(item);
                return {
                    alt: `${displayName} post ${index + 1}`,
                    avatarUrl: profile.avatarUrl,
                    caption: item.caption,
                    height: dimensions.height,
                    imageUrl:
                        loadedPostImageURLFor(item) ??
                        (selectedPost?.id == item.id
                            ? selectedPost.photo.imageUrl
                            : ""),
                    name: displayName,
                    postId: item.postId,
                    spaceId: item.spaceId,
                    timestampMs: item.timestampMs,
                    viewerLiked: item.viewerLiked,
                    width: dimensions.width,
                };
            }),
        [
            dimensionsForPost,
            displayName,
            loadedPostImageURLFor,
            profile.avatarUrl,
            selectedPost?.id,
            selectedPost?.photo.imageUrl,
            visiblePostItems,
        ],
    );

    const handleSelectedPostIndexChange = React.useCallback(
        (postIndex: number) => {
            const item = visiblePostItems[postIndex];
            if (!item) return;

            const updateSelectedPost = (imageUrl: string) => {
                setSelectedPost((currentPost) => {
                    if (currentPost?.postIndex == undefined) {
                        return currentPost;
                    }
                    if (
                        currentPost.id == item.id &&
                        currentPost.photo.imageUrl == imageUrl
                    ) {
                        return currentPost;
                    }
                    return selectedPostForItem(item, postIndex, imageUrl);
                });
            };

            const imageUrl = loadedPostImageURLFor(item);
            if (imageUrl) {
                updateSelectedPost(imageUrl);
                return;
            }

            void loadPostImage(item).then((loadedImageUrl) => {
                if (loadedImageUrl) updateSelectedPost(loadedImageUrl);
            });
        },
        [
            loadPostImage,
            loadedPostImageURLFor,
            selectedPostForItem,
            visiblePostItems,
        ],
    );

    React.useEffect(() => {
        const currentPostIndex = selectedPost?.postIndex;
        if (currentPostIndex == undefined) return;

        for (const offset of [-1, 1]) {
            const adjacentPost = visiblePostItems[currentPostIndex + offset];
            if (!adjacentPost || loadedPostImageURLFor(adjacentPost)) continue;

            void loadPostImage(adjacentPost);
        }
    }, [
        loadPostImage,
        loadedPostImageURLFor,
        selectedPost?.postIndex,
        visiblePostItems,
    ]);

    const prepareSelectedPostPhoto = async (file: File) => {
        const canShowLocalPreview = canPreviewSpaceImageFile(file);
        if (!canShowLocalPreview) {
            const timestampMs = Date.now();
            const draftKey = `pending-preview-${timestampMs}`;
            activeLocalPostObjectUrlRef.current = draftKey;
            setSelectedPost({
                draftFile: file,
                id: `local-${timestampMs}`,
                isDraftImagePreviewPending: true,
                localObjectUrl: draftKey,
                photo: {
                    alt: `${displayName || "You"} post`,
                    avatarUrl: profile.avatarUrl,
                    imageUrl: "",
                    name: displayName || "You",
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
                        setSelectedPost((currentPost) => {
                            if (currentPost?.localObjectUrl != draftKey)
                                return currentPost;

                            return {
                                ...currentPost,
                                isDraftImagePreviewPending: false,
                                localObjectUrl: preview.url,
                                photo: {
                                    ...currentPost.photo,
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
                        setSelectedPost((currentPost) => {
                            if (currentPost?.localObjectUrl != draftKey)
                                return currentPost;

                            return { ...currentPost, draftImageError: message };
                        });
                    });
            }, 0);
            return;
        }

        const localPost = await createLoadedLocalPostPhoto({
            avatarUrl: profile.avatarUrl,
            file,
            name: displayName || "You",
        });
        localPostObjectUrlsRef.current.add(localPost.objectUrl);
        activeLocalPostObjectUrlRef.current = localPost.objectUrl;
        setSelectedPost({
            draftFile: file,
            id: `local-${localPost.photo.timestampMs}`,
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

    const shareProfile = async () => {
        if (!profileLink) return;

        if (typeof navigator.share == "function") {
            try {
                await navigator.share({ url: profileLink });
                return;
            } catch (error) {
                if (error instanceof DOMException && error.name == "AbortError")
                    return;
            }
        }

        try {
            await navigator.clipboard.writeText(profileLink);
            showProfileShareToast("Invite link copied");
        } catch (error) {
            console.error("Failed to copy profile link", error);
            showProfileShareToast("Couldn't copy link. Please try again.");
        }
    };

    const deleteSelectedPost = async () => {
        if (!selectedPost) return;

        if (selectedPost.photo.postId && onDeletePost) {
            await onDeletePost(selectedPost.photo.postId);
        }
        setDeletedPostIDs((currentPostIDs) => {
            const nextPostIDs = new Set(currentPostIDs);
            nextPostIDs.add(selectedPost.id);
            return nextPostIDs;
        });
    };

    React.useEffect(
        () => () => {
            activeLocalPostObjectUrlRef.current = null;
            revokeLocalPostObjectUrls();
        },
        [revokeLocalPostObjectUrls],
    );

    React.useEffect(
        () => () => {
            clearProfileShareToastTimers();
        },
        [clearProfileShareToastTimers],
    );

    return (
        <Box
            component="main"
            sx={{
                bgcolor: profileBackground,
                color: textBase,
                display: "grid",
                minHeight: "100svh",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
                position: "relative",
            }}
        >
            {selectedPost && <SpaceViewerFeedBackdrop />}
            <Box
                sx={{
                    bgcolor: profileBackground,
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    minHeight: "100svh",
                    mx: "auto",
                    overflow: "hidden",
                    position: "relative",
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                {isOwnerProfile && (
                    <Box
                        ref={postInputRef}
                        component="input"
                        type="file"
                        accept={spacePostImageInputAccept}
                        onChange={handlePostPhotoSelect}
                        sx={{ display: "none" }}
                    />
                )}
                <Box
                    sx={{
                        bgcolor: shouldShowCoverSkeleton
                            ? profileCoverSkeletonBackground
                            : profileCoverBackground,
                        height: profileCoverHeight,
                        insetInline: 0,
                        overflow: "hidden",
                        position: "absolute",
                        top: 0,
                        width: "100%",
                        zIndex: 0,
                        "@media (min-width: 600px)": {
                            borderBottomLeftRadius: photoMasonryRadius,
                            borderBottomRightRadius: photoMasonryRadius,
                        },
                    }}
                >
                    {shouldShowCoverSkeleton && (
                        <Skeleton
                            variant="rectangular"
                            sx={{
                                bgcolor: profileCoverSkeletonBackground,
                                display: "block",
                                height: "100%",
                                transform: "none",
                                width: "100%",
                            }}
                        />
                    )}
                    {coverImageUrl && (
                        <Box
                            component="img"
                            alt=""
                            src={coverImageUrl}
                            onLoad={() => setLoadedCoverUrl(coverImageUrl)}
                            sx={{
                                display: "block",
                                height: "100%",
                                inset: shouldShowCoverSkeleton ? 0 : undefined,
                                objectFit: "cover",
                                objectPosition: "center",
                                opacity: shouldShowCoverSkeleton ? 0 : 1,
                                position: shouldShowCoverSkeleton
                                    ? "absolute"
                                    : undefined,
                                width: "100%",
                            }}
                        />
                    )}
                    <Box
                        aria-hidden
                        sx={{
                            background: profileCoverTopShadow,
                            height: profileHeaderHeight + 8,
                            insetInline: 0,
                            pointerEvents: "none",
                            position: "absolute",
                            top: 0,
                        }}
                    />
                </Box>
                {canOpenProfileCover && (
                    <Box
                        component="button"
                        type="button"
                        aria-label="Open cover image"
                        onClick={onOpenProfileCover}
                        sx={{
                            bgcolor: "transparent",
                            border: 0,
                            cursor: "pointer",
                            height: profileCoverHeight,
                            insetInline: 0,
                            p: 0,
                            position: "absolute",
                            top: 0,
                            width: "100%",
                            zIndex: 2,
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: -4,
                            },
                        }}
                    />
                )}
                <Box
                    component="header"
                    sx={{
                        alignItems: "center",
                        color: coverForeground,
                        display: "grid",
                        gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                        height: profileHeaderHeight,
                        position: "relative",
                        px: 2,
                        py: 0,
                        width: "100%",
                        zIndex: 3,
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label={
                            isFriendProfile ? "Back to friends" : "Back to home"
                        }
                        onClick={onBack}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: "inherit",
                            cursor: "pointer",
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
                    <Box
                        component="h1"
                        sx={{
                            color: "inherit",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 18,
                            fontWeight: 700,
                            justifySelf: "center",
                            lineHeight: "24px",
                            m: 0,
                            maxWidth: "100%",
                            overflow: "hidden",
                            px: "4px",
                            textOverflow: "ellipsis",
                            whiteSpace: "nowrap",
                        }}
                    >
                        {profile.username}
                    </Box>
                    {isOwnerProfile ? (
                        <Box
                            component="button"
                            type="button"
                            aria-label="Settings"
                            onClick={onOpenSettings}
                            sx={{
                                alignItems: "center",
                                bgcolor: "transparent",
                                border: 0,
                                color: "inherit",
                                cursor: onOpenSettings ? "pointer" : "default",
                                display: "flex",
                                height: spaceTouchTargetSize,
                                justifyContent: "flex-end",
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
                                icon={Menu01Icon}
                                size={20}
                                strokeWidth={2.4}
                            />
                        </Box>
                    ) : (
                        <Box aria-hidden sx={{ width: spaceTouchTargetSize }} />
                    )}
                </Box>
                <Box
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        flexDirection: "column",
                        px: "16px",
                        position: "relative",
                        pt: `${profileAvatarTopOffset}px`,
                        textAlign: "center",
                        width: "100%",
                    }}
                >
                    <Box
                        sx={{
                            position: "relative",
                            width: profileAvatarSize,
                            zIndex: 3,
                        }}
                    >
                        <Box
                            component={canOpenProfilePhoto ? "button" : "div"}
                            type={canOpenProfilePhoto ? "button" : undefined}
                            aria-label={
                                canOpenProfilePhoto
                                    ? "Open profile picture"
                                    : undefined
                            }
                            onClick={onOpenProfilePhoto}
                            sx={{
                                alignItems: "center",
                                aspectRatio: "1 / 1",
                                bgcolor: profileCoverSkeletonBackground,
                                border: "4px solid #FFFFFF",
                                borderRadius: "50%",
                                boxSizing: "border-box",
                                cursor: canOpenProfilePhoto
                                    ? "pointer"
                                    : "default",
                                display: "flex",
                                justifyContent: "center",
                                overflow: "hidden",
                                p: 0,
                                width: "100%",
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 3,
                                },
                            }}
                        >
                            {profile.avatarUrl || !profile.avatarObjectID ? (
                                <SpaceAvatarImage src={profile.avatarUrl} />
                            ) : (
                                <Skeleton
                                    variant="circular"
                                    sx={{
                                        bgcolor: profileCoverSkeletonBackground,
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
                            display: "flex",
                            flexDirection: "column",
                            mt: "14px",
                            minWidth: 0,
                            width: "100%",
                        }}
                    >
                        <Box
                            sx={{
                                alignItems: "center",
                                display: "grid",
                                gridTemplateColumns:
                                    "minmax(0, 1fr) minmax(0, max-content) minmax(0, 1fr)",
                                height: "32px",
                                minWidth: 0,
                                position: "relative",
                                width: "100%",
                            }}
                        >
                            <Box
                                sx={{
                                    color: textStrong,
                                    fontFamily:
                                        '"Nunito", "Inter Variable", sans-serif',
                                    fontSize: 26,
                                    fontWeight: 800,
                                    gridColumn: 2,
                                    lineHeight: "32px",
                                    maxWidth: "calc(100vw - 72px)",
                                    "@media (min-width: 600px)": {
                                        maxWidth: 303,
                                    },
                                    overflow: "hidden",
                                    textOverflow: "ellipsis",
                                    whiteSpace: "nowrap",
                                }}
                            >
                                {displayName}
                            </Box>
                            {isOwnerProfile && (
                                <Box
                                    component="button"
                                    type="button"
                                    aria-label="Share profile"
                                    onClick={() => void shareProfile()}
                                    sx={{
                                        alignItems: "center",
                                        bgcolor: "transparent",
                                        border: 0,
                                        color: textStrong,
                                        cursor: profileLink
                                            ? "pointer"
                                            : "default",
                                        display: "flex",
                                        gridColumn: 3,
                                        height: spaceTouchTargetSize,
                                        justifyContent: "flex-start",
                                        justifySelf: "start",
                                        ml: "8px",
                                        p: 0,
                                        position: "absolute",
                                        top: "50%",
                                        transform: "translateY(-50%)",
                                        width: spaceTouchTargetSize,
                                        "&:focus-visible": {
                                            borderRadius: "50%",
                                            outline: `2px solid ${green}`,
                                            outlineOffset: 2,
                                        },
                                    }}
                                >
                                    <SpaceShareIcon strokeWidth={2.2} />
                                </Box>
                            )}
                        </Box>
                        {isStatsLoading ? (
                            <ProfileStatsSkeleton />
                        ) : (
                            <Box
                                sx={{
                                    color: textSoft,
                                    display: "flex",
                                    gap: "5px",
                                    alignItems: "baseline",
                                    flexWrap: "wrap",
                                    justifyContent: "center",
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 16,
                                    fontWeight: 600,
                                    lineHeight: "20px",
                                    mt: "2px",
                                    maxWidth: "100%",
                                    overflow: "hidden",
                                    textOverflow: "ellipsis",
                                    whiteSpace: "nowrap",
                                }}
                            >
                                <Box component="span" sx={{ color: textBase }}>
                                    {postsSharedCount}
                                </Box>
                                <Box component="span">
                                    {postsSharedCount == 1 ? "post" : "posts"}
                                </Box>
                                <Box component="span">·</Box>
                                <Box
                                    component={
                                        canOpenFriends ? "button" : "span"
                                    }
                                    type={canOpenFriends ? "button" : undefined}
                                    aria-label={
                                        canOpenFriends
                                            ? "Open friends"
                                            : undefined
                                    }
                                    onClick={
                                        canOpenFriends
                                            ? onOpenFriends
                                            : undefined
                                    }
                                    sx={{
                                        alignItems: "baseline",
                                        bgcolor: "transparent",
                                        border: 0,
                                        color: "inherit",
                                        cursor: canOpenFriends
                                            ? "pointer"
                                            : "default",
                                        display: "inline-flex",
                                        gap: "5px",
                                        font: "inherit",
                                        lineHeight: "inherit",
                                        p: 0,
                                        "&:focus-visible": {
                                            borderRadius: "6px",
                                            outline: `2px solid ${green}`,
                                            outlineOffset: 2,
                                        },
                                    }}
                                >
                                    <Box
                                        component="span"
                                        sx={{ color: textBase }}
                                    >
                                        {friendsCount}
                                    </Box>
                                    <Box component="span">
                                        {friendsCount == 1
                                            ? "friend"
                                            : "friends"}
                                    </Box>
                                </Box>
                            </Box>
                        )}
                    </Box>
                </Box>
                <Box
                    component="section"
                    sx={{
                        alignItems: "stretch",
                        boxSizing: "border-box",
                        display: "flex",
                        flex: hasProfilePosts ? "0 0 auto" : "1 1 0",
                        flexDirection: "column",
                        gap: "24px",
                        minHeight: hasProfilePosts ? undefined : 0,
                        mt: "24px",
                        pb: "16px",
                        px: 0,
                        width: "100%",
                    }}
                >
                    {hasProfilePosts ? (
                        visiblePostGroups.map((group) => {
                            const masonryRows = buildPostMasonryRows(
                                group.items,
                                loadedPhotoDimensionsByID,
                            );

                            return (
                                <Box
                                    component="section"
                                    key={group.label}
                                    sx={{ width: "100%" }}
                                >
                                    <Box
                                        sx={{
                                            mb: "10px",
                                            px: "18px",
                                            width: "100%",
                                        }}
                                    >
                                        <Box
                                            component="h2"
                                            sx={{
                                                color: textStrong,
                                                fontFamily:
                                                    '"Inter Variable", Inter, sans-serif',
                                                fontSize: 14,
                                                fontWeight: 650,
                                                letterSpacing: 0,
                                                lineHeight: "20px",
                                                m: 0,
                                            }}
                                        >
                                            {group.label}
                                        </Box>
                                    </Box>
                                    <Box
                                        sx={{
                                            borderRadius: photoMasonryRadius,
                                            display: "flex",
                                            flexDirection: "column",
                                            gap: photoMasonryGap,
                                            mx: "16px",
                                            overflow: "hidden",
                                            width: "calc(100% - 32px)",
                                        }}
                                    >
                                        {masonryRows.map((row, rowIndex) => {
                                            const isSingleItemRow =
                                                row.tiles.length == 1;
                                            return (
                                                <Box
                                                    key={`${group.label}-row-${rowIndex}`}
                                                    sx={{
                                                        display: "flex",
                                                        gap: photoMasonryGap,
                                                        aspectRatio:
                                                            isSingleItemRow
                                                                ? undefined
                                                                : `${row.aspectRatio} / 1`,
                                                        width: "100%",
                                                    }}
                                                >
                                                    {row.tiles.map(
                                                        ({
                                                            aspectRatio,
                                                            dimensions,
                                                            item,
                                                            index,
                                                        }) => {
                                                            const imageUrl =
                                                                loadedPostImageURLFor(
                                                                    item,
                                                                );
                                                            return (
                                                                <ProfilePostTile
                                                                    key={`${group.label}-${item.id}-${index}`}
                                                                    aspectRatio={
                                                                        aspectRatio
                                                                    }
                                                                    dimensions={
                                                                        dimensions
                                                                    }
                                                                    displayName={
                                                                        displayName
                                                                    }
                                                                    groupLabel={
                                                                        group.label
                                                                    }
                                                                    imageUrl={
                                                                        imageUrl
                                                                    }
                                                                    index={
                                                                        index
                                                                    }
                                                                    isSingleItemRow={
                                                                        isSingleItemRow
                                                                    }
                                                                    item={item}
                                                                    onLoadImage={() =>
                                                                        loadPostImage(
                                                                            item,
                                                                        )
                                                                    }
                                                                    onOpen={(
                                                                        openedImageUrl,
                                                                    ) =>
                                                                        setSelectedPost(
                                                                            selectedPostForItem(
                                                                                item,
                                                                                visiblePostIndexByID.get(
                                                                                    item.id,
                                                                                ) ??
                                                                                    index,
                                                                                openedImageUrl,
                                                                            ),
                                                                        )
                                                                    }
                                                                    onRememberDimensions={
                                                                        rememberLoadedPhotoDimensions
                                                                    }
                                                                />
                                                            );
                                                        },
                                                    )}
                                                </Box>
                                            );
                                        })}
                                    </Box>
                                </Box>
                            );
                        })
                    ) : shouldShowPostLoadingIndicator ? (
                        <ProfilePostLoadingIndicator />
                    ) : isPostsLoading ? null : (
                        <Box
                            sx={{
                                alignItems: "center",
                                boxSizing: "border-box",
                                display: "flex",
                                flexDirection: "column",
                                justifyContent: "center",
                                minHeight: 0,
                                pb: 0,
                                pointerEvents: "none",
                                position: "absolute",
                                px: 3,
                                top: `${profileCoverHeight}px`,
                                bottom: 0,
                                insetInline: 0,
                                textAlign: "center",
                                width: "100%",
                            }}
                        >
                            <Box
                                component="p"
                                sx={{
                                    color: textSoft,
                                    fontFamily:
                                        '"Inter Variable", Inter, sans-serif',
                                    fontSize: 14,
                                    fontWeight: 500,
                                    lineHeight: "20px",
                                    m: 0,
                                    maxWidth: isOwnerProfile ? 230 : 250,
                                }}
                            >
                                {isOwnerProfile
                                    ? "What are you up to?"
                                    : `${firstName} hasn't posted anything yet.`}
                            </Box>
                            {isOwnerProfile && (
                                <Box
                                    className="green-bg"
                                    component="button"
                                    type="button"
                                    disabled={isPostPhotoOpening}
                                    onClick={openPostPhotoPicker}
                                    sx={{
                                        appearance: "none",
                                        alignItems: "center",
                                        bgcolor: green,
                                        border: 0,
                                        borderRadius: "20px",
                                        boxSizing: "border-box",
                                        color: "#FFFFFF",
                                        cursor: isPostPhotoOpening
                                            ? "default"
                                            : "pointer",
                                        display: "inline-flex",
                                        fontFamily:
                                            '"Inter Variable", Inter, sans-serif',
                                        fontSize: 14,
                                        fontWeight: 600,
                                        gap: "8px",
                                        height: spaceTouchTargetSize,
                                        justifyContent: "center",
                                        lineHeight: "20px",
                                        mt: "24px",
                                        px: "16px",
                                        py: 0,
                                        pointerEvents: "auto",
                                        whiteSpace: "nowrap",
                                        "& svg": {
                                            display: "block",
                                            flexShrink: 0,
                                        },
                                        "&:focus-visible": {
                                            outline: `2px solid ${green}`,
                                            outlineOffset: 2,
                                        },
                                        "&:hover": isPostPhotoOpening
                                            ? undefined
                                            : { bgcolor: "#07AE22" },
                                    }}
                                >
                                    <HugeiconsIcon
                                        icon={AddSquareIcon}
                                        size={20}
                                        strokeWidth={1.8}
                                    />
                                    Post
                                </Box>
                            )}
                        </Box>
                    )}
                </Box>
                {isOwnerProfile && (
                    <SpacePostFloatingActionButton
                        disabled={isPostPhotoOpening}
                        onClick={openPostPhotoPicker}
                    />
                )}
                {profileShareToast && (
                    <ProfileToast
                        message={profileShareToast.message}
                        open={profileShareToast.open}
                        onClose={hideProfileShareToast}
                        onExited={clearClosedProfileShareToast}
                    />
                )}
                {selectedPost && (
                    <SpaceFileViewer
                        photo={selectedPost.photo}
                        draftPostPreparationError={selectedPost.draftImageError}
                        isDraftPostPreviewPending={
                            selectedPost.isDraftImagePreviewPending
                        }
                        postActionMode={
                            selectedPost.postActionMode ??
                            selectedPostActionMode
                        }
                        photos={
                            selectedPost.postIndex == undefined
                                ? undefined
                                : profileViewerPhotos
                        }
                        photoIndex={selectedPost.postIndex}
                        onPhotoIndexChange={
                            selectedPost.postIndex == undefined
                                ? undefined
                                : handleSelectedPostIndexChange
                        }
                        onClose={closeSelectedPost}
                        onDeletePost={
                            isOwnerProfile ? deleteSelectedPost : undefined
                        }
                        onOpenProfile={closeSelectedPost}
                        onReplyToPost={
                            isFriendProfile ? onReplyToPost : undefined
                        }
                        onPublishDraftPost={
                            selectedPost.draftFile && onCreatePost
                                ? (caption, edit) => {
                                      const previewUrl =
                                          selectedPost.photo.imageUrl;
                                      const publishPromise = onCreatePost(
                                          {
                                              cropArea: edit.cropArea,
                                              file: selectedPost.draftFile!,
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
                        onDraftPostPublished={
                            onDraftPostPublished
                                ? () => {
                                      void clearSelectedPostHistory(
                                          "back",
                                      ).finally(onDraftPostPublished);
                                  }
                                : undefined
                        }
                        onSetPostLiked={onSetPostLiked}
                    />
                )}
            </Box>
        </Box>
    );
};
