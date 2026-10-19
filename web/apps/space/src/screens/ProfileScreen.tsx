import {
    AddSquareIcon,
    ArrowLeft02Icon,
    BubbleChatIcon,
    HandPointingRightIcon,
    Menu01Icon,
    Tick02Icon,
    UserRemove01Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Skeleton } from "@mui/material";
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
import { ConfirmationActionSheet } from "components/ConfirmationActionSheet";
import {
    SpaceFileViewer,
    type SpaceFileViewerController,
    type SpaceViewerPhoto,
    type SpaceViewerPostActionMode,
} from "components/FileViewer";
import { SpacePostGrid } from "components/PostGrid";
import { SpacePostPhotoInput } from "components/PostPhotoInput";
import { SpacePostTile, type SpacePostTileItem } from "components/PostTile";
import { SpaceLoadingSpinner } from "components/RouteFallback";
import { SpaceShareIcon } from "components/ShareInviteButton";
import { SpaceSkipLink } from "components/SkipLink";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React, { useState } from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";
import type { SpaceInviteIntent } from "services/invite";
import { isSpaceContentError, type SpacePostAsset } from "services/space";
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
import { spaceTouchTargetSize } from "styles/touch-targets";
import { firstNameFrom } from "utils/display";
import { spaceDefaultCoverImagePath } from "utils/post-image";
import { viewerPhotosFromPost } from "utils/post-photos";

const green = "#08C225";
const textBase = spaceText;
const textSoft = spaceTextMuted;
const coverForeground = "#FFFFFF";
const profileIdentityColor = spaceText;
const profileStatsColor = spaceTextMuted;
const profileStatsValueColor = spaceText;
const profileCoverBackground = spaceSurface;
const profileCoverTopShadow =
    "linear-gradient(180deg, rgba(0, 0, 0, 0.26) 0%, rgba(0, 0, 0, 0.18) 36%, rgba(0, 0, 0, 0.08) 72%, rgba(0, 0, 0, 0) 100%)";
const profileCoverSkeletonBackground = spaceSurface;
const profileAvatarTopOffset = 54;
const profileAvatarSize = 132;
const photoPlaceholderBackground = spaceSurface;
const profileCoverRadius = "24px";
const profilePostLoadRootMargin = "800px 0px";
const publicProfilePostLoadRootMargin = "400px 0px";
interface ProfilePhotoDimensions {
    height: number;
    width: number;
}

export type ProfilePostItem = SpacePostTileItem;

interface SelectedProfilePost {
    id: string;
    photo: SpaceViewerPhoto;
    photoIndex: number;
}

const profilePostImageCacheKey = (item: ProfilePostItem) =>
    [item.id, item.imageAsset?.objectKey ?? item.imageUrl ?? ""].join(":");

const profilePostPhoto = (item: ProfilePostItem, index: number) => {
    const photo = item.photos?.[index];
    return index > 0 && photo
        ? { ...item, ...photo, imageUrl: photo.imageUrl }
        : item;
};

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

const ProfilePostLoadingIndicator: React.FC<{ coverHeight: number }> = ({
    coverHeight,
}) => (
    <Box
        sx={{
            alignItems: "center",
            bottom: 0,
            display: "flex",
            insetInline: 0,
            justifyContent: "center",
            pointerEvents: "none",
            position: "absolute",
            top: `var(--space-profile-post-loading-top, calc(${coverHeight}px + var(--space-profile-safe-area-top, 0px)))`,
            width: "100%",
        }}
    >
        <SpaceLoadingSpinner ariaLabel="Loading posts" />
    </Box>
);

