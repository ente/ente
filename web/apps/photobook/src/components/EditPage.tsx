"use client";

import { toolbarColors, uiColors } from "@/theme/colors";

import { useBook } from "@/context/book";
import {
    Alert,
    Backdrop,
    Box,
    CircularProgress,
    Snackbar,
    Typography,
} from "@mui/material";
import React, {
    useCallback,
    useEffect,
    useLayoutEffect,
    useMemo,
    useRef,
    useState,
    type RefCallback,
} from "react";
import AddPageDialog from "./AddPageDialog";
import AddPhotosDialog from "./AddPhotosDialog";
import BookBindingSelect from "./BookBindingSelect";
import BookHeader from "./BookHeader";
import EditorActions, { EditorPreviewButton } from "./EditorActions";
import EmptyBookState from "./EmptyBookState";
import type { PageInsertPosition } from "./PageMenu";
import PageStrip from "./PageStrip";
import PrinterBlankPage from "./PrinterBlankPage";
import SpreadPage, { PICKER_WIDTH } from "./SpreadPage";
import {
    EDITOR_CANVAS_PADDING,
    EDITOR_PANEL_BOTTOM_INSET,
    EDITOR_PANEL_INSET,
    EDITOR_PANEL_SX,
    EDITOR_SCROLLBAR_SX,
    EDITOR_SIDEBAR_WIDTH,
} from "./editorLayout";

import { useAutoScroll } from "@/hooks/useAutoScroll";
import { usePageDrag } from "@/hooks/usePageDrag";
import { usePhotoDrag } from "@/hooks/usePhotoDrag";
import { useSpreads } from "@/hooks/useSpreads";
import type { PhotoDestination } from "@/lib/photoPlacement";
import { getSpreadPageIndices } from "@/lib/spreads";
import type { TextBlock } from "@/lib/types";

const PAGE_GAP = 2;
// Spreads within this many rows of the current row are always mounted, on
// top of whatever the IntersectionObserver reports. This keeps the "about
// to be scrolled into" region warm so fast scrolls never reveal an
// unmounted dark row or a post-mount image decode flash.
const NEIGHBORHOOD_RADIUS = 4;

