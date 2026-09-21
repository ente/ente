import { Add01Icon, Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { keyframes } from "@mui/material/styles";
import React from "react";
import { maxSpacePostPhotos, movePostPhoto } from "utils/post-photos";

interface StripPhoto {
    id: number;
    imageUrl?: string;
}

interface PhotoDrag {
    from: number;
    to: number;
    x: number;
    top: number;
}

const photoSize = 48;
const photoGap = 8;
const liftPhoto = keyframes`
    from { transform: translateY(4px) scale(1); }
    to { transform: translateY(0) scale(1.04); }
`;
const iconButtonSx = {
    alignItems: "center",
    background: "none",
    border: 0,
    color: "#D8D8D8",
    cursor: "pointer",
    display: "flex",
    justifyContent: "center",
    p: 0,
    "&:disabled": { opacity: 0.3, cursor: "default" },
    "&:focus-visible": { outline: "2px solid #FFFFFF", outlineOffset: 2 },
};

export const SpacePostPhotoStrip: React.FC<{
    activeIndex: number;
    disabled: boolean;
    onAdd?: () => void;
    onMove?: (from: number, to: number) => void;
    onRemove?: () => void;
    onSelect: (index: number) => void;
    photos: StripPhoto[];
}> = ({ activeIndex, disabled, onAdd, onMove, onRemove, onSelect, photos }) => {
    const stripRef = React.useRef<HTMLDivElement | null>(null);
    const suppressClickRef = React.useRef(false);
    const callbacksRef = React.useRef({ onMove, onSelect });
    callbacksRef.current = { onMove, onSelect };
    const [drag, setDrag] = React.useState<PhotoDrag>();
    const [announcement, setAnnouncement] = React.useState("");
    const [hasPhotosOnRight, setHasPhotosOnRight] = React.useState(false);
    const dragging = Boolean(drag);
    const canMove = Boolean(onMove);

    React.useEffect(() => {
        const strip = stripRef.current;
        if (!strip) return;
        const updateOverflow = () =>
            setHasPhotosOnRight(
                strip.scrollWidth - strip.clientWidth - strip.scrollLeft > 1,
            );
        const observer = new ResizeObserver(updateOverflow);
        observer.observe(strip);
        strip.addEventListener("scroll", updateOverflow, { passive: true });
        updateOverflow();
        return () => {
            observer.disconnect();
            strip.removeEventListener("scroll", updateOverflow);
        };
    }, [photos.length]);

    React.useEffect(() => {
        if (dragging) return;
        stripRef.current
            ?.querySelector('[aria-pressed="true"]')
            ?.scrollIntoView({ block: "nearest", inline: "nearest" });
    }, [activeIndex, dragging, photos.length]);

    React.useEffect(() => {
        const strip = stripRef.current;
        if (!strip || disabled || !canMove || photos.length < 2) return;
        let gesture:
            | {
                  pointerID: number;
                  startX: number;
                  startY: number;
                  touch: boolean;
                  active: boolean;
                  drag: PhotoDrag;
              }
            | undefined;
        let holdTimer: number | undefined;
        let frame: number | undefined;

        const stop = () => {
            window.clearTimeout(holdTimer);
            if (frame != undefined) cancelAnimationFrame(frame);
            gesture = undefined;
            setDrag(undefined);
        };
        const positionAt = (x: number) => {
            let distance = Infinity;
            let position = 0;
            strip
                .querySelectorAll<HTMLElement>("[data-photo-slot]")
                .forEach((slot, index) => {
                    const rect = slot.getBoundingClientRect();
                    const nextDistance = Math.abs(
                        x - rect.left - rect.width / 2,
                    );
                    if (nextDistance < distance) {
                        distance = nextDistance;
                        position = index;
                    }
                });
            return position;
        };
        const update = () => {
            if (!gesture?.active) return;
            const { x } = gesture.drag;
            const bounds = strip.getBoundingClientRect();
            const edge = 32;
            const scroll =
                x < bounds.left + edge
                    ? -Math.min(8, (bounds.left + edge - x) / 4)
                    : x > bounds.right - edge
                      ? Math.min(8, (x - bounds.right + edge) / 4)
                      : 0;
            strip.scrollLeft += scroll;
            gesture.drag.to = positionAt(x);
            setDrag({ ...gesture.drag });
            frame = requestAnimationFrame(update);
        };
        const activate = () => {
            if (!gesture) return;
            gesture.active = true;
            suppressClickRef.current = true;
            callbacksRef.current.onSelect(gesture.drag.from);
            strip.setPointerCapture(gesture.pointerID);
            update();
        };
        const start = (event: PointerEvent) => {
            suppressClickRef.current = false;
            if (gesture || !event.isPrimary) {
                stop();
                return;
            }
            if (event.button != 0 || !(event.target instanceof Element)) return;
            const photo =
                event.target.closest<HTMLElement>("[data-photo-index]");
            if (!photo) return;
            const from = Number(photo.dataset.photoIndex);
            gesture = {
                pointerID: event.pointerId,
                startX: event.clientX,
                startY: event.clientY,
                touch: event.pointerType == "touch",
                active: false,
                drag: {
                    from,
                    to: from,
                    x: event.clientX,
                    top: photo.getBoundingClientRect().top - 4,
                },
            };
            if (gesture.touch) holdTimer = window.setTimeout(activate, 180);
        };
        const move = (event: PointerEvent) => {
            if (event.pointerId != gesture?.pointerID) return;
            gesture.drag.x = event.clientX;
            if (gesture.active) return;
            const distance = Math.hypot(
                event.clientX - gesture.startX,
                event.clientY - gesture.startY,
            );
            if (distance < 8) return;
            if (gesture.touch) stop();
            else activate();
        };
        const finish = (event: PointerEvent) => {
            if (event.pointerId != gesture?.pointerID) return;
            const { active, drag: completed } = gesture;
            completed.to = positionAt(event.clientX);
            stop();
            if (active && completed.from != completed.to) {
                callbacksRef.current.onMove?.(completed.from, completed.to);
                setAnnouncement(
                    `Photo moved to position ${completed.to + 1} of ${photos.length}`,
                );
            }
        };
        const preventScroll = (event: TouchEvent) => {
            if (gesture?.active) event.preventDefault();
        };
        const cancelOnEscape = (event: KeyboardEvent) => {
            if (event.key != "Escape" || !gesture) return;
            event.preventDefault();
            event.stopPropagation();
            stop();
        };
        strip.addEventListener("pointerdown", start);
        strip.addEventListener("touchmove", preventScroll, { passive: false });
        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", finish);
        window.addEventListener("pointercancel", stop);
        window.addEventListener("keydown", cancelOnEscape, true);
        return () => {
            stop();
            strip.removeEventListener("pointerdown", start);
            strip.removeEventListener("touchmove", preventScroll);
            window.removeEventListener("pointermove", move);
            window.removeEventListener("pointerup", finish);
            window.removeEventListener("pointercancel", stop);
            window.removeEventListener("keydown", cancelOnEscape, true);
        };
    }, [canMove, disabled, photos.length]);

    const shownPhotos = drag
        ? movePostPhoto(photos, drag.from, drag.to)
        : photos;
    const draggedPhoto = drag ? photos[drag.from] : undefined;
    const preview = (photo: StripPhoto) =>
        photo.imageUrl ? (
            <Box
                component="img"
                src={photo.imageUrl}
                alt=""
                draggable={false}
                sx={{
                    height: "100%",
                    width: "100%",
                    objectFit: "cover",
                    pointerEvents: "none",
                }}
            />
        ) : (
            photos.indexOf(photo) + 1
        );

    return (
        <Box sx={{ mb: "8px" }}>
            <Box
                sx={{
                    display: "flex",
                    alignItems: "center",
                    gap: "4px",
                    minWidth: 0,
                }}
            >
                <Box sx={{ flex: 1, minWidth: 0, position: "relative" }}>
                    <Box
                        ref={stripRef}
                        onClickCapture={(event) => {
                            if (!suppressClickRef.current || event.detail == 0)
                                return;
                            event.preventDefault();
                            event.stopPropagation();
                        }}
                        onContextMenu={(event) => event.preventDefault()}
                        sx={{
                            display: "flex",
                            gap: `${photoGap}px`,
                            overflowX: "auto",
                            px: "6px",
                            py: "10px",
                            scrollbarWidth: "none",
                            userSelect: "none",
                            WebkitTouchCallout: "none",
                            "&::-webkit-scrollbar": { display: "none" },
                        }}
                    >
                        {photos.map((photo, index) => (
                            <Box
                                key={photo.id}
                                data-photo-slot
                                sx={{
                                    flexShrink: 0,
                                    height: photoSize,
                                    width: photoSize,
                                    position: "relative",
                                }}
                            >
                                <Box
                                    sx={{
                                        height: "100%",
                                        width: "100%",
                                        position: "relative",
                                        transform: `translateX(${(shownPhotos.indexOf(photo) - index) * (photoSize + photoGap)}px)`,
                                        transition: dragging
                                            ? "transform 180ms cubic-bezier(0.2, 0.8, 0.2, 1)"
                                            : undefined,
                                        "@media (prefers-reduced-motion: reduce)":
                                            { transition: "none" },
                                    }}
                                >
                                    <Box
                                        component="button"
                                        type="button"
                                        data-photo-index={index}
                                        aria-label={`Photo ${index + 1}`}
                                        aria-pressed={
                                            photo.id == photos[activeIndex]?.id
                                        }
                                        aria-keyshortcuts={
                                            onMove
                                                ? "Alt+ArrowLeft Alt+ArrowRight"
                                                : undefined
                                        }
                                        disabled={disabled}
                                        onClick={() => onSelect(index)}
                                        onKeyDown={(
                                            event: React.KeyboardEvent,
                                        ) => {
                                            if (
                                                !onMove ||
                                                !event.altKey ||
                                                ![
                                                    "ArrowLeft",
                                                    "ArrowRight",
                                                ].includes(event.key)
                                            )
                                                return;
                                            event.preventDefault();
                                            event.stopPropagation();
                                            const to =
                                                index +
                                                (event.key == "ArrowLeft"
                                                    ? -1
                                                    : 1);
                                            if (to < 0 || to >= photos.length)
                                                return;
                                            onMove(index, to);
                                            setAnnouncement(
                                                `Photo moved to position ${to + 1} of ${photos.length}`,
                                            );
                                        }}
                                        sx={{
                                            ...iconButtonSx,
                                            bgcolor: "#242424",
                                            outline:
                                                photo.id ==
                                                photos[activeIndex]?.id
                                                    ? "1.5px solid #FFFFFF"
                                                    : "none",
                                            outlineOffset: "-1.5px",
                                            borderRadius: "9px",
                                            cursor: disabled
                                                ? "default"
                                                : onMove
                                                  ? "grab"
                                                  : "pointer",
                                            height: "100%",
                                            width: "100%",
                                            overflow: "hidden",
                                            scrollMarginInlineEnd: "36px",
                                            opacity:
                                                photo.id == draggedPhoto?.id
                                                    ? 0.3
                                                    : 1,
                                        }}
                                    >
                                        {preview(photo)}
                                    </Box>
                                    {onRemove &&
                                        index == activeIndex &&
                                        !dragging && (
                                            <Box
                                                component="button"
                                                type="button"
                                                aria-label="Remove photo"
                                                disabled={disabled}
                                                onClick={onRemove}
                                                sx={{
                                                    ...iconButtonSx,
                                                    position: "absolute",
                                                    right: -10,
                                                    top: -10,
                                                    width: 32,
                                                    height: 32,
                                                }}
                                            >
                                                <Box
                                                    component="span"
                                                    sx={{
                                                        alignItems: "center",
                                                        bgcolor: "#3A3A3A",
                                                        border: "1px solid #000000",
                                                        borderRadius: "50%",
                                                        display: "flex",
                                                        justifyContent:
                                                            "center",
                                                        width: 20,
                                                        height: 20,
                                                    }}
                                                >
                                                    <HugeiconsIcon
                                                        icon={Cancel01Icon}
                                                        size={12}
                                                    />
                                                </Box>
                                            </Box>
                                        )}
                                </Box>
                            </Box>
                        ))}
                        {onAdd && photos.length < maxSpacePostPhotos && (
                            <Box
                                component="button"
                                type="button"
                                aria-label="Add photos"
                                disabled={disabled}
                                onClick={onAdd}
                                sx={{
                                    ...iconButtonSx,
                                    bgcolor: "#242424",
                                    borderRadius: "9px",
                                    flexShrink: 0,
                                    width: photoSize,
                                    height: photoSize,
                                }}
                            >
                                <HugeiconsIcon icon={Add01Icon} size={20} />
                            </Box>
                        )}
                    </Box>
                    {hasPhotosOnRight && (
                        <Box
                            aria-hidden
                            sx={{
                                background:
                                    "linear-gradient(to right, transparent, #000000)",
                                bottom: 0,
                                pointerEvents: "none",
                                position: "absolute",
                                right: 0,
                                top: 0,
                                width: 36,
                            }}
                        />
                    )}
                </Box>
            </Box>
            <Box
                role="status"
                sx={{
                    position: "absolute",
                    width: 1,
                    height: 1,
                    overflow: "hidden",
                    clipPath: "inset(50%)",
                }}
            >
                {announcement}
            </Box>
            {drag && draggedPhoto && (
                <Box
                    aria-hidden
                    sx={{
                        position: "fixed",
                        left: drag.x - photoSize / 2,
                        top: drag.top,
                        width: photoSize,
                        height: photoSize,
                        borderRadius: "9px",
                        outline: "1.5px solid #FFFFFF",
                        outlineOffset: "-1.5px",
                        bgcolor: "#242424",
                        overflow: "hidden",
                        boxShadow: "0 4px 12px #00000088",
                        transform: "scale(1.04)",
                        animation: `${liftPhoto} 100ms ease-out`,
                        "@media (prefers-reduced-motion: reduce)": {
                            animation: "none",
                        },
                        pointerEvents: "none",
                        zIndex: 5,
                        boxSizing: "border-box",
                    }}
                >
                    {preview(draggedPhoto)}
                </Box>
            )}
        </Box>
    );
};
