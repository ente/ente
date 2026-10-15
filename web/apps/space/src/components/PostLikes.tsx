import { FavouriteIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, Dialog, Skeleton, useMediaQuery } from "@mui/material";
import { SpaceActivityAvatar } from "components/ActivityList";
import { SpaceBottomSheetTransition } from "components/BottomSheetTransition";
import type { FriendProfile } from "data/friends";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import {
    loadCurrentFriendAvatarURL,
    loadCurrentPostLikes,
} from "services/space";
import { spaceActivityRowSx } from "styles/activity-list";
import {
    spaceDialogBackground,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import { spaceTouchTargetSize } from "styles/touch-targets";

const LikeRow = ({
    actor,
    spaceId,
}: {
    actor: FriendProfile;
    spaceId: string;
}) => {
    const [avatarURL, setAvatarURL] = React.useState(actor.avatarUrl);
    const hasAvatar = Boolean(actor.avatarObjectID && actor.avatarKeyVersion);
    React.useEffect(() => {
        if (actor.avatarUrl || !hasAvatar) return;
        let cancelled = false;
        void loadCurrentFriendAvatarURL(actor, spaceId)
            .catch((error: unknown) => {
                log.warn("Failed to load post like avatar", error);
                return null;
            })
            .then((url) => {
                if (!cancelled) setAvatarURL(url);
            });
        return () => {
            cancelled = true;
        };
    }, [actor, hasAvatar, spaceId]);

    return (
        <Box
            component="li"
            sx={{
                ...spaceActivityRowSx,
                gridTemplateColumns: "32px minmax(0, 1fr) 20px",
                minHeight: 56,
                mx: 0,
                px: 0,
                width: "100%",
                "&:hover, &:active": { bgcolor: "transparent" },
            }}
        >
            <SpaceActivityAvatar
                avatarUrl={actor.avatarUrl || avatarURL}
                loading={
                    hasAvatar && !actor.avatarUrl && avatarURL === undefined
                }
                size={32}
            />
            <Box
                sx={{
                    minWidth: 0,
                    fontSize: 14,
                    fontWeight: 700,
                    lineHeight: "20px",
                    overflowWrap: "anywhere",
                }}
            >
                {actor.fullName.trim() || actor.username}
            </Box>
            <HugeiconsIcon
                aria-hidden
                icon={FavouriteIcon}
                size={20}
                color="#08C225"
                fill="currentColor"
                strokeWidth={1.8}
            />
        </Box>
    );
};

export const SpacePostLikes = ({
    likeCount,
    spaceId,
    postId,
    open,
    onOpen,
    onClose,
}: {
    likeCount?: number;
    spaceId: string;
    postId: number;
    open: boolean;
    onOpen: () => void;
    onClose: () => void;
}) => {
    const isBottomSheet = useMediaQuery("(max-width: 599px)");
    const prefersReducedMotion = useMediaQuery(
        "(prefers-reduced-motion: reduce)",
    );
    const dragStartY = React.useRef<number | undefined>(undefined);
    const wasDragged = React.useRef(false);
    const [isDragging, setIsDragging] = React.useState(false);
    const [dragOffset, setDragOffset] = React.useState(0);
    const postKey = `${spaceId}:${postId}`;
    const [postLikes, setPostLikes] = React.useState<
        Record<string, FriendProfile[]>
    >({});
    const actors = postLikes[postKey];
    const displayedLikeCount = actors?.length ?? likeCount;
    const [error, setError] = React.useState(false);
    const [retry, setRetry] = React.useState(0);
    useBrowserBackClose({ open, onClose, stateKey: "space-post-likes" });

    React.useEffect(() => {
        if (!open) return;
        let cancelled = false;
        setError(false);
        void loadCurrentPostLikes(spaceId, postId)
            .then((items) => {
                if (!cancelled)
                    setPostLikes((current) => ({
                        ...current,
                        [postKey]: items,
                    }));
            })
            .catch((error: unknown) => {
                log.error("Failed to load post likes", error);
                if (!cancelled) setError(true);
            });
        return () => {
            cancelled = true;
        };
    }, [spaceId, postId, postKey, open, retry]);

    return (
        <>
            <Box
                component="button"
                type="button"
                aria-label={
                    displayedLikeCount !== undefined
                        ? `View ${displayedLikeCount} ${displayedLikeCount == 1 ? "like" : "likes"}`
                        : "View likes"
                }
                aria-haspopup="dialog"
                aria-expanded={open}
                onClick={onOpen}
                sx={{
                    alignItems: "center",
                    alignSelf: "flex-end",
                    bgcolor: "transparent",
                    border: 0,
                    borderRadius: "24px",
                    color: spaceTextMuted,
                    cursor: "pointer",
                    display: "flex",
                    gap: "8px",
                    minHeight: spaceTouchTargetSize,
                    minWidth: 64,
                    px: "14px",
                    transform: "translate(8px, 8px)",
                    fontFamily: '"Inter Variable", Inter, sans-serif',
                    fontSize: 14,
                    fontWeight: 600,
                    "&:focus-visible": {
                        outline: "2px solid #08C225",
                        outlineOffset: 2,
                    },
                }}
            >
                <HugeiconsIcon
                    icon={FavouriteIcon}
                    size={20}
                    strokeWidth={1.8}
                />
                <Box
                    component="span"
                    sx={{
                        flexShrink: 0,
                        fontVariantNumeric: "tabular-nums",
                        height: "20px",
                        lineHeight: "20px",
                        textAlign: "left",
                        whiteSpace: "nowrap",
                        width: "1ch",
                    }}
                >
                    {displayedLikeCount ?? ""}
                </Box>
            </Box>
            <Dialog
                open={open}
                onClose={onClose}
                maxWidth={false}
                slots={
                    isBottomSheet && !prefersReducedMotion
                        ? { transition: SpaceBottomSheetTransition }
                        : undefined
                }
                transitionDuration={prefersReducedMotion ? 0 : undefined}
                sx={{
                    zIndex: 1500,
                    "--space-dialog-backdrop": "rgba(0 0 0 / 0.64)",
                }}
                slotProps={{
                    paper: {
                        "aria-label": "Likes",
                        "aria-labelledby": undefined,
                        style: {
                            translate: `0 ${dragOffset}px`,
                            transition:
                                isDragging || prefersReducedMotion
                                    ? "none"
                                    : "translate 160ms ease-out",
                        },
                        sx: {
                            bgcolor: spaceDialogBackground,
                            borderRadius: "28px 28px 0 0",
                            bottom: 0,
                            boxShadow: "none",
                            boxSizing: "border-box",
                            color: spaceText,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            left: 0,
                            m: 0,
                            maxHeight: "min(560px, calc(100dvh - 64px))",
                            maxWidth: "none",
                            overflow: "hidden",
                            position: "fixed",
                            width: "100vw",
                            pb: "calc(20px + env(safe-area-inset-bottom))",
                            "@media (min-width: 600px)": {
                                borderRadius: "20px",
                                bottom: "auto",
                                left: "50%",
                                top: "50%",
                                transform: "translate(-50%, -50%)",
                                width: 420,
                                py: "20px",
                            },
                        },
                    },
                    transition: { onExited: () => setDragOffset(0) },
                }}
            >
                {isBottomSheet && (
                    <Box
                        component="button"
                        type="button"
                        aria-label="Dismiss likes"
                        onClick={(
                            event: React.MouseEvent<HTMLButtonElement>,
                        ) => {
                            if (event.detail == 0 || !wasDragged.current)
                                onClose();
                            wasDragged.current = false;
                        }}
                        onPointerDown={(
                            event: React.PointerEvent<HTMLButtonElement>,
                        ) => {
                            if (event.button != 0) return;
                            dragStartY.current = event.clientY;
                            wasDragged.current = false;
                            setIsDragging(true);
                            event.currentTarget.setPointerCapture(
                                event.pointerId,
                            );
                        }}
                        onPointerMove={(
                            event: React.PointerEvent<HTMLButtonElement>,
                        ) => {
                            if (dragStartY.current == undefined) return;
                            const distance = event.clientY - dragStartY.current;
                            if (Math.abs(distance) > 4)
                                wasDragged.current = true;
                            setDragOffset(Math.max(0, distance));
                        }}
                        onPointerUp={(
                            event: React.PointerEvent<HTMLButtonElement>,
                        ) => {
                            if (dragStartY.current == undefined) return;
                            const distance = event.clientY - dragStartY.current;
                            dragStartY.current = undefined;
                            setIsDragging(false);
                            if (distance > 80) onClose();
                            else setDragOffset(0);
                        }}
                        onPointerCancel={() => {
                            dragStartY.current = undefined;
                            wasDragged.current = true;
                            setIsDragging(false);
                            setDragOffset(0);
                        }}
                        sx={{
                            alignItems: "center",
                            appearance: "none",
                            bgcolor: "transparent",
                            border: 0,
                            cursor: isDragging ? "grabbing" : "grab",
                            display: "flex",
                            flexShrink: 0,
                            height: spaceTouchTargetSize,
                            justifyContent: "center",
                            p: 0,
                            touchAction: "none",
                            width: "100%",
                            "&:focus-visible": {
                                outline: `2px solid ${spaceTextMuted}`,
                                outlineOffset: -2,
                            },
                        }}
                    >
                        <Box
                            component="span"
                            sx={{
                                bgcolor: "#686868",
                                borderRadius: "999px",
                                height: 4,
                                width: 32,
                            }}
                        />
                    </Box>
                )}
                <Box
                    sx={{
                        height: "min(224px, 40dvh)",
                        overflowY: "auto",
                        overscrollBehaviorY: "contain",
                        px: "20px",
                        minHeight: 0,
                        WebkitOverflowScrolling: "touch",
                    }}
                >
                    {error ? (
                        <Box
                            role="alert"
                            sx={{
                                color: spaceTextMuted,
                                py: "28px",
                                textAlign: "center",
                                fontSize: 14,
                            }}
                        >
                            Couldn&apos;t load likes.
                            <Box
                                component="button"
                                type="button"
                                onClick={() => setRetry((value) => value + 1)}
                                sx={{
                                    bgcolor: "transparent",
                                    border: 0,
                                    color: spaceText,
                                    cursor: "pointer",
                                    display: "block",
                                    font: "inherit",
                                    fontWeight: 600,
                                    mx: "auto",
                                    mt: "8px",
                                    minHeight: spaceTouchTargetSize,
                                    p: "10px",
                                }}
                            >
                                Try again
                            </Box>
                        </Box>
                    ) : !actors ? (
                        <Box role="status" aria-label="Loading likes">
                            {[0, 1, 2].map((index) => (
                                <Box
                                    key={index}
                                    sx={{
                                        alignItems: "center",
                                        display: "flex",
                                        gap: "12px",
                                        minHeight: 56,
                                        py: "8px",
                                    }}
                                >
                                    <Skeleton
                                        variant="circular"
                                        width={32}
                                        height={32}
                                    />
                                    <Skeleton width={120} height={24} />
                                </Box>
                            ))}
                        </Box>
                    ) : actors.length == 0 ? (
                        <Box
                            sx={{
                                alignItems: "center",
                                color: spaceTextMuted,
                                display: "flex",
                                height: "100%",
                                justifyContent: "center",
                                textAlign: "center",
                                fontSize: 14,
                            }}
                        >
                            No likes yet
                        </Box>
                    ) : (
                        <Box
                            component="ul"
                            sx={{ listStyle: "none", m: 0, p: 0 }}
                        >
                            {actors.map((actor) => (
                                <LikeRow
                                    key={actor.id}
                                    actor={actor}
                                    spaceId={spaceId}
                                />
                            ))}
                        </Box>
                    )}
                </Box>
            </Dialog>
        </>
    );
};
