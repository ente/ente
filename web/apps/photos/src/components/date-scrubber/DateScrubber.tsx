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
    const pointer = useRef<number | undefined>(undefined);
    const [dragging, setDragging] = useState(false);
    const [hoverOffset, setHoverOffset] = useState<number>();
    const [focused, setFocused] = useState(false);
    const maxOffset = Math.max(0, timeline.totalHeight - height);
    const trackHeight = Math.max(1, height - 2 * inset);
    const clamp = (offset: number) => Math.max(0, Math.min(maxOffset, offset));
    const position = (offset: number) =>
        inset + (clamp(offset) / Math.max(1, maxOffset)) * trackHeight;
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
                month: "long",
                year: "numeric",
            }),
        [i18n.resolvedLanguage],
    );
    const monthAt = (offset: number) =>
        months[indexAtOffset(monthOffsets, offset + 1)]!;
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
        setDragging(false);
        const rail = railRef.current!;
        return () => {
            const id = pointer.current;
            pointer.current = undefined;
            if (id !== undefined && rail.hasPointerCapture(id))
                rail.releasePointerCapture(id);
        };
    }, [timeline, height]);

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
                if (event.button !== 0) return;
                event.preventDefault();
                pointer.current = event.pointerId;
                event.currentTarget.setPointerCapture(event.pointerId);
                setDragging(true);
                seek(offsetAtPointer(event.clientY));
            }}
            onPointerMove={(event) => {
                const offset = offsetAtPointer(event.clientY);
                setHoverOffset(offset);
                if (pointer.current === event.pointerId) seek(offset);
            }}
            onPointerLeave={() => setHoverOffset(undefined)}
            onPointerUp={(event) => {
                if (event.currentTarget.hasPointerCapture(event.pointerId))
                    event.currentTarget.releasePointerCapture(event.pointerId);
            }}
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
                cursor: "ns-resize",
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
                        width: 88,
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
                            width: 88,
                            height: 24,
                            bgcolor: "transparent",
                            cursor: "pointer",
                        }}
                    >
                        <Box
                            component="span"
                            className="date-year-label date-label"
                            sx={{
                                right: 32,
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
                aria-valuenow={Math.round(
                    (clamp(scrollOffset) / Math.max(1, maxOffset)) * 100,
                )}
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
