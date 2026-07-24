import {
    Cancel01Icon,
    Delete02Icon,
    Edit01Icon,
    FavouriteIcon,
    Loading03Icon,
    MoreHorizontalIcon,
    Navigation03Icon,
    Tick02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Menu, MenuItem } from "@mui/material";
import { keyframes } from "@mui/material/styles";
import { ConfirmationActionSheet } from "components/ConfirmationActionSheet";
import {
    spaceActionDoneDurationMs,
    type SpaceActionPhase,
} from "components/SpaceActionFeedback";
import { SpaceAvatarImage } from "components/SpaceAvatarImage";
import {
    spacePostLikeButtonPop,
    spacePostLikeHeartPop,
    spacePostLikePopDurationMs,
    spacePostLikePopTiming,
} from "components/SpacePostLikeAnimation";
import type PhotoSwipe from "photoswipe";
import React from "react";
import { spaceTouchTargetSize } from "styles/touchTargets";
import { firstNameFrom, formatSpaceDate } from "utils/spaceDisplay";
import { clampSpaceMessageText } from "utils/spaceMessageLimits";
import type { SpaceImageCropArea } from "utils/spacePostImage";

const green = "#08C225";
const textBase = "#F4F4F4";
const textSecondary = "#A6A6A6";
const textTertiary = "rgba(244, 244, 244, 0.52)";
const viewerBackground = "#000000";
const controlBackground = "rgba(36, 36, 36, 0.72)";
const controlBackgroundHover = "rgba(48, 48, 48, 0.86)";
const inputBackground = "rgba(58, 58, 58, 0.86)";
const inputBackgroundActive = "rgba(72, 72, 72, 0.9)";
const controlIcon = "#D8D8D8";
const dangerColor = "#F63A3A";
const viewerHeaderHeight = 56;
const viewerBottomPadding = 88;
const viewerDesktopMinWidth = 600;
const draftViewerBottomPadding = 88;
const captionInputMinHeight = 40;
const replyInputMinHeight = 48;
const replyInputPadding = 14;
const replyInputPaddingLeft = 18;
const viewerActionDoneDurationMs = 1000;
const captionInputMaxHeight = 112;
const defaultPhotoWidth = 900;
const defaultPhotoHeight = 680;
const viewerSwipeMinDeltaPx = 72;
const viewerSwipeAxisRatio = 1.5;
const viewerHeaderAvatarSize = 28;
const viewerHeaderButtonVisualSize = 28;
const draftPostExitDurationMs = 320;

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

const photoPreviewSkeletonShimmer = keyframes`
    from {
        background-position: 100% 0;
    }

    to {
        background-position: -100% 0;
    }
`;

export type SpaceViewerPostActionMode = "draft-post" | "hidden" | "like-only";

export interface SpaceViewerDraftPostEdit {
    cropArea?: SpaceImageCropArea;
    height?: number;
    rotationDegrees: number;
    width?: number;
}

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
    name: string;
    postId?: number;
    spaceId?: string;
    timestampMs: number;
    viewerLiked?: boolean;
    width?: number;
}

interface SpaceViewerDeleteSnapshot {
    photoIndex: number;
    photos: SpaceViewerPhoto[];
}

interface SpaceFileViewerProps {
    draftPostPreparationError?: string;
    isDraftPostPreparing?: boolean;
    isDraftPostPreviewPending?: boolean;
    onClose: () => void;
    onDeletePost?: () => Promise<void> | void;
    onDraftPostExitStart?: () => void;
    onDraftPostPublished?: () => void;
    onOpenProfile?: () => void;
    onPublishDraftPost?: (
        caption: string,
        edit: SpaceViewerDraftPostEdit,
    ) => Promise<void>;
    onReplyToPost?: (
        spaceId: string,
        postId: number,
        text: string,
    ) => Promise<void>;
    onSetPostLiked?: (postId: number, liked: boolean) => Promise<void>;
    onUpdatePostCaption?: (postId: number, caption: string) => Promise<void>;
    onSwipeLeft?: () => void;
    onSwipeRight?: () => void;
    onPhotoIndexChange?: (index: number) => void;
    photo: SpaceViewerPhoto;
    photoIndex?: number;
    photos?: SpaceViewerPhoto[];
    focusReplyOnOpen?: boolean;
    postActionMode?: SpaceViewerPostActionMode;
}

