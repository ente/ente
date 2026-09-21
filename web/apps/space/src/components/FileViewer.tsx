import {
    ArrowLeft02Icon,
    ArrowRight02Icon,
    Cancel01Icon,
    Delete02Icon,
    Edit01Icon,
    Edit03Icon,
    Loading03Icon,
    MoreHorizontalIcon,
    Tick02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Menu, MenuItem } from "@mui/material";
import { keyframes } from "@mui/material/styles";
import {
    spaceActionDoneDurationMs,
    type SpaceActionPhase,
} from "components/ActionFeedback";
import { SpaceAvatarImage } from "components/AvatarImage";
import { SpaceCaptionText } from "components/CaptionText";
import { ConfirmationActionSheet } from "components/ConfirmationActionSheet";
import { spacePostLikePopDurationMs } from "components/post-like-animation";
import { SpacePostPhotosCounter } from "components/PostPhotosCounter";
import { SpacePostReplyControls } from "components/PostReplyControls";
import log from "ente-base/log";
import type PhotoSwipe from "photoswipe";
import React from "react";
import type { SpaceInviteIntent } from "services/invite";
import type { SpacePostAsset, SpacePostAssetURLLoader } from "services/space";
import { spaceDialogBackground, spaceTextMuted } from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";
import { firstNameFrom, formatSpaceDate } from "utils/display";
import { clampSpaceMessageText } from "utils/message-limits";

const green = "#08C225";
const textBase = "#F4F4F4";
const textSecondary = "#A6A6A6";
const textTertiary = "rgba(244, 244, 244, 0.52)";
const viewerBackground = "#000000";
const inputBackground = "rgba(58, 58, 58, 0.86)";
const inputBackgroundActive = "rgba(72, 72, 72, 0.9)";
const controlIcon = "#D8D8D8";
const dangerColor = "#F63A3A";
const viewerHeaderHeight = 56;
const viewerBottomPadding = 88;
const viewerDesktopMinWidth = 600;
const captionInputMinHeight = 40;
const replyInputMinHeight = 48;
const replyInputPadding = 14;
const replyInputPaddingLeft = 18;
const viewerActionDoneDurationMs = 1000;
const captionInputMaxHeight = 112;
const defaultPhotoWidth = 900;
const defaultPhotoHeight = 680;
const viewerHeaderAvatarSize = 28;
const draftPostExitDurationMs = 320;
const keyboardInsetThresholdPx = 80;
const keyboardDismissMaxDurationMs = 500;

interface ViewerViewportSize {
    x: number;
    y: number;
}

const currentViewerViewportSize = (
    root: HTMLElement | null,
): ViewerViewportSize => {
    if (typeof window == "undefined" || typeof document == "undefined") {
        return { x: defaultPhotoWidth, y: defaultPhotoHeight };
    }

    return {
        x:
            root?.clientWidth ||
            document.documentElement.clientWidth ||
            window.innerWidth,
        y:
            root?.clientHeight ||
            document.documentElement.clientHeight ||
            window.innerHeight,
    };
};

const postButtonSpin = keyframes`
    from {
        transform: rotate(0deg);
    }

    to {
        transform: rotate(360deg);
    }
`;

export type SpaceViewerPostActionMode = "draft-post" | "hidden" | "like-only";

interface SpaceViewerPostActionConfig {
    showLikeButton: boolean;
}

const spaceViewerPostActionConfigs: Record<
    SpaceViewerPostActionMode,
    SpaceViewerPostActionConfig
> = {
    "draft-post": { showLikeButton: false },
    hidden: { showLikeButton: false },
    "like-only": { showLikeButton: true },
};

export interface SpaceViewerPhoto {
    alt?: string;
    avatarUrl?: string | null;
    caption?: string;
    friendID?: string;
    height?: number;
    imageUrl: string;
    imageAsset?: SpacePostAsset;
    postPhotoIndex?: number;
    postPhotoCount?: number;
    name: string;
    postId?: number;
    spaceId?: string;
    timestampMs: number;
    username?: string;
    viewerLiked?: boolean;
    width?: number;
}

interface SpaceViewerDeleteSnapshot {
    photoIndex: number;
    photos: SpaceViewerPhoto[];
}

type DraftPostExitPhase = "idle" | "waiting-for-keyboard" | "animating";

interface SpaceFileViewerProps {
    closeOnSwipePastEnd?: boolean;
    draftPhotoControls?: React.ReactNode;
    onLoadPhoto?: SpacePostAssetURLLoader;
    draftPostPreparationError?: string;
    isDraftPostPreviewPending?: boolean;
    onClose: () => void;
    onEditDraftPhoto?: () => void;
    onDeletePost?: () => Promise<void> | void;
    onDraftPostExitAnimationStart?: () => void;
    onDraftPostExitStart?: () => void;
    onDraftPostPublished?: () => void;
    onAddFriendForPostAction?: (intent: SpaceInviteIntent) => void;
    onOpenProfile?: () => void;
    onPublishDraftPost?: (caption: string) => Promise<void>;
    onReplyToPost?: (
        spaceId: string,
        postId: number,
        text: string,
        objectKey: string,
    ) => Promise<void>;
    onSetPostLiked?: (postId: number, liked: boolean) => Promise<void>;
    onUpdatePostCaption?: (postId: number, caption: string) => Promise<void>;
    onPhotoIndexChange?: (index: number) => void;
    photo: SpaceViewerPhoto;
    photoIndex?: number;
    initialPhotoIndex?: number;
    photos?: SpaceViewerPhoto[];
    focusReplyOnOpen?: boolean;
    postActionMode?: SpaceViewerPostActionMode;
}

const viewerTouchPoint = (event: Event) => {
    if ("changedTouches" in event) {
        const touch = (event as TouchEvent).changedTouches[0];
        return touch ? { x: touch.pageX, y: touch.pageY } : undefined;
    }
    if (
        "pointerType" in event &&
        (event as PointerEvent).pointerType != "mouse"
    ) {
        const pointer = event as PointerEvent;
        return { x: pointer.pageX, y: pointer.pageY };
    }
    return undefined;
};

const viewerPhotoContentKey = (photo: SpaceViewerPhoto) =>
    `${photo.imageUrl}:${photo.width ?? ""}:${photo.height ?? ""}:${photo.postPhotoCount ?? ""}`;

const viewerSwipeStartsOnInteractiveTarget = (target: EventTarget | null) =>
    target instanceof Element &&
    Boolean(
        target.closest(
            "input, textarea, select, button, [data-space-viewer-chrome='true'], [data-space-viewer-bottom='true']",
        ),
    );

export const SpaceViewerPostBackdrop: React.FC<{ exiting?: boolean }> = ({
    exiting = false,
}) => (
    <Box
        aria-hidden
        sx={{
            bgcolor: viewerBackground,
            bottom: "-100vh",
            left: 0,
            opacity: exiting ? 0 : 1,
            pointerEvents: "none",
            position: "absolute",
            right: 0,
            top: "-100vh",
            transition: `opacity ${draftPostExitDurationMs}ms cubic-bezier(0.22, 1, 0.36, 1)`,
            zIndex: 1299,
            "@media (prefers-reduced-motion: reduce)": { transition: "none" },
        }}
    />
);

const viewerHeaderButtonSx = {
    alignItems: "center",
    bgcolor: "transparent",
    border: 0,
    borderRadius: "50%",
    color: "#E4E4E4",
    cursor: "pointer",
    display: "flex",
    height: spaceTouchTargetSize,
    justifyContent: "center",
    left: "8px",
    mx: "-8px",
    p: 0,
    position: "relative",
    width: spaceTouchTargetSize,
    "&:focus-visible": { outline: `2px solid ${green}`, outlineOffset: 2 },
};

const resizeCaptionInput = (
    input: HTMLTextAreaElement | null,
    minHeight = captionInputMinHeight,
) => {
    if (!input) return;

    input.style.height = `${minHeight}px`;
    const nextHeight = Math.min(input.scrollHeight, captionInputMaxHeight);
    input.style.height = `${Math.max(minHeight, nextHeight)}px`;
    input.style.overflowY =
        input.scrollHeight > captionInputMaxHeight ? "auto" : "hidden";
};

const viewerCaptionTextSx = {
    color: "#E6E6E6",
    fontFamily: '"Inter Variable", Inter, sans-serif',
    fontSize: 14,
    fontWeight: 600,
    lineHeight: "23px",
    textAlign: "center",
    textWrap: "balance",
    whiteSpace: "pre-wrap",
} as const;

