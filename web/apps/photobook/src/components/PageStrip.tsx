import { useBook } from "@/context/book";
import { useSpreads } from "@/hooks/useSpreads";
import { getSpreadLabel } from "@/lib/spreads";
import { thumbnailShadow, uiColors } from "@/theme/colors";
import { Box, Typography, useMediaQuery } from "@mui/material";
import {
    memo,
    useEffect,
    useMemo,
    useRef,
    useState,
    type RefCallback,
    type RefObject,
} from "react";
import { Layer, Stage } from "react-konva";
import PageCanvas from "./PageCanvas";
import { EDITOR_SCROLLBAR_SX, EDITOR_SIDEBAR_WIDTH } from "./editorLayout";

export interface PageStripProps {
    onSpreadClick?: (spreadIdx: number) => void;
}

function PageStrip({
    onSpreadClick,
    scrollRef,
}: PageStripProps & { scrollRef: RefObject<HTMLDivElement | null> }) {
    const { book } = useBook("book");
    const isCompact = useMediaQuery("(max-width: 899px)");
    const thumbnailWidth =
        (EDITOR_SIDEBAR_WIDTH[isCompact ? "xs" : "md"] - 40 - 2) / 2;
    const labelLineHeight = isCompact ? 16 : 18;
    const pages = book.pages;

    const spreads = useSpreads(pages.length);

    const [visibleSpreads, setVisibleSpreads] = useState<Set<number>>(
        () => new Set([0, 1, 2, 3, 4, 5, 6, 7]),
    );
    const stripElsRef = useRef<Map<number, Element>>(new Map());
    const stripObserverRef = useRef<IntersectionObserver | null>(null);

    useEffect(() => {
        const root = scrollRef.current;
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
    }, [scrollRef, spreads.length]);

    const stripSpreadRefs = useMemo(
        () =>
            spreads.map((_, idx): RefCallback<HTMLDivElement> => (el) => {
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
            }),
        [spreads],
    );

    return (
        <Box
            ref={scrollRef}
            sx={{
                width: "100%",
                display: "flex",
                flexDirection: "column",
                py: 3,
                flex: 1,
                minHeight: 0,
                overflowX: "hidden",
                overflowY: "auto",
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
                    alignItems: "flex-start",
                    gap: 3,
                }}
            >
                {spreads.map((spread, spreadIdx) => (
                    <Box
                        key={spreadIdx}
                        ref={stripSpreadRefs[spreadIdx]}
                        data-strip-spread-index={spreadIdx}
                        role="button"
                        tabIndex={0}
                        aria-label={`Go to ${getSpreadLabel(spread, pages.length)}`}
                        onClick={() => onSpreadClick?.(spreadIdx)}
                        onKeyDown={(event) => {
                            if (event.key === "Enter" || event.key === " ") {
                                event.preventDefault();
                                onSpreadClick?.(spreadIdx);
                            }
                        }}
                        sx={{
                            cursor: "pointer",
                            width: thumbnailWidth * 2 + 2,
                            ml: 2.5,
                            display: "grid",
                            gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
                            gap: "2px",
                            minHeight: thumbnailWidth + labelLineHeight + 4,
                            "&:hover .page-strip-thumbnail": {
                                transform: "translateY(-2px)",
                                boxShadow:
                                    "0 0 0 1px rgba(255,255,255,0.18), 0 6px 12px rgba(0,0,0,0.3)",
                            },
                            "&:focus-visible": { outline: "none" },
                            "&:focus-visible .page-strip-thumbnail": {
                                outline: `2px solid ${uiColors.text}`,
                                outlineOffset: 2,
                            },
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
                                            gridColumn: side === "left" ? 1 : 2,
                                        }}
                                    >
                                        <Box
                                            className="page-strip-thumbnail"
                                            aria-label={
                                                entry === "printer-blank"
                                                    ? "Blank page (required)"
                                                    : undefined
                                            }
                                            sx={{
                                                width: thumbnailWidth,
                                                height: thumbnailWidth,
                                                bgcolor: uiColors.paper,
                                                boxShadow: thumbnailShadow,
                                                borderRadius: 0.5,
                                                overflow: "hidden",
                                                transition:
                                                    "transform 120ms ease, box-shadow 120ms ease",
                                                "@media (prefers-reduced-motion: reduce)":
                                                    { transition: "none" },
                                            }}
                                        >
                                            {page && pageIndex !== null && (
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
                                            )}
                                        </Box>
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

export default memo(PageStrip);
