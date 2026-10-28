"use client";

import { useBook } from "@/context/book";
import { getPrintBinding } from "@/lib/printProducts";
import { clipSoftcoverInsidePages } from "@/lib/softcoverPreview";
import {
    getFlipPageIndex,
    getFlipPages,
    getSpreadPageIndices,
    getSpreads,
} from "@/lib/spreads";
import type { BookPage } from "@/lib/types";
import { uiColors } from "@/theme/colors";
import { Box, IconButton } from "@mui/material";
import { PageFlip } from "page-flip";
import {
    forwardRef,
    useCallback,
    useEffect,
    useImperativeHandle,
    useLayoutEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import { createPortal } from "react-dom";
import { Layer, Stage } from "react-konva";
import BookPageNavigation from "./BookPageNavigation";
import styles from "./BookViewer.module.css";
import { ChevronLeftIcon, ChevronRightIcon } from "./icons";
import PageCanvas from "./PageCanvas";

const PAGE_NAVIGATION_SPACE = 72;

const navigationButtonSx = {
    position: "absolute",
    top: 0,
    transform: "translateY(-50%)",
    pointerEvents: "auto",
    width: { xs: 40, sm: 48 },
    height: { xs: 40, sm: 48 },
    color: uiColors.text,
    bgcolor: uiColors.control,
    "&:hover": { bgcolor: uiColors.controlHover },
    "&.Mui-disabled": { opacity: 0.3 },
} as const;

export interface BookViewerHandle {
    flipNext: () => void;
    flipPrev: () => void;
}

interface BookViewerProps {
    pages: BookPage[];
    onSpreadChange: (spreadIndex: number) => void;
}

const BookViewer = forwardRef<BookViewerHandle, BookViewerProps>(
    function BookViewer({ pages, onSpreadChange }, ref) {
        const { book: bookState, photoUrls, loadPreviews } = useBook();
        const binding = getPrintBinding(bookState.printSelection);
        const flipPages = useMemo(
            () => getFlipPages(pages.length, binding),
            [pages.length, binding],
        );
        const spreads = useMemo(
            () => getSpreads(pages.length, binding),
            [pages.length, binding],
        );
        const containerRef = useRef<HTMLDivElement>(null);
        const mountRef = useRef<HTMLDivElement>(null);
        const pageFlipRef = useRef<PageFlip | null>(null);
        const [pageElements, setPageElements] = useState<HTMLElement[]>([]);
        const [pageSize, setPageSize] = useState(1);
        const [currentPage, setCurrentPage] = useState(0);
        const [turning, setTurning] = useState(false);
        const onSpreadChangeRef = useRef(onSpreadChange);
        onSpreadChangeRef.current = onSpreadChange;
        const startPageRef = useRef(0);

        const allPhotoIds = useMemo(
            () => [
                ...new Set(
                    pages.flatMap((page) =>
                        page.slots.flatMap((slot) =>
                            slot.photoId ? [slot.photoId] : [],
                        ),
                    ),
                ),
            ],
            [pages],
        );
        useEffect(() => {
            if (allPhotoIds.length > 0)
                void loadPreviews(allPhotoIds).catch((error: unknown) =>
                    console.error("Failed to load previews", error),
                );
        }, [allPhotoIds, loadPreviews]);

        // Measure the space remaining after the responsive navigation margins.
        // Observe the container, since panel changes need not resize the window.
        useLayoutEffect(() => {
            const container = containerRef.current;
            if (!container) return;
            const measure = () => {
                const { width, height } = container.getBoundingClientRect();
                setPageSize(
                    Math.max(
                        1,
                        Math.floor(
                            Math.min(
                                width / 2,
                                Math.max(1, height - PAGE_NAVIGATION_SPACE),
                                1200,
                            ) * 0.768,
                        ),
                    ),
                );
            };
            measure();
            const observer = new ResizeObserver(measure);
            observer.observe(container);
            return () => observer.disconnect();
        }, []);

        const flipNext = useCallback(() => {
            const book = pageFlipRef.current;
            if (book?.getState() === "read") book.flipNext("bottom");
        }, []);
        const flipPrev = useCallback(() => {
            const book = pageFlipRef.current;
            if (book?.getState() === "read") book.flipPrev("bottom");
        }, []);
        useImperativeHandle(ref, () => ({ flipNext, flipPrev }), [
            flipNext,
            flipPrev,
        ]);

        const goToSpread = useCallback(
            (spreadIndex: number) => {
                const book = pageFlipRef.current;
                const physicalIndex = flipPages.findIndex(
                    (page) => page.spreadIndex === spreadIndex,
                );
                if (book?.getState() === "read" && physicalIndex >= 0)
                    book.turnToPage(physicalIndex);
            },
            [flipPages],
        );

        useEffect(() => {
            const mount = mountRef.current;
            if (!mount || flipPages.length === 0) return;

            // PageFlip moves pages and removes its root on destroy. Give it its own
            // DOM subtree; portals keep React's canvas content attached to those pages.
            const root = document.createElement("div");
            root.className = "book-preview-root";
            const elements = flipPages.map(({ pageIndex }, index) => {
                const element = document.createElement("div");
                element.className = `book-preview-page ${styles.page}`;
                if (index > 0 && index < flipPages.length - 1) {
                    element.dataset.spineEdge =
                        index % 2 === 0 ? "left" : "right";
                }
                element.dataset.density =
                    binding === "Hardcover" &&
                    (index < 2 || index >= flipPages.length - 2)
                        ? "hard"
                        : "soft";
                if (pageIndex === null)
                    element.setAttribute("aria-label", "Blank page (required)");
                root.appendChild(element);
                return element;
            });
            mount.appendChild(root);

            const book = new PageFlip(root, {
                width: 600,
                height: 600,
                size: "stretch",
                minWidth: 1,
                minHeight: 1,
                maxWidth: 1200,
                maxHeight: 1200,
                autoSize: false,
                showCover: true,
                mobileScrollSupport: true,
                flippingTime: 450,
                useMouseEvents: true,
                swipeDistance: 30,
                startPage:
                    getFlipPageIndex(
                        pages.length,
                        Math.min(startPageRef.current, pages.length - 1),
                        binding,
                    ) ?? 0,
                // Page-local gutter shading follows the paper's clipping and stacking.
                // Keep the library's changing turn shadows from doubling its strength.
                drawShadow: false,
                showPageCorners: false,
                // Preserve paired spreads at every size. Portrait mode clones DOM
                // pages, which cannot copy the bitmap contents of our Konva canvases.
                usePortrait: false,
            });
            book.on("flip", (event: { data: number }) => {
                startPageRef.current =
                    getSpreadPageIndices(
                        spreads[flipPages[event.data]?.spreadIndex ?? 0]!,
                    )[0] ??
                    (event.data < flipPages.length / 2 ? 0 : pages.length - 1);
                setCurrentPage(event.data);
                onSpreadChangeRef.current(
                    flipPages[event.data]?.spreadIndex ?? 0,
                );
            });
            book.on("changeState", (event: { data: string }) => {
                setTurning(event.data !== "read");
            });
            book.loadFromHTML(elements);
            // showCover forces rigid covers; restore the selected density on both sides.
            elements.forEach((element, index) =>
                book
                    .getPage(index)
                    .setDensity(element.dataset.density as "hard" | "soft"),
            );
            const restoreCoverDrawing =
                binding === "Softcover"
                    ? clipSoftcoverInsidePages(book)
                    : undefined;
            book.update();
            pageFlipRef.current = book;
            setPageElements(elements);
            setCurrentPage(book.getCurrentPageIndex());
            setTurning(false);

            return () => {
                const index = book.getCurrentPageIndex();
                startPageRef.current =
                    getSpreadPageIndices(
                        spreads[flipPages[index]?.spreadIndex ?? 0]!,
                    )[0] ??
                    (index < flipPages.length / 2 ? 0 : pages.length - 1);
                pageFlipRef.current = null;
                restoreCoverDrawing?.();
                book.destroy();
            };
        }, [flipPages, spreads, binding, pages.length]);

        // Stretch updates the existing instance and preserves the current spread.
        useLayoutEffect(() => {
            pageFlipRef.current?.update();
        }, [pageSize]);

        const frontCover = currentPage === 0 && flipPages.length > 1;
        const backCover = currentPage === flipPages.length - 1;
        const closed = frontCover || backCover;
        const showSpread = !closed || turning;
        const shift = turning ? 0 : frontCover ? "-25%" : backCover ? "25%" : 0;

        return (
            <Box
                ref={containerRef}
                data-binding={binding}
                sx={{
                    flex: 1,
                    minWidth: 0,
                    minHeight: 0,
                    position: "relative",
                    mx: { xs: 0, sm: 7 },
                    my: 3,
                    "& .book-preview-root, & .book-preview-mount": {
                        width: "100%",
                        height: "100%",
                    },
                    // PageFlip replaces style.cssText on every frame. Paper appearance
                    // must stay in CSS, including blanks that have no canvas background.
                    "& .book-preview-page": {
                        backgroundColor: uiColors.paper,
                        overflow: "hidden",
                    },
                }}
            >
                <Box
                    sx={{
                        position: "absolute",
                        left: "50%",
                        top: "50%",
                        width: pageSize * 2,
                        height: pageSize + PAGE_NAVIGATION_SPACE,
                        transform: "translate(-50%, -50%)",
                    }}
                >
                    <Box
                        sx={{
                            width: "100%",
                            height: pageSize,
                            transform: `translateX(${shift})`,
                            transition: "transform 300ms ease",
                            "@media (prefers-reduced-motion: reduce)": {
                                transition: "none",
                            },
                        }}
                    >
                        <div ref={mountRef} className="book-preview-mount" />
                    </Box>
                    <Box
                        sx={{
                            position: "absolute",
                            left: "50%",
                            top: pageSize / 2,
                            // Percentages stay constant during initial measurement and resizing,
                            // so only opening or closing the book animates the arrow spacing.
                            width: showSpread ? "100%" : "50%",
                            height: 0,
                            transform: "translate(-50%, -50%)",
                            transition: "width 300ms ease",
                            "@media (prefers-reduced-motion: reduce)": {
                                transition: "none",
                            },
                            zIndex: 20,
                            pointerEvents: "none",
                        }}
                    >
                        <IconButton
                            aria-label="Previous pages"
                            onClick={flipPrev}
                            disabled={
                                currentPage === 0 ||
                                turning ||
                                flipPages.length === 0
                            }
                            sx={{
                                ...navigationButtonSx,
                                right: "100%",
                                mr: { xs: 1, sm: 3 },
                            }}
                        >
                            <ChevronLeftIcon
                                sx={{ fontSize: { xs: 28, sm: 32 } }}
                            />
                        </IconButton>
                        <IconButton
                            aria-label="Next pages"
                            onClick={flipNext}
                            disabled={
                                currentPage >= flipPages.length - 1 || turning
                            }
                            sx={{
                                ...navigationButtonSx,
                                left: "100%",
                                ml: { xs: 1, sm: 3 },
                            }}
                        >
                            <ChevronRightIcon
                                sx={{ fontSize: { xs: 28, sm: 32 } }}
                            />
                        </IconButton>
                    </Box>
                    <Box
                        sx={{
                            position: "absolute",
                            top: pageSize + 24,
                            left: "50%",
                            transform: "translateX(-50%)",
                        }}
                    >
                        <BookPageNavigation
                            pageCount={pages.length}
                            spreads={spreads}
                            spreadIndex={
                                flipPages[currentPage]?.spreadIndex ?? 0
                            }
                            disabled={pageElements.length === 0}
                            turning={turning}
                            onGoToSpread={goToSpread}
                        />
                    </Box>
                </Box>
                {flipPages.map(({ pageIndex, spreadIndex }, index) => {
                    const element = pageElements.at(index);
                    const page = pageIndex === null ? null : pages[pageIndex];
                    if (!element || !page) return null;
                    return createPortal(
                        <Stage
                            width={pageSize}
                            height={pageSize}
                            listening={false}
                        >
                            <Layer>
                                <PageCanvas
                                    page={page}
                                    photoUrls={photoUrls}
                                    pageWidth={pageSize}
                                    pageHeight={pageSize}
                                    isBackCover={pageIndex === pages.length - 1}
                                    isFrontCover={pageIndex === 0}
                                />
                            </Layer>
                        </Stage>,
                        element,
                        `${page.id}-${spreadIndex}`,
                    );
                })}
            </Box>
        );
    },
);

export default BookViewer;