const SpaceViewerCaption: React.FC<{ caption: string }> = ({ caption }) => {
    const bubbleRef = React.useRef<HTMLParagraphElement | null>(null);
    const [isLongCaption, setIsLongCaption] = React.useState(false);

    React.useLayoutEffect(() => {
        const bubble = bubbleRef.current;
        if (!bubble) return;

        const updateLayout = () => {
            const lineHeight = parseFloat(getComputedStyle(bubble).lineHeight);
            setIsLongCaption(
                bubble.getBoundingClientRect().height > lineHeight * 4,
            );
        };
        updateLayout();
        const observer = new ResizeObserver(updateLayout);
        observer.observe(bubble);
        return () => observer.disconnect();
    }, [caption]);

    return (
        <>
            <Box
                ref={bubbleRef}
                component="p"
                aria-hidden={isLongCaption || undefined}
                data-space-viewer-chrome="true"
                title={caption}
                sx={{
                    ...viewerCaptionTextSx,
                    bottom: "14%",
                    left: "50%",
                    m: 0,
                    maxWidth: "78vw",
                    minWidth: 0,
                    overflowWrap: "break-word",
                    position: "fixed",
                    transform: "translateX(-50%)",
                    visibility: isLongCaption ? "hidden" : "visible",
                    width: "78vw",
                    zIndex: 2,
                }}
            >
                <SpaceCaptionText caption={caption} />
            </Box>
            {isLongCaption && (
                <Box
                    role="region"
                    aria-label="Caption"
                    tabIndex={0}
                    sx={{
                        ...viewerCaptionTextSx,
                        bgcolor: "rgba(32, 32, 32, 0.85)",
                        borderRadius: "16px",
                        boxSizing: "border-box",
                        fontWeight: 400,
                        lineHeight: "22px",
                        maxHeight: "33svh",
                        overflowWrap: "anywhere",
                        overflowY: "auto",
                        overscrollBehaviorY: "contain",
                        p: "14px 16px",
                        scrollbarWidth: "thin",
                        textAlign: "left",
                        textWrap: "wrap",
                        "&:focus-visible": {
                            outline: `2px solid ${green}`,
                            outlineOffset: 2,
                        },
                    }}
                >
                    {caption}
                </Box>
            )}
        </>
    );
};