export default function EditPage() {
    const {
        book,
        currentSpreadIndex,
        setCurrentSpreadIndex,
        addPage,
        addPhotos,
        removeSlot,
        updateTextBlock,
        removeTextBlock,
        undo,
        redo,
        processingPhotos,
        processingProgress,
    } = useBook();

    // Selection state
    const [selectedSlotId, setSelectedSlotId] = useState<string | null>(null);
    const [selectedPageId, setSelectedPageId] = useState<string | null>(null);
    const [selectedTextId, setSelectedTextId] = useState<string | null>(null);

    // Inline text editing state
    const [editingTextId, setEditingTextId] = useState<string | null>(null);
    const [insertedPageId, setInsertedPageId] = useState<string | null>(null);
    const [addPageDialogOpen, setAddPageDialogOpen] = useState(false);
    const [pendingFiles, setPendingFiles] = useState<File[] | null>(null);
    const [photoImportError, setPhotoImportError] = useState<string | null>(
        null,
    );
    const [showPhotoImportProgress, setShowPhotoImportProgress] =
        useState(false);
    const pagePhotoImportBusy =
        processingPhotos && !pendingFiles && book.pages.length > 0;

    useEffect(() => {
        if (!pagePhotoImportBusy) {
            setShowPhotoImportProgress(false);
            return;
        }
        // Most page imports finish quickly; avoid flashing a loading panel for them.
        const timeout = window.setTimeout(
            () => setShowPhotoImportProgress(true),
            300,
        );
        return () => window.clearTimeout(timeout);
    }, [pagePhotoImportBusy]);

    // Refs
    const containerRef = useRef<HTMLDivElement>(null);
    const photoInputRef = useRef<HTMLInputElement>(null);
    const photoDestinationRef = useRef<string | undefined>(undefined);

    const [containerWidth, setContainerWidth] = useState(0);

    const pages = book.pages;
    const totalPages = pages.length;

    // Drag hooks
    const autoScroll = useAutoScroll(containerRef);
    const photoDrag = usePhotoDrag(containerRef, autoScroll);
    const pageDrag = usePageDrag();

    const spreads = useSpreads(pages.length);

    // Map the current page-based spread index (stored in context) to the row
    // index within `spreads`, so we can build a neighborhood window around it.
    const currentSpreadRow = useMemo(() => {
        const idx = spreads.findIndex(
            (s) =>
                s.left === currentSpreadIndex || s.right === currentSpreadIndex,
        );
        return idx >= 0 ? idx : 0;
    }, [spreads, currentSpreadIndex]);

    // Virtualization: only render visible spreads + buffer
    const [visibleSpreads, setVisibleSpreads] = useState<Set<number>>(
        () => new Set([0, 1, 2]),
    );
    const spreadElsRef = useRef<Map<number, Element>>(new Map());
    const observerRef = useRef<IntersectionObserver | null>(null);

    useEffect(() => {
        const root = containerRef.current;
        if (!root) return;

        const observer = new IntersectionObserver(
            (entries) => {
                setVisibleSpreads((prev) => {
                    const next = new Set(prev);
                    for (const entry of entries) {
                        const idx = Number(
                            (entry.target as HTMLElement).dataset.spreadIndex,
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
            // Generous margin so fast flings stay ahead of the viewport. Paired
            // with the NEIGHBORHOOD_RADIUS window below, this means a spread is
            // mounted well before it could possibly scroll into view.
            { root, rootMargin: "2000px 0px" },
        );
        observerRef.current = observer;

        // Observe all currently tracked elements
        spreadElsRef.current.forEach((el) => observer.observe(el));

        return () => {
            observer.disconnect();
            observerRef.current = null;
        };
    }, [spreads.length]);

    const spreadRefCallback = useCallback(
        (idx: number): RefCallback<HTMLDivElement> =>
            (el) => {
                const prev = spreadElsRef.current.get(idx);
                if (prev && observerRef.current)
                    observerRef.current.unobserve(prev);

                if (el) {
                    spreadElsRef.current.set(idx, el);
                    if (observerRef.current) observerRef.current.observe(el);
                } else {
                    spreadElsRef.current.delete(idx);
                }
            },
        [],
    );

    // Keyboard shortcuts for photo deletion and undo/redo.
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            const target = e.target;
            if (
                e.defaultPrevented ||
                e.isComposing ||
                processingPhotos ||
                (target instanceof HTMLElement &&
                    (target.isContentEditable ||
                        target.closest(
                            'input, textarea, select, [role="textbox"], [role="dialog"], [role="menu"], [role="listbox"], [role="combobox"]',
                        )))
            )
                return;
            if (
                (e.key === "Delete" || e.key === "Backspace") &&
                !e.metaKey &&
                !e.ctrlKey &&
                !e.altKey &&
                !e.shiftKey &&
                !e.repeat
            ) {
                const slot = pages
                    .find((page) => page.id === selectedPageId)
                    ?.slots.find((slot) => slot.id === selectedSlotId);
                if (selectedPageId && slot?.photoId) {
                    e.preventDefault();
                    removeSlot(selectedPageId, slot.id);
                    setSelectedSlotId(null);
                    setSelectedPageId(null);
                    setSelectedTextId(null);
                    setEditingTextId(null);
                }
                return;
            }
            if ((e.metaKey || e.ctrlKey) && e.key === "z") {
                e.preventDefault();
                if (e.shiftKey) {
                    redo();
                } else {
                    undo();
                }
            }
        };
        window.addEventListener("keydown", handleKeyDown);
        return () => window.removeEventListener("keydown", handleKeyDown);
    }, [
        undo,
        redo,
        processingPhotos,
        pages,
        selectedPageId,
        selectedSlotId,
        removeSlot,
    ]);

    // Measure before the first paint so restored books never show fallback-sized pages.
    useLayoutEffect(() => {
        const el = containerRef.current;
        if (!el) return;
        const measureWidth = () => setContainerWidth(el.clientWidth);
        measureWidth();
        const observer = new ResizeObserver(measureWidth);
        observer.observe(el);
        return () => observer.disconnect();
    }, []);

    // Calculate page dimensions based on container width (height is scrollable)
    const { pageWidth, pageHeight } = useMemo(() => {
        const availW =
            containerWidth -
            EDITOR_CANVAS_PADDING * 2 -
            PAGE_GAP -
            PICKER_WIDTH * 2;
        const size = Math.round(Math.max(200, Math.min(availW / 2, 500)));

        return { pageWidth: size, pageHeight: size };
    }, [containerWidth]);

    // Track the current spread at most once per animation frame.
    const scrollRafRef = useRef<number | null>(null);
    const handleMainScroll = useCallback(() => {
        if (scrollRafRef.current !== null) return;
        scrollRafRef.current = requestAnimationFrame(() => {
            scrollRafRef.current = null;
            const main = containerRef.current;
            if (!main) return;

            const maxMainScroll = main.scrollHeight - main.clientHeight;
            if (maxMainScroll <= 0) return;

            const fraction = main.scrollTop / maxMainScroll;

            // Update currentSpreadIndex based on visible spread
            const visibleIdx = Math.round(
                fraction * Math.max(0, spreads.length - 1),
            );
            const spread = spreads.at(visibleIdx);
            if (spread) {
                const newIndex =
                    getSpreadPageIndices(spread)[0] ??
                    (visibleIdx < spreads.length / 2 ? 0 : pages.length - 1);
                if (newIndex !== currentSpreadIndex) {
                    setCurrentSpreadIndex(newIndex);
                }
            }
        });
    }, [spreads, currentSpreadIndex, setCurrentSpreadIndex, pages.length]);

    // Cancel any pending scroll-handler frame on unmount.
    useEffect(() => {
        return () => {
            if (scrollRafRef.current !== null) {
                cancelAnimationFrame(scrollRafRef.current);
                scrollRafRef.current = null;
            }
        };
    }, []);

    // Scroll main area to a specific spread row (called from sidebar click)
    const handleSidebarSpreadClick = useCallback((spreadIdx: number) => {
        const main = containerRef.current;
        if (!main) return;
        const spreadEl = main.querySelector(
            `[data-spread-index="${spreadIdx}"]`,
        );
        if (spreadEl) {
            spreadEl.scrollIntoView({ behavior: "smooth", block: "center" });
        }
    }, []);

    // Selection handlers
    const handleSlotClick = useCallback((pageId: string, slotId: string) => {
        setSelectedSlotId(slotId);
        setSelectedPageId(pageId);
        setSelectedTextId(null);
    }, []);

    const handleTextClick = useCallback((pageId: string, textId: string) => {
        setSelectedTextId(textId);
        setSelectedPageId(pageId);
        setSelectedSlotId(null);
    }, []);

    const handleTextDblClick = useCallback((pageId: string, textId: string) => {
        setEditingTextId(textId);
        setSelectedTextId(textId);
        setSelectedPageId(pageId);
    }, []);

    const clearSelection = useCallback(() => {
        setSelectedSlotId(null);
        setSelectedPageId(null);
        setSelectedTextId(null);
        setEditingTextId(null);
    }, []);

    const handleWorkspaceClick = useCallback(
        (e: React.MouseEvent<HTMLDivElement>) => {
            // Pages handle their own photo, text, control and background clicks.
            if (!(e.target as Element).closest("[data-book-page]"))
                clearSelection();
        },
        [clearSelection],
    );

    const handleInsertPage = useCallback(
        (pageIndex: number, position: PageInsertPosition) => {
            clearSelection();
            const pageId = addPage(
                position === "before" ? pageIndex - 1 : pageIndex,
            );
            setInsertedPageId(pageId);
        },
        [addPage, clearSelection],
    );

    const handleAddPhotos = useCallback(
        (pageId?: string) => {
            const input = photoInputRef.current;
            if (!input || processingPhotos) return;
            setPhotoImportError(null);
            photoDestinationRef.current = pageId;
            input.multiple = !pageId || pageId !== pages[0]?.id;
            input.click();
        },
        [pages, processingPhotos],
    );

    const importPhotos = useCallback(
        async (files: File[], destination: PhotoDestination) => {
            const pageId = await addPhotos(files, {
                replace: pages.length === 0,
                destination,
            });
            clearSelection();
            if (pageId) setInsertedPageId(pageId);
        },
        [addPhotos, pages.length, clearSelection],
    );

    useEffect(() => {
        if (!insertedPageId) return;
        const pageIndex = pages.findIndex((page) => page.id === insertedPageId);
        if (pageIndex < 0) return;
        const spreadIndex = spreads.findIndex(
            (spread) => spread.left === pageIndex || spread.right === pageIndex,
        );
        // Spread rows stay mounted even when their page canvases are virtualized.
        const row = containerRef.current?.querySelector(
            `[data-spread-index="${spreadIndex}"]`,
        );
        if (!row) return;
        setCurrentSpreadIndex(pageIndex);
        row.scrollIntoView({ behavior: "smooth", block: "center" });
        setInsertedPageId(null);
    }, [insertedPageId, pages, spreads, setCurrentSpreadIndex]);

    const handleTextUpdate = useCallback(
        (pageId: string, blockId: string, updates: Partial<TextBlock>) => {
            updateTextBlock(pageId, blockId, updates);
        },
        [updateTextBlock],
    );

    const handleTextDelete = useCallback(
        (pageId: string, blockId: string) => {
            removeTextBlock(pageId, blockId);
            setSelectedTextId(null);
            setEditingTextId(null);
        },
        [removeTextBlock],
    );

    const handleTextEditEnd = useCallback(() => {
        setEditingTextId(null);
    }, []);

    return (
        <Box
            sx={{
                display: "flex",
                flexDirection: "column",
                height: "100dvh",
                px: EDITOR_PANEL_INSET,
                bgcolor: uiColors.background,
            }}
        >
            <BookHeader showBookControls={pages.length > 0}>
                <BookBindingSelect />
                <EditorPreviewButton />
            </BookHeader>

            <Box
                sx={{
                    display: "flex",
                    flex: 1,
                    minHeight: 0,
                    gap: EDITOR_PANEL_INSET,
                    mb: EDITOR_PANEL_BOTTOM_INSET,
                }}
            >
                <Box
                    component="aside"
                    id="book-pages-sidebar"
                    aria-label="Book pages"
                    sx={{
                        ...EDITOR_PANEL_SX,
                        borderRadius: "20px",
                        width: EDITOR_SIDEBAR_WIDTH,
                        display: pages.length > 0 ? "flex" : "none",
                        flexDirection: "column",
                        flexShrink: 0,
                        overflow: "hidden",
                    }}
                >
                    <PageStrip onSpreadClick={handleSidebarSpreadClick} />
                </Box>

                {/* Clip the scroll container to the island's rounded corners. */}
                <Box
                    component="main"
                    aria-label="Photobook editor"
                    sx={{
                        ...EDITOR_PANEL_SX,
                        bgcolor:
                            pages.length > 0
                                ? EDITOR_PANEL_SX.bgcolor
                                : "transparent",
                        borderRadius: "20px",
                        flex: 1,
                        minWidth: 0,
                        display: "flex",
                        flexDirection: "column",
                        overflow: "hidden",
                    }}
                >
                    <Box
                        ref={containerRef}
                        onScroll={handleMainScroll}
                        onClick={handleWorkspaceClick}
                        onDragOver={
                            pages.length > 0
                                ? photoDrag.handleContainerDragOver
                                : undefined
                        }
                        onDragEnd={photoDrag.handleDragEnd}
                        sx={{
                            flex: 1,
                            minWidth: 0,
                            minHeight: 0,
                            display: "flex",
                            flexDirection: "column",
                            overflow: "auto",
                            scrollbarGutter:
                                pages.length > 0 ? "stable" : "auto",
                            ...EDITOR_SCROLLBAR_SX,
                        }}
                    >
                        {pages.length === 0 ? (
                            <EmptyBookState />
                        ) : (
                            containerWidth > 0 && (
                                <Box
                                    sx={{
                                        display: "flex",
                                        flexDirection: "column",
                                        alignItems: "center",
                                        px: `${EDITOR_CANVAS_PADDING}px`,
                                        pt: 4,
                                        pb: {
                                            xs: "calc(144px + env(safe-area-inset-bottom))",
                                            sm: "calc(96px + env(safe-area-inset-bottom))",
                                        },
                                        gap: 3,
                                    }}
                                >
                                    {/* Spreads (virtualized: only visible spreads render full content) */}
                                    {spreads.map((spread, spreadIdx) => {
                                        // Union of the IntersectionObserver-reported visible set with a
                                        // fixed ±NEIGHBORHOOD_RADIUS window around the current spread
                                        // row, so rows immediately above and below the viewport stay
                                        // mounted during fast scrolls.
                                        const isVisible =
                                            visibleSpreads.has(spreadIdx) ||
                                            Math.abs(
                                                spreadIdx - currentSpreadRow,
                                            ) <= NEIGHBORHOOD_RADIUS;
                                        const leftIndex =
                                            typeof spread.left === "number"
                                                ? spread.left
                                                : null;
                                        const rightIndex =
                                            typeof spread.right === "number"
                                                ? spread.right
                                                : null;
                                        const lp =
                                            leftIndex !== null
                                                ? pages[leftIndex]
                                                : null;
                                        const rp =
                                            rightIndex !== null
                                                ? pages[rightIndex]
                                                : null;

                                        return (
                                            <Box
                                                key={spreadIdx}
                                                ref={spreadRefCallback(
                                                    spreadIdx,
                                                )}
                                                data-spread-index={spreadIdx}
                                                sx={{
                                                    display: "flex",
                                                    gap: `${PAGE_GAP}px`,
                                                    alignItems: "start",
                                                    width:
                                                        PICKER_WIDTH +
                                                        pageWidth * 2 +
                                                        PAGE_GAP +
                                                        PICKER_WIDTH,
                                                    justifyContent:
                                                        spread.left !== null
                                                            ? "flex-start"
                                                            : "flex-end",
                                                    minHeight: pageHeight,
                                                }}
                                            >
                                                {isVisible &&
                                                    spread.left ===
                                                        "printer-blank" && (
                                                        <Box
                                                            sx={{
                                                                pl: `${PICKER_WIDTH}px`,
                                                            }}
                                                        >
                                                            <PrinterBlankPage
                                                                width={
                                                                    pageWidth
                                                                }
                                                                height={
                                                                    pageHeight
                                                                }
                                                                showLabel
                                                            />
                                                        </Box>
                                                    )}
                                                {isVisible && lp && (
                                                    <SpreadPage
                                                        page={lp}
                                                        pageIndex={leftIndex!}
                                                        pickerSide="left"
                                                        pageWidth={pageWidth}
                                                        pageHeight={pageHeight}
                                                        totalPages={totalPages}
                                                        selectedSlotId={
                                                            selectedSlotId
                                                        }
                                                        selectedPageId={
                                                            selectedPageId
                                                        }
                                                        selectedTextId={
                                                            selectedTextId
                                                        }
                                                        editingTextId={
                                                            editingTextId
                                                        }
                                                        onSlotClick={
                                                            handleSlotClick
                                                        }
                                                        onTextClick={
                                                            handleTextClick
                                                        }
                                                        onTextDblClick={
                                                            handleTextDblClick
                                                        }
                                                        onTextUpdate={
                                                            handleTextUpdate
                                                        }
                                                        onTextDelete={
                                                            handleTextDelete
                                                        }
                                                        onTextEditEnd={
                                                            handleTextEditEnd
                                                        }
                                                        onClearSelection={
                                                            clearSelection
                                                        }
                                                        onInsertPage={
                                                            handleInsertPage
                                                        }
                                                        onAddPhotos={
                                                            handleAddPhotos
                                                        }
                                                        dragSourceInfo={
                                                            photoDrag.dragSourceInfo
                                                        }
                                                        dragOverInfo={
                                                            photoDrag.dragOverInfo
                                                        }
                                                        dragOverPageId={
                                                            photoDrag.dragOverPageId
                                                        }
                                                        onPhotoDragStart={
                                                            photoDrag.handleDragStart
                                                        }
                                                        onSlotDragOver={
                                                            photoDrag.handleSlotDragOver
                                                        }
                                                        onPhotoDrop={
                                                            photoDrag.handleDrop
                                                        }
                                                        onPhotoDragEnd={
                                                            photoDrag.handleDragEnd
                                                        }
                                                        onPageDragOver={
                                                            photoDrag.handlePageDragOver
                                                        }
                                                        onPageDrop={
                                                            photoDrag.handlePageDrop
                                                        }
                                                        pageDragSource={
                                                            pageDrag.pageDragSource
                                                        }
                                                        pageDragTarget={
                                                            pageDrag.pageDragTarget
                                                        }
                                                        pageDragSourceRef={
                                                            pageDrag.pageDragSourceRef
                                                        }
                                                        onPageDragStart={
                                                            pageDrag.handlePageDragStart
                                                        }
                                                        onPageDragOverPage={
                                                            pageDrag.handlePageDragOverPage
                                                        }
                                                        onPageDropOnPage={
                                                            pageDrag.handlePageDropOnPage
                                                        }
                                                        onPageDragEndCleanup={
                                                            pageDrag.handlePageDragEndCleanup
                                                        }
                                                    />
                                                )}
                                                {isVisible && rp && (
                                                    <SpreadPage
                                                        page={rp}
                                                        pageIndex={rightIndex!}
                                                        pickerSide="right"
                                                        pageWidth={pageWidth}
                                                        pageHeight={pageHeight}
                                                        totalPages={totalPages}
                                                        selectedSlotId={
                                                            selectedSlotId
                                                        }
                                                        selectedPageId={
                                                            selectedPageId
                                                        }
                                                        selectedTextId={
                                                            selectedTextId
                                                        }
                                                        editingTextId={
                                                            editingTextId
                                                        }
                                                        onSlotClick={
                                                            handleSlotClick
                                                        }
                                                        onTextClick={
                                                            handleTextClick
                                                        }
                                                        onTextDblClick={
                                                            handleTextDblClick
                                                        }
                                                        onTextUpdate={
                                                            handleTextUpdate
                                                        }
                                                        onTextDelete={
                                                            handleTextDelete
                                                        }
                                                        onTextEditEnd={
                                                            handleTextEditEnd
                                                        }
                                                        onClearSelection={
                                                            clearSelection
                                                        }
                                                        onInsertPage={
                                                            handleInsertPage
                                                        }
                                                        onAddPhotos={
                                                            handleAddPhotos
                                                        }
                                                        dragSourceInfo={
                                                            photoDrag.dragSourceInfo
                                                        }
                                                        dragOverInfo={
                                                            photoDrag.dragOverInfo
                                                        }
                                                        dragOverPageId={
                                                            photoDrag.dragOverPageId
                                                        }
                                                        onPhotoDragStart={
                                                            photoDrag.handleDragStart
                                                        }
                                                        onSlotDragOver={
                                                            photoDrag.handleSlotDragOver
                                                        }
                                                        onPhotoDrop={
                                                            photoDrag.handleDrop
                                                        }
                                                        onPhotoDragEnd={
                                                            photoDrag.handleDragEnd
                                                        }
                                                        onPageDragOver={
                                                            photoDrag.handlePageDragOver
                                                        }
                                                        onPageDrop={
                                                            photoDrag.handlePageDrop
                                                        }
                                                        pageDragSource={
                                                            pageDrag.pageDragSource
                                                        }
                                                        pageDragTarget={
                                                            pageDrag.pageDragTarget
                                                        }
                                                        pageDragSourceRef={
                                                            pageDrag.pageDragSourceRef
                                                        }
                                                        onPageDragStart={
                                                            pageDrag.handlePageDragStart
                                                        }
                                                        onPageDragOverPage={
                                                            pageDrag.handlePageDragOverPage
                                                        }
                                                        onPageDropOnPage={
                                                            pageDrag.handlePageDropOnPage
                                                        }
                                                        onPageDragEndCleanup={
                                                            pageDrag.handlePageDragEndCleanup
                                                        }
                                                    />
                                                )}
                                                {isVisible &&
                                                    spread.right ===
                                                        "printer-blank" && (
                                                        <Box
                                                            sx={{
                                                                pr: `${PICKER_WIDTH}px`,
                                                            }}
                                                        >
                                                            <PrinterBlankPage
                                                                width={
                                                                    pageWidth
                                                                }
                                                                height={
                                                                    pageHeight
                                                                }
                                                                showLabel
                                                            />
                                                        </Box>
                                                    )}
                                            </Box>
                                        );
                                    })}
                                </Box>
                            )
                        )}
                    </Box>
                </Box>
            </Box>

            {/* Keep mounted so the Reset dialog can finish closing after the book is emptied. */}
            <Box
                component="nav"
                aria-label="Photobook tools"
                sx={{
                    ...EDITOR_PANEL_SX,
                    "--toolbar-radius": "20px",
                    "--toolbar-inset": "6px",
                    bgcolor: toolbarColors.background,
                    display: pages.length > 0 ? "block" : "none",
                    position: "fixed",
                    left: "50%",
                    bottom: "calc(20px + env(safe-area-inset-bottom))",
                    transform: "translateX(-50%)",
                    width: "max-content",
                    maxWidth: "calc(100% - 32px)",
                    p: "var(--toolbar-inset)",
                    borderRadius: "var(--toolbar-radius)",
                    zIndex: 1200,
                    boxShadow: `inset 0 0 0 1px ${toolbarColors.border}, 0 8px 24px rgba(0,0,0,0.3)`,
                }}
            >
                <EditorActions
                    onAddPage={() => setAddPageDialogOpen(true)}
                    onAddPhotos={() => handleAddPhotos()}
                />
            </Box>

            <input
                ref={photoInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.heic,.heif"
                multiple
                style={{ display: "none" }}
                onChange={async (event) => {
                    const files = Array.from(event.currentTarget.files ?? []);
                    const pageId = photoDestinationRef.current;
                    event.currentTarget.value = "";
                    if (files.length === 0) return;
                    if (!pageId) {
                        setPendingFiles(files);
                        return;
                    }
                    try {
                        await importPhotos(files, { kind: "page", pageId });
                    } catch (error) {
                        setPhotoImportError(
                            error instanceof Error
                                ? error.message
                                : "Couldn't add these photos. Please try again.",
                        );
                    }
                }}
            />
            {pendingFiles && (
                <AddPhotosDialog
                    pages={pages}
                    photoCount={pendingFiles.length}
                    busy={processingPhotos}
                    progress={processingProgress}
                    onClose={() => setPendingFiles(null)}
                    onAdd={(destination) =>
                        importPhotos(pendingFiles, destination)
                    }
                />
            )}
            <Backdrop
                open={pagePhotoImportBusy}
                invisible={!showPhotoImportProgress}
                transitionDuration={0}
                sx={{ zIndex: (theme) => theme.zIndex.modal + 1 }}
            >
                {pagePhotoImportBusy && showPhotoImportProgress && (
                    <Box
                        role="status"
                        aria-live="polite"
                        sx={{
                            display: "flex",
                            alignItems: "center",
                            gap: 2,
                            bgcolor: uiColors.surface,
                            color: uiColors.text,
                            p: 3,
                            borderRadius: 3,
                        }}
                    >
                        <CircularProgress size={24} sx={{ color: "#08C225" }} />
                        <Typography>
                            Adding photos… {processingProgress}%
                        </Typography>
                    </Box>
                )}
            </Backdrop>
            <Snackbar
                open={!!photoImportError}
                onClose={() => setPhotoImportError(null)}
                anchorOrigin={{ vertical: "top", horizontal: "center" }}
            >
                <Alert
                    severity="error"
                    onClose={() => setPhotoImportError(null)}
                >
                    {photoImportError}
                </Alert>
            </Snackbar>

            {addPageDialogOpen && (
                <AddPageDialog
                    pages={pages}
                    initialPageId={
                        selectedPageId ?? pages[currentSpreadIndex]?.id
                    }
                    disabled={processingPhotos}
                    onClose={() => setAddPageDialogOpen(false)}
                    onInsert={handleInsertPage}
                />
            )}

            {/* Offscreen canvas for drag ghost */}
            <canvas
                ref={photoDrag.dragGhostRef}
                style={{ position: "fixed", left: -9999 }}
            />
        </Box>
    );
}