interface ViewerSwipeGesture {
    lastX: number;
    lastY: number;
    pointerId?: number;
    startX: number;
    startY: number;
}

const viewerSwipePointFromEvent = (event: Event) => {
    if (event.type.startsWith("mouse")) return undefined;
    if (
        "pointerType" in event &&
        (event as PointerEvent).pointerType == "mouse"
    ) {
        return undefined;
    }
    if ("changedTouches" in event) {
        const touch = (event as TouchEvent).changedTouches[0];
        if (!touch) return undefined;
        return { x: touch.pageX, y: touch.pageY };
    }
    if ("pageX" in event && "pageY" in event) {
        return {
            pointerId:
                "pointerId" in event
                    ? (event as PointerEvent).pointerId
                    : undefined,
            x: (event as MouseEvent).pageX,
            y: (event as MouseEvent).pageY,
        };
    }
    return undefined;
};

const viewerSwipeStartsOnInteractiveTarget = (target: EventTarget | null) =>
    target instanceof Element &&
    Boolean(
        target.closest(
            "input, textarea, select, button, [data-space-viewer-chrome='true'], [data-space-viewer-bottom='true']",
        ),
    );

const viewerActionButtonSx = {
    alignItems: "center",
    bgcolor: controlBackground,
    border: 0,
    borderRadius: "50%",
    boxShadow: "0 10px 28px rgba(0, 0, 0, 0.36)",
    color: controlIcon,
    cursor: "pointer",
    display: "flex",
    height: 48,
    justifyContent: "center",
    p: 0,
    width: 48,
    "&:active": { bgcolor: "#3A3A3A" },
    "&:focus-visible": { outline: `2px solid ${green}`, outlineOffset: 2 },
    "&:hover": { bgcolor: controlBackgroundHover },
};

