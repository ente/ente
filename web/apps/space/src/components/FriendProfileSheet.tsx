import { Box, useMediaQuery } from "@mui/material";
import FocusTrap from "@mui/material/Unstable_TrapFocus";
import { AuthenticatedFriendProfile } from "components/AuthenticatedFriendProfile";
import type { FriendProfile } from "data/friends";
import React from "react";
import { spaceAppBackgroundColor } from "styles/colors";
import {
    friendSheetSnap,
    stepFriendSheetSpring,
} from "utils/friend-profile-sheet";

interface FriendProfileSheetProps {
    expanded: boolean;
    friend: FriendProfile;
    onClose: () => void;
    onExpand: () => void;
}

type SheetSnap = "collapsed" | "expanded" | "closed";
const handleHeight = 28;

export const FriendProfileSheet: React.FC<FriendProfileSheetProps> = ({
    expanded,
    friend,
    onClose,
    onExpand,
}) => {
    const reducedMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
    const rootRef = React.useRef<HTMLDivElement>(null);
    const panelRef = React.useRef<HTMLDivElement>(null);
    const contentRef = React.useRef<HTMLDivElement>(null);
    const headerRef = React.useRef<HTMLDivElement>(null);
    const handleRef = React.useRef<HTMLButtonElement>(null);
    const backdropRef = React.useRef<HTMLDivElement>(null);
    const geometry = React.useRef({ collapsed: 0, height: 0 });
    const motion = React.useRef({ position: 0, velocity: 0, frame: 0 });
    const destination = React.useRef<SheetSnap>(
        expanded ? "expanded" : "collapsed",
    );
    const callbacks = React.useRef({ onClose, onExpand });
    callbacks.current = { onClose, onExpand };
    const gesture = React.useRef<{
        pointerId: number;
        startY: number;
        startPosition: number;
        lastY: number;
        lastTime: number;
        velocity: number;
        moved: boolean;
    } | null>(null);
    const suppressClick = React.useRef(false);

    const paint = React.useCallback((position: number) => {
        const { collapsed, height } = geometry.current;
        const preview = collapsed > 0 ? Math.min(1, position / collapsed) : 0;
        const backdrop =
            position > collapsed
                ? (0.64 * (height - position)) / (height - collapsed)
                : 1 - 0.36 * preview;
        motion.current.position = position;
        panelRef.current!.style.transform = `translate3d(0, ${position}px, 0)`;
        panelRef.current!.style.borderRadius = `${28 * preview}px ${28 * preview}px 0 0`;
        panelRef.current!.style.setProperty(
            "--space-friend-profile-reveal",
            String(1 - preview),
        );
        panelRef.current!.style.setProperty(
            "--space-friend-profile-top",
            `${position}px`,
        );
        handleRef.current!.style.opacity = String(preview);
        backdropRef.current!.style.opacity = String(Math.max(0, backdrop));
    }, []);

    const animate = React.useCallback(
        (snap: SheetSnap, complete?: () => void) => {
            destination.current = snap;
            cancelAnimationFrame(motion.current.frame);
            let previousTime = performance.now();
            const frame = (time: number) => {
                const { collapsed, height } = geometry.current;
                const target =
                    snap == "expanded"
                        ? 0
                        : snap == "closed"
                          ? height
                          : collapsed;
                const next = stepFriendSheetSpring(
                    motion.current.position,
                    motion.current.velocity,
                    target,
                    time - previousTime,
                );
                previousTime = time;
                if (
                    reducedMotion ||
                    (Math.abs(next.position - target) < 0.5 &&
                        Math.abs(next.velocity) < 5)
                ) {
                    motion.current.velocity = 0;
                    motion.current.frame = 0;
                    paint(target);
                    complete?.();
                    return;
                }
                motion.current.velocity = next.velocity;
                paint(Math.max(0, Math.min(height, next.position)));
                motion.current.frame = requestAnimationFrame(frame);
            };
            motion.current.frame = requestAnimationFrame(frame);
        },
        [paint, reducedMotion],
    );

    React.useLayoutEffect(() => {
        if (expanded) {
            panelRef.current!.style.removeProperty("transform");
            panelRef.current!.style.removeProperty("border-radius");
            window.scrollTo(0, 0);
            return;
        }
        const animation = motion.current;
        const overflow = document.body.style.overflow;
        document.body.style.overflow = "hidden";
        const measure = () => {
            const header = headerRef.current;
            if (!header) return;
            const height = rootRef.current!.clientHeight;
            const headerBottom =
                header.getBoundingClientRect().bottom -
                contentRef.current!.getBoundingClientRect().top -
                parseFloat(
                    getComputedStyle(header.previousElementSibling!).paddingTop,
                );
            const bottomPadding = parseFloat(
                getComputedStyle(contentRef.current!).paddingBottom,
            );
            const collapsed = Math.max(
                handleHeight,
                height - headerBottom - bottomPadding,
            );
            const initial = geometry.current.height == 0;
            geometry.current = { collapsed, height };
            if (initial) {
                paint(height);
            }
            if (!gesture.current && !motion.current.frame) {
                animate(destination.current);
            }
        };
        const observer = new ResizeObserver(measure);
        observer.observe(rootRef.current!);
        observer.observe(contentRef.current!);
        return () => {
            observer.disconnect();
            cancelAnimationFrame(animation.frame);
            animation.frame = 0;
            document.body.style.overflow = overflow;
        };
    }, [animate, expanded, paint]);

    const dismiss = () => {
        panelRef.current!.scrollTop = 0;
        animate("closed", () => callbacks.current.onClose());
    };
    const expand = () =>
        animate("expanded", () => callbacks.current.onExpand());

    const finishDrag = (event: React.PointerEvent<HTMLDivElement>) => {
        const current = gesture.current;
        if (event.pointerId != current?.pointerId) return;
        gesture.current = null;
        if (!current.moved) {
            animate("collapsed");
            return;
        }
        suppressClick.current = true;
        motion.current.velocity =
            event.timeStamp - current.lastTime < 100 ? current.velocity : 0;
        const { collapsed, height } = geometry.current;
        const snap = friendSheetSnap(
            motion.current.position,
            motion.current.velocity,
            collapsed,
            height,
        );
        animate(
            snap,
            snap == "expanded"
                ? () => callbacks.current.onExpand()
                : snap == "closed"
                  ? () => callbacks.current.onClose()
                  : undefined,
        );
    };

    return (
        <Box
            ref={rootRef}
            sx={{
                "--space-profile-post-loading-top": "50%",
                ...(expanded
                    ? { position: "relative" }
                    : { inset: 0, position: "fixed", zIndex: 1300 }),
            }}
        >
            <Box
                ref={backdropRef}
                aria-hidden
                onClick={expanded ? undefined : dismiss}
                sx={{
                    bgcolor: spaceAppBackgroundColor,
                    display: expanded ? "none" : "block",
                    inset: 0,
                    opacity: expanded ? 1 : 0,
                    position: "absolute",
                }}
            />
            <FocusTrap open={!expanded} disableEnforceFocus>
                <Box
                    ref={panelRef}
                    role={expanded ? undefined : "dialog"}
                    aria-modal={expanded ? undefined : true}
                    aria-label={`${friend.fullName.trim() || friend.username}'s profile`}
                    tabIndex={-1}
                    onKeyDown={(event) => {
                        if (
                            event.key == "Escape" &&
                            !event.defaultPrevented &&
                            (event.target as HTMLElement).closest(
                                '[role="dialog"]',
                            ) == event.currentTarget
                        ) {
                            event.stopPropagation();
                            dismiss();
                        }
                    }}
                    onPointerDown={(event) => {
                        if (
                            expanded ||
                            !event.isPrimary ||
                            event.button != 0 ||
                            !event.currentTarget.contains(event.target as Node)
                        )
                            return;
                        (event.target as Element).setPointerCapture(
                            event.pointerId,
                        );
                        cancelAnimationFrame(motion.current.frame);
                        motion.current.frame = 0;
                        motion.current.velocity = 0;
                        suppressClick.current = false;
                        gesture.current = {
                            pointerId: event.pointerId,
                            startY: event.clientY,
                            startPosition: motion.current.position,
                            lastY: event.clientY,
                            lastTime: event.timeStamp,
                            velocity: 0,
                            moved: false,
                        };
                    }}
                    onPointerMove={(event) => {
                        const current = gesture.current;
                        if (event.pointerId != current?.pointerId) return;
                        const distance = event.clientY - current.startY;
                        if (!current.moved && Math.abs(distance) < 6) return;
                        if (!current.moved)
                            event.currentTarget.setPointerCapture(
                                event.pointerId,
                            );
                        current.moved = true;
                        const elapsed = event.timeStamp - current.lastTime;
                        if (elapsed > 0)
                            current.velocity =
                                0.5 * current.velocity +
                                ((0.5 * (event.clientY - current.lastY)) /
                                    elapsed) *
                                    1000;
                        current.lastY = event.clientY;
                        current.lastTime = event.timeStamp;
                        paint(
                            Math.max(
                                0,
                                Math.min(
                                    geometry.current.height,
                                    current.startPosition + distance,
                                ),
                            ),
                        );
                    }}
                    onPointerUp={finishDrag}
                    onPointerCancel={() => {
                        if (!gesture.current) return;
                        gesture.current = null;
                        motion.current.velocity = 0;
                        animate("collapsed");
                    }}
                    onDragStart={(event) => {
                        if (!expanded) event.preventDefault();
                    }}
                    onClickCapture={(event) => {
                        if (expanded || !suppressClick.current) return;
                        suppressClick.current = false;
                        event.preventDefault();
                        event.stopPropagation();
                    }}
                    sx={{
                        bgcolor: spaceAppBackgroundColor,
                        borderRadius: expanded ? 0 : "28px 28px 0 0",
                        height: expanded ? "auto" : "100%",
                        inset: expanded ? undefined : 0,
                        mx: "auto",
                        outline: "none",
                        overflow: expanded ? "visible" : "hidden",
                        overscrollBehavior: expanded ? "auto" : "contain",
                        position: expanded ? "relative" : "absolute",
                        touchAction: expanded ? "auto" : "none",
                        userSelect: expanded ? "auto" : "none",
                        transform: expanded
                            ? "none"
                            : "translate3d(0, 100%, 0)",
                        willChange: expanded ? "auto" : "transform",
                        width: "100%",
                        ...(!expanded && { "& *": { touchAction: "none" } }),
                    }}
                >
                    <Box
                        ref={contentRef}
                        sx={{
                            pb: expanded
                                ? 0
                                : "max(24px, env(safe-area-inset-bottom))",
                        }}
                    >
                        <AuthenticatedFriendProfile
                            friendSpaceId={friend.spaceId ?? friend.id}
                            headerRef={headerRef}
                            isPreview={!expanded}
                            showPostLoadingIndicator={expanded}
                            onBack={expanded ? onClose : dismiss}
                            username={friend.username}
                        />
                    </Box>
                    <Box
                        ref={handleRef}
                        component="button"
                        type="button"
                        aria-label="Expand profile"
                        aria-hidden={expanded}
                        tabIndex={expanded ? -1 : 0}
                        onClick={expand}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            cursor: "grab",
                            display: expanded ? "none" : "flex",
                            height: handleHeight,
                            justifyContent: "center",
                            opacity: expanded ? 0 : 1,
                            pointerEvents: expanded ? "none" : "auto",
                            p: 0,
                            position: "absolute",
                            top: 0,
                            width: "100%",
                            zIndex: 4,
                            "&:focus-visible": {
                                outline: "2px solid #08C225",
                                outlineOffset: -2,
                            },
                        }}
                    >
                        <Box
                            sx={{
                                bgcolor: "#D8D8D8",
                                borderRadius: "999px",
                                boxShadow: "0 1px 3px rgba(0, 0, 0, 0.4)",
                                height: 5,
                                width: 44,
                            }}
                        />
                    </Box>
                </Box>
            </FocusTrap>
        </Box>
    );
};
