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
import { Box, IconButton, useMediaQuery } from "@mui/material";
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
import { SINGLE_PAGE_QUERY } from "./editorLayout";
import { ChevronLeftIcon, ChevronRightIcon } from "./icons";
import PageCanvas from "./PageCanvas";
import PrinterBlankPage from "./PrinterBlankPage";

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
        const singlePage = useMediaQuery(SINGLE_PAGE_QUERY);
        const swipeStart = useRef<{ x: number; y: number } | null>(null);
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
                                width / (singlePage ? 1 : 2),
                                Math.max(1, height - PAGE_NAVIGATION_SPACE),
                                1200,
                            ) * (singlePage ? 1 : 0.768),
                        ),
                    ),
                );
            };
            measure();
            const observer = new ResizeObserver(measure);
            observer.observe(container);
            return () => observer.disconnect();
        }, [singlePage]);

        const showMobilePage = useCallback(
            (index: number) => {
                const next = Math.max(0, Math.min(index, flipPages.length - 1));
                setCurrentPage(next);
                const pageIndex = flipPages[next]?.pageIndex;
                if (pageIndex !== null && pageIndex !== undefined)
                    startPageRef.current = pageIndex;
                onSpreadChangeRef.current(flipPages[next]?.spreadIndex ?? 0);
            },
            [flipPages],
        );

        const flipNext = useCallback(() => {
            if (singlePage) {
                showMobilePage(currentPage + 1);
                return;
            }
            const book = pageFlipRef.current;
            if (book?.getState() === "read") book.flipNext("bottom");
        }, [singlePage, showMobilePage, currentPage]);
        const flipPrev = useCallback(() => {
            if (singlePage) {
                showMobilePage(currentPage - 1);
                return;
            }
            const book = pageFlipRef.current;
            if (book?.getState() === "read") book.flipPrev("bottom");
        }, [singlePage, showMobilePage, currentPage]);
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
            if (singlePage) {
                showMobilePage(
                    getFlipPageIndex(
                        pages.length,
                        Math.min(startPageRef.current, pages.length - 1),
                        binding,
                    ) ?? 0,
                );
                return;
            }
            const mount = mountRef.current;
            if (!mount || flipPages.length === 0) return;

            const root = document.createElement("div");
            root.className = "book-preview-root";
            const elements = flipPages.map(({ pageIndex }, index) => {
                const element = document.createElement("div");
                element.className = "book-preview-page";
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

            const requestedPage = startPageRef.current;
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
                drawShadow: false,
                showPageCorners: false,
                usePortrait: false,
            });
            book.on("flip", (event: { data: number }) => {
                const indices = getSpreadPageIndices(
                    spreads[flipPages[event.data]?.spreadIndex ?? 0]!,
                );
                if (!indices.includes(startPageRef.current))
                    startPageRef.current =
                        indices[0] ??
                        (event.data < flipPages.length / 2
                            ? 0
                            : pages.length - 1);
                setCurrentPage(event.data);
                onSpreadChangeRef.current(
                    flipPages[event.data]?.spreadIndex ?? 0,
                );
            });
            book.on("changeState", (event: { data: string }) => {
                setTurning(event.data !== "read");
            });
            book.loadFromHTML(elements);
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
            startPageRef.current = requestedPage;
            pageFlipRef.current = book;
            setPageElements(elements);
            setCurrentPage(book.getCurrentPageIndex());
            setTurning(false);

            return () => {
                const index = book.getCurrentPageIndex();
                const indices = getSpreadPageIndices(
                    spreads[flipPages[index]?.spreadIndex ?? 0]!,
                );
                if (!indices.includes(startPageRef.current))
                    startPageRef.current =
                        indices[0] ??
                        (index < flipPages.length / 2 ? 0 : pages.length - 1);
                pageFlipRef.current = null;
                restoreCoverDrawing?.();
                book.destroy();
            };
        }, [
            flipPages,
            spreads,
            binding,
            pages.length,
            singlePage,
            showMobilePage,
        ]);

        useLayoutEffect(() => {
            if (!singlePage) pageFlipRef.current?.update();
        }, [pageSize, singlePage]);

        const frontCover = currentPage === 0 && flipPages.length > 1;
        const backCover = currentPage === flipPages.length - 1;
        const closed = frontCover || backCover;
        const showSpread = !closed || turning;
        const shift = turning ? 0 : frontCover ? "-25%" : backCover ? "25%" : 0;

        if (singlePage) {
            const entry = flipPages[currentPage];
            const page =
                entry?.pageIndex != null ? pages[entry.pageIndex] : null;
            const navigationPages = flipPages.map(({ pageIndex }) => ({
                left: pageIndex ?? ("printer-blank" as const),
                right: null,
            }));
            return (
                <Box
                    ref={containerRef}
                    data-binding={binding}
                    sx={{
                        flex: 1,
                        minWidth: 0,
                        minHeight: 0,
                        my: 2,
                        position: "relative",
                    }}
                >
                    <Box
                        sx={{
                            position: "absolute",
                            top: "50%",
                            left: "50%",
                            transform: "translate(-50%, -50%)",
                            width: pageSize,
                            maxWidth: "100%",
                        }}
                    >
                        <Box
                            aria-label={
                                page
                                    ? entry?.pageIndex === 0
                                        ? "Front cover"
                                        : entry?.pageIndex === pages.length - 1
                                          ? "Back cover"
                                          : `Page ${entry?.pageIndex}`
                                    : "Blank page (required)"
                            }
                            onPointerDown={(event) => {
                                if (event.button !== 0) return;
                                swipeStart.current = {
                                    x: event.clientX,
                                    y: event.clientY,
                                };
                                event.currentTarget.setPointerCapture(
                                    event.pointerId,
                                );
                            }}
                            onPointerUp={(event) => {
                                const start = swipeStart.current;
                                swipeStart.current = null;
                                if (!start) return;
                                const dx = event.clientX - start.x;
                                if (
                                    Math.abs(dx) > 45 &&
                                    Math.abs(dx) >
                                        Math.abs(event.clientY - start.y)
                                ) {
                                    if (dx < 0) flipNext();
                                    else flipPrev();
                                }
                            }}
                            onPointerCancel={() => {
                                swipeStart.current = null;
                            }}
                            sx={{ touchAction: "pan-y pinch-zoom" }}
                        >
                            {page ? (
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
                                            isFrontCover={
                                                entry?.pageIndex === 0
                                            }
                                            isBackCover={
                                                entry?.pageIndex ===
                                                pages.length - 1
                                            }
                                        />
                                    </Layer>
                                </Stage>
                            ) : (
                                <PrinterBlankPage
                                    width={pageSize}
                                    height={pageSize}
                                    showLabel
                                />
                            )}
                        </Box>
                        <Box
                            sx={{
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "center",
                                gap: 1,
                                mt: 3,
                            }}
                        >
                            <IconButton
                                aria-label="Previous page"
                                disabled={currentPage === 0}
                                onClick={flipPrev}
                                sx={{ width: 44, height: 44 }}
                            >
                                <ChevronLeftIcon />
                            </IconButton>
                            <BookPageNavigation
                                pageCount={pages.length}
                                spreads={navigationPages}
                                spreadIndex={currentPage}
                                disabled={flipPages.length === 0}
                                turning={false}
                                onGoToSpread={showMobilePage}
                            />
                            <IconButton
                                aria-label="Next page"
                                disabled={currentPage >= flipPages.length - 1}
                                onClick={flipNext}
                                sx={{ width: 44, height: 44 }}
                            >
                                <ChevronRightIcon />
                            </IconButton>
                        </Box>
                    </Box>
                </Box>
            );
        }

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
                    "& .book-preview-page": {
                        backgroundColor: uiColors.paper,
                        overflow: "hidden",
                        "&[data-spine-edge]::after": {
                            content: '""',
                            position: "absolute",
                            top: 0,
                            bottom: 0,
                            width: 6,
                            zIndex: 1,
                            pointerEvents: "none",
                        },
                        '&[data-spine-edge="left"]::after': {
                            left: 0,
                            background:
                                "linear-gradient(to right, rgba(0, 0, 0, 0.09), transparent)",
                        },
                        '&[data-spine-edge="right"]::after': {
                            right: 0,
                            background:
                                "linear-gradient(to left, rgba(0, 0, 0, 0.09), transparent)",
                        },
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
