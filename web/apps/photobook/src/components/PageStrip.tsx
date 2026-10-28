"use client";

import { thumbnailShadow, toolbarColors, uiColors } from "@/theme/colors";

import { useBook } from "@/context/book";
import { usePageDrag } from "@/hooks/usePageDrag";
import { useSpreads } from "@/hooks/useSpreads";
import { Box, Typography, useMediaQuery } from "@mui/material";
import {
    useCallback,
    useEffect,
    useRef,
    useState,
    type RefCallback,
} from "react";
import { Layer, Stage } from "react-konva";
import PageCanvas from "./PageCanvas";
import PrinterBlankPage from "./PrinterBlankPage";
import { EDITOR_SCROLLBAR_SX } from "./editorLayout";

interface PageStripProps {
    onSpreadClick?: (spreadIdx: number) => void;
}

export default function PageStrip({ onSpreadClick }: PageStripProps) {
    const { book } = useBook();
    const isCompact = useMediaQuery("(max-width: 599px)");
    const thumbnailWidth = isCompact ? 52 : 136;
    const rowPadding = isCompact ? 8 : 12;
    const labelLineHeight = isCompact ? 16 : 18;
    const pages = book.pages;
    const pageDrag = usePageDrag();
    const stripContainerRef = useRef<HTMLDivElement | null>(null);

    const spreads = useSpreads(pages.length);

    // Virtualization: only render visible spread thumbnails
    const [visibleSpreads, setVisibleSpreads] = useState<Set<number>>(
        () => new Set([0, 1, 2, 3, 4, 5, 6, 7]),
    );
    const stripElsRef = useRef<Map<number, Element>>(new Map());
    const stripObserverRef = useRef<IntersectionObserver | null>(null);

    useEffect(() => {
        const root = stripContainerRef.current;
        if (!root) return;

        const observer = new IntersectionObserver(
            (entries) => {
                setVisibleSpreads((prev) => {
                    const next = new Set(prev);
                    for (const entry of entries) {
                        const idx = Number(
                            (entry.target as HTMLElement).dataset
                                .stripSpreadIndex,
                        );
                        if (!isNaN(idx)) {
                            if (entry.isIntersecting) next.add(idx);
                            else next.delete(idx);
                        }
                    }
                    if (
                        next.size === prev.size &&
                        [...next].every((v) => prev.has(v))
                    )
                        return prev;
                    return next;
                });
            },
            { root, rootMargin: "300px 0px" },
        );
        stripObserverRef.current = observer;

        stripElsRef.current.forEach((el) => observer.observe(el));

        return () => {
            observer.disconnect();
            stripObserverRef.current = null;
        };
    }, [spreads.length]);

    const stripSpreadRefCallback = useCallback(
        (idx: number): RefCallback<HTMLDivElement> =>
            (el) => {
                const prev = stripElsRef.current.get(idx);
                if (prev && stripObserverRef.current)
                    stripObserverRef.current.unobserve(prev);

                if (el) {
                    stripElsRef.current.set(idx, el);
                    if (stripObserverRef.current)
                        stripObserverRef.current.observe(el);
                } else {
                    stripElsRef.current.delete(idx);
                }
            },
        [],
    );

    return (
        <Box
            ref={stripContainerRef}
            sx={{
                width: "100%",
                display: "flex",
                flexDirection: "column",
                px: { xs: 1, sm: 2 },
                py: 3,
                flex: 1,
                minHeight: 0,
                overflowX: "hidden",
                overflowY: "auto",
                scrollbarGutter: "stable both-edges",
                ...EDITOR_SCROLLBAR_SX,
            }}
        >
            {pages.length === 0 && (
                <Typography
                    sx={{
                        px: 1,
                        pt: 3,
                        fontSize: 12,
                        lineHeight: 1.5,
                        color: uiColors.muted,
                        textAlign: "center",
                    }}
                >
                    Your pages will appear here
                </Typography>
            )}
            <Box
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    gap: { xs: 1, sm: 1.5 },
                }}
            >
                {spreads.map((spread, spreadIdx) => (
                    <Box
                        key={spreadIdx}
                        ref={stripSpreadRefCallback(spreadIdx)}
                        data-strip-spread-index={spreadIdx}
                        onClick={() => onSpreadClick?.(spreadIdx)}
                        sx={{
                            cursor: "pointer",
                            borderRadius: `${rowPadding + 4}px`,
                            p: `${rowPadding}px`,
                            width:
                                (spread.left !== null && spread.right !== null
                                    ? thumbnailWidth * 2 + 2
                                    : thumbnailWidth) +
                                rowPadding * 2,
                            ml:
                                spread.left === null
                                    ? `${thumbnailWidth + 2}px`
                                    : 0,
                            mr:
                                spread.right === null
                                    ? `${thumbnailWidth + 2}px`
                                    : 0,
                            display: "flex",
                            gap: "2px",
                            minHeight:
                                thumbnailWidth +
                                rowPadding * 2 +
                                labelLineHeight +
                                4,
                            "&:hover": { bgcolor: toolbarColors.control },
                            transition: "background-color 120ms ease",
                        }}
                    >
                        {visibleSpreads.has(spreadIdx) &&
                            (["left", "right"] as const).map((side) => {
                                const entry = spread[side];
                                if (entry === null) return null;
                                const pageIndex =
                                    typeof entry === "number" ? entry : null;
                                const page =
                                    pageIndex !== null
                                        ? pages[pageIndex]
                                        : null;
                                const canDrag =
                                    pageIndex !== null &&
                                    pageIndex > 0 &&
                                    pageIndex < pages.length - 1;
                                const label =
                                    entry === "printer-blank"
                                        ? "Blank"
                                        : pageIndex === null
                                          ? ""
                                          : pageIndex === 0
                                            ? "Cover"
                                            : pageIndex === pages.length - 1
                                              ? "Back cover"
                                              : pageIndex;

                                return (
                                    <Box
                                        key={side}
                                        sx={{
                                            width: thumbnailWidth,
                                            flexShrink: 0,
                                        }}
                                    >
                                        {entry === "printer-blank" ? (
                                            <PrinterBlankPage
                                                width={thumbnailWidth}
                                                height={thumbnailWidth}
                                            />
                                        ) : page && pageIndex !== null ? (
                                            <Box
                                                draggable={canDrag}
                                                onDragStart={(e) =>
                                                    pageDrag.handlePageDragStart(
                                                        e,
                                                        pageIndex,
                                                    )
                                                }
                                                onDragOver={(e) =>
                                                    pageDrag.handlePageDragOverPage(
                                                        e,
                                                        pageIndex,
                                                    )
                                                }
                                                onDrop={(e) =>
                                                    pageDrag.handlePageDropOnPage(
                                                        e,
                                                        pageIndex,
                                                    )
                                                }
                                                onDragEnd={
                                                    pageDrag.handlePageDragEndCleanup
                                                }
                                                sx={{
                                                    width: thumbnailWidth,
                                                    height: thumbnailWidth,
                                                    bgcolor: uiColors.paper,
                                                    boxShadow: thumbnailShadow,
                                                    borderRadius: 0.5,
                                                    overflow: "hidden",
                                                    cursor: canDrag
                                                        ? "grab"
                                                        : "pointer",
                                                    outline:
                                                        pageDrag.pageDragTarget ===
                                                        pageIndex
                                                            ? "2px solid #08C225"
                                                            : undefined,
                                                    opacity:
                                                        pageDrag.pageDragSource ===
                                                        pageIndex
                                                            ? 0.4
                                                            : 1,
                                                }}
                                            >
                                                <Stage
                                                    width={thumbnailWidth}
                                                    height={thumbnailWidth}
                                                    listening={false}
                                                    style={{
                                                        pointerEvents: "none",
                                                    }}
                                                >
                                                    <Layer>
                                                        <PageCanvas
                                                            page={page}
                                                            pageWidth={
                                                                thumbnailWidth
                                                            }
                                                            pageHeight={
                                                                thumbnailWidth
                                                            }
                                                            isFrontCover={
                                                                pageIndex === 0
                                                            }
                                                            isBackCover={
                                                                pageIndex ===
                                                                pages.length - 1
                                                            }
                                                        />
                                                    </Layer>
                                                </Stage>
                                            </Box>
                                        ) : null}
                                        <Typography
                                            title={
                                                entry === "printer-blank"
                                                    ? "Blank page (required)"
                                                    : undefined
                                            }
                                            sx={{
                                                mt: 0.5,
                                                fontSize: isCompact ? 12 : 14,
                                                lineHeight: `${labelLineHeight}px`,
                                                fontWeight: 600,
                                                color: uiColors.muted,
                                                textAlign: "center",
                                            }}
                                        >
                                            {label}
                                        </Typography>
                                    </Box>
                                );
                            })}
                    </Box>
                ))}
            </Box>
        </Box>
    );
}
