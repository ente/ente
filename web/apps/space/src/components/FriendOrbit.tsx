import { Box, useMediaQuery } from "@mui/material";
import React from "react";
import {
    arrangeFriendOrbit,
    createFriendOrbitCircle,
    friendOrbitCircleSize,
    stepFriendOrbit,
    type FriendOrbitBounds,
    type FriendOrbitCircle,
} from "utils/friend-orbit";

interface FriendOrbitProps {
    initialOuterID?: string;
    items: {
        id: string;
        size?: number;
        fixedSize?: number;
        content: React.ReactNode;
    }[];
}

interface OrbitDrag {
    pointerID: number;
    circle: FriendOrbitCircle;
    startX: number;
    startY: number;
    originX: number;
    originY: number;
    moved: boolean;
}

export const FriendOrbit: React.FC<FriendOrbitProps> = ({
    initialOuterID,
    items,
}) => {
    const fieldRef = React.useRef<HTMLUListElement>(null);
    const elements = React.useRef(new Map<string, HTMLLIElement>());
    const circles = React.useRef<FriendOrbitCircle[]>([]);
    const bounds = React.useRef<FriendOrbitBounds>({
        width: 0,
        height: 0,
        scale: 1,
    });
    const elapsed = React.useRef(0);
    const drag = React.useRef<OrbitDrag | null>(null);
    const suppressClick = React.useRef(false);
    const [heldFriendID, setHeldFriendID] = React.useState<string>();
    const reducedMotion = useMediaQuery("(prefers-reduced-motion: reduce)");

    const paintCircle = React.useCallback((circle: FriendOrbitCircle) => {
        const { width, height, scale } = bounds.current;
        const element = elements.current.get(circle.id);
        if (!element) return;
        const size = circle.size * scale;
        element.style.transform = `translate3d(${width / 2 + circle.x * scale - size / 2}px, ${height / 2 + circle.y * scale - size / 2}px, 0)`;
    }, []);
    const paint = React.useCallback(
        () => circles.current.forEach(paintCircle),
        [paintCircle],
    );

    React.useLayoutEffect(() => {
        const current = new Map(
            circles.current.map((circle) => [circle.id, circle]),
        );
        circles.current = items.map(
            (item, index) =>
                current.get(item.id) ?? createFriendOrbitCircle(item.id, index),
        );
        const field = fieldRef.current!;
        const resize = () => {
            const width = field.clientWidth;
            const scale =
                width <= 430
                    ? 0.84
                    : width <= 560
                      ? 0.98
                      : width <= 700
                        ? 1.176
                        : 1.4;
            field.style.minHeight = "0px";
            const availableBounds = {
                width,
                height: field.clientHeight,
                scale,
            };
            circles.current.forEach((circle, index) => {
                const item = items[index]!;
                circle.size = item.fixedSize
                    ? item.fixedSize / scale
                    : (item.size ??
                      friendOrbitCircleSize(
                          index,
                          items.length,
                          availableBounds,
                      ));
            });
            const area = circles.current.reduce(
                (total, circle) =>
                    total + Math.PI * ((circle.size * scale) / 2 + 10) ** 2,
                0,
            );
            field.style.minHeight = `${Math.ceil(area / (width * 0.52))}px`;
            const height = field.clientHeight;
            const layoutChanged =
                width != bounds.current.width ||
                height != bounds.current.height;
            bounds.current = { width, height, scale };
            circles.current.forEach((circle) => {
                const element = elements.current.get(circle.id)!;
                element.style.width = `${circle.size * scale}px`;
                element.style.height = `${circle.size * scale}px`;
            });
            if (layoutChanged)
                arrangeFriendOrbit(
                    circles.current,
                    bounds.current,
                    elapsed.current,
                    initialOuterID,
                );
            else
                stepFriendOrbit(
                    circles.current,
                    bounds.current,
                    elapsed.current,
                    0,
                );
            paint();
            field.style.opacity = "1";
        };
        const observer = new ResizeObserver(resize);
        observer.observe(field);
        resize();
        return () => observer.disconnect();
    }, [initialOuterID, items, paint]);

    React.useEffect(() => {
        if (reducedMotion) return;
        let frameID = 0;
        let previous = performance.now();
        const animate = (now: number) => {
            const delta = Math.min(now - previous, 33.334);
            previous = now;
            elapsed.current += delta;
            stepFriendOrbit(
                circles.current,
                bounds.current,
                elapsed.current,
                delta,
                drag.current?.circle.id,
            );
            paint();
            frameID = requestAnimationFrame(animate);
        };
        frameID = requestAnimationFrame(animate);
        return () => cancelAnimationFrame(frameID);
    }, [paint, reducedMotion]);

    const startDrag = (
        event: React.PointerEvent<HTMLLIElement>,
        friendID: string,
    ) => {
        if (event.button != 0 || !event.isPrimary) return;
        event.stopPropagation();
        const circle = circles.current.find((circle) => circle.id == friendID)!;
        const target =
            (event.target as Element).closest("button") ?? event.currentTarget;
        target.setPointerCapture(event.pointerId);
        drag.current = {
            pointerID: event.pointerId,
            circle,
            startX: event.clientX,
            startY: event.clientY,
            originX: circle.x,
            originY: circle.y,
            moved: false,
        };
        circle.vx = 0;
        circle.vy = 0;
        suppressClick.current = false;
        setHeldFriendID(friendID);
    };

    const moveDrag = (event: React.PointerEvent<HTMLLIElement>) => {
        const active = drag.current;
        if (active?.pointerID != event.pointerId) return;
        const dx = event.clientX - active.startX;
        const dy = event.clientY - active.startY;
        if (!active.moved && Math.hypot(dx, dy) < 3) return;
        active.moved = true;
        suppressClick.current = true;
        active.circle.x = active.originX + dx / bounds.current.scale;
        active.circle.y = active.originY + dy / bounds.current.scale;
        paintCircle(active.circle);
    };

    const endDrag = (event: React.PointerEvent<HTMLLIElement>) => {
        const active = drag.current;
        if (active?.pointerID != event.pointerId) return;
        drag.current = null;
        setHeldFriendID(undefined);
        if (reducedMotion) {
            active.circle.x = active.originX;
            active.circle.y = active.originY;
            stepFriendOrbit(
                circles.current,
                bounds.current,
                0,
                0,
                undefined,
                true,
            );
            paint();
        }
    };

    return (
        <Box
            component="ul"
            ref={fieldRef}
            aria-label="Friends and friend requests"
            onDragStart={(event) => event.preventDefault()}
            onClickCapture={(event) => {
                if (!suppressClick.current) return;
                event.preventDefault();
                event.stopPropagation();
                suppressClick.current = false;
            }}
            sx={{
                height: "calc(var(--space-page-height, 100svh) - 56px)",
                listStyle: "none",
                m: 0,
                overflow: "hidden",
                opacity: 0,
                p: 0,
                position: "relative",
                userSelect: "none",
                width: "100%",
            }}
        >
            {items.map((item) => (
                <Box
                    component="li"
                    key={item.id}
                    ref={(element: HTMLLIElement | null) => {
                        if (element) elements.current.set(item.id, element);
                        else elements.current.delete(item.id);
                    }}
                    onPointerDown={(event) => startDrag(event, item.id)}
                    onPointerMove={moveDrag}
                    onPointerUp={endDrag}
                    onPointerCancel={endDrag}
                    onLostPointerCapture={endDrag}
                    onContextMenu={(event) => event.preventDefault()}
                    sx={{
                        borderRadius: "50%",
                        cursor: heldFriendID == item.id ? "grabbing" : "grab",
                        left: 0,
                        position: "absolute",
                        top: 0,
                        touchAction: "none",
                        WebkitTouchCallout: "none",
                        willChange: "transform",
                        zIndex: heldFriendID == item.id ? 2 : undefined,
                        "&:hover, &:focus-within": { zIndex: 1 },
                        "& > button": {
                            cursor:
                                heldFriendID == item.id ? "grabbing" : "grab",
                            ...(heldFriendID == item.id && { scale: "1.06" }),
                        },
                        "& img": { pointerEvents: "none" },
                    }}
                >
                    {item.content}
                </Box>
            ))}
        </Box>
    );
};
