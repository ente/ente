import {
    AddSquareIcon,
    ArrowLeft02Icon,
    BubbleChatIcon,
    Menu01Icon,
    MoreHorizontalIcon,
    Tick02Icon,
    UserRemove01Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Menu, MenuItem, Skeleton } from "@mui/material";
import {
    spaceActionDoneDurationMs,
    type SpaceActionPhase,
} from "components/ActionFeedback";
import {
    SpaceActionToast,
    spaceToastAutoDismissDurationMs,
} from "components/ActionToast";
import { SpaceAvatarImage } from "components/AvatarImage";
import { SpaceButtonSpinner } from "components/ButtonSpinner";
import { SpaceCaptionText } from "components/CaptionText";
import { ConfirmationActionSheet } from "components/ConfirmationActionSheet";
import { SpaceFeedPostButton } from "components/FeedPostButton";
import {
    SpaceFileViewer,
    type SpaceViewerPhoto,
    type SpaceViewerPostActionMode,
} from "components/FileViewer";
import { SpacePostComposer } from "components/PostComposer";
import { SpacePostPhotoInput } from "components/PostPhotoInput";
import { SpacePostPhotosBadge } from "components/PostPhotosBadge";
import { SpaceLoadingSpinner } from "components/RouteFallback";
import { SpaceShareIcon } from "components/ShareInviteButton";
import { SpaceSkipLink } from "components/SkipLink";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React, { useState } from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";
import type { SpaceInviteIntent } from "services/invite";
import {
    isSpaceContentError,
    type SpacePostAsset,
    type SpacePostPhoto,
} from "services/space";
import { spaceEmptyStateButtonSx } from "styles/buttons";
import {
    spaceAppBackground,
    spaceAppBackgroundColor,
    spaceDialogBackground,
    spaceSurface,
    spaceSurfaceHover,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import {
    minimumPostPhotoFrameAspectRatio,
    spaceProfilePostRadius,
} from "styles/tiles";
import { spaceTouchTargetSize } from "styles/touch-targets";
import { firstNameFrom, formatSpaceDate } from "utils/display";
import {
    spaceDefaultCoverImagePath,
    type SpaceDraftPostImage,
} from "utils/post-image";
import { viewerPhotosFromPost } from "utils/post-photos";
import { thumbHashDataURLFromBase64 } from "utils/thumbhash";

const green = "#08C225";
const dangerColor = "#F63A3A";
const textBase = spaceText;
const textSoft = spaceTextMuted;
const coverForeground = "#FFFFFF";
const profileIdentityColor = spaceText;
const profileStatsColor = spaceTextMuted;
const profileStatsValueColor = spaceText;
const profileCoverBackground = "#1F1F1F";
const profileCoverTopShadow =
    "linear-gradient(180deg, rgba(0, 0, 0, 0.26) 0%, rgba(0, 0, 0, 0.18) 36%, rgba(0, 0, 0, 0.08) 72%, rgba(0, 0, 0, 0) 100%)";
const profileCoverSkeletonBackground = spaceSurface;
const profileHeaderHeight = 56;
const profileAvatarTopOffset = 54;
const profileAvatarSize = 132;
const profileCoverHeight =
    profileHeaderHeight + profileAvatarTopOffset + profileAvatarSize / 2;
const photoPlaceholderBackground = spaceSurface;
const profileCoverRadius = "12px";
const profilePostLoadRootMargin = "800px 0px";
const publicProfilePostLoadRootMargin = "400px 0px";
interface ProfilePhotoDimensions {
    height: number;
    width: number;
}

export interface ProfilePostItem {
    avatarUrl?: string | null;
    caption?: string;
    friendID?: string;
    height?: number;
    id: string;
    imageAsset?: SpacePostAsset;
    imageUrl?: string;
    photos?: SpacePostPhoto[];
    isUnavailable?: boolean;
    name?: string;
    postId?: number;
    spaceId?: string;
    timestampMs: number;
    thumbHash?: string;
    viewerLiked?: boolean;
    width?: number;
}

interface SelectedProfilePost {
    id: string;
    photo: SpaceViewerPhoto;
    photoIndex: number;
}

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
                bgcolor: photoPlaceholderBackground,
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
                bgcolor: photoPlaceholderBackground,
                borderRadius: "999px",
                height: 18,
                transform: "none",
                width: 68,
            }}
        />
    </Box>
);

interface PublicProfileActionButtonProps {
    disabled?: boolean;
    label: string;
    onClick: () => void;
    showSpinner?: boolean;
}

