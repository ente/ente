import { useBook } from "@/context/book";
import { availablePhotoSpaces } from "@/lib/photoPlacement";
import { useCallback, useRef, useState } from "react";
import type { useAutoScroll } from "./useAutoScroll";

export interface DragInfo {
    pageId: string;
    slotId: string;
}

export function usePhotoDrag(
    containerRef: React.RefObject<HTMLElement | null>,
    autoScroll: ReturnType<typeof useAutoScroll>,
) {
    const { thumbnailUrls, swapPhotos, movePhotoToPage, book } = useBook();
    const pages = book.pages;

    const [dragSourceInfo, setDragSourceInfo] = useState<DragInfo | null>(null);
    const dragSourceRef = useRef<DragInfo | null>(null);
    const [dragOverInfo, setDragOverInfo] = useState<DragInfo | null>(null);
    const dragOverRef = useRef<DragInfo | null>(null);
    const [dragOverPageId, setDragOverPageId] = useState<string | null>(null);
    const dragOverPageRef = useRef<string | null>(null);
    const dragGhostRef = useRef<HTMLCanvasElement>(null);

    const handleDragStart = useCallback(
        (
            e: React.DragEvent,
            pageId: string,
            slotId: string,
            photoId: string,
        ) => {
            const source = { pageId, slotId };
            dragSourceRef.current = source;
            setDragSourceInfo(source);
            e.dataTransfer.effectAllowed = "move";
            e.dataTransfer.setData(
                "text/plain",
                JSON.stringify({ pageId, slotId }),
            );
            // Create a small drag ghost from the thumbnail
            const thumbUrl = thumbnailUrls.get(photoId);
            if (thumbUrl && dragGhostRef.current) {
                const canvas = dragGhostRef.current;
                const ctx = canvas.getContext("2d");
                const img = new window.Image();
                img.src = thumbUrl;
                const size = 200;
                canvas.width = size;
                canvas.height = size;
                if (ctx) {
                    const aspect = img.naturalWidth / img.naturalHeight || 1;
                    const dw = aspect >= 1 ? size : size * aspect;
                    const dh = aspect >= 1 ? size / aspect : size;
                    ctx.clearRect(0, 0, size, size);
                    ctx.drawImage(
                        img,
                        (size - dw) / 2,
                        (size - dh) / 2,
                        dw,
                        dh,
                    );
                }
                e.dataTransfer.setDragImage(canvas, size / 2, size / 2);
            }

            // Fallback cleanup: the source SpreadPage can unmount mid-drag due to
            // virtualization (NEIGHBORHOOD_RADIUS + IntersectionObserver trimming).
            // When that happens, React's onDragEnd never fires on the detached slot
            // div, so autoScroll.stop() is never called and dragOverPageId stays set —
            // leaving the rAF loop pulling the viewport back to the last edge position
            // and the green overlay stuck. Window-level listeners run regardless of
            // which element (or no element) the drop/dragend targeted, and are
            // idempotent when the normal React handlers already cleaned up.
            const onGlobalEnd = () => {
                autoScroll.stop();
                dragSourceRef.current = null;
                dragOverRef.current = null;
                dragOverPageRef.current = null;
                setDragSourceInfo(null);
                setDragOverInfo(null);
                setDragOverPageId(null);
                window.removeEventListener("dragend", onGlobalEnd);
                window.removeEventListener("drop", onGlobalEnd);
            };
            window.addEventListener("dragend", onGlobalEnd);
            window.addEventListener("drop", onGlobalEnd);
        },
        [thumbnailUrls, autoScroll],
    );

    const handleSlotDragOver = useCallback(
        (e: React.DragEvent, pageId: string, slotId: string) => {
            e.preventDefault();
            // Deliberately DO NOT stopPropagation here: the outer scroll container's
            // onDragOver (handleContainerDragOver) is the only place auto-scroll
            // speed gets computed, and slot overlay divs cover almost the whole page.
            // Stopping propagation here meant dragging anywhere over slots near the
            // top/bottom edge never triggered auto-scroll. The page-level drop zone
            // is a sibling of the slot (not an ancestor), so letting the event bubble
            // does not cause duplicate page-drop handling.
            e.dataTransfer.dropEffect = "move";
            // Only update state when the target actually changes
            const cur = dragOverRef.current;
            if (cur?.pageId !== pageId || cur.slotId !== slotId) {
                const info = { pageId, slotId };
                dragOverRef.current = info;
                setDragOverInfo(info);
            }
            // Clear page-level highlight when on a slot
            if (dragOverPageRef.current !== null) {
                dragOverPageRef.current = null;
                setDragOverPageId(null);
            }
        },
        [],
    );

    const handleDrop = useCallback(
        (e: React.DragEvent, toPageId: string, toSlotId: string) => {
            e.preventDefault();
            e.stopPropagation();
            autoScroll.stop();
            dragOverRef.current = null;
            setDragOverInfo(null);
            dragOverPageRef.current = null;
            setDragOverPageId(null);
            const source = dragSourceRef.current;
            if (source) {
                const { pageId: fromPageId, slotId: fromSlotId } = source;
                if (fromPageId !== toPageId || fromSlotId !== toSlotId) {
                    swapPhotos(fromPageId, fromSlotId, toPageId, toSlotId);
                }
                dragSourceRef.current = null;
                setDragSourceInfo(null);
            }
        },
        [swapPhotos, autoScroll],
    );

    const handlePageDragOver = useCallback(
        (e: React.DragEvent, pageId: string) => {
            e.preventDefault();
            const isBackCover = pages.at(-1)?.id === pageId;
            const toPage = pages.find((p) => p.id === pageId);
            const hasRoom =
                !isBackCover &&
                toPage &&
                availablePhotoSpaces(toPage, pages[0]?.id === pageId) > 0;
            e.dataTransfer.dropEffect = hasRoom ? "move" : "none";
            // Clear slot-level highlight when hovering page background
            const cur = dragOverRef.current;
            if (cur !== null) {
                dragOverRef.current = null;
                setDragOverInfo(null);
            }
            // Set page-level highlight (only for cross-page drops on pages with room)
            const source = dragSourceRef.current;
            if (source && source.pageId !== pageId && !isBackCover) {
                if (hasRoom) {
                    if (dragOverPageRef.current !== pageId) {
                        dragOverPageRef.current = pageId;
                        setDragOverPageId(pageId);
                    }
                } else if (dragOverPageRef.current !== null) {
                    dragOverPageRef.current = null;
                    setDragOverPageId(null);
                }
            } else if (dragOverPageRef.current !== null) {
                dragOverPageRef.current = null;
                setDragOverPageId(null);
            }
        },
        [pages],
    );

    const handlePageDrop = useCallback(
        (e: React.DragEvent, toPageId: string) => {
            e.preventDefault();
            autoScroll.stop();
            dragOverRef.current = null;
            setDragOverInfo(null);
            dragOverPageRef.current = null;
            setDragOverPageId(null);
            const source = dragSourceRef.current;
            if (source) {
                const { pageId: fromPageId, slotId: fromSlotId } = source;
                if (fromPageId !== toPageId && toPageId !== pages.at(-1)?.id) {
                    // Cross-page drop on empty area: move photo to target page
                    const toPage = pages.find((p) => p.id === toPageId);
                    if (
                        toPage &&
                        availablePhotoSpaces(
                            toPage,
                            pages[0]?.id === toPageId,
                        ) > 0
                    ) {
                        movePhotoToPage(fromPageId, fromSlotId, toPageId);
                    }
                }
                dragSourceRef.current = null;
                setDragSourceInfo(null);
            }
        },
        [pages, movePhotoToPage, autoScroll],
    );

    const handleDragEnd = useCallback(() => {
        autoScroll.stop();
        dragSourceRef.current = null;
        dragOverRef.current = null;
        dragOverPageRef.current = null;
        setDragSourceInfo(null);
        setDragOverInfo(null);
        setDragOverPageId(null);
    }, [autoScroll]);

    const handleContainerDragOver = useCallback(
        (e: React.DragEvent) => {
            e.preventDefault();
            e.dataTransfer.dropEffect = "move";

            // Auto-scroll when dragging near top/bottom edges
            const el = containerRef.current;
            if (!el) return;
            const rect = el.getBoundingClientRect();
            const edgeZone = 120;
            const maxSpeed = 30;
            const distFromTop = e.clientY - rect.top;
            const distFromBottom = rect.bottom - e.clientY;

            if (distFromTop < edgeZone) {
                autoScroll.speed.current = -Math.round(
                    maxSpeed * (1 - distFromTop / edgeZone),
                );
                autoScroll.start();
            } else if (distFromBottom < edgeZone) {
                autoScroll.speed.current = Math.round(
                    maxSpeed * (1 - distFromBottom / edgeZone),
                );
                autoScroll.start();
            } else {
                autoScroll.speed.current = 0;
            }
        },
        [containerRef, autoScroll],
    );

    return {
        dragSourceInfo,
        dragOverInfo,
        dragOverPageId,
        handleDragStart,
        handleSlotDragOver,
        handleDrop,
        handlePageDragOver,
        handlePageDrop,
        handleDragEnd,
        handleContainerDragOver,
        dragGhostRef,
    };
}
