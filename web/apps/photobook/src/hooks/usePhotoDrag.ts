import { useBook } from "@/context/book";
import { availablePhotoSpaces } from "@/lib/photoPlacement";
import { useCallback, useRef, useState } from "react";
import type { useAutoScroll } from "./useAutoScroll";

export interface DragInfo {
    pageId: string;
    slotId: string;
}

export type PhotoDropChoice = "add" | "swap" | "cancel";

export function usePhotoDrag(
    containerRef: React.RefObject<HTMLElement | null>,
    autoScroll: ReturnType<typeof useAutoScroll>,
    clearSelection: () => void,
) {
    const { thumbnailUrls, swapPhotos, movePhotoToPage, book } = useBook(
        "thumbnailUrls",
        "swapPhotos",
        "movePhotoToPage",
        "book",
    );
    const pagesRef = useRef(book.pages);
    pagesRef.current = book.pages;

    const [dragSourceInfo, setDragSourceInfo] = useState<DragInfo | null>(null);
    const dragSourceRef = useRef<DragInfo | null>(null);
    const [dragOverInfo, setDragOverInfo] = useState<DragInfo | null>(null);
    const dragOverRef = useRef<DragInfo | null>(null);
    const [dragOverPageId, setDragOverPageId] = useState<string | null>(null);
    const dragOverPageRef = useRef<string | null>(null);
    const dragGhostRef = useRef<HTMLCanvasElement>(null);
    const [pendingDrop, setPendingDrop] = useState<{
        source: DragInfo;
        target: DragInfo;
    } | null>(null);

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
            e.dataTransfer.dropEffect = "move";
            const cur = dragOverRef.current;
            if (cur?.pageId !== pageId || cur.slotId !== slotId) {
                const info = { pageId, slotId };
                dragOverRef.current = info;
                setDragOverInfo(info);
            }
            if (dragOverPageRef.current !== null) {
                dragOverPageRef.current = null;
                setDragOverPageId(null);
            }
        },
        [],
    );

    const placePhoto = useCallback(
        (source: DragInfo, pageId: string, slotId?: string) => {
            if (slotId)
                swapPhotos(source.pageId, source.slotId, pageId, slotId);
            else movePhotoToPage(source.pageId, source.slotId, pageId);
            clearSelection();
        },
        [swapPhotos, movePhotoToPage, clearSelection],
    );

    const resolveDrop = (choice: PhotoDropChoice) => {
        if (pendingDrop && choice !== "cancel") {
            const { source, target } = pendingDrop;
            placePhoto(
                source,
                target.pageId,
                choice === "swap" ? target.slotId : undefined,
            );
        }
        setPendingDrop(null);
    };

    const handlePageDragOver = useCallback(
        (e: React.DragEvent, pageId: string) => {
            const pages = pagesRef.current;
            e.preventDefault();
            const isBackCover = pages.at(-1)?.id === pageId;
            const toPage = pages.find((p) => p.id === pageId);
            const hasRoom =
                !isBackCover &&
                toPage &&
                availablePhotoSpaces(toPage, pages[0]?.id === pageId) > 0;
            e.dataTransfer.dropEffect = hasRoom ? "move" : "none";
            const cur = dragOverRef.current;
            if (cur !== null) {
                dragOverRef.current = null;
                setDragOverInfo(null);
            }
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
        [],
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

    const handleDrop = useCallback(
        (e: React.DragEvent, pageId: string, slotId?: string) => {
            e.preventDefault();
            const source = dragSourceRef.current;
            handleDragEnd();
            if (!source) return;
            if (
                source.pageId === pageId &&
                (!slotId || source.slotId === slotId)
            )
                return;

            const pages = pagesRef.current;
            const page = pages.find((p) => p.id === pageId);
            if (!page || page === pages.at(-1)) return;
            const isFrontCover = page === pages[0];
            const slot = page.slots[0];
            if (
                !isFrontCover &&
                source.pageId !== pageId &&
                page.slots.length === 1 &&
                slot?.photoId &&
                slot.x === 0 &&
                slot.y === 0 &&
                slot.width === 100 &&
                slot.height === 100
            ) {
                setPendingDrop({ source, target: { pageId, slotId: slot.id } });
            } else if (slotId || availablePhotoSpaces(page, isFrontCover) > 0) {
                placePhoto(source, pageId, slotId);
            }
        },
        [handleDragEnd, placePhoto],
    );

    const handleContainerDragOver = useCallback(
        (e: React.DragEvent) => {
            e.preventDefault();
            e.dataTransfer.dropEffect = "move";

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
        awaitingDropChoice: !!pendingDrop,
        resolveDrop,
        handleDragEnd,
        handleContainerDragOver,
        dragGhostRef,
    };
}