const PublicProfileActionButton: React.FC<PublicProfileActionButtonProps> = ({
    disabled = false,
    label,
    onClick,
    showSpinner = false,
}) => (
    <Box
        component="button"
        type="button"
        disabled={disabled}
        onClick={onClick}
        sx={{
            alignItems: "center",
            appearance: "none",
            bgcolor: spaceSurface,
            border: 0,
            borderRadius: "14px",
            color: spaceText,
            cursor: disabled ? "default" : "pointer",
            display: "flex",
            flexShrink: 0,
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 14,
            fontWeight: 600,
            justifyContent: "center",
            justifySelf: "end",
            lineHeight: "18px",
            px: "14px",
            py: "8px",
            "&:hover": { bgcolor: disabled ? spaceSurface : spaceSurfaceHover },
            "&:focus-visible": {
                outline: `2px solid ${green}`,
                outlineOffset: 2,
            },
        }}
    >
        {showSpinner ? <SpaceButtonSpinner /> : label}
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

interface ProfilePostProps {
    dimensions: ProfilePhotoDimensions;
    displayName: string;
    imageUrl?: string;
    index: number;
    isUnavailable: boolean;
    item: ProfilePostItem;
    loadRootMargin: string;
    onImageDecodeError: () => void;
    onLoadImage: () => Promise<string | undefined>;
    onOpen: (imageUrl: string) => void;
    onRememberDimensions: (itemID: string, image: HTMLImageElement) => void;
}

const ProfilePost: React.FC<ProfilePostProps> = ({
    dimensions,
    displayName,
    imageUrl,
    index,
    isUnavailable: isPostUnavailable,
    item,
    loadRootMargin,
    onImageDecodeError,
    onLoadImage,
    onOpen,
    onRememberDimensions,
}) => {
    const [shouldLoad, setShouldLoad] = React.useState(Boolean(imageUrl));
    const [readyImageUrl, setReadyImageUrl] = React.useState<string>();
    const [imageDecodeFailed, setImageDecodeFailed] = React.useState(false);
    const postRef = React.useRef<HTMLElement | null>(null);
    const thumbHashDataURL = React.useMemo(
        () => thumbHashDataURLFromBase64(item.thumbHash),
        [item.thumbHash],
    );
    const isCurrentImageReady = Boolean(imageUrl && readyImageUrl == imageUrl);
    const isUnavailable = isPostUnavailable || imageDecodeFailed;
    const aspectRatio =
        dimensions.width > 0 && dimensions.height > 0
            ? dimensions.width / dimensions.height
            : 1;
    const frameAspectRatio = Math.max(
        minimumPostPhotoFrameAspectRatio,
        aspectRatio,
    );
    const caption = item.caption?.trim();
    const photoCount = item.photos?.length ?? 1;

    React.useEffect(() => {
        if (imageUrl) setShouldLoad(true);
    }, [imageUrl]);

    React.useEffect(() => {
        if (isUnavailable) return;
        if (shouldLoad || imageUrl) return;
        const element = postRef.current;
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
            { rootMargin: loadRootMargin },
        );
        observer.observe(element);
        return () => observer.disconnect();
    }, [imageUrl, isUnavailable, loadRootMargin, shouldLoad]);

    React.useEffect(() => {
        if (isUnavailable) return;
        if (!shouldLoad || imageUrl) return;
        void onLoadImage().catch((error: unknown) => {
            log.warn("Failed to load profile post image", error);
        });
    }, [imageUrl, isUnavailable, onLoadImage, shouldLoad]);

    return (
        <Box
            ref={postRef}
            component="article"
            sx={{
                aspectRatio: frameAspectRatio,
                bgcolor: photoPlaceholderBackground,
                borderRadius: `${spaceProfilePostRadius}px`,
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
            <Box
                component="button"
                type="button"
                aria-label={
                    isUnavailable
                        ? "Post unavailable"
                        : `Open ${displayName} post ${index + 1}${
                              photoCount > 1 ? `, ${photoCount} photos` : ""
                          }`
                }
                disabled={!imageUrl || isUnavailable}
                onClick={() => {
                    if (imageUrl && !isUnavailable) onOpen(imageUrl);
                }}
                sx={{
                    appearance: "none",
                    bgcolor: "transparent",
                    border: 0,
                    cursor: imageUrl && !isUnavailable ? "pointer" : "default",
                    display: "block",
                    height: "100%",
                    p: 0,
                    position: "relative",
                    width: "100%",
                    "&:focus-visible": {
                        outline: `2px solid ${green}`,
                        outlineOffset: -2,
                    },
                }}
            >
                {!isUnavailable && thumbHashDataURL ? (
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
                {!isUnavailable && imageUrl ? (
                    <Box
                        component="img"
                        alt={`${displayName} post ${index + 1}`}
                        onLoad={(event) => {
                            setReadyImageUrl(imageUrl);
                            onRememberDimensions(item.id, event.currentTarget);
                        }}
                        onError={() => {
                            log.warn(
                                `Post ${item.postId} is unavailable because the browser could not decode its image`,
                            );
                            setImageDecodeFailed(true);
                            onImageDecodeError();
                        }}
                        src={imageUrl}
                        sx={{
                            display: "block",
                            height: "100%",
                            inset: 0,
                            objectFit: "cover",
                            objectPosition: "center",
                            opacity:
                                isCurrentImageReady || !thumbHashDataURL
                                    ? 1
                                    : 0,
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
                {isUnavailable && (
                    <Box
                        sx={{
                            alignItems: "center",
                            color: textSoft,
                            display: "flex",
                            fontSize: 12,
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
            {!isUnavailable && (
                <>
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
                        }}
                    />
                    <Box
                        component="time"
                        dateTime={new Date(item.timestampMs).toISOString()}
                        sx={{
                            color: "#C8C8C8",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 12,
                            fontWeight: 500,
                            left: 16,
                            lineHeight: "16px",
                            pointerEvents: "none",
                            position: "absolute",
                            top: 16,
                        }}
                    >
                        {formatSpaceDate(item.timestampMs)}
                    </Box>
                    <SpacePostPhotosBadge count={photoCount} inset={12} />
                    {caption && (
                        <Box
                            title={caption}
                            sx={{
                                bottom: 20,
                                color: "#E6E6E6",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 13,
                                fontWeight: 600,
                                left: "50%",
                                lineHeight: "21px",
                                maxWidth: "78%",
                                pointerEvents: "none",
                                position: "absolute",
                                textAlign: "center",
                                textWrap: "balance",
                                transform: "translateX(-50%)",
                                width: "max-content",
                            }}
                        >
                            <SpaceCaptionText caption={caption} lineClamp={2} />
                        </Box>
                    )}
                </>
            )}
        </Box>
    );
};

interface ProfileScreenProps {
    friendsCount?: number;
    headerVariant?: "friend" | "owner" | "public" | "public-anonymous";
    isAddingFriend?: boolean;
    showAddingFriendSpinner?: boolean;
    isCoverLoading?: boolean;
    isNameLoading?: boolean;
    isPostsLoading?: boolean;
    isStatsLoading?: boolean;
    showPostLoadingIndicator?: boolean;
    onBack?: () => void;
    onPostSubmitted?: () => void;
    onAddFriend?: () => void;
    onAddFriendForPostAction?: (intent: SpaceInviteIntent) => void;
    onCreateSpace?: () => void;
    onCreatePost?: (
        images: SpaceDraftPostImage[],
        caption: string,
    ) => Promise<void>;
    onDeletePost?: (postId: number) => Promise<void> | void;
    onOpenFriends?: () => void;
    onOpenProfileCover?: () => void;
    onOpenProfilePhoto?: () => void;
    onOpenSettings?: () => void;
    onLoadPostImage?: (asset: SpacePostAsset) => Promise<string>;
    onMessageFriend?: () => void;
    onReplyToPost?: (
        postSpaceId: string,
        postId: number,
        text: string,
        objectKey: string,
    ) => Promise<void>;
    onSetPostLiked?: (postId: number, liked: boolean) => Promise<void>;
    onUnfriend?: () => Promise<void> | void;
    onUnfriendComplete?: () => void;
    onUpdatePostCaption?: (postId: number, caption: string) => Promise<void>;
    postItems?: ProfilePostItem[];
    postsCount?: number;
    profile: SetupProfile;
    profileLink?: string;
    publicNotificationControl?: React.ReactNode;
}

export const ProfileScreen: React.FC<ProfileScreenProps> = ({
    friendsCount = 0,
    headerVariant = "owner",
    isAddingFriend = false,
    isCoverLoading = false,
    isNameLoading = false,
    isPostsLoading = false,
    isStatsLoading = false,
    onBack,
    onPostSubmitted,
    onAddFriend,
    onAddFriendForPostAction,
    onCreateSpace,
    onCreatePost,
    onDeletePost,
    onOpenFriends,
    onOpenProfileCover,
    onOpenProfilePhoto,
    onOpenSettings,
    onLoadPostImage,
    onMessageFriend,
    onReplyToPost,
    onSetPostLiked,
    onUnfriend,
    onUnfriendComplete,
    onUpdatePostCaption,
    postItems = [],
    postsCount,
    profile,
    profileLink,
    publicNotificationControl,
    showAddingFriendSpinner = isAddingFriend,
    showPostLoadingIndicator,
}) => {
    const [selectedPost, setSelectedPost] =
        useState<SelectedProfilePost | null>(null);
    const [draftFiles, setDraftFiles] = useState<File[] | null>(null);
    const isPostPhotoOpening = Boolean(draftFiles);
    const [isInviteLinkCopied, setIsInviteLinkCopied] = useState(false);
    const [deletedPostIDs, setDeletedPostIDs] = useState<Set<string>>(
        () => new Set(),
    );
    const [friendActionsAnchor, setFriendActionsAnchor] =
        useState<HTMLElement | null>(null);
    const [isUnfriendSheetOpen, setIsUnfriendSheetOpen] = useState(false);
    const [unfriendActionPhase, setUnfriendActionPhase] =
        useState<SpaceActionPhase | null>(null);
    const [unfriendErrorMessage, setUnfriendErrorMessage] = useState<
        string | null
    >(null);
    const [loadedPhotoDimensionsByID, setLoadedPhotoDimensionsByID] = useState<
        Record<string, ProfilePhotoDimensions>
    >({});
    const [loadedPostImageURLsByKey, setLoadedPostImageURLsByKey] = useState<
        Record<string, string>
    >({});
    const [unavailablePostsByKey, setUnavailablePostsByKey] = useState<
        Record<string, true>
    >({});
    const [loadedCoverUrl, setLoadedCoverUrl] = useState<string | null>(null);
    const postInputRef = React.useRef<HTMLInputElement | null>(null);
    const postImageLoadsInFlightRef = React.useRef<
        Map<string, Promise<string | undefined>>
    >(new Map());
    const isOwnerProfile = headerVariant == "owner";
    const isFriendProfile = headerVariant == "friend";
    const isAnonymousPublicProfile = headerVariant == "public-anonymous";
    const isPublicProfile =
        headerVariant == "public" || isAnonymousPublicProfile;
    const friendActionsButtonID = React.useId();
    const friendActionsMenuID = React.useId();
    const isFriendActionsOpen = Boolean(friendActionsAnchor);
    const isUnfriendActionRunning = unfriendActionPhase != null;
    const canManageFriend = isFriendProfile && Boolean(onUnfriend);
    const displayName = profile.fullName.trim() || profile.username.trim();
    const coverUrl = profile.coverUrl ?? null;
    const isCoverURLPending = Boolean(profile.coverObjectID && !coverUrl);
    const coverImageUrl = coverUrl
        ? coverUrl
        : isCoverURLPending
          ? undefined
          : spaceDefaultCoverImagePath;
    const firstName = firstNameFrom(displayName);
    const visiblePostItems = postItems.filter(
        (item) => !deletedPostIDs.has(item.id),
    );
    const viewerPostItems = visiblePostItems.filter(
        (item) =>
            !item.isUnavailable &&
            !unavailablePostsByKey[profilePostImageCacheKey(item)],
    );
    const viewerPostIndexByID = new Map(
        viewerPostItems.map((item, index) => [item.id, index]),
    );
    const postsSharedCount = visiblePostItems.length;
    const displayedPostsCount = postsCount ?? postsSharedCount;
    const canOpenFriends = isOwnerProfile && Boolean(onOpenFriends);
    const canOpenProfileCover = Boolean(onOpenProfileCover);
    const canOpenProfilePhoto = Boolean(onOpenProfilePhoto);
    const hasProfilePosts = postsSharedCount > 0;
    const shouldShowPostLoadingIndicator =
        isPostsLoading && (showPostLoadingIndicator ?? true);
    const isCoverImageLoading = Boolean(
        coverImageUrl && loadedCoverUrl != coverImageUrl,
    );
    const shouldShowCoverSkeleton =
        isCoverLoading || isCoverURLPending || isCoverImageLoading;
    const selectedPostActionMode: SpaceViewerPostActionMode =
        isOwnerProfile || (isPublicProfile && !onAddFriendForPostAction)
            ? "hidden"
            : "like-only";
    const postImageLoadRootMargin = isAnonymousPublicProfile
        ? publicProfilePostLoadRootMargin
        : profilePostLoadRootMargin;
    const closeFriendActions = () => setFriendActionsAnchor(null);

    const requestUnfriend = () => {
        closeFriendActions();
        setUnfriendErrorMessage(null);
        setIsUnfriendSheetOpen(true);
    };

    const cancelUnfriend = () => {
        if (isUnfriendActionRunning) return;
        setUnfriendErrorMessage(null);
        setIsUnfriendSheetOpen(false);
    };

    const confirmUnfriend = () => {
        if (!onUnfriend || isUnfriendActionRunning) return;
        setUnfriendErrorMessage(null);
        setUnfriendActionPhase("busy");
        void (async () => {
            try {
                await Promise.resolve(onUnfriend());
                setUnfriendActionPhase("done");
            } catch (error) {
                log.error("Failed to unfriend space friend", error);
                setUnfriendActionPhase(null);
                setUnfriendErrorMessage("Couldn't unfriend. Please try again.");
            }
        })();
    };

    React.useEffect(() => {
        if (unfriendActionPhase != "done") return;

        const timeoutID = window.setTimeout(() => {
            setIsUnfriendSheetOpen(false);
            onUnfriendComplete?.();
        }, spaceActionDoneDurationMs);

        return () => window.clearTimeout(timeoutID);
    }, [onUnfriendComplete, unfriendActionPhase]);

    const handleUnfriendSheetExited = () => {
        setUnfriendActionPhase(null);
        setUnfriendErrorMessage(null);
    };

    const openPostPhotoPicker = () => {
        if (!isPostPhotoOpening) postInputRef.current?.click();
    };
    const closeSelectedPost = () => setSelectedPost(null);
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
            if (unavailablePostsByKey[cacheKey]) {
                return Promise.resolve(undefined);
            }
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
                    log.warn("Failed to load profile post image", error);
                    if (isSpaceContentError(error)) {
                        setUnavailablePostsByKey((current) => ({
                            ...current,
                            [cacheKey]: true,
                        }));
                    }
                    return undefined;
                })
                .finally(() => {
                    postImageLoadsInFlightRef.current.delete(cacheKey);
                });
            postImageLoadsInFlightRef.current.set(cacheKey, load);
            return load;
        },
        [loadedPostImageURLFor, onLoadPostImage, unavailablePostsByKey],
    );

    const dimensionsForPost = React.useCallback(
        (item: ProfilePostItem): ProfilePhotoDimensions =>
            loadedPhotoDimensionsByID[item.id] ?? {
                height: item.height ?? 1,
                width: item.width ?? 1,
            },
        [loadedPhotoDimensionsByID],
    );

    const profileViewerPhotos = viewerPostItems.flatMap((item) =>
        viewerPhotosFromPost({
            ...item,
            ...dimensionsForPost(item),
            avatarUrl: profile.avatarUrl,
            imageUrl: loadedPostImageURLFor(item),
            name: displayName,
        }),
    );
    const handleSelectedPostIndexChange = (photoIndex: number) => {
        const photo = profileViewerPhotos[photoIndex];
        if (!photo) return;
        const item = viewerPostItems.find(
            (item) => item.postId == photo.postId,
        );
        if (item) setSelectedPost({ id: item.id, photo, photoIndex });
    };

    const shareInvite = async () => {
        if (!profileLink) return;

        try {
            if (typeof navigator.share == "function") {
                await navigator.share({ url: profileLink });
            } else {
                await navigator.clipboard.writeText(profileLink);
                setIsInviteLinkCopied(true);
            }
        } catch (error) {
            if (
                !(error instanceof DOMException && error.name == "AbortError")
            ) {
                log.warn("Failed to share Space invite link", error);
            }
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

    const renderPost = (item: ProfilePostItem, index: number) => {
        const imageUrl = loadedPostImageURLFor(item);
        const isUnavailable = !viewerPostIndexByID.has(item.id);
        return (
            <ProfilePost
                key={item.id}
                dimensions={dimensionsForPost(item)}
                displayName={displayName}
                imageUrl={imageUrl}
                index={index}
                isUnavailable={isUnavailable}
                item={item}
                loadRootMargin={postImageLoadRootMargin}
                onLoadImage={() => loadPostImage(item)}
                onImageDecodeError={() =>
                    setUnavailablePostsByKey((current) => ({
                        ...current,
                        [profilePostImageCacheKey(item)]: true,
                    }))
                }
                onOpen={(openedImageUrl) => {
                    const postIndex = viewerPostIndexByID.get(item.id);
                    if (postIndex == undefined) return;
                    const photoIndex = profileViewerPhotos.findIndex(
                        (photo) => photo.postId == item.postId,
                    );
                    setSelectedPost({
                        id: item.id,
                        photoIndex,
                        photo: {
                            ...profileViewerPhotos[photoIndex]!,
                            imageUrl: openedImageUrl,
                        },
                    });
                }}
                onRememberDimensions={rememberLoadedPhotoDimensions}
            />
        );
    };

    const renderHeader = () => {
        return (
            <Box
                component="header"
                sx={{
                    alignItems: "center",
                    color: coverForeground,
                    display: isPublicProfile ? "flex" : "grid",
                    gridTemplateColumns: isPublicProfile
                        ? undefined
                        : `${spaceTouchTargetSize}px minmax(0, 1fr) ${spaceTouchTargetSize}px`,
                    height: profileHeaderHeight,
                    justifyContent: isPublicProfile
                        ? "space-between"
                        : undefined,
                    mx: "auto",
                    position: "relative",
                    px: 2,
                    py: 0,
                    width: "100%",
                    zIndex: 3,
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                {isPublicProfile ? (
                    <>
                        <Box
                            component="a"
                            href="/"
                            aria-label="Go to Space"
                            sx={{
                                display: "block",
                                flexShrink: 0,
                                lineHeight: 0,
                            }}
                        >
                            <Box
                                component="img"
                                alt="Space"
                                src="/images/space.svg"
                                sx={{
                                    display: "block",
                                    height: 17,
                                    width: "auto",
                                }}
                            />
                        </Box>
                        {isAnonymousPublicProfile
                            ? onCreateSpace && (
                                  <PublicProfileActionButton
                                      label="Create your Space"
                                      onClick={onCreateSpace}
                                  />
                              )
                            : onAddFriend && (
                                  <PublicProfileActionButton
                                      disabled={isAddingFriend}
                                      label="Add Friend"
                                      onClick={onAddFriend}
                                      showSpinner={showAddingFriendSpinner}
                                  />
                              )}
                    </>
                ) : (
                    <>
                        <Box
                            component="button"
                            type="button"
                            aria-label={
                                isFriendProfile
                                    ? "Back to friends"
                                    : "Back to home"
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
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
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
                            {firstName}
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
                                    cursor: onOpenSettings
                                        ? "pointer"
                                        : "default",
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
                        ) : onMessageFriend ? (
                            <Box
                                component="button"
                                type="button"
                                aria-label={`Message ${displayName}`}
                                onClick={onMessageFriend}
                                sx={{
                                    alignItems: "center",
                                    bgcolor: "transparent",
                                    border: 0,
                                    color: "inherit",
                                    cursor: "pointer",
                                    display: "flex",
                                    height: spaceTouchTargetSize,
                                    justifyContent: "flex-end",
                                    p: 0,
                                    width: spaceTouchTargetSize,
                                    "& svg path:first-of-type": {
                                        display: "none",
                                    },
                                    "&:focus-visible": {
                                        borderRadius: "50%",
                                        outline: `2px solid ${green}`,
                                        outlineOffset: 2,
                                    },
                                }}
                            >
                                <HugeiconsIcon
                                    icon={BubbleChatIcon}
                                    size={20}
                                    strokeWidth={2}
                                />
                            </Box>
                        ) : (
                            <Box
                                aria-hidden
                                sx={{ width: spaceTouchTargetSize }}
                            />
                        )}
                    </>
                )}
            </Box>
        );
    };

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
            {!isPublicProfile && <SpaceSkipLink />}
            <Box
                sx={{
                    bgcolor: "transparent",
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
                    <SpacePostPhotoInput
                        inputRef={postInputRef}
                        onSelect={setDraftFiles}
                    />
                )}
                <Box
                    sx={{
                        bgcolor: shouldShowCoverSkeleton
                            ? profileCoverSkeletonBackground
                            : profileCoverBackground,
                        borderBottomLeftRadius: profileCoverRadius,
                        borderBottomRightRadius: profileCoverRadius,
                        height: profileCoverHeight,
                        insetInline: 0,
                        overflow: "hidden",
                        position: "absolute",
                        top: 0,
                        width: "100%",
                        zIndex: 0,
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
                {renderHeader()}
                <Box
                    component={isPublicProfile ? "div" : "section"}
                    id={isPublicProfile ? undefined : "space-main-content"}
                    aria-label={
                        isPublicProfile ? undefined : `${displayName}'s profile`
                    }
                    tabIndex={isPublicProfile ? undefined : -1}
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
                                bgcolor: spaceAppBackgroundColor,
                                border: 0,
                                borderRadius: "50%",
                                boxSizing: "border-box",
                                cursor: canOpenProfilePhoto
                                    ? "pointer"
                                    : "default",
                                display: "flex",
                                justifyContent: "center",
                                overflow: "hidden",
                                p: 0,
                                position: "relative",
                                width: "100%",
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 3,
                                },
                            }}
                        >
                            <Box
                                sx={{
                                    bgcolor: profileCoverSkeletonBackground,
                                    borderRadius: "50%",
                                    inset: 3,
                                    overflow: "hidden",
                                    position: "absolute",
                                }}
                            >
                                {profile.avatarUrl ||
                                !profile.avatarObjectID ? (
                                    <SpaceAvatarImage src={profile.avatarUrl} />
                                ) : (
                                    <Skeleton
                                        variant="circular"
                                        sx={{
                                            bgcolor:
                                                profileCoverSkeletonBackground,
                                            height: "100%",
                                            transform: "none",
                                            width: "100%",
                                        }}
                                    />
                                )}
                            </Box>
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
                                    color: profileIdentityColor,
                                    fontFamily:
                                        '"Nunito", "Inter Variable", sans-serif',
                                    fontSize: 26,
                                    fontWeight: 700,
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
                                {isNameLoading ? (
                                    <Skeleton
                                        variant="rounded"
                                        sx={{
                                            bgcolor: photoPlaceholderBackground,
                                            height: 26,
                                            transform: "none",
                                            width: 112,
                                        }}
                                    />
                                ) : isPublicProfile ? (
                                    displayName
                                ) : (
                                    profile.username
                                )}
                            </Box>
                            {isOwnerProfile ? (
                                <Box
                                    component="button"
                                    type="button"
                                    aria-label="Share invite link"
                                    onClick={() => void shareInvite()}
                                    sx={{
                                        alignItems: "center",
                                        bgcolor: "transparent",
                                        border: 0,
                                        color: profileIdentityColor,
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
                            ) : (
                                canManageFriend && (
                                    <Box
                                        component="button"
                                        id={friendActionsButtonID}
                                        type="button"
                                        aria-label={`Actions for ${displayName}`}
                                        aria-controls={
                                            isFriendActionsOpen
                                                ? friendActionsMenuID
                                                : undefined
                                        }
                                        aria-expanded={
                                            isFriendActionsOpen
                                                ? "true"
                                                : undefined
                                        }
                                        aria-haspopup="menu"
                                        onClick={(event) =>
                                            setFriendActionsAnchor(
                                                event.currentTarget,
                                            )
                                        }
                                        sx={{
                                            alignItems: "center",
                                            bgcolor: "transparent",
                                            border: 0,
                                            color: profileIdentityColor,
                                            cursor: "pointer",
                                            display: "flex",
                                            gridColumn: 3,
                                            height: 24,
                                            justifyContent: "flex-start",
                                            justifySelf: "start",
                                            ml: "8px",
                                            p: 0,
                                            width: 24,
                                            "&:focus-visible": {
                                                borderRadius: "50%",
                                                outline: `2px solid ${green}`,
                                                outlineOffset: 2,
                                            },
                                        }}
                                    >
                                        <HugeiconsIcon
                                            icon={MoreHorizontalIcon}
                                            size={24}
                                            strokeWidth={2}
                                        />
                                    </Box>
                                )
                            )}
                            {canManageFriend && (
                                <Menu
                                    id={friendActionsMenuID}
                                    anchorEl={friendActionsAnchor}
                                    open={isFriendActionsOpen}
                                    onClose={closeFriendActions}
                                    anchorOrigin={{
                                        horizontal: "left",
                                        vertical: "bottom",
                                    }}
                                    transformOrigin={{
                                        horizontal: "left",
                                        vertical: "top",
                                    }}
                                    slotProps={{
                                        paper: {
                                            sx: {
                                                bgcolor: spaceDialogBackground,
                                                borderRadius: "14px",
                                                boxShadow:
                                                    "0 14px 40px rgba(0, 0, 0, 0.16)",
                                                mt: "6px",
                                                minWidth: 0,
                                                p: "4px",
                                                width: "max-content",
                                            },
                                        },
                                        list: {
                                            "aria-labelledby":
                                                friendActionsButtonID,
                                            sx: { p: 0 },
                                        },
                                    }}
                                >
                                    {onUnfriend && (
                                        <MenuItem
                                            dense
                                            disableRipple
                                            onClick={requestUnfriend}
                                            sx={{
                                                alignItems: "center",
                                                borderRadius: "10px",
                                                color: dangerColor,
                                                display: "flex",
                                                gap: "8px",
                                                minHeight: 36,
                                                px: "9px",
                                                py: "4px",
                                                whiteSpace: "nowrap",
                                                "&.Mui-focusVisible": {
                                                    bgcolor:
                                                        "rgba(246, 58, 58, 0.14)",
                                                },
                                                "&:active": {
                                                    bgcolor:
                                                        "rgba(246, 58, 58, 0.14)",
                                                },
                                                "&:hover": {
                                                    bgcolor:
                                                        "rgba(246, 58, 58, 0.14)",
                                                },
                                            }}
                                        >
                                            <HugeiconsIcon
                                                icon={UserRemove01Icon}
                                                size={18}
                                                strokeWidth={1.8}
                                                style={{ flexShrink: 0 }}
                                            />
                                            <Box
                                                sx={{
                                                    fontFamily:
                                                        '"Inter Variable", Inter, sans-serif',
                                                    fontSize: 13,
                                                    fontWeight: 650,
                                                    lineHeight: "18px",
                                                }}
                                            >
                                                Unfriend
                                            </Box>
                                        </MenuItem>
                                    )}
                                </Menu>
                            )}
                        </Box>
                        {!isFriendProfile &&
                            (isStatsLoading ? (
                                <ProfileStatsSkeleton />
                            ) : (
                                <Box
                                    sx={{
                                        color: profileStatsColor,
                                        display: "flex",
                                        gap: "5px",
                                        alignItems: "baseline",
                                        flexWrap: "wrap",
                                        justifyContent: "center",
                                        fontFamily:
                                            '"Inter Variable", Inter, sans-serif',
                                        fontSize: 16,
                                        fontWeight: 550,
                                        lineHeight: "20px",
                                        mt: "2px",
                                        maxWidth: "100%",
                                        overflow: "hidden",
                                        textOverflow: "ellipsis",
                                        whiteSpace: "nowrap",
                                    }}
                                >
                                    <Box
                                        component="span"
                                        sx={{ color: profileStatsValueColor }}
                                    >
                                        {displayedPostsCount}
                                    </Box>
                                    <Box component="span">
                                        {displayedPostsCount == 1
                                            ? "post"
                                            : "posts"}
                                    </Box>
                                    <Box component="span">·</Box>
                                    <Box
                                        component={
                                            canOpenFriends ? "button" : "span"
                                        }
                                        type={
                                            canOpenFriends
                                                ? "button"
                                                : undefined
                                        }
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
                                            sx={{
                                                color: profileStatsValueColor,
                                            }}
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
                            ))}
                        {isPublicProfile && publicNotificationControl && (
                            <Box
                                sx={{
                                    display: selectedPost ? "none" : "contents",
                                }}
                            >
                                {publicNotificationControl}
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
                        minHeight: 0,
                        mt: "24px",
                        pb: "16px",
                        px: 0,
                        width: "100%",
                    }}
                >
                    {hasProfilePosts ? (
                        <Box
                            sx={{
                                display: "flex",
                                flexDirection: "column",
                                gap: "24px",
                                mt: "6px",
                                mx: "16px",
                                width: "calc(100% - 32px)",
                            }}
                        >
                            {visiblePostItems.map(renderPost)}
                        </Box>
                    ) : shouldShowPostLoadingIndicator ? (
                        <ProfilePostLoadingIndicator />
                    ) : isPostsLoading ? null : (
                        <Box
                            sx={{
                                alignItems: "center",
                                boxSizing: "border-box",
                                display: "flex",
                                flexDirection: "column",
                                gap: "16px",
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
                            {!isOwnerProfile && (
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
                                        maxWidth: 250,
                                        textWrap: "balance",
                                    }}
                                >
                                    {`${firstName} hasn't posted anything yet.`}
                                </Box>
                            )}
                            {isOwnerProfile && (
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
                                        maxWidth: 250,
                                    }}
                                >
                                    Share something from your day.
                                </Box>
                            )}
                            {isOwnerProfile && (
                                <Box
                                    className="green-bg"
                                    component="button"
                                    type="button"
                                    disabled={isPostPhotoOpening}
                                    onClick={openPostPhotoPicker}
                                    sx={spaceEmptyStateButtonSx}
                                >
                                    <HugeiconsIcon
                                        icon={AddSquareIcon}
                                        size={18}
                                        strokeWidth={1.8}
                                    />
                                    Post
                                </Box>
                            )}
                        </Box>
                    )}
                </Box>
                {isOwnerProfile && hasProfilePosts && (
                    <SpaceFeedPostButton
                        disabled={isPostPhotoOpening}
                        onClick={openPostPhotoPicker}
                    />
                )}
                {draftFiles && onCreatePost && (
                    <SpacePostComposer
                        files={draftFiles}
                        onClose={() => setDraftFiles(null)}
                        onPublish={onCreatePost}
                        onPublished={onPostSubmitted}
                        profile={profile}
                    />
                )}
                {selectedPost && (
                    <SpaceFileViewer
                        photo={selectedPost.photo}
                        photos={profileViewerPhotos}
                        photoIndex={selectedPost.photoIndex}
                        onPhotoIndexChange={handleSelectedPostIndexChange}
                        onLoadPhoto={onLoadPostImage}
                        postActionMode={selectedPostActionMode}
                        onClose={closeSelectedPost}
                        onAddFriendForPostAction={
                            isPublicProfile
                                ? onAddFriendForPostAction
                                : undefined
                        }
                        onDeletePost={
                            isOwnerProfile ? deleteSelectedPost : undefined
                        }
                        onOpenProfile={closeSelectedPost}
                        onReplyToPost={
                            isFriendProfile ? onReplyToPost : undefined
                        }
                        onSetPostLiked={onSetPostLiked}
                        onUpdatePostCaption={
                            isOwnerProfile ? onUpdatePostCaption : undefined
                        }
                    />
                )}
            </Box>
            {isInviteLinkCopied && (
                <SpaceActionToast
                    autoDismissAfterMs={spaceToastAutoDismissDurationMs}
                    closeLabel="Dismiss invite link copied message"
                    icon={
                        <HugeiconsIcon
                            icon={Tick02Icon}
                            size={20}
                            strokeWidth={1.8}
                        />
                    }
                    message="Invite link copied"
                    onClose={() => setIsInviteLinkCopied(false)}
                />
            )}
            <ConfirmationActionSheet
                open={isUnfriendSheetOpen}
                title="Are you sure you want to unfriend?"
                confirmLabel="Yes, unfriend"
                confirmActionPhase={unfriendActionPhase}
                confirmDisabled={isUnfriendActionRunning}
                errorMessage={unfriendErrorMessage}
                cancelDisabled={isUnfriendActionRunning}
                onCancel={cancelUnfriend}
                onConfirm={confirmUnfriend}
                onExited={handleUnfriendSheetExited}
            />
        </Box>
    );
};