interface ProfileScreenProps {
    headerRef?: React.Ref<HTMLDivElement>;
    friendsCount?: number;
    headerVariant?: "friend" | "owner" | "public" | "public-anonymous";
    isAddingFriend?: boolean;
    showAddingFriendSpinner?: boolean;
    isCoverLoading?: boolean;
    isNameLoading?: boolean;
    isPostsLoading?: boolean;
    isPreview?: boolean;
    isPostPhotoOpening?: boolean;
    isStatsLoading?: boolean;
    showPostLoadingIndicator?: boolean;
    onAddFriend?: () => void;
    onAddFriendForPostAction?: (intent: SpaceInviteIntent) => void;
    onBack?: () => void;
    onCreateSpace?: () => void;
    onPostPhotoSelect?: (files: File[]) => void;
    onDeletePost?: (postId: number) => Promise<void> | void;
    onOpenFriends?: () => void;
    onOpenProfileCover?: () => void;
    onOpenProfilePhoto?: () => void;
    onOpenSettings?: () => void;
    onLoadPostImage?: (asset: SpacePostAsset) => Promise<string>;
    onMessageFriend?: () => void;
    onPokeFriend?: (requestID: string) => Promise<void>;
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
    headerRef,
    friendsCount = 0,
    headerVariant = "owner",
    isAddingFriend = false,
    isCoverLoading = false,
    isNameLoading = false,
    isPostsLoading = false,
    isPreview = false,
    isPostPhotoOpening = false,
    isStatsLoading = false,
    onBack,
    onAddFriend,
    onAddFriendForPostAction,
    onCreateSpace,
    onPostPhotoSelect,
    onDeletePost,
    onOpenFriends,
    onOpenProfileCover,
    onOpenProfilePhoto,
    onOpenSettings,
    onLoadPostImage,
    onMessageFriend,
    onPokeFriend,
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
    const [tilePhotoIndices, setTilePhotoIndices] = useState<
        Record<string, number>
    >({});
    const [isInviteLinkCopied, setIsInviteLinkCopied] = useState(false);
    const [deletedPostIDs, setDeletedPostIDs] = useState<Set<string>>(
        () => new Set(),
    );
    const [pokePhase, setPokePhase] = useState<SpaceActionPhase>();
    const [pokeFailed, setPokeFailed] = useState(false);
    const pokeRequestID = React.useRef<string | undefined>(undefined);
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
    const profileHeaderHeight = isAnonymousPublicProfile ? 56 : 68;
    const profileCoverHeight =
        profileHeaderHeight + profileAvatarTopOffset + profileAvatarSize / 2;
    const isUnfriendActionRunning = unfriendActionPhase != null;
    const canManageFriend =
        isFriendProfile &&
        Boolean(onMessageFriend || onPokeFriend || onUnfriend);
    const displayName = profile.fullName.trim() || profile.username.trim();
    const coverUrl = profile.coverUrl ?? null;
    const isCoverURLPending = Boolean(profile.coverObjectID && !coverUrl);
    const coverImageUrl = coverUrl
        ? coverUrl
        : isCoverURLPending
          ? undefined
          : spaceDefaultCoverImagePath;
    const firstName = firstNameFrom(displayName);
    const visiblePostItems = postItems
        .filter((item) => !deletedPostIDs.has(item.id))
        .sort((a, b) => b.timestampMs - a.timestampMs);
    const viewerPostItems = visiblePostItems.filter(
        (item) =>
            !item.isUnavailable &&
            !unavailablePostsByKey[profilePostImageCacheKey(item)],
    );
    const viewerPostIDs = new Set(viewerPostItems.map((item) => item.id));
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

    const poke = async () => {
        if (!onPokeFriend || pokePhase) return;
        setPokePhase("busy");
        setPokeFailed(false);
        pokeRequestID.current ??= crypto.randomUUID();
        try {
            await onPokeFriend(pokeRequestID.current);
            pokeRequestID.current = undefined;
            setPokePhase("done");
        } catch (error) {
            log.error("Failed to send poke", error);
            setPokeFailed(true);
            setPokePhase(undefined);
        }
    };

    React.useEffect(() => {
        if (pokePhase != "done") return;

        const timeoutID = window.setTimeout(() => {
            setPokePhase(undefined);
        }, 2100);

        return () => window.clearTimeout(timeoutID);
    }, [pokePhase]);

