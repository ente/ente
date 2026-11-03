import { Box } from "@mui/material";
import { useEffect, useMemo, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import {
    adjacentMonthOffset,
    indexAtOffset,
    timelineMarkers,
    wheelScrollDelta,
    type Timeline,
} from "./timeline";

interface DateScrubberProps {
    timeline: Timeline;
    height: number;
    scrollOffset: number;
    onSeek: (offset: number, row: number) => void;
    onScrollBy: (delta: number) => void;
}

const inset = 24;

export const DateScrubber = ({
    timeline,
    height,
    scrollOffset,
    onSeek,
    onScrollBy,
}: DateScrubberProps) => {
    const { t, i18n } = useTranslation();
    const railRef = useRef<HTMLDivElement>(null);
    const pointer = useRef<
        { id: number; grabOffset: number; lastY: number } | undefined
    >(undefined);
    const [dragging, setDragging] = useState(false);
    const [hoverOffset, setHoverOffset] = useState<number>();
    const [focused, setFocused] = useState(false);
    const maxOffset = Math.max(0, timeline.totalHeight - height);
    const trackHeight = Math.max(1, height - 2 * inset);
    const clamp = (offset: number) => Math.max(0, Math.min(maxOffset, offset));
    const fraction = (offset: number) => clamp(offset) / Math.max(1, maxOffset);
    const position = (offset: number) => inset + fraction(offset) * trackHeight;
    const { months } = timeline;
    const monthOffsets = useMemo(
        () => months.map(({ offset }) => offset),
        [months],
    );
    const markers = useMemo(
        () => timelineMarkers(months, maxOffset, trackHeight),
        [months, maxOffset, trackHeight],
    );
    const formatter = useMemo(
        () =>
            new Intl.DateTimeFormat(i18n.resolvedLanguage, {
                calendar: "gregory",
                month: "long",
                year: "numeric",
            }),
        [i18n.resolvedLanguage],
    );
    const bottomOffset = Math.floor(maxOffset);
    const monthAt = (offset: number) =>
        offset > 0 && offset >= bottomOffset
            ? months[months.length - 1]!
            : months[indexAtOffset(monthOffsets, offset + 1)]!;
    const seek = (offset: number) => {
        const target = clamp(offset);
        onSeek(target, indexAtOffset(timeline.offsets, target));
    };
    const offsetAtPointer = (clientY: number) =>
        clamp(
            ((clientY - railRef.current!.getBoundingClientRect().top - inset) /
                trackHeight) *
                maxOffset,
        );

    useEffect(() => {
        const rail = railRef.current!;
        const onWheel = (event: WheelEvent) => {
            const delta = wheelScrollDelta(event, height);
            if (!delta) return;
            event.preventDefault();
            event.stopPropagation();
            onScrollBy(delta);
        };
        rail.addEventListener("wheel", onWheel, { passive: false });
        return () => rail.removeEventListener("wheel", onWheel);
    }, [height, onScrollBy]);

    useEffect(() => {
        setHoverOffset(undefined);
    }, [timeline, height]);

    useEffect(() => {
        const rail = railRef.current!;
        return () => {
            const id = pointer.current?.id;
            pointer.current = undefined;
            if (id !== undefined && rail.hasPointerCapture(id))
                rail.releasePointerCapture(id);
        };
    }, []);

    const stopDragging = () => {
        pointer.current = undefined;
        setDragging(false);
        setHoverOffset(undefined);
    };

    const previewOffset = dragging
        ? scrollOffset
        : (hoverOffset ?? scrollOffset);
    const label = formatter.format(monthAt(previewOffset).date);
    return (
        <Box
            ref={railRef}
            data-date-scrubber
            data-date-scrubber-active={dragging ? "" : undefined}
            onPointerDown={(event) => {
                if (
                    event.button !== 0 ||
                    pointer.current ||
                    !(event.target as HTMLElement).closest(".date-handle")
                )
                    return;
                event.preventDefault();
                const grabOffset =
                    event.clientY -
                    event.currentTarget.getBoundingClientRect().top -
                    position(scrollOffset);
                pointer.current = {
                    id: event.pointerId,
                    grabOffset,
                    lastY: event.clientY,
                };
                event.currentTarget.setPointerCapture(event.pointerId);
                setDragging(true);
            }}
            onPointerMove={(event) => {
                const drag = pointer.current;
                if (!drag) {
                    setHoverOffset(offsetAtPointer(event.clientY));
                } else if (
                    drag.id === event.pointerId &&
                    drag.lastY !== event.clientY
                ) {
                    drag.lastY = event.clientY;
                    seek(offsetAtPointer(event.clientY - drag.grabOffset));
                }
            }}
            onPointerLeave={() => setHoverOffset(undefined)}
            onPointerCancel={stopDragging}
            onLostPointerCapture={stopDragging}
            sx={{
                position: "absolute",
                right: 0,
                top: 0,
                width: 24,
                height,
                touchAction: "none",
                userSelect: "none",
                zIndex: 1,
                "& .date-tick, & .date-handle, & .date-label": {
                    position: "absolute",
                    transform: "translateY(-50%)",
                },
                "& .date-tick, & .date-handle": {
                    transition: "opacity 250ms ease-in-out",
                },
                "& .date-tick": { opacity: 0 },
                "& .date-year-target": { pointerEvents: "none" },
                "& .date-handle": { opacity: 0.3 },
                "& .date-year-target, & .date-handle": { p: 0, border: 0 },
                "& .date-label": {
                    px: 1,
                    py: 0.5,
                    border: "0.5px solid",
                    borderColor: "stroke.faint",
                    borderRadius: "6px",
                    bgcolor: "background.elevatedPaper",
                    boxShadow: "0 2px 3px rgba(0, 0, 0, 0.1)",
                },
                "&:hover, &:has(:focus-visible), &[data-date-scrubber-active]":
                    {
                        "& .date-tick, & .date-handle": { opacity: 1 },
                        "& .date-year-target": { pointerEvents: "auto" },
                    },
                "@media (prefers-reduced-motion: reduce)": {
                    "& .date-tick, & .date-handle": { transition: "none" },
                },
            }}
        >
            {markers.map((marker) =>
                !marker.yearStart ? (
                    <Box
                        key={`${marker.date.getFullYear()}-${marker.date.getMonth()}`}
                        className="date-tick"
                        aria-hidden
                        sx={{
                            top: inset + marker.position,
                            right: 11,
                            width: 3,
                            height: "3px",
                            bgcolor: "text.muted",
                            borderRadius: "50%",
                            pointerEvents: "none",
                        }}
                    />
                ) : (
                    <Box
                        component="button"
                        type="button"
                        className="date-tick date-year-target"
                        key={`${marker.date.getFullYear()}-${marker.date.getMonth()}`}
                        aria-label={t("jump_to_date", {
                            date: formatter.format(marker.date),
                        })}
                        onPointerDown={(event) => event.stopPropagation()}
                        onPointerMove={(event) => {
                            event.stopPropagation();
                            setHoverOffset(marker.offset);
                        }}
                        onFocus={() => setHoverOffset(marker.offset)}
                        onBlur={() => setHoverOffset(undefined)}
                        onClick={() => seek(marker.offset)}
                        sx={{
                            top: inset + marker.position,
                            right: 0,
                            width: 24,
                            height: 24,
                            bgcolor: "transparent",
                            cursor: "pointer",
                            "&::before": {
                                content: '""',
                                position: "absolute",
                                top: "50%",
                                right: 8,
                                width: 8,
                                height: "2px",
                                bgcolor: "text.muted",
                            },
                        }}
                    >
                        <Box
                            component="span"
                            className="date-year-label date-label"
                            sx={{
                                right: 32,
                                pointerEvents: "none",
                                top: "50%",
                                color: "text.muted",
                                typography: "mini",
                                fontVariantNumeric: "tabular-nums",
                            }}
                        >
                            {marker.date.getFullYear()}
                        </Box>
                    </Box>
                ),
            )}
            <Box
                component="button"
                type="button"
                role="slider"
                className="date-handle"
                aria-label={t("browse_photos_by_date")}
                aria-orientation="vertical"
                aria-valuemin={0}
                aria-valuemax={100}
                aria-valuenow={Math.round(fraction(scrollOffset) * 100)}
                aria-valuetext={formatter.format(monthAt(scrollOffset).date)}
                onFocus={() => setFocused(true)}
                onBlur={() => setFocused(false)}
                onKeyDown={(event) => {
                    const edges: Partial<Record<string, number>> = {
                        Home: 0,
                        End: maxOffset,
                    };
                    let target = edges[event.key];
                    if (event.key.startsWith("Arrow")) {
                        const older = ["ArrowDown", "ArrowRight"].includes(
                            event.key,
                        );
                        target =
                            adjacentMonthOffset(
                                monthOffsets,
                                clamp(scrollOffset),
                                older ? "older" : "newer",
                                bottomOffset,
                            ) ?? (older ? maxOffset : 0);
                    }
                    if (target === undefined) return;
                    event.preventDefault();
                    setHoverOffset(undefined);
                    seek(target);
                }}
                sx={{
                    top: position(scrollOffset),
                    right: 8,
                    width: 8,
                    height: 36,
                    borderRadius: "4px",
                    bgcolor: "text.muted",
                    cursor: "ns-resize",
                    touchAction: "none",
                    "&::before": {
                        content: '""',
                        position: "absolute",
                        inset: "-4px -7px",
                    },
                }}
            />
            {(hoverOffset !== undefined || dragging || focused) && (
                <Box
                    role="tooltip"
                    className="date-label"
                    sx={{
                        right: 88,
                        top: position(previewOffset),
                        color: "text.primary",
                        typography: "small",
                        whiteSpace: "nowrap",
                        pointerEvents: "none",
                        zIndex: 2,
                    }}
                >
                    {label}
                </Box>
            )}
        </Box>
    );
};