export const SpaceFileViewer: React.FC<SpaceFileViewerProps> = ({
    closeOnSwipePastEnd = false,
    draftPhotoControls,
    onLoadPhoto,
    draftPostPreparationError,
    focusReplyOnOpen = false,
    isDraftPostPreviewPending = false,
    onClose,
    onEditDraftPhoto,
    onDeletePost,
    onDraftPostExitAnimationStart,
    onDraftPostExitStart,
    onDraftPostPublished,
    onAddFriendForPostAction,
    onOpenProfile,
    onPublishDraftPost,
    onReplyToPost,
    onSetPostLiked,
    onUpdatePostCaption,
    onPhotoIndexChange,
    photo,
    photoIndex,
    initialPhotoIndex = 0,
    photos,
    postActionMode = "like-only",
}) => {
    const [localPhotoIndex, setLocalPhotoIndex] =
        React.useState(initialPhotoIndex);
    const [loadedPhotoURLs, setLoadedPhotoURLs] = React.useState<
        Record<string, string>
    >({});
    const [photoLoadErrors, setPhotoLoadErrors] = React.useState<
        Record<string, true>
    >({});
    const photoLoadsRef = React.useRef(new Set<string>());
    const photoKey = (item: SpaceViewerPhoto) =>
        item.imageAsset
            ? `${item.imageAsset.spaceId}:${item.imageAsset.objectKey}`
            : item.imageUrl;
    const hasDraftPhotoControls = Boolean(draftPhotoControls);
    const activePostActionMode = postActionMode;
    const isDraftPost = activePostActionMode == "draft-post";
    const { showLikeButton: showPhotoLikeButton } =
        spaceViewerPostActionConfigs[activePostActionMode];
    const canDeletePost = !isDraftPost && Boolean(onDeletePost);
    const [deleteActionPhase, setDeleteActionPhase] =
        React.useState<SpaceActionPhase | null>(null);
    const [isDeleteExit, setIsDeleteExit] = React.useState(false);
    const deleteSnapshotRef = React.useRef<SpaceViewerDeleteSnapshot | null>(
        null,
    );
    const isDeleteViewerLocked = Boolean(deleteActionPhase) || isDeleteExit;
    const incomingViewerPhotos = (
        photos && photos.length > 0 ? photos : [photo]
    ).map((item) => ({
        ...item,
        imageUrl: loadedPhotoURLs[photoKey(item)] || item.imageUrl || "",
    }));
    const viewerPhotos = isDeleteViewerLocked
        ? (deleteSnapshotRef.current?.photos ?? incomingViewerPhotos)
        : incomingViewerPhotos;
    const activePhotoIndex = Math.min(
        Math.max(
            isDeleteViewerLocked
                ? (deleteSnapshotRef.current?.photoIndex ??
                      photoIndex ??
                      localPhotoIndex)
                : (photoIndex ?? localPhotoIndex),
            0,
        ),
        viewerPhotos.length - 1,
    );
    const activePhoto = viewerPhotos[activePhotoIndex] ?? photo;
    const postPhotoCount = activePhoto.postPhotoCount ?? 1;
    const postPhotoIndex = activePhoto.postPhotoIndex ?? 0;
    const activePhotoKey = photoKey(activePhoto);
    const activeReplyKey = `${activePhoto.spaceId}:${activePhoto.postId}:${activePhoto.imageAsset?.objectKey}`;
    const activeReplyKeyRef = React.useRef(activeReplyKey);
    activeReplyKeyRef.current = activeReplyKey;
    const activePostKey = `${activePhoto.spaceId ?? ""}:${activePhoto.postId ?? ""}`;
    const hasPhotoLoadError = Boolean(photoLoadErrors[activePhotoKey]);
    const canUpdatePostCaption =
        !isDraftPost &&
        Boolean(activePhoto.postId) &&
        Boolean(onUpdatePostCaption);
    const canManagePost = canDeletePost || canUpdatePostCaption;
    const viewerPhotosRef = React.useRef(viewerPhotos);
    const onCloseRef = React.useRef(onClose);
    const onPhotoIndexChangeRef = React.useRef(onPhotoIndexChange);
    const initialPhotoIndexRef = React.useRef(activePhotoIndex);
    const fallbackPhotoRef = React.useRef(activePhoto);
    const pswpRef = React.useRef<PhotoSwipe | undefined>(undefined);
    const closeOnSwipePastEndRef = React.useRef(closeOnSwipePastEnd);
    closeOnSwipePastEndRef.current = closeOnSwipePastEnd;
    viewerPhotosRef.current = viewerPhotos;
    onCloseRef.current = onClose;
    onPhotoIndexChangeRef.current = onPhotoIndexChange;
    fallbackPhotoRef.current = activePhoto;
    const viewerPhotosContentKey = viewerPhotos
        .map(viewerPhotoContentKey)
        .join("|");
    const viewerPhotoKeys = viewerPhotos.map(photoKey).join("|");
    const displayedContentKeysRef = React.useRef<string[]>([]);
    const [isPhotoLiked, setIsPhotoLiked] = React.useState(
        activePhoto.viewerLiked ?? false,
    );
    const [photoLikePopID, setPhotoLikePopID] = React.useState(0);
    const [caption, setCaption] = React.useState(activePhoto.caption ?? "");
    const [captionEditValue, setCaptionEditValue] = React.useState(
        activePhoto.caption ?? "",
    );
    const [isCaptionEditing, setIsCaptionEditing] = React.useState(false);
    const [captionUpdateActionPhase, setCaptionUpdateActionPhase] =
        React.useState<SpaceActionPhase | null>(null);
    const [hasCaptionUpdateError, setHasCaptionUpdateError] =
        React.useState(false);
    const isCaptionEditingRef = React.useRef(isCaptionEditing);
    isCaptionEditingRef.current = isCaptionEditing;
    const [replyText, setReplyText] = React.useState("");
    const replyDraftsRef = React.useRef(new Map<string, string>());
    const [isReplyFocused, setIsReplyFocused] =
        React.useState(focusReplyOnOpen);
    const [replyPhases, setReplyPhases] = React.useState<
        Record<string, SpaceActionPhase | null>
    >({});
    const replyActionPhase = replyPhases[activeReplyKey] ?? null;
    const setReplyActionPhase = React.useCallback(
        (phase: SpaceActionPhase | null) => {
            setReplyPhases((phases) => ({
                ...phases,
                [activeReplyKey]: phase,
            }));
        },
        [activeReplyKey],
    );
    const [addFriendSheetOpen, setAddFriendSheetOpen] = React.useState(false);
    const [addFriendIntent, setAddFriendIntent] =
        React.useState<SpaceInviteIntent>("like");
    const [draftPostActionPhase, setDraftPostActionPhase] =
        React.useState<SpaceActionPhase | null>(null);
    const [draftPostExitPhase, setDraftPostExitPhase] =
        React.useState<DraftPostExitPhase>("idle");
    const isDraftPostExit = draftPostExitPhase != "idle";
    const isDraftPostExitAnimating = draftPostExitPhase == "animating";
    const [isDesktopViewer, setIsDesktopViewer] = React.useState(
        () =>
            typeof window != "undefined" &&
            window.innerWidth >= viewerDesktopMinWidth,
    );
    const displayName = firstNameFrom(activePhoto.name);
    const dateLabel = formatSpaceDate(activePhoto.timestampMs);
    const displayCaption = isDraftPost ? "" : caption.trim();
    const hasDisplayCaption = displayCaption.length > 0;
    const viewerRootRef = React.useRef<HTMLDivElement | null>(null);
    const stableViewportSizeRef = React.useRef<ViewerViewportSize>(
        currentViewerViewportSize(null),
    );
    const captionInputRef = React.useRef<HTMLTextAreaElement | null>(null);
    const cancelKeyboardDismissWaitRef = React.useRef<() => void>(undefined);
    const replyInputRef = React.useRef<HTMLTextAreaElement | null>(null);
    const [actionsAnchor, setActionsAnchor] =
        React.useState<HTMLElement | null>(null);
    const [deleteSheetOpen, setDeleteSheetOpen] = React.useState(false);
    const actionsMenuID = "space-viewer-actions-menu";
    const actionsButtonID = "space-viewer-actions-button";
    const isActionsOpen = Boolean(actionsAnchor);
    const isDeleteActionRunning = deleteActionPhase != null;
    const normalizedCaptionEditValue = captionEditValue.trim();
    const isCaptionUpdateActionRunning = captionUpdateActionPhase != null;
    const isCaptionUpdateDisabled =
        isCaptionUpdateActionRunning ||
        normalizedCaptionEditValue == caption.trim() ||
        !activePhoto.postId ||
        !onUpdatePostCaption;
    const isDraftPostActionRunning = draftPostActionPhase != null;
    const hasDraftPostPreparationError = Boolean(draftPostPreparationError);
    const isDraftPostPublishDisabled =
        isDraftPostActionRunning ||
        isDraftPostPreviewPending ||
        hasDraftPostPreparationError ||
        !onPublishDraftPost;
    const isReplyActionRunning = replyActionPhase != null;
    const canAddFriendForPostAction = Boolean(
        !isDraftPost && onAddFriendForPostAction,
    );
    const canReplyToPost = Boolean(
        !isDraftPost &&
        (canAddFriendForPostAction ||
            (activePhoto.spaceId &&
                activePhoto.postId &&
                activePhoto.imageAsset &&
                onReplyToPost)),
    );
    const isReplyMode =
        canReplyToPost &&
        (isReplyFocused || replyText.trim().length > 0 || isReplyActionRunning);
    const canSendReply =
        canReplyToPost &&
        !isReplyActionRunning &&
        (canAddFriendForPostAction || replyText.trim().length > 0);
    const isSwipeBlockedRef = React.useRef(false);
    isSwipeBlockedRef.current =
        isActionsOpen ||
        addFriendSheetOpen ||
        (canDeletePost && deleteSheetOpen) ||
        isDeleteExit ||
        isDraftPostExit ||
        isCaptionEditing ||
        isReplyActionRunning ||
        isDraftPostActionRunning;
    const isDismissBlockedRef = React.useRef(false);
    isDismissBlockedRef.current = isSwipeBlockedRef.current || isReplyMode;
    const viewerViewportSize = React.useCallback(() => {
        const currentSize = currentViewerViewportSize(viewerRootRef.current);
        const stableSize = stableViewportSizeRef.current;

        if (Math.abs(currentSize.x - stableSize.x) > 1) {
            stableViewportSizeRef.current = currentSize;
            return currentSize;
        }

        const nextSize = {
            x: currentSize.x,
            y: Math.max(currentSize.y, stableSize.y),
        };
        stableViewportSizeRef.current = nextSize;
        return nextSize;
    }, []);

    const requestAddFriendForPostAction = (intent: SpaceInviteIntent) => {
        if (!onAddFriendForPostAction) return;
        setAddFriendIntent(intent);
        setAddFriendSheetOpen(true);
    };

    const handlePhotoLikeClick = () => {
        if (canAddFriendForPostAction) {
            requestAddFriendForPostAction("like");
            return;
        }

        const nextLiked = !isPhotoLiked;
        if (!activePhoto.postId || !onSetPostLiked) {
            setIsPhotoLiked(nextLiked);
            if (nextLiked) setPhotoLikePopID((id) => id + 1);
            return;
        }

        setIsPhotoLiked(nextLiked);
        if (nextLiked) setPhotoLikePopID((id) => id + 1);
        void onSetPostLiked(activePhoto.postId, nextLiked).catch(
            (error: unknown) => {
                log.error("Failed to update post like", error);
                setIsPhotoLiked(!nextLiked);
            },
        );
    };

    const closeActions = () => setActionsAnchor(null);

    const requestCaptionEdit = () => {
        if (!canUpdatePostCaption || isCaptionUpdateActionRunning) return;

        closeActions();
        setCaptionEditValue(caption);
        setCaptionUpdateActionPhase(null);
        setHasCaptionUpdateError(false);
        setIsCaptionEditing(true);
    };

    const cancelCaptionEdit = React.useCallback(() => {
        setCaptionEditValue(caption);
        setHasCaptionUpdateError(false);
        setIsCaptionEditing(false);
    }, [caption]);

    const closeViewer = () => {
        if (isDraftPostExit || isDraftPostActionRunning) return;
        if (isCaptionEditing && !isCaptionUpdateActionRunning) {
            cancelCaptionEdit();
            return;
        }
        onClose();
    };

    const updateCaption = () => {
        if (isCaptionUpdateDisabled || !activePhoto.postId) {
            return;
        }

        setHasCaptionUpdateError(false);
        setCaptionUpdateActionPhase("busy");
        void onUpdatePostCaption(activePhoto.postId, normalizedCaptionEditValue)
            .then(() => {
                setCaption(normalizedCaptionEditValue);
                setCaptionEditValue(normalizedCaptionEditValue);
                setCaptionUpdateActionPhase("done");
            })
            .catch((error: unknown) => {
                log.error("Failed to update post caption", error);
                setCaptionUpdateActionPhase(null);
                setHasCaptionUpdateError(true);
            });
    };

    const requestDeletePost = () => {
        if (!canDeletePost || isDeleteActionRunning || isDeleteExit) return;
        closeActions();
        setDeleteSheetOpen(true);
    };

    const closeDeleteSheet = () => {
        if (isDeleteActionRunning || isDeleteExit) return;
        setDeleteSheetOpen(false);
    };

    const confirmDeletePost = () => {
        if (
            !onDeletePost ||
            !canDeletePost ||
            isDeleteActionRunning ||
            isDeleteExit
        )
            return;
        deleteSnapshotRef.current = {
            photoIndex: activePhotoIndex,
            photos: viewerPhotos.map((item) => ({ ...item })),
        };
        setDeleteActionPhase("busy");
        void (async () => {
            try {
                await Promise.resolve(onDeletePost());
                setDeleteActionPhase("done");
            } catch (error) {
                log.error("Failed to delete space post", error);
                deleteSnapshotRef.current = null;
                setDeleteActionPhase(null);
            }
        })();
    };

    const dismissCaptionKeyboard = React.useCallback(
        (onDismissed: () => void) => {
            const input = captionInputRef.current;
            const root = viewerRootRef.current;
            const viewport = window.visualViewport;
            const wasFocused = document.activeElement == input;

            input?.blur();
            if (
                !wasFocused ||
                !root ||
                !viewport ||
                root.clientHeight - viewport.height < keyboardInsetThresholdPx
            ) {
                onDismissed();
                return;
            }

            const visibleViewport = viewport;
            const targetHeight = root.clientHeight;
            let timeoutID = 0;
            function cancelWait() {
                visibleViewport.removeEventListener(
                    "resize",
                    handleViewportChange,
                );
                visibleViewport.removeEventListener(
                    "scroll",
                    handleViewportChange,
                );
                window.clearTimeout(timeoutID);
            }
            function finish() {
                cancelWait();
                cancelKeyboardDismissWaitRef.current = undefined;
                onDismissed();
            }
            function handleViewportChange() {
                if (
                    visibleViewport.height >= targetHeight - 1 &&
                    visibleViewport.offsetTop <= 1
                ) {
                    finish();
                }
            }

            visibleViewport.addEventListener("resize", handleViewportChange);
            visibleViewport.addEventListener("scroll", handleViewportChange);
            timeoutID = window.setTimeout(finish, keyboardDismissMaxDurationMs);
            cancelKeyboardDismissWaitRef.current = cancelWait;
        },
        [],
    );

    React.useEffect(() => () => cancelKeyboardDismissWaitRef.current?.(), []);

    const publishDraftPostWithCaption = React.useCallback(
        (captionToPublish: string) => {
            if (!onPublishDraftPost || isDeleteExit || isDraftPostExit) return;
            setDraftPostActionPhase("busy");
            let publication: Promise<void>;
            try {
                publication = onPublishDraftPost(captionToPublish);
            } catch (error) {
                log.error("Failed to publish space post", error);
                setDraftPostActionPhase(null);
                return;
            }
            setDraftPostExitPhase("waiting-for-keyboard");
            onDraftPostExitStart?.();
            dismissCaptionKeyboard(() => {
                setDraftPostExitPhase("animating");
                onDraftPostExitAnimationStart?.();
            });
            void publication.catch((error: unknown) => {
                log.error("Failed to publish space post", error);
            });
        },
        [
            isDeleteExit,
            isDraftPostExit,
            dismissCaptionKeyboard,
            onDraftPostExitAnimationStart,
            onDraftPostExitStart,
            onPublishDraftPost,
        ],
    );

    const publishDraftPost = () => {
        if (
            !isDraftPost ||
            isDraftPostActionRunning ||
            isDraftPostPreviewPending ||
            hasDraftPostPreparationError ||
            isDeleteExit ||
            isDraftPostExit
        )
            return;

        publishDraftPostWithCaption(caption);
    };

    const sendReply = () => {
        if (canAddFriendForPostAction) {
            requestAddFriendForPostAction("reply");
            return;
        }

        const text = replyText.trim();
        if (
            !canSendReply ||
            !activePhoto.spaceId ||
            !activePhoto.postId ||
            !activePhoto.imageAsset ||
            !onReplyToPost
        ) {
            return;
        }

        const objectKey = activePhoto.imageAsset.objectKey;
        setReplyActionPhase("busy");
        void (async () => {
            try {
                await onReplyToPost(
                    activePhoto.spaceId!,
                    activePhoto.postId!,
                    text,
                    objectKey,
                );
                replyDraftsRef.current.delete(activeReplyKey);
                if (activeReplyKeyRef.current == activeReplyKey)
                    setReplyText("");
                setReplyActionPhase("done");
            } catch (error) {
                log.error("Failed to send post reply", error);
                setReplyActionPhase(null);
            }
        })();
    };

    const handleReplyKeyDown = (event: React.KeyboardEvent) => {
        if (
            canAddFriendForPostAction &&
            (event.key == "Enter" || event.key == " ")
        ) {
            event.preventDefault();
            requestAddFriendForPostAction("reply");
            return;
        }

        if (event.key != "Enter" || event.shiftKey) return;

        event.preventDefault();
        sendReply();
    };

    const handleInputActionPointerDown = (event: React.PointerEvent) => {
        event.preventDefault();
    };

    const handleReplyInputPointerDown = (event: React.PointerEvent) => {
        if (!canAddFriendForPostAction) return;
        event.preventDefault();
        requestAddFriendForPostAction("reply");
    };

    const confirmAddFriendForPostAction = () => {
        setAddFriendSheetOpen(false);
        onAddFriendForPostAction?.(addFriendIntent);
    };

    React.useLayoutEffect(() => {
        resizeCaptionInput(captionInputRef.current, replyInputMinHeight);
    }, [caption, captionEditValue, isCaptionEditing]);

    React.useEffect(() => {
        if (!isCaptionEditing) return;

        const input = captionInputRef.current;
        if (!input) return;
        input.focus();
        input.setSelectionRange(input.value.length, input.value.length);
    }, [isCaptionEditing]);

    React.useLayoutEffect(() => {
        if (!focusReplyOnOpen || !canReplyToPost) return;

        setIsReplyFocused(true);
        replyInputRef.current?.focus();
    }, [canReplyToPost, focusReplyOnOpen, activePhoto.postId]);

    React.useEffect(() => {
        if (deleteActionPhase != "done") return;

        const timeoutID = window.setTimeout(() => {
            setDeleteSheetOpen(false);
            setIsDeleteExit(true);
        }, spaceActionDoneDurationMs);

        return () => window.clearTimeout(timeoutID);
    }, [deleteActionPhase]);

    React.useEffect(() => {
        if (captionUpdateActionPhase != "done") return;

        const timeoutID = window.setTimeout(() => {
            setCaptionUpdateActionPhase(null);
            setIsCaptionEditing(false);
        }, viewerActionDoneDurationMs);

        return () => window.clearTimeout(timeoutID);
    }, [captionUpdateActionPhase]);

    React.useEffect(() => {
        if (replyActionPhase != "done") return;

        const timeoutID = window.setTimeout(() => {
            setReplyActionPhase(null);
            setIsReplyFocused(false);
        }, viewerActionDoneDurationMs);

        return () => window.clearTimeout(timeoutID);
    }, [replyActionPhase, setReplyActionPhase]);

    React.useEffect(() => {
        if (isDraftPost || isCaptionEditingRef.current) return;

        setCaption(activePhoto.caption ?? "");
        setCaptionEditValue(activePhoto.caption ?? "");
    }, [activePhoto.caption, activePhoto.postId, isDraftPost]);

    React.useEffect(() => {
        setIsPhotoLiked(activePhoto.viewerLiked ?? false);
    }, [activePhoto.postId, activePhoto.viewerLiked]);

    React.useEffect(() => {
        setCaptionUpdateActionPhase(null);
        setHasCaptionUpdateError(false);
        setIsCaptionEditing(false);
    }, [activePostKey]);

    React.useLayoutEffect(() => {
        setReplyText(replyDraftsRef.current.get(activeReplyKey) ?? "");
        setIsReplyFocused(focusReplyOnOpen && canReplyToPost);
    }, [activeReplyKey, canReplyToPost, focusReplyOnOpen]);

    React.useEffect(() => {
        setPhotoLikePopID(0);
    }, [activePhoto.imageUrl, activePhoto.postId]);

    React.useEffect(() => {
        if (photoLikePopID == 0) return;

        const timeoutID = window.setTimeout(
            () => setPhotoLikePopID(0),
            spacePostLikePopDurationMs,
        );
        return () => window.clearTimeout(timeoutID);
    }, [photoLikePopID]);

    React.useEffect(() => {
        if (!onLoadPhoto) return;
        const requested = viewerPhotosRef.current.slice(
            Math.max(0, activePhotoIndex - 1),
            activePhotoIndex + 2,
        );
        for (const item of requested) {
            const key = photoKey(item);
            if (
                !item.imageAsset ||
                photoLoadErrors[key] ||
                photoLoadsRef.current.has(key)
            )
                continue;
            photoLoadsRef.current.add(key);
            void onLoadPhoto(item.imageAsset)
                .then((url) => {
                    setLoadedPhotoURLs((current) =>
                        current[key] == url
                            ? current
                            : { ...current, [key]: url },
                    );
                })
                .catch((error: unknown) => {
                    log.warn("Failed to load post photo", error);
                    setPhotoLoadErrors((current) => ({
                        ...current,
                        [key]: true,
                    }));
                })
                .finally(() => {
                    photoLoadsRef.current.delete(key);
                });
        }
    }, [activePhotoIndex, onLoadPhoto, viewerPhotoKeys, photoLoadErrors]);

    React.useEffect(() => {
        const pswp = pswpRef.current;
        if (!pswp) return;

        pswp.options.allowPanToNext = viewerPhotosRef.current.length > 1;
        const contentKeys = viewerPhotosRef.current.map(viewerPhotoContentKey);
        const previousKeys = displayedContentKeysRef.current;
        displayedContentKeysRef.current = contentKeys;
        contentKeys.forEach((key, index) => {
            if (key != previousKeys[index]) {
                pswp.refreshSlideContent(index);
            }
        });
    }, [viewerPhotosContentKey]);

    React.useEffect(() => {
        const pswp = pswpRef.current;
        if (pswp && pswp.currIndex != activePhotoIndex)
            pswp.goTo(activePhotoIndex);
    }, [activePhotoIndex]);

    const handleDeleteSheetExited = () => {
        if (!isDeleteExit) return;

        setDeleteActionPhase(null);
    };

    React.useEffect(() => {
        const mediaQuery = window.matchMedia(
            `(min-width: ${viewerDesktopMinWidth}px)`,
        );
        const syncDesktopViewer = () => setIsDesktopViewer(mediaQuery.matches);

        syncDesktopViewer();
        mediaQuery.addEventListener("change", syncDesktopViewer);
        return () =>
            mediaQuery.removeEventListener("change", syncDesktopViewer);
    }, []);

    React.useEffect(() => {
        if (!isDeleteExit) return;

        onClose();
    }, [isDeleteExit, onClose]);

    const finishDraftPostExit = React.useCallback(() => {
        onClose();
        onDraftPostPublished?.();
    }, [onClose, onDraftPostPublished]);

    React.useEffect(() => {
        if (!isDraftPostExitAnimating) return;
        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches)
            finishDraftPostExit();
    }, [finishDraftPostExit, isDraftPostExitAnimating]);

    React.useEffect(() => {
        const root = viewerRootRef.current;
        if (!root || !canReplyToPost) return;

        const blurReplyInputOnOutsidePointerDown = (event: PointerEvent) => {
            const input = replyInputRef.current;
            if (!input || document.activeElement != input) return;
            if (
                event.target instanceof Element &&
                event.target.closest("[data-space-viewer-bottom='true']")
            ) {
                return;
            }

            input.blur();
        };

        root.addEventListener(
            "pointerdown",
            blurReplyInputOnOutsidePointerDown,
            true,
        );
        return () =>
            root.removeEventListener(
                "pointerdown",
                blurReplyInputOnOutsidePointerDown,
                true,
            );
    }, [canReplyToPost]);

    React.useEffect(() => {
        const root = viewerRootRef.current;
        if (!root || !isCaptionEditing) return;

        const blockPhotoGesture = (event: PointerEvent) => {
            if (viewerSwipeStartsOnInteractiveTarget(event.target)) return;
            event.stopPropagation();
        };

        root.addEventListener("pointerdown", blockPhotoGesture, true);
        return () =>
            root.removeEventListener("pointerdown", blockPhotoGesture, true);
    }, [isCaptionEditing]);

    React.useEffect(() => {
        const root = viewerRootRef.current;
        if (!root) return;

        let disposed = false;
        let closedByReact = false;
        let pswp: PhotoSwipe | undefined;
        let edgeSwipeStart: { x: number; y: number } | undefined;

        void import("photoswipe").then(({ default: PhotoSwipeClass }) => {
            if (disposed || !viewerRootRef.current) return;

            pswp = new PhotoSwipeClass({
                allowPanToNext: viewerPhotosRef.current.length > 1,
                appendToEl: viewerRootRef.current,
                arrowKeys: true,
                arrowNext: false,
                arrowPrev: false,
                bgClickAction: false,
                bgOpacity: 0,
                clickToCloseNonZoomable: false,
                close: false,
                closeOnVerticalDrag: true,
                counter: false,
                doubleTapAction: "zoom",
                errorMsg: "Unable to preview this photo",
                escKey: false,
                getViewportSizeFn: viewerViewportSize,
                imageClickAction: "zoom",
                index: initialPhotoIndexRef.current,
                loop: false,
                mainClass: "pswp-space-viewer",
                paddingFn: () => ({
                    bottom: hasDraftPhotoControls
                        ? 176
                        : window.innerWidth >= viewerDesktopMinWidth
                          ? 0
                          : viewerBottomPadding,
                    left: 0,
                    right: 0,
                    top:
                        window.innerWidth >= viewerDesktopMinWidth
                            ? 0
                            : viewerHeaderHeight,
                }),
                pinchToClose: false,
                returnFocus: false,
                showHideAnimationType: "none",
                spacing: 0,
                tapAction: false,
                trapFocus: false,
                wheelToZoom: true,
                zoom: false,
            });
            pswpRef.current = pswp;
            displayedContentKeysRef.current = viewerPhotosRef.current.map(
                viewerPhotoContentKey,
            );
            pswp.addFilter("numItems", () => viewerPhotosRef.current.length);
            pswp.addFilter("itemData", (_, index) => {
                const item =
                    viewerPhotosRef.current[index] ?? fallbackPhotoRef.current;
                if (!item.imageUrl)
                    return {
                        html: `<div class="space-photo-placeholder" role="status">${item.postPhotoCount == 0 ? "Add photos to your post" : "Loading photo…"}</div>`,
                    };
                return {
                    alt: item.alt ?? `${item.name} post`,
                    height: item.height ?? defaultPhotoHeight,
                    src: item.imageUrl,
                    width: item.width ?? defaultPhotoWidth,
                };
            });
            pswp.on("close", () => {
                if (!closedByReact) onCloseRef.current();
            });
            pswp.on("verticalDrag", (event) => {
                if (isDismissBlockedRef.current) event.preventDefault();
            });
            pswp.on("zoomPanUpdate", () => {
                root.style.setProperty(
                    "--space-viewer-bg-opacity",
                    String(pswp!.bgOpacity),
                );
            });
            pswp.on("change", () => {
                const nextIndex = pswp?.currIndex;
                if (nextIndex != undefined) {
                    setLocalPhotoIndex(nextIndex);
                    onPhotoIndexChangeRef.current?.(nextIndex);
                }
            });
            pswp.on("keydown", (event) => {
                if (
                    isSwipeBlockedRef.current ||
                    event.originalEvent.target instanceof HTMLTextAreaElement
                ) {
                    event.preventDefault();
                }
            });
            pswp.on("pointerDown", (event) => {
                if (isSwipeBlockedRef.current) {
                    event.preventDefault();
                    return;
                }
                if (edgeSwipeStart) {
                    edgeSwipeStart = undefined;
                    return;
                }
                if (
                    !closeOnSwipePastEndRef.current ||
                    isDismissBlockedRef.current ||
                    pswp!.currIndex != viewerPhotosRef.current.length - 1 ||
                    pswp!.currSlide?.isPannable()
                )
                    return;
                edgeSwipeStart = viewerTouchPoint(event.originalEvent);
            });
            pswp.on("pointerUp", ({ originalEvent }) => {
                const start = edgeSwipeStart;
                edgeSwipeStart = undefined;
                if (
                    !start ||
                    originalEvent.type.endsWith("cancel") ||
                    isDismissBlockedRef.current ||
                    pswp!.gestures.isMultitouch ||
                    pswp!.currSlide?.isPannable()
                )
                    return;
                const end = viewerTouchPoint(originalEvent);
                if (!end) return;
                const dx = end.x - start.x;
                const dy = end.y - start.y;
                if (dx < -72 && Math.abs(dx) > Math.abs(dy) * 1.5) {
                    onCloseRef.current();
                }
            });
            pswp.init();
        });

        return () => {
            disposed = true;
            closedByReact = true;
            pswpRef.current = undefined;
            pswp?.destroy();
            root.style.removeProperty("--space-viewer-bg-opacity");
        };
    }, [hasDraftPhotoControls, viewerViewportSize]);

    React.useEffect(() => {
        if (typeof document == "undefined") return;

        const previousOverflow = document.body.style.overflow;
        document.body.style.overflow = "hidden";
        return () => {
            document.body.style.overflow = previousOverflow;
        };
    }, []);

    React.useEffect(() => {
        const closeOnEscape = (event: KeyboardEvent) => {
            if (
                addFriendSheetOpen ||
                deleteSheetOpen ||
                isDraftPostExit ||
                isDraftPostActionRunning
            )
                return;
            if (event.key != "Escape") return;

            if (isCaptionEditing && !isCaptionUpdateActionRunning) {
                cancelCaptionEdit();
                return;
            }
            onCloseRef.current();
        };

        window.addEventListener("keydown", closeOnEscape);
        return () => window.removeEventListener("keydown", closeOnEscape);
    }, [
        cancelCaptionEdit,
        isDraftPostActionRunning,
        addFriendSheetOpen,
        deleteSheetOpen,
        isDraftPostExit,
        isCaptionEditing,
        isCaptionUpdateActionRunning,
    ]);

    return (
        <Box
            ref={viewerRootRef}
            role="dialog"
            aria-label={`${displayName} photo viewer`}
            aria-modal="true"
            onTransitionEnd={(event) => {
                if (
                    !isDraftPostExitAnimating ||
                    event.currentTarget != event.target ||
                    event.propertyName != "opacity"
                )
                    return;

                finishDraftPostExit();
            }}
            sx={{
                bgcolor: "rgb(0 0 0 / var(--space-viewer-bg-opacity, 1))",
                boxSizing: "border-box",
                color: textBase,
                display: "flex",
                flexDirection: "column",
                inset: 0,
                isolation: "isolate",
                maxWidth: "100vw",
                minHeight: "100svh",
                opacity: isDraftPostExitAnimating ? 0 : 1,
                overflow: "hidden",
                overflowX: "hidden",
                pointerEvents: isDraftPostExit ? "none" : "auto",
                position: "fixed",
                transition: `opacity ${draftPostExitDurationMs}ms cubic-bezier(0.22, 1, 0.36, 1)`,
                width: "100%",
                zIndex: 1300,
                "& .space-photo-placeholder": {
                    alignItems: "center",
                    color: "#A6A6A6",
                    display: "flex",
                    height: "100%",
                    justifyContent: "center",
                    fontSize: 14,
                },
                "& [data-space-viewer-chrome='true'], & [data-space-viewer-bottom='true']":
                    { opacity: "var(--space-viewer-bg-opacity, 1)" },
                "@media (prefers-reduced-motion: reduce)": {
                    transition: "none",
                },
            }}
        >
            <Box
                component="header"
                data-space-viewer-chrome="true"
                sx={{
                    alignItems: "center",
                    display: "grid",
                    flexShrink: 0,
                    gap: "12px",
                    gridTemplateColumns: "minmax(0, 1fr) auto",
                    minHeight: viewerHeaderHeight,
                    position: "relative",
                    px: "16px",
                    width: "100%",
                    zIndex: 2,
                }}
            >
                <Box
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        gap: "8px",
                        minWidth: 0,
                    }}
                >
                    <Box
                        component={onOpenProfile ? "button" : "div"}
                        type={onOpenProfile ? "button" : undefined}
                        aria-label={
                            onOpenProfile
                                ? `Open ${displayName}'s profile`
                                : undefined
                        }
                        onClick={onOpenProfile}
                        sx={{
                            appearance: "none",
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            borderRadius: "50%",
                            cursor: onOpenProfile ? "pointer" : "default",
                            display: "flex",
                            flexShrink: 0,
                            height: spaceTouchTargetSize,
                            justifyContent: "center",
                            mx: "-8px",
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <Box
                            sx={{
                                borderRadius: "50%",
                                height: viewerHeaderAvatarSize,
                                overflow: "hidden",
                                width: viewerHeaderAvatarSize,
                            }}
                        >
                            <SpaceAvatarImage src={activePhoto.avatarUrl} />
                        </Box>
                    </Box>
                    <Box
                        sx={{
                            alignItems: "baseline",
                            display: "flex",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            gap: "4px",
                            lineHeight: "20px",
                            minWidth: 0,
                            overflow: "hidden",
                            whiteSpace: "nowrap",
                        }}
                    >
                        <Box
                            component={onOpenProfile ? "button" : "span"}
                            type={onOpenProfile ? "button" : undefined}
                            aria-label={
                                onOpenProfile
                                    ? `Open ${displayName}'s profile`
                                    : undefined
                            }
                            onClick={onOpenProfile}
                            sx={{
                                appearance: "none",
                                bgcolor: "transparent",
                                border: 0,
                                color: "inherit",
                                cursor: onOpenProfile ? "pointer" : "default",
                                fontFamily: "inherit",
                                fontSize: "inherit",
                                fontWeight: 650,
                                lineHeight: "inherit",
                                minWidth: 0,
                                overflow: "hidden",
                                p: 0,
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
                            {displayName}
                        </Box>
                        {!isDraftPost && (
                            <>
                                <Box
                                    component="span"
                                    aria-hidden
                                    sx={{
                                        color: textSecondary,
                                        flexShrink: 0,
                                        fontWeight: 500,
                                    }}
                                >
                                    ·
                                </Box>
                                <Box
                                    component="time"
                                    dateTime={new Date(
                                        activePhoto.timestampMs,
                                    ).toISOString()}
                                    sx={{
                                        color: textTertiary,
                                        flexShrink: 0,
                                        fontSize: 12,
                                        fontWeight: 500,
                                    }}
                                >
                                    {dateLabel}
                                </Box>
                            </>
                        )}
                    </Box>
                </Box>
                <Box
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        gap: "8px",
                        justifySelf: "flex-end",
                    }}
                >
                    {canManagePost && !isCaptionEditing && (
                        <Box
                            component="button"
                            id={actionsButtonID}
                            type="button"
                            aria-label="Post actions"
                            aria-controls={
                                isActionsOpen ? actionsMenuID : undefined
                            }
                            aria-expanded={isActionsOpen ? "true" : undefined}
                            aria-haspopup="menu"
                            onClick={(event) =>
                                setActionsAnchor(event.currentTarget)
                            }
                            sx={{
                                alignItems: "center",
                                bgcolor: "transparent",
                                border: 0,
                                color: controlIcon,
                                cursor: "pointer",
                                display: "flex",
                                height: spaceTouchTargetSize,
                                justifyContent: "center",
                                p: 0,
                                width: spaceTouchTargetSize,
                                "&:focus-visible": {
                                    borderRadius: "50%",
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                                "&:hover": { color: textBase },
                            }}
                        >
                            <HugeiconsIcon
                                icon={MoreHorizontalIcon}
                                size={26}
                                strokeWidth={2}
                            />
                        </Box>
                    )}
                    {isDraftPost && onEditDraftPhoto && (
                        <Box
                            component="button"
                            type="button"
                            aria-label="Edit photo"
                            title="Edit photo"
                            disabled={
                                isDraftPostActionRunning ||
                                isDraftPostPreviewPending ||
                                Boolean(draftPostPreparationError)
                            }
                            onClick={onEditDraftPhoto}
                            sx={{
                                ...viewerHeaderButtonSx,
                                mr: postPhotoCount > 1 ? "8px" : 0,
                                "&:disabled": {
                                    opacity: 0.3,
                                    cursor: "default",
                                },
                            }}
                        >
                            <HugeiconsIcon
                                icon={Edit03Icon}
                                size={16}
                                strokeWidth={1.8}
                            />
                        </Box>
                    )}
                    <SpacePostPhotosCounter
                        index={postPhotoIndex}
                        count={postPhotoCount}
                    />
                    <Box
                        component="button"
                        type="button"
                        aria-label={
                            isCaptionEditing && !isCaptionUpdateActionRunning
                                ? "Cancel caption edit"
                                : "Close viewer"
                        }
                        onClick={closeViewer}
                        sx={viewerHeaderButtonSx}
                    >
                        <HugeiconsIcon
                            icon={Cancel01Icon}
                            size={20}
                            strokeWidth={1.8}
                        />
                    </Box>
                </Box>
                {canManagePost && (
                    <Menu
                        id={actionsMenuID}
                        anchorEl={actionsAnchor}
                        open={isActionsOpen}
                        onClose={closeActions}
                        anchorOrigin={{
                            horizontal: "right",
                            vertical: "bottom",
                        }}
                        transformOrigin={{
                            horizontal: "right",
                            vertical: "top",
                        }}
                        slotProps={{
                            paper: {
                                sx: {
                                    bgcolor: "#1E1E1E",
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
                                "aria-labelledby": actionsButtonID,
                                sx: { p: 0 },
                            },
                        }}
                    >
                        {canUpdatePostCaption && (
                            <MenuItem
                                dense
                                disableRipple
                                onClick={requestCaptionEdit}
                                sx={{
                                    alignItems: "center",
                                    borderRadius: "10px",
                                    color: textBase,
                                    display: "flex",
                                    gap: "8px",
                                    minHeight: 36,
                                    px: "9px",
                                    py: "4px",
                                    whiteSpace: "nowrap",
                                    "&.Mui-focusVisible": {
                                        bgcolor: "rgba(255, 255, 255, 0.1)",
                                    },
                                    "&:active": {
                                        bgcolor: "rgba(255, 255, 255, 0.1)",
                                    },
                                    "&:hover": {
                                        bgcolor: "rgba(255, 255, 255, 0.1)",
                                    },
                                }}
                            >
                                <HugeiconsIcon
                                    icon={Edit01Icon}
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
                                    Edit caption
                                </Box>
                            </MenuItem>
                        )}
                        {canDeletePost && (
                            <MenuItem
                                dense
                                disableRipple
                                onClick={requestDeletePost}
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
                                        bgcolor: "rgba(246, 58, 58, 0.14)",
                                    },
                                    "&:active": {
                                        bgcolor: "rgba(246, 58, 58, 0.14)",
                                    },
                                    "&:hover": {
                                        bgcolor: "rgba(246, 58, 58, 0.14)",
                                    },
                                }}
                            >
                                <HugeiconsIcon
                                    icon={Delete02Icon}
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
                                    Delete post
                                </Box>
                            </MenuItem>
                        )}
                    </Menu>
                )}
            </Box>
            <Box
                sx={{
                    flex: "1 1 auto",
                    minHeight: 0,
                    position: "relative",
                    width: "100%",
                }}
            />
            {isDesktopViewer && viewerPhotos.length > 1 && (
                <>
                    {[-1, 1].map((direction) => (
                        <Box
                            key={direction}
                            component="button"
                            type="button"
                            aria-label={
                                direction < 0 ? "Previous photo" : "Next photo"
                            }
                            disabled={
                                isSwipeBlockedRef.current ||
                                (direction < 0
                                    ? activePhotoIndex == 0
                                    : activePhotoIndex ==
                                      viewerPhotos.length - 1)
                            }
                            onClick={() =>
                                pswpRef.current?.goTo(
                                    activePhotoIndex + direction,
                                )
                            }
                            sx={{
                                ...viewerHeaderButtonSx,
                                bgcolor: "rgba(0,0,0,0.5)",
                                left: direction < 0 ? 16 : "auto",
                                right: direction > 0 ? 16 : "auto",
                                position: "absolute",
                                top: "45%",
                                zIndex: 2,
                                "&:disabled": { opacity: 0.25 },
                            }}
                        >
                            <HugeiconsIcon
                                icon={
                                    direction < 0
                                        ? ArrowLeft02Icon
                                        : ArrowRight02Icon
                                }
                                size={24}
                            />
                        </Box>
                    ))}
                </>
            )}
            {hasPhotoLoadError && (
                <Box
                    sx={{
                        alignSelf: "center",
                        position: "absolute",
                        top: "45%",
                        zIndex: 2,
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        onClick={() =>
                            setPhotoLoadErrors((current) => {
                                return Object.fromEntries(
                                    Object.entries(current).filter(
                                        ([key]) => key != activePhotoKey,
                                    ),
                                );
                            })
                        }
                        sx={{
                            bgcolor: "#333333",
                            border: 0,
                            borderRadius: "24px",
                            color: textBase,
                            cursor: "pointer",
                            p: 2,
                        }}
                    >
                        Couldn&apos;t load photo. Retry
                    </Box>
                </Box>
            )}
            <Box
                aria-hidden
                data-space-viewer-chrome="true"
                sx={{
                    background:
                        "linear-gradient(180deg, rgba(0, 0, 0, 0.32) 0%, rgba(0, 0, 0, 0.13) 58%, rgba(0, 0, 0, 0) 100%)",
                    height: 44,
                    left: 0,
                    pointerEvents: "none",
                    position: "fixed",
                    right: 0,
                    top: 0,
                    zIndex: 1,
                }}
            />
            <Box
                aria-hidden
                data-space-viewer-chrome="true"
                sx={{
                    background:
                        "linear-gradient(0deg, rgba(0, 0, 0, 0.34) 0%, rgba(0, 0, 0, 0.14) 58%, rgba(0, 0, 0, 0) 100%)",
                    bottom: 0,
                    height: 52,
                    left: 0,
                    pointerEvents: "none",
                    position: "fixed",
                    right: 0,
                    zIndex: 1,
                }}
            />
            {isDraftPost ? (
                <Box
                    data-space-viewer-bottom="true"
                    sx={{
                        alignItems: "stretch",
                        bottom: "max(24px, calc(env(safe-area-inset-bottom) + 16px))",
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: "4px",
                        left: { xs: "16px", sm: "auto" },
                        maxWidth: { sm: 390 },
                        position: "fixed",
                        right: "16px",
                        width: { sm: "calc(100% - 32px)" },
                        zIndex: 2,
                    }}
                >
                    {draftPhotoControls}
                    {draftPostPreparationError && (
                        <Box
                            role="alert"
                            sx={{
                                bgcolor: "rgba(246, 58, 58, 0.16)",
                                borderRadius: "12px",
                                color: "#FF8A8A",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 13,
                                fontWeight: 650,
                                lineHeight: "18px",
                                px: "12px",
                                py: "8px",
                            }}
                        >
                            {draftPostPreparationError}
                        </Box>
                    )}
                    <Box
                        sx={{
                            alignItems: "flex-end",
                            display: "flex",
                            gap: "8px",
                        }}
                    >
                        <Box
                            ref={captionInputRef}
                            component="textarea"
                            aria-label="Add a caption"
                            disabled={isDraftPostActionRunning}
                            onChange={(event) => {
                                setCaption(event.target.value);
                                resizeCaptionInput(
                                    event.currentTarget,
                                    replyInputMinHeight,
                                );
                            }}
                            placeholder="Add a caption..."
                            rows={1}
                            value={caption}
                            sx={{
                                bgcolor: inputBackground,
                                border: 0,
                                borderRadius: "24px",
                                boxSizing: "border-box",
                                color: textBase,
                                flex: "1 1 auto",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 500,
                                lineHeight: "20px",
                                maxHeight: captionInputMaxHeight,
                                minHeight: replyInputMinHeight,
                                minWidth: 0,
                                outline: 0,
                                overflow: "hidden",
                                pb: `${replyInputPadding}px`,
                                pl: `${replyInputPaddingLeft}px`,
                                pr: `${replyInputPadding}px`,
                                pt: `${replyInputPadding}px`,
                                resize: "none",
                                "&::placeholder": { color: textSecondary },
                                "&:disabled": { opacity: 0.74 },
                                "&:focus": { bgcolor: inputBackgroundActive },
                            }}
                        />
                        <Box
                            component="button"
                            type="button"
                            aria-label={
                                draftPostPreparationError
                                    ? "Photo could not be prepared"
                                    : "Post photos"
                            }
                            disabled={isDraftPostPublishDisabled}
                            onClick={publishDraftPost}
                            onPointerDown={handleInputActionPointerDown}
                            sx={{
                                alignItems: "center",
                                bgcolor: "#FFFFFF",
                                border: 0,
                                borderRadius: "24px",
                                boxSizing: "border-box",
                                boxShadow: "0 10px 28px rgba(0, 0, 0, 0.28)",
                                color: "#1C1C1E",
                                cursor: isDraftPostPublishDisabled
                                    ? "default"
                                    : "pointer",
                                display: "flex",
                                flexShrink: 0,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 750,
                                height: replyInputMinHeight,
                                justifyContent: "center",
                                lineHeight: "20px",
                                minWidth: 70,
                                px: "20px",
                                py: "10px",
                                "&:disabled": { opacity: 1 },
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                                "&:hover": {
                                    filter: isDraftPostPublishDisabled
                                        ? undefined
                                        : "brightness(0.96)",
                                },
                            }}
                        >
                            Post
                        </Box>
                    </Box>
                </Box>
            ) : null}
            {isCaptionEditing && (
                <Box
                    data-space-viewer-bottom="true"
                    sx={{
                        alignItems: "stretch",
                        bottom: "max(24px, calc(env(safe-area-inset-bottom) + 16px))",
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: "8px",
                        left: { xs: "16px", sm: "auto" },
                        maxWidth: { sm: 390 },
                        position: "fixed",
                        right: "16px",
                        width: { sm: "calc(100% - 32px)" },
                        zIndex: 2,
                    }}
                >
                    {hasCaptionUpdateError && (
                        <Box
                            role="alert"
                            sx={{
                                bgcolor: "rgba(246, 58, 58, 0.16)",
                                borderRadius: "12px",
                                color: "#FF8A8A",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 13,
                                fontWeight: 650,
                                lineHeight: "18px",
                                px: "12px",
                                py: "8px",
                            }}
                        >
                            Couldn&apos;t save caption. Try again.
                        </Box>
                    )}
                    <Box
                        sx={{
                            alignItems: "flex-end",
                            display: "flex",
                            gap: "8px",
                        }}
                    >
                        <Box
                            ref={captionInputRef}
                            component="textarea"
                            aria-label="Edit caption"
                            disabled={isCaptionUpdateActionRunning}
                            onChange={(event) => {
                                setCaptionEditValue(event.target.value);
                                setHasCaptionUpdateError(false);
                                resizeCaptionInput(
                                    event.currentTarget,
                                    replyInputMinHeight,
                                );
                            }}
                            placeholder="Add a caption..."
                            rows={1}
                            value={captionEditValue}
                            sx={{
                                bgcolor: inputBackground,
                                border: 0,
                                borderRadius: "24px",
                                boxSizing: "border-box",
                                color: textBase,
                                flex: "1 1 auto",
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 500,
                                lineHeight: "20px",
                                maxHeight: captionInputMaxHeight,
                                minHeight: replyInputMinHeight,
                                minWidth: 0,
                                outline: 0,
                                overflow: "hidden",
                                pb: `${replyInputPadding}px`,
                                pl: `${replyInputPaddingLeft}px`,
                                pr: `${replyInputPadding}px`,
                                pt: `${replyInputPadding}px`,
                                resize: "none",
                                "&::placeholder": { color: textSecondary },
                                "&:disabled": { opacity: 0.74 },
                                "&:focus": { bgcolor: inputBackgroundActive },
                            }}
                        />
                        <Box
                            component="button"
                            type="button"
                            aria-label={
                                captionUpdateActionPhase == "busy"
                                    ? "Saving caption"
                                    : captionUpdateActionPhase == "done"
                                      ? "Caption saved"
                                      : "Save caption"
                            }
                            disabled={isCaptionUpdateDisabled}
                            onClick={updateCaption}
                            sx={{
                                alignItems: "center",
                                bgcolor: "#FFFFFF",
                                border: 0,
                                borderRadius: "24px",
                                boxSizing: "border-box",
                                boxShadow: "0 10px 28px rgba(0, 0, 0, 0.28)",
                                color: "#1C1C1E",
                                cursor: isCaptionUpdateDisabled
                                    ? "default"
                                    : "pointer",
                                display: "flex",
                                flexShrink: 0,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 14,
                                fontWeight: 750,
                                height: replyInputMinHeight,
                                justifyContent: "center",
                                lineHeight: "20px",
                                minWidth: 70,
                                px: "20px",
                                py: "10px",
                                transition:
                                    "background-color 160ms ease, color 160ms ease, filter 120ms ease",
                                "&:disabled": isCaptionUpdateActionRunning
                                    ? undefined
                                    : {
                                          bgcolor: spaceDialogBackground,
                                          color: spaceTextMuted,
                                      },
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                                "&:hover:not(:disabled)": {
                                    filter: "brightness(0.96)",
                                },
                                "&:active:not(:disabled)": {
                                    filter: "brightness(0.92)",
                                },
                            }}
                        >
                            <Box
                                component="span"
                                sx={{ display: "grid", placeItems: "center" }}
                            >
                                <Box
                                    component="span"
                                    sx={{
                                        gridArea: "1 / 1",
                                        visibility:
                                            captionUpdateActionPhase == null
                                                ? "visible"
                                                : "hidden",
                                    }}
                                >
                                    Save
                                </Box>
                                <Box
                                    component="span"
                                    sx={{
                                        animation:
                                            captionUpdateActionPhase == "busy"
                                                ? `${postButtonSpin} 2.4s linear infinite`
                                                : "none",
                                        display: "flex",
                                        gridArea: "1 / 1",
                                        lineHeight: 0,
                                        visibility:
                                            captionUpdateActionPhase == "busy"
                                                ? "visible"
                                                : "hidden",
                                    }}
                                >
                                    <HugeiconsIcon
                                        icon={Loading03Icon}
                                        size={22}
                                        strokeWidth={1.8}
                                    />
                                </Box>
                                <Box
                                    component="span"
                                    sx={{
                                        display: "flex",
                                        gridArea: "1 / 1",
                                        lineHeight: 0,
                                        visibility:
                                            captionUpdateActionPhase == "done"
                                                ? "visible"
                                                : "hidden",
                                    }}
                                >
                                    <HugeiconsIcon
                                        icon={Tick02Icon}
                                        size={22}
                                        strokeWidth={1.8}
                                    />
                                </Box>
                            </Box>
                        </Box>
                    </Box>
                </Box>
            )}
            {(hasDisplayCaption || showPhotoLikeButton) &&
                !isCaptionEditing && (
                    <Box
                        data-space-viewer-bottom="true"
                        sx={{
                            alignItems: "stretch",
                            bottom: "max(24px, calc(env(safe-area-inset-bottom) + 16px))",
                            display: "flex",
                            flexDirection: "column",
                            gap: "12px",
                            left: { xs: "16px", sm: "auto" },
                            maxWidth: { sm: 390 },
                            position: "fixed",
                            right: "16px",
                            width: { sm: "calc(100% - 32px)" },
                            zIndex: 2,
                        }}
                    >
                        {hasDisplayCaption && (
                            <SpaceViewerCaption
                                key={activePostKey}
                                caption={displayCaption}
                            />
                        )}
                        {showPhotoLikeButton && (
                            <SpacePostReplyControls
                                canSendReply={canSendReply}
                                isReplyMode={isReplyMode}
                                liked={isPhotoLiked}
                                likePopID={photoLikePopID}
                                onLike={handlePhotoLikeClick}
                                onSendReply={sendReply}
                                replyActionPhase={replyActionPhase}
                                replyInputRef={replyInputRef}
                                replyInputProps={
                                    canReplyToPost
                                        ? {
                                              onBlur: () =>
                                                  setIsReplyFocused(false),
                                              onChange: (event) => {
                                                  const nextText =
                                                      clampSpaceMessageText(
                                                          event.target.value,
                                                      );
                                                  event.currentTarget.value =
                                                      nextText;
                                                  setReplyText(nextText);
                                                  replyDraftsRef.current.set(
                                                      activeReplyKey,
                                                      nextText,
                                                  );
                                              },
                                              onFocus: () =>
                                                  setIsReplyFocused(true),
                                              onKeyDown: handleReplyKeyDown,
                                              onPointerDown:
                                                  handleReplyInputPointerDown,
                                              readOnly:
                                                  canAddFriendForPostAction,
                                              value: replyText,
                                          }
                                        : undefined
                                }
                            />
                        )}
                    </Box>
                )}
            {canDeletePost && (
                <ConfirmationActionSheet
                    open={deleteSheetOpen}
                    title="Are you sure you want to delete this?"
                    confirmLabel="Yes, delete"
                    confirmActionPhase={deleteActionPhase}
                    confirmDisabled={isDeleteActionRunning}
                    cancelDisabled={isDeleteActionRunning}
                    onCancel={closeDeleteSheet}
                    onConfirm={confirmDeletePost}
                    onExited={handleDeleteSheetExited}
                />
            )}
            {canAddFriendForPostAction && (
                <ConfirmationActionSheet
                    open={addFriendSheetOpen}
                    title={
                        addFriendIntent == "like"
                            ? `Add ${displayName} as a friend to like?`
                            : `Add ${displayName} as a friend to reply?`
                    }
                    confirmLabel="Add friend"
                    confirmBackgroundColor={green}
                    confirmClassName="green-bg"
                    onCancel={() => setAddFriendSheetOpen(false)}
                    onConfirm={confirmAddFriendForPostAction}
                />
            )}
        </Box>
    );
};