    const requestUnfriend = () => {
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
    const viewerRef = React.useRef<SpaceFileViewerController>(null);
    useBrowserBackClose({
        open: Boolean(selectedPost),
        onClose: () => viewerRef.current?.close(),
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
        }).map((photo, index) => ({
            ...photo,
            id: item.id,
            imageUrl:
                photo.imageUrl ||
                (loadedPostImageURLFor(profilePostPhoto(item, index)) ?? ""),
        })),
    );
    const selectedPostPhotos = profileViewerPhotos.filter(
        (photo) => photo.id == selectedPost?.id,
    );
    const handleSelectedPostIndexChange = (photoIndex: number) => {
        const photo = selectedPostPhotos[photoIndex];
        if (!photo) return;
        setSelectedPost({
            id: photo.id,
            photo,
            photoIndex: photo.postPhotoIndex!,
        });
        setTilePhotoIndices((current) => ({
            ...current,
            [photo.id]: photo.postPhotoIndex ?? 0,
        }));
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
            if (!(
                error instanceof DOMException && error.name == "AbortError"
            )) {
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

    const renderPostTile = (item: ProfilePostItem, index: number) => {
        const remembered = Math.min(
            tilePhotoIndices[item.id] ?? 0,
            (item.photos?.length || 1) - 1,
        );
        const photoIndex =
            remembered > 0 &&
            unavailablePostsByKey[
                profilePostImageCacheKey(profilePostPhoto(item, remembered))
            ]
                ? 0
                : remembered;
        const shown = profilePostPhoto(item, photoIndex);
        const imageUrl = loadedPostImageURLFor(shown);
        const isUnavailable = !viewerPostIDs.has(item.id);
        return (
            <SpacePostTile
                key={item.id}
                displayName={displayName}
                imageUrl={imageUrl}
                index={index}
                isUnavailable={isUnavailable}
                item={{ ...item, ...dimensionsForPost(item) }}
                photoIndex={photoIndex}
                loadRootMargin={postImageLoadRootMargin}
                onLoadImage={() => loadPostImage(shown)}
                onImageDecodeError={() =>
                    setUnavailablePostsByKey((current) => ({
                        ...current,
                        [profilePostImageCacheKey(shown)]: true,
                    }))
                }
                onOpen={(openedImageUrl) => {
                    const photo = profileViewerPhotos.find(
                        (photo) =>
                            photo.id == item.id &&
                            (photo.postPhotoIndex ?? 0) == photoIndex,
                    );
                    if (!photo) return;
                    setSelectedPost({
                        id: item.id,
                        photoIndex,
                        photo: { ...photo, imageUrl: openedImageUrl },
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
                inert={isPreview}
                sx={{
                    alignItems: "center",
                    color: coverForeground,
                    display: isPublicProfile ? "flex" : "grid",
                    gridTemplateColumns: isPublicProfile
                        ? undefined
                        : `${spaceTouchTargetSize}px minmax(0, 1fr) ${spaceTouchTargetSize}px`,
                    height: `calc(${profileHeaderHeight}px + var(--space-profile-safe-area-top))`,
                    justifyContent: isPublicProfile
                        ? "space-between"
                        : undefined,
                    mx: "auto",
                    opacity: isPreview
                        ? "clamp(0, calc((var(--space-friend-profile-reveal, 0) - 0.7) * 5), 1)"
                        : 1,
                    position: "relative",
                    pl: `max(${isPublicProfile ? 8 : 16}px, var(--space-ios-safe-area-left, 0px))`,
                    pr: `max(${isPublicProfile ? 8 : 16}px, var(--space-ios-safe-area-right, 0px))`,
                    pt: "var(--space-profile-safe-area-top)",
                    pb: 0,
                    width: "100%",
                    zIndex: 3,
                    "@media (min-width: 600px)": {
                        maxWidth: isPreview ? "none" : 390,
                    },
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
                            aria-label="Back"
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
                        {isOwnerProfile && onOpenSettings ? (
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
                                    cursor: "pointer",
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
                                    size={23}
                                    strokeWidth={1.8}
                                    absoluteStrokeWidth
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
                "--space-profile-safe-area-top": isPreview
                    ? "max(0px, calc(var(--space-ios-safe-area-top, 0px) - var(--space-friend-profile-top, 100vh)))"
                    : "var(--space-ios-safe-area-top, 0px)",
                background: spaceAppBackground,
                color: textBase,
                display: "grid",
                minHeight: "var(--space-page-height, 100svh)",
                overflowX: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
                position: "relative",
            }}
        >
            {!isPublicProfile && !isPreview && <SpaceSkipLink />}
            <Box
                sx={{
                    bgcolor: "transparent",
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    minHeight: "var(--space-page-height, 100svh)",
                    mx: "auto",
                    overflow: "hidden",
                    position: "relative",
                    width: "100%",
                    "@media (min-width: 600px)": {
                        maxWidth: isPreview ? "none" : 390,
                    },
                }}
            >
                {isOwnerProfile && onPostPhotoSelect && (
                    <SpacePostPhotoInput
                        inputRef={postInputRef}
                        onSelect={onPostPhotoSelect}
                    />
                )}
                <Box
                    sx={{
                        bgcolor: shouldShowCoverSkeleton
                            ? profileCoverSkeletonBackground
                            : profileCoverBackground,
                        borderBottomLeftRadius: profileCoverRadius,
                        borderBottomRightRadius: profileCoverRadius,
                        height: `calc(${profileCoverHeight}px + var(--space-profile-safe-area-top))`,
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
                            height: `calc(${profileHeaderHeight + 8}px + var(--space-profile-safe-area-top))`,
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
                            height: `calc(${profileCoverHeight}px + var(--space-profile-safe-area-top))`,
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
                    ref={headerRef}
                    component={isPublicProfile ? "div" : "section"}
                    id={
                        isPublicProfile || isPreview
                            ? undefined
                            : "space-main-content"
                    }
                    aria-label={
                        isPublicProfile ? undefined : `${displayName}'s profile`
                    }
                    tabIndex={isPublicProfile ? undefined : -1}
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        flexDirection: "column",
                        px: "8px",
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
                            {isOwnerProfile && (
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
                            )}
                        </Box>
                        {canManageFriend && (
                            <Box
                                sx={{
                                    mt: "20px",
                                    mx: "auto",
                                    width: "100%",
                                    maxWidth: 320,
                                }}
                            >
                                <Box
                                    role="group"
                                    aria-label="Friend actions"
                                    sx={{
                                        display: "grid",
                                        gap: "8px",
                                        gridAutoColumns: "minmax(0, 1fr)",
                                        gridAutoFlow: "column",
                                        position: "relative",
                                        zIndex: 4,
                                    }}
                                >
                                    {[
                                        {
                                            label: "Poke",
                                            icon: HandPointingRightIcon,
                                            onClick: onPokeFriend
                                                ? () => void poke()
                                                : undefined,
                                        },
                                        {
                                            label: "Message",
                                            icon: BubbleChatIcon,
                                            onClick: onMessageFriend,
                                        },
                                        {
                                            label: "Unfriend",
                                            icon: UserRemove01Icon,
                                            onClick: onUnfriend
                                                ? requestUnfriend
                                                : undefined,
                                        },
                                    ]
                                        .filter((action) => action.onClick)
                                        .map((action) => {
                                            const isPoke =
                                                action.label == "Poke";
                                            const active =
                                                isPoke &&
                                                pokePhase !== undefined;
                                            const done =
                                                isPoke && pokePhase == "done";
                                            return (
                                                <Box
                                                    key={action.label}
                                                    component="button"
                                                    type="button"
                                                    aria-label={
                                                        done
                                                            ? "Poke sent"
                                                            : action.label
                                                    }
                                                    aria-busy={
                                                        isPoke &&
                                                        pokePhase == "busy"
                                                    }
                                                    aria-live={
                                                        isPoke
                                                            ? "polite"
                                                            : undefined
                                                    }
                                                    disabled={active}
                                                    onClick={action.onClick}
                                                    sx={{
                                                        alignItems: "center",
                                                        bgcolor:
                                                            spaceDialogBackground,
                                                        border: 0,
                                                        borderRadius: "22px",
                                                        color: active
                                                            ? green
                                                            : textBase,
                                                        cursor: active
                                                            ? "default"
                                                            : "pointer",
                                                        display: "flex",
                                                        height: 40,
                                                        justifyContent:
                                                            "center",
                                                        minWidth: 0,
                                                        p: "0 8px",
                                                        "&:hover:not(:disabled)":
                                                            {
                                                                bgcolor:
                                                                    spaceSurfaceHover,
                                                            },
                                                        "&:focus-visible": {
                                                            outline: `2px solid ${green}`,
                                                            outlineOffset: 2,
                                                        },
                                                    }}
                                                >
                                                    <Box
                                                        component="span"
                                                        aria-hidden
                                                        sx={{
                                                            alignItems:
                                                                "center",
                                                            display: "flex",
                                                            flexShrink: 0,
                                                            height: 22,
                                                            justifyContent:
                                                                "center",
                                                            width: 22,
                                                            animation: active
                                                                ? "spacePokeJab 2000ms ease-in-out"
                                                                : "none",
                                                            "@keyframes spacePokeJab":
                                                                {
                                                                    "0%, 100%":
                                                                        {
                                                                            transform:
                                                                                "translate(0, 0) rotate(0deg) scale(1)",
                                                                        },
                                                                    "27.5%, 52%, 73.75%":
                                                                        {
                                                                            transform:
                                                                                "translate(36px, -94px) rotate(-40deg) scale(3)",
                                                                        },
                                                                    "41%, 63%":
                                                                        {
                                                                            transform:
                                                                                "translate(52px, -108px) rotate(-40deg) scale(3)",
                                                                        },
                                                                },
                                                            "@media (prefers-reduced-motion: reduce)":
                                                                {
                                                                    animation:
                                                                        "none",
                                                                },
                                                            ...(action.icon ==
                                                                BubbleChatIcon && {
                                                                "& svg path:last-of-type":
                                                                    {
                                                                        display:
                                                                            "none",
                                                                    },
                                                            }),
                                                        }}
                                                    >
                                                        <HugeiconsIcon
                                                            icon={action.icon}
                                                            size={22}
                                                            strokeWidth={2.2}
                                                        />
                                                    </Box>
                                                </Box>
                                            );
                                        })}
                                </Box>
                                {pokeFailed && (
                                    <Box
                                        role="alert"
                                        sx={{
                                            color: textSoft,
                                            fontSize: 12,
                                            mt: "8px",
                                        }}
                                    >
                                        Couldn&apos;t send poke. Try again.
                                    </Box>
                                )}
                            </Box>
                        )}
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
                    inert={isPreview}
                    sx={{
                        alignItems: "stretch",
                        boxSizing: "border-box",
                        display: "flex",
                        opacity: isPreview
                            ? "var(--space-friend-profile-reveal, 0)"
                            : 1,
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
                                mx: "8px",
                                width: "calc(100% - 16px)",
                            }}
                        >
                            <SpacePostGrid
                                items={visiblePostItems.map((item) => ({
                                    ...item,
                                    ...dimensionsForPost(item),
                                }))}
                                postCount={displayedPostsCount}
                                renderTile={renderPostTile}
                            />
                        </Box>
                    ) : shouldShowPostLoadingIndicator ? (
                        <ProfilePostLoadingIndicator
                            coverHeight={profileCoverHeight}
                        />
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
                                top: `calc(${profileCoverHeight}px + var(--space-profile-safe-area-top))`,
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
                {selectedPost && (
                    <SpaceFileViewer
                        ref={viewerRef}
                        closeOnSwipePastEnd
                        headerHeight={profileHeaderHeight}
                        photo={selectedPost.photo}
                        photos={selectedPostPhotos}
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
                title={`Unfriend ${profile.fullName.trim().split(/\s+/)[0] || profile.username}?`}
                description="You’ll no longer see each other’s posts or message each other."
                confirmLabel="Unfriend"
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
