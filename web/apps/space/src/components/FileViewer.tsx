import {
    Add01Icon,
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
import { Box, Fade, Menu, MenuItem, Modal, Portal } from "@mui/material";
import { keyframes } from "@mui/material/styles";
import { visuallyHidden } from "@mui/utils";
import {
    spaceActionDoneDurationMs,
    type SpaceActionPhase,
} from "components/ActionFeedback";
import { SpaceAvatarImage } from "components/AvatarImage";
import { SpaceBottomSheetTransition } from "components/BottomSheetTransition";
import { SpaceCaptionText } from "components/CaptionText";
import { ConfirmationActionSheet } from "components/ConfirmationActionSheet";
import { spacePostLikePopDurationMs } from "components/post-like-animation";
import { paintStretchingDot } from "components/post-photos-dots";
import { SpacePostPhotosDots } from "components/PostPhotosDots";
import { SpacePostReplyControls } from "components/PostReplyControls";
import { createSpaceVideoContent } from "components/PostVideoContent";
import { SpaceVideoError } from "components/VideoError";
import {
    findViewerOrigin,
    playViewerClose,
    playViewerOpen,
    viewerCornerRadii,
    viewerOriginKey,
} from "components/viewer-transition";
import log from "ente-base/log";
import { isSpaceIOS } from "hooks/use-pwa-install-prompt";
import type PhotoSwipe from "photoswipe";
import React from "react";
import type { SpaceInviteIntent } from "services/invite";
import { SpaceMediaRateLimitError } from "services/media-load";
import type {
    SpacePostAsset,
    SpacePostAssetURLLoader,
    SpacePostVideo,
} from "services/space";
import {
    spaceControlBackground,
    spaceControlBackgroundHover,
    spaceDialogBackground,
    spaceMenuBackground,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";
import { firstNameFrom, formatSpaceDate } from "utils/display";
import { clampSpaceMessageText } from "utils/message-limits";
import {
    shownPhotoState,
    viewerBackgroundOpacity,
    type ViewerCornerRadii,
    type ViewerPhotoState,
    type ViewerRect,
} from "utils/viewer-geometry";

const green = "#08C225";
const textBase = spaceText;
const textSecondary = spaceTextMuted;
const textTertiary = "rgba(244, 244, 244, 0.52)";
const viewerBackground = "#000000";
const inputBackground = spaceControlBackground;
const inputBackgroundActive = spaceControlBackgroundHover;
const dangerColor = "#F63A3A";
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
const viewerHeaderAvatarSize = 32;
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
    preparationError?: string;
    isVideo?: boolean;
    video?: SpacePostVideo;
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

export interface SpaceFileViewerController {
    close: () => void;
}

interface SpaceFileViewerProps {
    ref?: React.Ref<SpaceFileViewerController>;
    closeOnSwipePastEnd?: boolean;
    headerHeight?: number;
    draftPhotoControls?: React.ReactNode;
    onLoadPhoto?: SpacePostAssetURLLoader;
    isDraftPostPreviewPending?: boolean;
    onClose: () => void;
    onAddDraftPhoto?: () => void;
    onEditDraftPhoto?: () => void;
    onDeletePost?: () => Promise<void> | void;
    onDraftPostExitAnimationStart?: () => void;
    onDraftPostExitStart?: () => Promise<void>;
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

const setViewerBackground = (root: HTMLElement, opacity: number) =>
    root.style.setProperty("--space-viewer-bg-opacity", String(opacity));

const viewerPadding = (
    hasDraftPhotoControls: boolean,
    headerHeight: number,
    header: HTMLElement | null,
) => {
    const isDesktop = window.innerWidth >= viewerDesktopMinWidth;
    let top = isDesktop ? 0 : headerHeight;
    let bottom = hasDraftPhotoControls
        ? 176
        : isDesktop
          ? 0
          : viewerBottomPadding;
    if (header && document.documentElement.hasAttribute("data-space-ios-pwa")) {
        const headerStyle = getComputedStyle(header);
        top = isDesktop
            ? parseFloat(headerStyle.paddingTop)
            : header.offsetHeight;
        bottom += parseFloat(
            headerStyle.getPropertyValue("--space-ios-safe-area-bottom"),
        );
    }
    return { bottom, left: 0, right: 0, top };
};

// index is the photo whose dots are shown, position the gallery index as a float.
const paintViewerPhotoDot = (
    root: HTMLElement,
    photos: SpaceViewerPhoto[],
    index: number,
    position: number,
) => {
    const photo = photos[index];
    if (!photo) return;
    const count = photo.postPhotoCount ?? 1;
    const neighbour = photos[position > index ? index + 1 : index - 1];
    const offset = neighbour?.postId == photo.postId ? position - index : 0;
    paintStretchingDot(root, (photo.postPhotoIndex ?? 0) + offset, count);
};

interface ViewerMotion {
    closing: boolean;
    landed: boolean;
    flight?: ReturnType<typeof playViewerOpen>;
    reveal?: () => void;
}

const endOpenFlight = (motion: ViewerMotion, root: HTMLElement) => {
    motion.flight?.release();
    motion.flight = undefined;
    delete root.dataset.spaceViewerFlying;
    delete root.dataset.spaceViewerWaiting;
    setViewerBackground(root, 1);
};

// The flying photo stays until PhotoSwipe shows its own, which Safari only does
// once the image has decoded.
const handOverOpenFlight = (
    motion: ViewerMotion,
    root: HTMLElement,
    pswp: PhotoSwipe | undefined,
) => {
    if (!motion.flight || !motion.landed || !pswp) return;
    const content = pswp.currSlide?.content;
    const image = content?.element;
    const isShown =
        content?.isError() ||
        (image instanceof HTMLImageElement &&
            image.complete &&
            image.naturalWidth > 0 &&
            image.isConnected &&
            !content?.isDecoding);
    if (isShown) endOpenFlight(motion, root);
};

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
    `${photo.imageUrl}:${photo.width ?? ""}:${photo.height ?? ""}:${photo.postPhotoCount ?? ""}:${photo.video?.asset?.objectKey ?? photo.video?.url ?? ""}:${photo.video?.start ?? ""}:${photo.video?.end ?? ""}:${photo.video?.muted ?? ""}:${photo.preparationError ?? ""}`;

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

const draftHeaderButtonSx = {
    ...viewerHeaderButtonSx,
    borderRadius: "999px",
    fontFamily: "inherit",
    fontSize: 12,
    fontWeight: 600,
    left: 0,
    minWidth: spaceTouchTargetSize,
    mx: 0,
    width: "auto",
    "&:disabled": { opacity: 0.3, cursor: "default" },
};

const draftHeaderButtonContentSx = {
    alignItems: "center",
    bgcolor: spaceControlBackground,
    borderRadius: "999px",
    display: "flex",
    gap: "6px",
    height: 32,
    px: "10px",
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

const SpaceViewerPhotoOverlay: React.FC<{
    caption: string;
    onOpenCaption: () => void;
    photoIndex: number;
    photoCount: number;
}> = ({ caption, onOpenCaption, photoIndex, photoCount }) => {
    const [isCaptionTruncated, setIsCaptionTruncated] = React.useState(false);

    return (
        <Box
            data-space-viewer-chrome="true"
            sx={{
                alignItems: "center",
                bottom: "14%",
                display: "flex",
                flexDirection: "column",
                gap: "16px",
                left: "50%",
                pointerEvents: "none",
                position: "fixed",
                transform: "translateX(-50%)",
                width: "78vw",
                zIndex: 2,
            }}
        >
            <SpacePostPhotosDots
                index={photoIndex}
                count={photoCount}
                stretches
            />
            {caption && (
                <Box
                    component={isCaptionTruncated ? "button" : "div"}
                    type={isCaptionTruncated ? "button" : undefined}
                    aria-label={
                        isCaptionTruncated ? "Read full caption" : undefined
                    }
                    aria-haspopup={isCaptionTruncated ? "dialog" : undefined}
                    onClick={isCaptionTruncated ? onOpenCaption : undefined}
                    sx={{
                        ...viewerCaptionTextSx,
                        appearance: "none",
                        bgcolor: "transparent",
                        border: 0,
                        cursor: isCaptionTruncated ? "pointer" : undefined,
                        m: 0,
                        minWidth: 0,
                        overflowWrap: "break-word",
                        p: 0,
                        pointerEvents: isCaptionTruncated ? "auto" : "none",
                        width: "100%",
                        "&:focus-visible": {
                            outline: `2px solid ${green}`,
                            outlineOffset: 4,
                        },
                    }}
                >
                    <SpaceCaptionText
                        caption={caption}
                        lineClamp={4}
                        onTruncationChange={setIsCaptionTruncated}
                    />
                </Box>
            )}
        </Box>
    );
};

export const SpaceFileViewer: React.FC<SpaceFileViewerProps> = ({
    ref,
    closeOnSwipePastEnd = false,
    headerHeight = 68,
    draftPhotoControls,
    onLoadPhoto,
    focusReplyOnOpen = false,
    isDraftPostPreviewPending = false,
    onClose,
    onAddDraftPhoto,
    onEditDraftPhoto,
    onDeletePost,
    onDraftPostExitAnimationStart,
    onDraftPostExitStart,
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
        Record<string, { retryAt?: number }>
    >({});
    const [now, setNow] = React.useState(Date.now);
    const photoLoadsRef = React.useRef(new Set<string>());
    const photoKey = (item: SpaceViewerPhoto) =>
        item.imageAsset
            ? `${item.imageAsset.spaceId}:${item.imageAsset.objectKey}`
            : item.imageUrl;
    const hasDraftPhotoControls = Boolean(draftPhotoControls);
    const hasDraftPhotoControlsRef = React.useRef(hasDraftPhotoControls);
    hasDraftPhotoControlsRef.current = hasDraftPhotoControls;
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
    const draftPostPreparationError = isDraftPost
        ? activePhoto.preparationError
        : undefined;
    const postPhotoCount = activePhoto.postPhotoCount ?? 1;
    const postPhotoIndex = activePhoto.postPhotoIndex ?? 0;
    const activePhotoKey = photoKey(activePhoto);
    const activeReplyKey = `${activePhoto.spaceId}:${activePhoto.postId}:${activePhoto.imageAsset?.objectKey}`;
    const activeReplyKeyRef = React.useRef(activeReplyKey);
    activeReplyKeyRef.current = activeReplyKey;
    const activePostKey = `${activePhoto.spaceId ?? ""}:${activePhoto.postId ?? ""}`;
    const hasPhotoLoadError = Boolean(photoLoadErrors[activePhotoKey]);
    const photoRetryAt = photoLoadErrors[activePhotoKey]?.retryAt;
    const isPhotoRateLimited = photoRetryAt !== undefined && now < photoRetryAt;
    const canUpdatePostCaption =
        !isDraftPost &&
        Boolean(activePhoto.postId) &&
        Boolean(onUpdatePostCaption);
    const canManagePost = canDeletePost || canUpdatePostCaption;
    const videoLoaderRef = React.useRef(onLoadPhoto);
    videoLoaderRef.current = onLoadPhoto;
    const viewerPhotosRef = React.useRef(viewerPhotos);
    const onCloseRef = React.useRef(onClose);
    const onPhotoIndexChangeRef = React.useRef(onPhotoIndexChange);
    const initialPhotoIndexRef = React.useRef(activePhotoIndex);
    const fallbackPhotoRef = React.useRef(activePhoto);
    const pswpRef = React.useRef<PhotoSwipe | undefined>(undefined);
    const motionRef = React.useRef<ViewerMotion>({
        closing: false,
        landed: false,
    });
    const isSyncingPhotosRef = React.useRef(false);
    const videoContentsRef = React.useRef(
        new Map<object, ReturnType<typeof createSpaceVideoContent>>(),
    );
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
    const [photoLikeToggleID, setPhotoLikeToggleID] = React.useState(0);
    const [caption, setCaption] = React.useState(activePhoto.caption ?? "");
    const [captionEditValue, setCaptionEditValue] = React.useState(
        activePhoto.caption ?? "",
    );
    const [isCaptionEditing, setIsCaptionEditing] = React.useState(false);
    const [isCaptionDialogOpen, setIsCaptionDialogOpen] = React.useState(false);
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
    const CaptionTransition = isDesktopViewer
        ? Fade
        : SpaceBottomSheetTransition;
    const viewerRootRef = React.useRef<HTMLDivElement | null>(null);
    const viewerHeaderRef = React.useRef<HTMLDivElement>(null);
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
    const hasDraftPostPreparationError =
        isDraftPost && viewerPhotos.some((item) => item.preparationError);
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
        isCaptionDialogOpen ||
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

    const viewerPhotoRect = React.useCallback(
        (width: number, height: number): ViewerRect => {
            const viewport = viewerViewportSize();
            const { top, bottom } = viewerPadding(
                hasDraftPhotoControlsRef.current,
                headerHeight,
                viewerHeaderRef.current,
            );
            const areaHeight = viewport.y - top - bottom;
            const scale = Math.min(1, viewport.x / width, areaHeight / height);
            const w = width * scale;
            const h = height * scale;
            return {
                x: (viewport.x - w) / 2,
                y: top + (areaHeight - h) / 2,
                w,
                h,
            };
        },
        [headerHeight, viewerViewportSize],
    );

    const requestCloseRef = React.useRef<
        (throwVelocity?: { x: number; y: number }) => void
    >(() => undefined);
    requestCloseRef.current = (throwVelocity = { x: 0, y: 0 }) => {
        const motion = motionRef.current;
        if (motion.closing) return;
        const root = viewerRootRef.current;
        const pswp = pswpRef.current;
        const item =
            viewerPhotosRef.current[pswp?.currIndex ?? activePhotoIndex];
        const element = pswp?.currSlide?.content.element;
        let from: ViewerPhotoState | undefined = motion.flight?.current();
        let src = from ? motion.flight?.src : undefined;
        const rect = element?.getBoundingClientRect();
        if (
            !from &&
            !motion.flight &&
            rect &&
            rect.width > 0 &&
            rect.height > 0 &&
            element instanceof HTMLImageElement &&
            element.complete &&
            element.naturalWidth > 0
        ) {
            const scale = Number(pswp?.currSlide?.container.style.scale) || 1;
            from = shownPhotoState(
                { x: rect.left, y: rect.top, w: rect.width, h: rect.height },
                { x: 0, y: 0, w: window.innerWidth, h: window.innerHeight },
                viewerCornerRadii(element, scale),
            );
            src = element.currentSrc || element.src;
        }
        const origin =
            item && !isDraftPost && !item.video
                ? findViewerOrigin(viewerOriginKey(item.spaceId, item.postId))
                : null;
        const background = root?.style.getPropertyValue(
            "--space-viewer-bg-opacity",
        );
        const startBackground = background ? Number(background) : 1;
        motion.flight?.stop();
        motion.flight = undefined;
        motion.reveal?.();
        motion.reveal = undefined;
        if (root) {
            delete root.dataset.spaceViewerFlying;
            delete root.dataset.spaceViewerWaiting;
        }
        if (root && item && origin && from && src) {
            playViewerClose(
                root,
                {
                    origin,
                    src,
                    photo: {
                        width: item.width ?? defaultPhotoWidth,
                        height: item.height ?? defaultPhotoHeight,
                    },
                },
                from,
                throwVelocity,
                startBackground,
            );
        }
        motion.closing = true;
        onCloseRef.current();
    };

    React.useImperativeHandle(
        ref,
        () => ({ close: () => requestCloseRef.current() }),
        [],
    );

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
        setPhotoLikeToggleID((id) => id + 1);
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
        requestCloseRef.current();
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
            const exitReady = onDraftPostExitStart?.();
            dismissCaptionKeyboard(() => {
                void Promise.resolve(exitReady)
                    .catch((error: unknown) => {
                        log.error("Failed to open the home feed", error);
                    })
                    .then(() => {
                        setDraftPostExitPhase("animating");
                        onDraftPostExitAnimationStart?.();
                    });
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
        }
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
        setIsCaptionDialogOpen(false);
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
                        [key]: {
                            retryAt:
                                error instanceof SpaceMediaRateLimitError
                                    ? error.retryAt
                                    : undefined,
                        },
                    }));
                })
                .finally(() => {
                    photoLoadsRef.current.delete(key);
                });
        }
    }, [activePhotoIndex, onLoadPhoto, viewerPhotoKeys, photoLoadErrors]);

    React.useEffect(() => {
        if (photoRetryAt === undefined) return;
        setNow(Date.now());
        const timer = window.setTimeout(
            () => setNow(Date.now()),
            Math.max(0, photoRetryAt - Date.now()),
        );
        return () => window.clearTimeout(timer);
    }, [photoRetryAt]);

    React.useLayoutEffect(() => {
        const pswp = pswpRef.current;
        if (!pswp) return;

        isSyncingPhotosRef.current = true;
        if (pswp.currIndex != activePhotoIndex) pswp.goTo(activePhotoIndex);
        pswp.options.allowPanToNext = viewerPhotosRef.current.length > 1;
        const contentKeys = viewerPhotosRef.current.map(viewerPhotoContentKey);
        const previousKeys = displayedContentKeysRef.current;
        displayedContentKeysRef.current = contentKeys;
        contentKeys.forEach((key, index) => {
            if (key != previousKeys[index]) {
                pswp.refreshSlideContent(index);
            }
        });
        isSyncingPhotosRef.current = false;
    }, [activePhotoIndex, viewerPhotosContentKey]);

    React.useEffect(() => {
        pswpRef.current?.updateSize(true);
    }, [hasDraftPhotoControls]);

    React.useEffect(() => {
        if (!isSpaceIOS() || !canReplyToPost) return;
        const viewport = window.visualViewport;
        if (!viewport) return;

        const updateReplyViewport = () => {
            const rect =
                pswpRef.current?.currSlide?.content.element?.getBoundingClientRect();
            if (rect && rect.width > 0)
                motionRef.current.flight?.retarget({
                    x: rect.left,
                    y: rect.top,
                    w: rect.width,
                    h: rect.height,
                });
        };

        viewport.addEventListener("resize", updateReplyViewport);
        viewport.addEventListener("scroll", updateReplyViewport);
        return () => {
            viewport.removeEventListener("resize", updateReplyViewport);
            viewport.removeEventListener("scroll", updateReplyViewport);
        };
    }, [canReplyToPost]);

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

    React.useEffect(() => {
        if (!isDraftPostExitAnimating) return;
        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches)
            onClose();
    }, [onClose, isDraftPostExitAnimating]);

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

    React.useLayoutEffect(() => {
        const motion = motionRef.current;
        const root = viewerRootRef.current;
        const stopMotion = () => {
            motion.flight?.stop();
            motion.flight = undefined;
            motion.reveal?.();
            motion.reveal = undefined;
            if (root) {
                delete root.dataset.spaceViewerFlying;
                delete root.dataset.spaceViewerWaiting;
            }
        };
        const item = fallbackPhotoRef.current;
        if (!root || isDraftPost || item.video || !item.imageUrl)
            return stopMotion;
        const origin = findViewerOrigin(
            viewerOriginKey(item.spaceId, item.postId),
        );
        if (!origin) return stopMotion;

        const width = item.width ?? defaultPhotoWidth;
        const height = item.height ?? defaultPhotoHeight;
        const flight = playViewerOpen(
            root,
            { origin, src: item.imageUrl, photo: { width, height } },
            viewerPhotoRect(width, height),
            (t) => setViewerBackground(root, viewerBackgroundOpacity(t)),
            () => {
                motion.landed = true;
                root.dataset.spaceViewerWaiting = "true";
                handOverOpenFlight(motion, root, pswpRef.current);
            },
        );
        if (flight) {
            motion.flight = flight;
            motion.landed = false;
            motion.reveal = flight.reveal;
            root.dataset.spaceViewerFlying = "true";
        }
        return stopMotion;
    }, [isDraftPost, viewerPhotoRect]);

    React.useEffect(() => {
        const root = viewerRootRef.current;
        if (!root) return;

        let disposed = false;
        let closedByReact = false;
        let pswp: PhotoSwipe | undefined;
        const headerObserver = new ResizeObserver(() => pswp?.updateSize(true));
        if (document.documentElement.hasAttribute("data-space-ios-pwa"))
            headerObserver.observe(viewerHeaderRef.current!);
        let swipeStart:
            { x: number; y: number; photoIndex: number } | undefined;

        const loadPhotoSwipe = import("photoswipe");
        void loadPhotoSwipe.catch((error: unknown) => {
            log.error("Failed to load the photo viewer", error);
            endOpenFlight(motionRef.current, root);
        });
        void loadPhotoSwipe.then(({ default: PhotoSwipeClass }) => {
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
                errorMsg: "Unable to preview this item",
                escKey: false,
                getViewportSizeFn: viewerViewportSize,
                imageClickAction: "zoom",
                index: initialPhotoIndexRef.current,
                loop: false,
                mainClass: "pswp-space-viewer",
                paddingFn: () =>
                    viewerPadding(
                        hasDraftPhotoControlsRef.current,
                        headerHeight,
                        viewerHeaderRef.current,
                    ),
                pinchToClose: false,
                returnFocus: false,
                showHideAnimationType: "none",
                // A 16px gap between photos on a phone.
                spacing: 0.04,
                tapAction: false,
                trapFocus: false,
                wheelToZoom: true,
                zoom: false,
            });
            const videos = videoContentsRef.current;
            pswp.on("contentLoad", (event) => {
                if (event.content.data.type != "video") return;
                event.preventDefault();
                videos.get(event.content)?.destroy();
                const item = viewerPhotosRef.current[event.content.index]!;
                const video = createSpaceVideoContent(item, (asset) =>
                    videoLoaderRef.current!(asset),
                );
                event.content.element = video.element;
                event.content.onLoaded();
                videos.set(event.content, video);
            });
            pswp.on("contentActivate", ({ content }) =>
                videos.get(content)?.play(),
            );
            pswp.on("contentDeactivate", ({ content }) =>
                videos.get(content)?.deactivate(),
            );
            pswp.on("contentDestroy", ({ content }) => {
                videos.get(content)?.destroy();
                videos.delete(content);
            });
            const handOver = () => {
                queueMicrotask(() => {
                    if (!disposed)
                        handOverOpenFlight(motionRef.current, root, pswp);
                });
            };
            pswp.on("contentAppendImage", handOver);
            pswp.on("loadComplete", handOver);
            pswp.on("destroy", () => {
                videos.forEach((video) => video.destroy());
                videos.clear();
            });
            pswp.addFilter("isContentZoomable", (zoomable, content) =>
                content.data.type == "video" ? false : zoomable,
            );
            pswpRef.current = pswp;
            displayedContentKeysRef.current = viewerPhotosRef.current.map(
                viewerPhotoContentKey,
            );
            pswp.addFilter("numItems", () => viewerPhotosRef.current.length);
            pswp.addFilter("itemData", (_, index) => {
                const item =
                    viewerPhotosRef.current[index] ?? fallbackPhotoRef.current;
                if (item.video)
                    return {
                        type: "video",
                        width: item.width ?? defaultPhotoWidth,
                        height: item.height ?? defaultPhotoHeight,
                    };
                if (!item.imageUrl)
                    return {
                        html:
                            item.postPhotoCount == 0
                                ? '<div class="space-photo-placeholder" role="status">Add photos or videos to your post</div>'
                                : item.preparationError
                                  ? '<div class="space-photo-placeholder"></div>'
                                  : '<div class="space-photo-placeholder" role="status" aria-label="Preparing preview" aria-busy="true"></div>',
                        width: item.width ?? defaultPhotoWidth,
                        height:
                            item.height ??
                            defaultPhotoWidth * (isDraftPost ? 16 / 9 : 4 / 3),
                    };
                return {
                    alt: item.alt ?? `${item.name} post`,
                    height: item.height ?? defaultPhotoHeight,
                    src: item.imageUrl,
                    width: item.width ?? defaultPhotoWidth,
                };
            });
            pswp.on("close", () => {
                if (!closedByReact)
                    requestCloseRef.current(pswp!.gestures.velocity);
            });
            pswp.on("verticalDrag", (event) => {
                if (isDismissBlockedRef.current) event.preventDefault();
            });
            const reduceMotion = window.matchMedia(
                "(prefers-reduced-motion: reduce)",
            ).matches;
            // The drag pose and the parallax use the separate `scale` and
            // `translate` properties, which leave PhotoSwipe's transform alone.
            let posed:
                | {
                      container: HTMLElement;
                      element?: HTMLElement;
                      radii: ViewerCornerRadii;
                  }
                | undefined;
            const clearDismissPose = () => {
                if (!posed) return;
                posed.container.style.scale = "";
                posed.container.style.translate = "";
                if (posed.element) posed.element.style.borderRadius = "";
                posed = undefined;
            };
            const applyDismissPose = () => {
                const slide = pswp!.currSlide;
                if (!slide || reduceMotion) return;
                if (posed?.container != slide.container) clearDismissPose();
                const isAtFit =
                    slide.currZoomLevel <= slide.zoomLevels.fit + 0.001;
                const dy = isAtFit ? slide.pan.y - slide.bounds.center.y : 0;
                const element = slide.content.element;
                if (Math.abs(dy) < 0.5) {
                    clearDismissPose();
                    return;
                }
                if (!posed) {
                    const item = viewerPhotosRef.current[pswp!.currIndex];
                    const origin = findViewerOrigin(
                        viewerOriginKey(item?.spaceId, item?.postId),
                    );
                    posed = {
                        container: slide.container,
                        element,
                        radii: origin
                            ? viewerCornerRadii(origin)
                            : [24, 24, 24, 24],
                    };
                }
                const scale =
                    1 -
                    0.32 *
                        Math.min(
                            1,
                            Math.abs(dy) / (pswp!.viewportSize.y * 0.55),
                        );
                const { x, y } = pswp!.gestures.startP1;
                slide.container.style.scale = String(scale);
                slide.container.style.translate = `${x * (1 - scale)}px ${y * (1 - scale)}px`;
                if (element)
                    element.style.borderRadius = posed.radii
                        .map(
                            (radius) =>
                                `${(radius * Math.min(1, Math.abs(dy) / 140)) / scale}px`,
                        )
                        .join(" ");
            };
            pswp.on("zoomPanUpdate", () => {
                applyDismissPose();
                if (motionRef.current.flight || motionRef.current.closing)
                    return;
                root.style.setProperty(
                    "--space-viewer-bg-opacity",
                    String(pswp!.bgOpacity),
                );
            });
            pswp.on("moveMainScroll", () => {
                if (reduceMotion) return;
                const { currIndex, mainScroll, potentialIndex, viewportSize } =
                    pswp!;
                const drift =
                    (mainScroll.x - mainScroll.getCurrSlideX()) /
                    mainScroll.slideWidth;
                for (const { slide } of mainScroll.itemHolders) {
                    if (!slide) continue;
                    const offset = slide.index - potentialIndex + drift;
                    const isAtRest =
                        slide.currZoomLevel <= slide.zoomLevels.initial + 0.001;
                    slide.container.style.translate =
                        isAtRest && Math.abs(offset) > 0.001
                            ? `${-offset * viewportSize.x * 0.4}px 0`
                            : "";
                }
                paintViewerPhotoDot(
                    root,
                    viewerPhotosRef.current,
                    currIndex,
                    potentialIndex - drift,
                );
            });
            pswp.on("change", () => {
                clearDismissPose();
                const nextIndex = pswp?.currIndex;
                if (nextIndex != undefined) {
                    setLocalPhotoIndex(nextIndex);
                    if (!isSyncingPhotosRef.current)
                        onPhotoIndexChangeRef.current?.(nextIndex);
                }
            });
            pswp.on("keydown", (event) => {
                if (
                    isSwipeBlockedRef.current ||
                    motionRef.current.flight ||
                    motionRef.current.closing ||
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
                if (swipeStart) {
                    swipeStart = undefined;
                    return;
                }
                if (
                    !closeOnSwipePastEndRef.current ||
                    isDismissBlockedRef.current ||
                    viewerSwipeStartsOnInteractiveTarget(
                        event.originalEvent.target,
                    ) ||
                    pswp!.currSlide?.isPannable()
                )
                    return;
                const point = viewerTouchPoint(event.originalEvent);
                if (point)
                    swipeStart = { ...point, photoIndex: pswp!.currIndex };
            });
            pswp.on("pointerUp", ({ originalEvent }) => {
                const start = swipeStart;
                swipeStart = undefined;
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
                if (
                    closeOnSwipePastEndRef.current &&
                    Math.abs(dx) > 72 &&
                    Math.abs(dx) > Math.abs(dy) * 1.5 &&
                    ((dx < 0 &&
                        start.photoIndex ==
                            viewerPhotosRef.current.length - 1) ||
                        (dx > 0 && start.photoIndex == 0))
                ) {
                    requestCloseRef.current();
                }
            });
            pswp.init();
            const shown =
                pswp.currSlide?.content.element?.getBoundingClientRect();
            if (shown && shown.width > 0)
                motionRef.current.flight?.retarget({
                    x: shown.left,
                    y: shown.top,
                    w: shown.width,
                    h: shown.height,
                });
            handOverOpenFlight(motionRef.current, root, pswp);
        });

        return () => {
            disposed = true;
            headerObserver.disconnect();
            closedByReact = true;
            pswpRef.current = undefined;
            pswp?.destroy();
            root.style.removeProperty("--space-viewer-bg-opacity");
        };
    }, [headerHeight, isDraftPost, viewerViewportSize]);

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
                isCaptionDialogOpen ||
                isDraftPostExit ||
                isDraftPostActionRunning
            )
                return;
            if (event.key != "Escape") return;

            if (isCaptionEditing && !isCaptionUpdateActionRunning) {
                cancelCaptionEdit();
                return;
            }
            requestCloseRef.current();
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
        isCaptionDialogOpen,
        isCaptionUpdateActionRunning,
    ]);

    return (
        <Box
            ref={viewerRootRef}
            role="dialog"
            aria-label={`${displayName} post viewer`}
            aria-modal="true"
            onTransitionEnd={(event) => {
                if (
                    !isDraftPostExitAnimating ||
                    event.currentTarget != event.target ||
                    event.propertyName != "opacity"
                )
                    return;

                onClose();
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
                "& > .pswp, & > header, & > [data-space-viewer-chrome='true']":
                    {
                        translate:
                            isSpaceIOS() && canReplyToPost
                                ? "0 calc(-1 * var(--space-keyboard-inset, 0px))"
                                : undefined,
                    },
                "& .space-photo-placeholder": {
                    alignItems: "center",
                    color: spaceTextMuted,
                    display: "flex",
                    height: "100%",
                    width: isDraftPost ? "100vw" : "100%",
                    ml: isDraftPost ? "calc((100% - 100vw) / 2)" : 0,
                    justifyContent: "center",
                    fontSize: 14,
                },
                "& [data-space-viewer-chrome='true'], & [data-space-viewer-bottom='true']":
                    {
                        opacity:
                            "calc((var(--space-viewer-bg-opacity, 1) - 0.5) * 2)",
                    },
                // PhotoSwipe sets an inline opacity, so hide it with visibility.
                "&[data-space-viewer-flying='true'] .pswp": {
                    visibility: "hidden !important",
                },
                "&[data-space-viewer-flying='true'] :is([data-space-viewer-chrome='true'], [data-space-viewer-bottom='true'], [data-space-viewer-chrome='true'] *, [data-space-viewer-bottom='true'] *)":
                    { pointerEvents: "none !important" },
                "@media (prefers-reduced-motion: reduce)": {
                    transition: "none",
                },
            }}
        >
            {isSpaceIOS() && isReplyFocused && (
                <Portal
                    container={() =>
                        viewerRootRef.current?.parentElement ?? null
                    }
                >
                    <SpaceViewerPostBackdrop />
                </Portal>
            )}
            {!isDraftPost && (
                <Box
                    component="span"
                    role="status"
                    aria-live="polite"
                    aria-atomic="true"
                    sx={visuallyHidden}
                >
                    {postPhotoCount > 1
                        ? `Item ${postPhotoIndex + 1} of ${postPhotoCount}`
                        : null}
                </Box>
            )}
            <Box
                ref={viewerHeaderRef}
                component="header"
                sx={{
                    alignItems: "center",
                    display: "grid",
                    flexShrink: 0,
                    gap: "12px",
                    gridTemplateColumns: "minmax(0, 1fr) auto",
                    minHeight: `calc(${headerHeight}px + var(--space-ios-safe-area-top, 0px))`,
                    pt: "var(--space-ios-safe-area-top, 0px)",
                    position: "relative",
                    pl: "max(16px, var(--space-ios-safe-area-left, 0px))",
                    pr: "max(4px, var(--space-ios-safe-area-right, 0px))",
                    width: "100%",
                    zIndex: 2,
                }}
            >
                <Box
                    data-space-viewer-chrome="true"
                    sx={{
                        alignItems: "center",
                        display: "flex",
                        gap: "12px",
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
                        gap: canManagePost && !isCaptionEditing ? 0 : "8px",
                        justifySelf: "flex-end",
                    }}
                >
                    {canManagePost && !isCaptionEditing && (
                        <Box
                            component="button"
                            id={actionsButtonID}
                            data-space-viewer-chrome="true"
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
                            sx={{ ...draftHeaderButtonSx, color: "#C0C0C0" }}
                        >
                            <HugeiconsIcon
                                icon={MoreHorizontalIcon}
                                size={20}
                                strokeWidth={1.8}
                            />
                        </Box>
                    )}
                    {isDraftPost && onAddDraftPhoto && (
                        <Box
                            component="button"
                            type="button"
                            aria-label="Add photos or videos"
                            data-space-viewer-chrome="true"
                            title="Add photos or videos"
                            disabled={isDraftPostActionRunning}
                            onClick={onAddDraftPhoto}
                            sx={draftHeaderButtonSx}
                        >
                            <Box
                                component="span"
                                sx={draftHeaderButtonContentSx}
                            >
                                <HugeiconsIcon
                                    icon={Add01Icon}
                                    size={20}
                                    strokeWidth={1.8}
                                />
                                Add
                            </Box>
                        </Box>
                    )}
                    {isDraftPost && onEditDraftPhoto && (
                        <Box
                            component="button"
                            type="button"
                            aria-label="Edit item"
                            data-space-viewer-chrome="true"
                            title="Edit item"
                            disabled={
                                isDraftPostActionRunning ||
                                isDraftPostPreviewPending ||
                                Boolean(draftPostPreparationError)
                            }
                            onClick={() => {
                                videoContentsRef.current.forEach((video) =>
                                    video.deactivate(),
                                );
                                onEditDraftPhoto();
                            }}
                            sx={[
                                draftHeaderButtonSx,
                                { "&:disabled": { opacity: 1 } },
                            ]}
                        >
                            <Box
                                component="span"
                                sx={draftHeaderButtonContentSx}
                            >
                                <HugeiconsIcon
                                    icon={Edit03Icon}
                                    size={16}
                                    strokeWidth={1.8}
                                />
                                Edit
                            </Box>
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
                        data-space-viewer-close
                        disabled={isDraftPostActionRunning}
                        onClick={closeViewer}
                        sx={{ ...draftHeaderButtonSx, color: "#C0C0C0" }}
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
                                    bgcolor: spaceMenuBackground,
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
                                direction < 0 ? "Previous item" : "Next item"
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
                        disabled={isPhotoRateLimited}
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
                            textWrap: "balance",
                            "&:disabled": { cursor: "default" },
                        }}
                    >
                        {isPhotoRateLimited
                            ? "Couldn't load photo. Please try again later."
                            : "Couldn't load photo. Retry"}
                    </Box>
                </Box>
            )}
            {isDraftPost && draftPostPreparationError && (
                <Box
                    sx={{
                        position: "absolute",
                        top: "50%",
                        left: "50%",
                        transform: "translate(-50%, -50%)",
                        width: "calc(100% - 48px)",
                        maxWidth: 300,
                        zIndex: 2,
                        textAlign: "center",
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 14,
                        lineHeight: "20px",
                        color: textBase,
                    }}
                >
                    {activePhoto.isVideo ? (
                        <SpaceVideoError message={draftPostPreparationError} />
                    ) : (
                        <Box role="alert" sx={{ textWrap: "balance" }}>
                            {draftPostPreparationError}
                        </Box>
                    )}
                </Box>
            )}
            <Box
                aria-hidden
                data-space-viewer-chrome="true"
                sx={{
                    background:
                        "linear-gradient(180deg, rgba(0, 0, 0, 0.32) 0%, rgba(0, 0, 0, 0.13) 58%, rgba(0, 0, 0, 0) 100%)",
                    height: "calc(44px + var(--space-ios-safe-area-top, 0px))",
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
                                borderRadius: "16px",
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
                                hasDraftPostPreparationError
                                    ? "Item could not be prepared"
                                    : "Post"
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
                                borderRadius: "16px",
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
            {!isDraftPost &&
                (hasDisplayCaption ||
                    showPhotoLikeButton ||
                    postPhotoCount > 1) &&
                !isCaptionEditing && (
                    <Box
                        data-space-viewer-bottom="true"
                        sx={{
                            alignItems: "stretch",
                            bottom: isSpaceIOS()
                                ? "max(24px, calc(env(safe-area-inset-bottom) + 16px), calc(var(--space-keyboard-inset, 0px) + 16px))"
                                : "max(24px, calc(env(safe-area-inset-bottom) + 16px))",
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
                        {(hasDisplayCaption || postPhotoCount > 1) && (
                            <SpaceViewerPhotoOverlay
                                key={activePostKey}
                                caption={displayCaption}
                                onOpenCaption={() =>
                                    setIsCaptionDialogOpen(true)
                                }
                                photoIndex={postPhotoIndex}
                                photoCount={postPhotoCount}
                            />
                        )}
                        {showPhotoLikeButton && (
                            <SpacePostReplyControls
                                canSendReply={canSendReply}
                                isReplyMode={isReplyMode}
                                liked={isPhotoLiked}
                                likePopID={photoLikePopID}
                                likeToggleID={photoLikeToggleID}
                                postKey={activePostKey}
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
            <Modal
                open={isCaptionDialogOpen}
                onClose={() => setIsCaptionDialogOpen(false)}
                closeAfterTransition
                disableAutoFocus
                sx={{
                    alignItems: "center",
                    boxSizing: "border-box",
                    display: "flex",
                    flexDirection: "column",
                    overflowY: "auto",
                    overscrollBehaviorY: "contain",
                    pt: "max(24px, env(safe-area-inset-top))",
                    zIndex: 1500,
                    "@media (min-width: 600px)": { p: "24px" },
                }}
                slotProps={{
                    backdrop: { sx: { bgcolor: "rgba(0, 0, 0, 0.64)" } },
                }}
            >
                <CaptionTransition
                    in={isCaptionDialogOpen}
                    onEntered={(node) => node.focus({ preventScroll: true })}
                >
                    <Box
                        role="dialog"
                        aria-label="Full caption"
                        aria-modal="true"
                        tabIndex={-1}
                        sx={{
                            bgcolor: viewerBackground,
                            border: "1px solid rgba(255, 255, 255, 0.1)",
                            borderBottom: 0,
                            borderRadius: "24px 24px 0 0",
                            boxShadow: "0 16px 48px rgba(0, 0, 0, 0.28)",
                            boxSizing: "border-box",
                            flexShrink: 0,
                            mt: "auto",
                            outline: "none",
                            p: "24px 24px max(24px, env(safe-area-inset-bottom))",
                            width: "100%",
                            "@media (min-width: 600px)": {
                                borderBottom:
                                    "1px solid rgba(255, 255, 255, 0.1)",
                                borderRadius: "18px",
                                maxWidth: 480,
                                mb: "auto",
                                p: "24px",
                            },
                        }}
                    >
                        <Box
                            sx={{
                                ...viewerCaptionTextSx,
                                color: "#D0D0D0",
                                overflowWrap: "anywhere",
                                textAlign: "left",
                                textWrap: "wrap",
                            }}
                        >
                            {displayCaption}
                        </Box>
                    </Box>
                </CaptionTransition>
            </Modal>
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