export const SpaceViewerFeedBackdrop: React.FC<{ exiting?: boolean }> = ({
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
    color: controlIcon,
    cursor: "pointer",
    display: "flex",
    height: spaceTouchTargetSize,
    justifyContent: "center",
    mx: "-8px",
    p: 0,
    width: spaceTouchTargetSize,
    "&:focus-visible": { outline: `2px solid ${green}`, outlineOffset: 2 },
    "&:hover .space-viewer-header-button-visual": {
        bgcolor: controlBackgroundHover,
    },
};

const viewerHeaderButtonVisualSx = {
    alignItems: "center",
    bgcolor: controlBackground,
    borderRadius: "50%",
    display: "flex",
    height: viewerHeaderButtonVisualSize,
    justifyContent: "center",
    width: viewerHeaderButtonVisualSize,
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

export const SpaceFileViewer: React.FC<SpaceFileViewerProps> = ({
    draftPostPreparationError,
    focusReplyOnOpen = false,
    isDraftPostPreparing = false,
    isDraftPostPreviewPending = false,
    onClose,
    onDeletePost,
    onDraftPostExitStart,
    onDraftPostPublished,
    onOpenProfile,
    onPublishDraftPost,
    onReplyToPost,
    onSetPostLiked,
    onUpdatePostCaption,
    onSwipeLeft,
    onSwipeRight,
    onPhotoIndexChange,
    photo,
    photoIndex = 0,
    photos,
    postActionMode = "like-only",
}) => {
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
    const incomingViewerPhotos = photos && photos.length > 0 ? photos : [photo];
    const viewerPhotos = isDeleteViewerLocked
        ? (deleteSnapshotRef.current?.photos ?? incomingViewerPhotos)
        : incomingViewerPhotos;
    const activePhotoIndex = Math.min(
        Math.max(
            isDeleteViewerLocked
                ? (deleteSnapshotRef.current?.photoIndex ?? photoIndex)
                : photoIndex,
            0,
        ),
        viewerPhotos.length - 1,
    );
    const activePhoto = viewerPhotos[activePhotoIndex] ?? photo;
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
    viewerPhotosRef.current = viewerPhotos;
    onCloseRef.current = onClose;
    onPhotoIndexChangeRef.current = onPhotoIndexChange;
    fallbackPhotoRef.current = activePhoto;
    const viewerPhotosContentKey = viewerPhotos
        .map(
            (item) =>
                `${item.imageUrl}:${item.width ?? ""}:${item.height ?? ""}`,
        )
        .join("|");
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
    const [isReplyFocused, setIsReplyFocused] =
        React.useState(focusReplyOnOpen);
    const [replyActionPhase, setReplyActionPhase] =
        React.useState<SpaceActionPhase | null>(null);
    const [draftPostActionPhase, setDraftPostActionPhase] =
        React.useState<SpaceActionPhase | null>(null);
    const [isDraftPostExit, setIsDraftPostExit] = React.useState(false);
    const [isDesktopViewer, setIsDesktopViewer] = React.useState(
        () =>
            typeof window != "undefined" &&
            window.innerWidth >= viewerDesktopMinWidth,
    );
    const [queuedDraftPost, setQueuedDraftPost] = React.useState<{
        caption: string;
        edit: SpaceViewerDraftPostEdit;
    }>();
    const displayName = firstNameFrom(activePhoto.name);
    const dateLabel = formatSpaceDate(activePhoto.timestampMs);
    const displayCaption = isDraftPost ? "" : caption.trim();
    const hasDisplayCaption = displayCaption.length > 0;
    const viewerRootRef = React.useRef<HTMLDivElement | null>(null);
    const stableViewportSizeRef = React.useRef<ViewerViewportSize>(
        currentViewerViewportSize(null),
    );
    const captionInputRef = React.useRef<HTMLTextAreaElement | null>(null);
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
    const canQueueDraftPostPublish =
        isDraftPostPreparing &&
        !isDraftPostPreviewPending &&
        !hasDraftPostPreparationError;
    const isDraftPostPublishDisabled =
        isDraftPostActionRunning ||
        isDraftPostPreviewPending ||
        hasDraftPostPreparationError ||
        (!onPublishDraftPost && !canQueueDraftPostPublish);
    const isReplyActionRunning = replyActionPhase != null;
    const canReplyToPost = Boolean(
        !isDraftPost &&
        activePhoto.spaceId &&
        activePhoto.postId &&
        onReplyToPost,
    );
    const isReplyMode =
        canReplyToPost &&
        (isReplyFocused || replyText.trim().length > 0 || isReplyActionRunning);
    const isPhotoLikePopping =
        !isReplyMode && isPhotoLiked && photoLikePopID > 0;
    const usePhotoSwipeViewer = !isDraftPost || isDesktopViewer;
    const canSendReply =
        canReplyToPost && !isReplyActionRunning && replyText.trim().length > 0;
    const swipeGestureRef = React.useRef<ViewerSwipeGesture | null>(null);
    const swipeActionsRef = React.useRef({ onSwipeLeft, onSwipeRight });
    swipeActionsRef.current = { onSwipeLeft, onSwipeRight };
    const isSwipeBlockedRef = React.useRef(false);
    isSwipeBlockedRef.current =
        isActionsOpen ||
        (canDeletePost && deleteSheetOpen) ||
        isDeleteExit ||
        isDraftPostExit ||
        isCaptionEditing ||
        isDraftPost ||
        isDraftPostPreviewPending;
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

    const handlePhotoLikeClick = () => {
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
                console.error("Failed to update post like", error);
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
                console.error("Failed to update post caption", error);
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
                console.error("Failed to delete space post", error);
                deleteSnapshotRef.current = null;
                setDeleteActionPhase(null);
            }
        })();
    };

    const draftPostEdit = React.useCallback((): SpaceViewerDraftPostEdit => {
        return {
            height: activePhoto.height,
            rotationDegrees: 0,
            width: activePhoto.width,
        };
    }, [activePhoto.height, activePhoto.width]);

    const publishDraftPostWithCaption = React.useCallback(
        (captionToPublish: string, editToPublish: SpaceViewerDraftPostEdit) => {
            if (!onPublishDraftPost || isDeleteExit || isDraftPostExit) return;

            setDraftPostActionPhase("busy");
            let publishPromise: Promise<void>;
            try {
                publishPromise = Promise.resolve(
                    onPublishDraftPost(captionToPublish, editToPublish),
                );
            } catch (error) {
                console.error("Failed to publish space post", error);
                setDraftPostActionPhase(null);
                return;
            }

            setQueuedDraftPost(undefined);
            setIsDraftPostExit(true);
            onDraftPostExitStart?.();
            void publishPromise.catch((error: unknown) => {
                console.error("Failed to publish space post", error);
            });
        },
        [
            isDeleteExit,
            isDraftPostExit,
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

        const edit = draftPostEdit();
        if (!onPublishDraftPost) {
            if (!canQueueDraftPostPublish) return;

            setQueuedDraftPost({ caption, edit });
            setDraftPostActionPhase("busy");
            return;
        }

        publishDraftPostWithCaption(caption, edit);
    };

    const sendReply = () => {
        const text = replyText.trim();
        if (
            !canSendReply ||
            !activePhoto.spaceId ||
            !activePhoto.postId ||
            !onReplyToPost
        ) {
            return;
        }

        setReplyActionPhase("busy");
        void (async () => {
            try {
                await onReplyToPost(
                    activePhoto.spaceId!,
                    activePhoto.postId!,
                    text,
                );
                setReplyText("");
                setReplyActionPhase("done");
            } catch (error) {
                console.error("Failed to send post reply", error);
                setReplyActionPhase(null);
            }
        })();
    };

    const handleReplyKeyDown = (event: React.KeyboardEvent) => {
        if (event.key != "Enter" || event.shiftKey) return;

        event.preventDefault();
        sendReply();
    };

    const handleReplyActionPointerDown = (event: React.PointerEvent) => {
        event.preventDefault();
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
        resizeCaptionInput(replyInputRef.current, replyInputMinHeight);
    }, [replyText]);

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
        if (draftPostPreparationError && queuedDraftPost != undefined) {
            setQueuedDraftPost(undefined);
            setDraftPostActionPhase(null);
        }
    }, [draftPostPreparationError, queuedDraftPost]);

    React.useEffect(() => {
        if (queuedDraftPost == undefined || !onPublishDraftPost) return;

        const draftPost = queuedDraftPost;
        setQueuedDraftPost(undefined);
        publishDraftPostWithCaption(draftPost.caption, draftPost.edit);
    }, [onPublishDraftPost, publishDraftPostWithCaption, queuedDraftPost]);

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
    }, [replyActionPhase]);

    React.useEffect(() => {
        if (isCaptionEditingRef.current) return;

        setCaption(activePhoto.caption ?? "");
        setCaptionEditValue(activePhoto.caption ?? "");
    }, [activePhoto.caption]);

    React.useEffect(() => {
        setIsPhotoLiked(activePhoto.viewerLiked ?? false);
        setCaptionUpdateActionPhase(null);
        setHasCaptionUpdateError(false);
        setIsCaptionEditing(false);
        setReplyText("");
        setIsReplyFocused(focusReplyOnOpen && canReplyToPost);
        setReplyActionPhase(null);
    }, [
        activePhoto.imageUrl,
        activePhoto.postId,
        activePhoto.timestampMs,
        activePhoto.viewerLiked,
        canReplyToPost,
        focusReplyOnOpen,
    ]);

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
        const pswp = pswpRef.current;
        if (!pswp) return;

        const refreshIndex = (index: number) => {
            if (index >= 0 && index < viewerPhotosRef.current.length) {
                pswp.refreshSlideContent(index);
            }
        };
        refreshIndex(pswp.currIndex - 1);
        refreshIndex(pswp.currIndex);
        refreshIndex(pswp.currIndex + 1);
    }, [viewerPhotosContentKey]);

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
        if (!isDraftPostExit) return;
        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches)
            finishDraftPostExit();
    }, [finishDraftPostExit, isDraftPostExit]);

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
        if (!usePhotoSwipeViewer || isDraftPostPreviewPending) return;

        let disposed = false;
        let closedByReact = false;
        let pswp: PhotoSwipe | undefined;

        void import("photoswipe").then(({ default: PhotoSwipeClass }) => {
            if (disposed || !viewerRootRef.current) return;

            pswp = new PhotoSwipeClass({
                allowPanToNext: viewerPhotosRef.current.length > 1,
                appendToEl: viewerRootRef.current,
                arrowKeys: false,
                arrowNext: false,
                arrowPrev: false,
                bgClickAction: false,
                bgOpacity: 1,
                clickToCloseNonZoomable: false,
                close: false,
                closeOnVerticalDrag: false,
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
                    bottom:
                        window.innerWidth >= viewerDesktopMinWidth
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
            pswp.addFilter("numItems", () => viewerPhotosRef.current.length);
            pswp.addFilter("itemData", (_, index) => {
                const item =
                    viewerPhotosRef.current[index] ?? fallbackPhotoRef.current;
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
            pswp.on("change", () => {
                const nextIndex = pswp?.currIndex;
                if (nextIndex != undefined) {
                    onPhotoIndexChangeRef.current?.(nextIndex);
                }
            });
            pswp.on("pointerDown", ({ originalEvent }) => {
                if (isSwipeBlockedRef.current) return;
                if (
                    !swipeActionsRef.current.onSwipeLeft &&
                    !swipeActionsRef.current.onSwipeRight
                ) {
                    return;
                }
                if (viewerSwipeStartsOnInteractiveTarget(originalEvent.target))
                    return;

                const point = viewerSwipePointFromEvent(originalEvent);
                if (!point) return;

                swipeGestureRef.current = {
                    lastX: point.x,
                    lastY: point.y,
                    pointerId: point.pointerId,
                    startX: point.x,
                    startY: point.y,
                };
            });
            pswp.on("pointerMove", ({ originalEvent }) => {
                const gesture = swipeGestureRef.current;
                if (!gesture) return;

                const point = viewerSwipePointFromEvent(originalEvent);
                if (!point) return;
                if (
                    gesture.pointerId != undefined &&
                    point.pointerId != undefined &&
                    gesture.pointerId != point.pointerId
                ) {
                    return;
                }

                gesture.lastX = point.x;
                gesture.lastY = point.y;
            });
            pswp.on("pointerUp", ({ originalEvent }) => {
                const gesture = swipeGestureRef.current;
                swipeGestureRef.current = null;
                if (!gesture || isSwipeBlockedRef.current) return;

                const point = viewerSwipePointFromEvent(originalEvent);
                if (
                    point &&
                    (gesture.pointerId == undefined ||
                        point.pointerId == undefined ||
                        gesture.pointerId == point.pointerId)
                ) {
                    gesture.lastX = point.x;
                    gesture.lastY = point.y;
                }

                const deltaX = gesture.lastX - gesture.startX;
                const deltaY = gesture.lastY - gesture.startY;
                if (Math.abs(deltaX) < viewerSwipeMinDeltaPx) return;
                if (
                    Math.abs(deltaX) <
                    Math.abs(deltaY) * viewerSwipeAxisRatio
                ) {
                    return;
                }
                if (deltaX < 0 && pswp?.currSlide?.isPannable()) return;

                const swipeAction =
                    deltaX < 0
                        ? swipeActionsRef.current.onSwipeLeft
                        : swipeActionsRef.current.onSwipeRight;
                swipeAction?.();
            });
            pswp.init();
        });

        return () => {
            disposed = true;
            closedByReact = true;
            swipeGestureRef.current = null;
            pswpRef.current = undefined;
            pswp?.destroy();
        };
    }, [isDraftPostPreviewPending, usePhotoSwipeViewer, viewerViewportSize]);

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
            if (deleteSheetOpen || isDraftPostExit) return;
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
                    !isDraftPostExit ||
                    event.currentTarget != event.target ||
                    event.propertyName != "opacity"
                )
                    return;

                finishDraftPostExit();
            }}
            sx={{
                bgcolor: viewerBackground,
                boxSizing: "border-box",
                color: textBase,
                display: "flex",
                flexDirection: "column",
                inset: 0,
                isolation: "isolate",
                maxWidth: "100vw",
                minHeight: "100svh",
                opacity: isDraftPostExit ? 0 : 1,
                overflow: "hidden",
                overflowX: "hidden",
                pointerEvents: isDraftPostExit ? "none" : "auto",
                position: "fixed",
                transition: `opacity ${draftPostExitDurationMs}ms cubic-bezier(0.22, 1, 0.36, 1)`,
                width: "100%",
                zIndex: 1300,
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
                        <Box
                            className="space-viewer-header-button-visual"
                            component="span"
                            sx={viewerHeaderButtonVisualSx}
                        >
                            <HugeiconsIcon
                                icon={Cancel01Icon}
                                size={18}
                                strokeWidth={1.8}
                            />
                        </Box>
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
            {isDraftPost && (!isDesktopViewer || isDraftPostPreviewPending) && (
                <Box
                    sx={{
                        bottom: { xs: draftViewerBottomPadding, sm: 0 },
                        boxSizing: "border-box",
                        display: "grid",
                        left: 0,
                        overflow: "hidden",
                        placeItems: "center",
                        position: "fixed",
                        right: 0,
                        top: { xs: viewerHeaderHeight, sm: 0 },
                        zIndex: 0,
                    }}
                >
                    {isDraftPostPreviewPending ? (
                        <Box
                            role="status"
                            aria-label="Preparing photo preview"
                            sx={{
                                animation: `${photoPreviewSkeletonShimmer} 1.4s ease-in-out infinite`,
                                aspectRatio: "3 / 4",
                                bgcolor: "#171717",
                                backgroundImage:
                                    "linear-gradient(90deg, #171717 0%, #242424 42%, #2D2D2D 50%, #242424 58%, #171717 100%)",
                                backgroundSize: "200% 100%",
                                boxShadow: "0 16px 42px rgba(0, 0, 0, 0.34)",
                                overflow: "hidden",
                                width: "100vw",
                            }}
                        />
                    ) : (
                        <Box
                            component="img"
                            alt={activePhoto.alt ?? `${activePhoto.name} post`}
                            src={activePhoto.imageUrl}
                            sx={{
                                display: "block",
                                maxHeight: "100%",
                                maxWidth: "100vw",
                                objectFit: "contain",
                            }}
                        />
                    )}
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
                        gap: "8px",
                        left: { xs: "16px", sm: "auto" },
                        maxWidth: { sm: 390 },
                        position: "fixed",
                        right: "16px",
                        width: { sm: "calc(100% - 32px)" },
                        zIndex: 2,
                    }}
                >
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
                                draftPostActionPhase == "busy"
                                    ? "Posting"
                                    : draftPostPreparationError
                                      ? "Photo could not be prepared"
                                      : "Post photo"
                            }
                            disabled={isDraftPostPublishDisabled}
                            onClick={publishDraftPost}
                            sx={{
                                alignItems: "center",
                                bgcolor: "var(--feed-card-bg)",
                                border: 0,
                                borderRadius: "24px",
                                boxSizing: "border-box",
                                boxShadow: "0 10px 28px rgba(0, 0, 0, 0.28)",
                                color: "var(--text-color)",
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
                                    bgcolor: isDraftPostPublishDisabled
                                        ? "var(--feed-card-bg)"
                                        : "var(--feed-action-hover-bg)",
                                },
                            }}
                        >
                            {draftPostPreparationError ? "Error" : "Post"}
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
                                bgcolor: "var(--feed-card-bg)",
                                border: 0,
                                borderRadius: "24px",
                                boxSizing: "border-box",
                                boxShadow: "0 10px 28px rgba(0, 0, 0, 0.28)",
                                color: "var(--text-color)",
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
                                "&:disabled": {
                                    opacity: captionUpdateActionPhase
                                        ? 1
                                        : 0.62,
                                },
                                "&:focus-visible": {
                                    outline: `2px solid ${green}`,
                                    outlineOffset: 2,
                                },
                                "&:hover": {
                                    bgcolor: isCaptionUpdateDisabled
                                        ? "var(--feed-card-bg)"
                                        : "var(--feed-action-hover-bg)",
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
                                        primaryColor={green}
                                        size={22}
                                        strokeWidth={1.8}
                                    />
                                </Box>
                            </Box>
                        </Box>
                    </Box>
                </Box>
            )}
            {hasDisplayCaption && !isCaptionEditing && (
                <Box
                    component="p"
                    data-space-viewer-chrome="true"
                    title={displayCaption}
                    sx={{
                        boxSizing: "border-box",
                        color: textBase,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 14,
                        fontWeight: 650,
                        left: "50%",
                        lineHeight: "23px",
                        m: 0,
                        maxWidth: "90vw",
                        minWidth: 0,
                        overflowWrap: "break-word",
                        position: "fixed",
                        textAlign: "center",
                        textShadow: "0 1px 10px rgba(0, 0, 0, 0.74)",
                        bottom: "14%",
                        transform: "translateX(-50%)",
                        whiteSpace: "pre-wrap",
                        width: "90vw",
                        zIndex: 2,
                    }}
                >
                    <Box
                        component="span"
                        sx={{
                            bgcolor: "rgba(48, 48, 48, 0.82)",
                            borderRadius: "10px",
                            boxDecorationBreak: "clone",
                            px: "8px",
                            py: "2px",
                            WebkitBoxDecorationBreak: "clone",
                        }}
                    >
                        {displayCaption}
                    </Box>
                </Box>
            )}
            {showPhotoLikeButton && !isCaptionEditing && (
                <Box
                    data-space-viewer-bottom="true"
                    sx={{
                        alignItems: "stretch",
                        bottom: "max(24px, calc(env(safe-area-inset-bottom) + 16px))",
                        display: "flex",
                        flexDirection: "column",
                        gap: 0,
                        left: canReplyToPost
                            ? { xs: "16px", sm: "auto" }
                            : "auto",
                        maxWidth: canReplyToPost ? { sm: 390 } : undefined,
                        position: "fixed",
                        right: "16px",
                        width: canReplyToPost
                            ? { sm: "calc(100% - 32px)" }
                            : undefined,
                        zIndex: 2,
                    }}
                >
                    <Box
                        sx={{
                            alignItems: "flex-end",
                            display: "flex",
                            gap: "8px",
                            justifyContent: "flex-end",
                            width: "100%",
                        }}
                    >
                        {canReplyToPost && (
                            <Box
                                ref={replyInputRef}
                                component="textarea"
                                aria-label="Reply to post"
                                disabled={isReplyActionRunning}
                                onBlur={() => setIsReplyFocused(false)}
                                onChange={(event) => {
                                    const nextText = clampSpaceMessageText(
                                        event.target.value,
                                    );
                                    event.currentTarget.value = nextText;
                                    setReplyText(nextText);
                                    resizeCaptionInput(
                                        event.currentTarget,
                                        replyInputMinHeight,
                                    );
                                }}
                                onFocus={() => setIsReplyFocused(true)}
                                onKeyDown={handleReplyKeyDown}
                                placeholder={`Reply privately to ${displayName}...`}
                                rows={1}
                                value={replyText}
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
                                    "&:focus": {
                                        bgcolor: inputBackgroundActive,
                                    },
                                }}
                            />
                        )}
                        <Box
                            sx={{ height: 48, position: "relative", width: 48 }}
                        >
                            <Box
                                component="button"
                                type="button"
                                aria-label={
                                    isReplyMode
                                        ? replyActionPhase == "busy"
                                            ? "Sending reply"
                                            : replyActionPhase == "done"
                                              ? "Reply sent"
                                              : "Send reply"
                                        : isPhotoLiked
                                          ? "Unlike photo"
                                          : "Like photo"
                                }
                                aria-pressed={
                                    isReplyMode ? undefined : isPhotoLiked
                                }
                                aria-disabled={
                                    isReplyMode && !canSendReply
                                        ? true
                                        : undefined
                                }
                                onClick={
                                    isReplyMode
                                        ? sendReply
                                        : handlePhotoLikeClick
                                }
                                onPointerDown={
                                    isReplyMode
                                        ? handleReplyActionPointerDown
                                        : undefined
                                }
                                sx={{
                                ...viewerActionButtonSx,
                                animation: isPhotoLikePopping
                                    ? `${spacePostLikeButtonPop} ${spacePostLikePopDurationMs}ms ${spacePostLikePopTiming} both`
                                    : undefined,
                                bgcolor:
                                    isReplyMode && canSendReply
                                        ? "var(--feed-card-bg)"
                                        : controlBackground,
                                color:
                                    isReplyMode && canSendReply
                                        ? "var(--text-color)"
                                        : controlIcon,
                                cursor:
                                    isReplyMode && !canSendReply
                                        ? "default"
                                        : "pointer",
                                touchAction: "manipulation",
                                userSelect: "none",
                                WebkitTouchCallout: "none",
                                WebkitUserSelect: "none",
                                "&:hover": {
                                    bgcolor: isReplyMode
                                        ? canSendReply
                                            ? "var(--feed-action-hover-bg)"
                                            : controlBackground
                                        : controlBackgroundHover,
                                },
                                "@media (prefers-reduced-motion: reduce)": {
                                    animation: "none",
                                },
                            }}
                            >
                                {isReplyMode ? (
                                    replyActionPhase == "busy" ? (
                                        <Box
                                            component="span"
                                            sx={{
                                                animation: `${postButtonSpin} 2.4s linear infinite`,
                                                display: "flex",
                                                lineHeight: 0,
                                            }}
                                        >
                                            <HugeiconsIcon
                                                icon={Loading03Icon}
                                                size={22}
                                                strokeWidth={1.8}
                                            />
                                        </Box>
                                    ) : replyActionPhase == "done" ? (
                                        <HugeiconsIcon
                                            icon={Tick02Icon}
                                            primaryColor={green}
                                            size={22}
                                            strokeWidth={1.8}
                                        />
                                    ) : (
                                        <HugeiconsIcon
                                            icon={Navigation03Icon}
                                            size={24}
                                            strokeWidth={1.8}
                                            style={{
                                                transform:
                                                    "translate(-1px, 1px)",
                                            }}
                                        />
                                    )
                                ) : (
                                    <Box
                                        key={
                                            isPhotoLikePopping
                                                ? `heart-${photoLikePopID}`
                                                : "heart"
                                        }
                                        component="span"
                                        sx={{
                                            animation: isPhotoLikePopping
                                                ? `${spacePostLikeHeartPop} ${spacePostLikePopDurationMs}ms ${spacePostLikePopTiming} both`
                                                : undefined,
                                            display: "flex",
                                            lineHeight: 0,
                                            transformOrigin: "50% 58%",
                                            "@media (prefers-reduced-motion: reduce)":
                                                { animation: "none" },
                                        }}
                                    >
                                        <HugeiconsIcon
                                            fill={isPhotoLiked ? green : "none"}
                                            icon={FavouriteIcon}
                                            primaryColor={
                                                isPhotoLiked ? green : undefined
                                            }
                                            size={26}
                                            strokeWidth={1.8}
                                        />
                                    </Box>
                                )}
                            </Box>
                        </Box>
                    </Box>
                </Box>
            )}
            {canDeletePost && (
                <ConfirmationActionSheet
                    appearance="dark"
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
        </Box>
    );
};
