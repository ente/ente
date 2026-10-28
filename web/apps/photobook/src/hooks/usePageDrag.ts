import { useBook } from "@/context/book";
import { useCallback, useRef, useState } from "react";

export function usePageDrag() {
    const { book, reorderPages } = useBook();
    const pageCount = book.pages.length;

    const [pageDragSource, setPageDragSource] = useState<number | null>(null);
    const [pageDragTarget, setPageDragTarget] = useState<number | null>(null);
    const pageDragSourceRef = useRef<number | null>(null);

    const handlePageDragStart = useCallback(
        (e: React.DragEvent, pageIndex: number) => {
            if (pageIndex === 0 || pageIndex === pageCount - 1) {
                e.preventDefault();
                return;
            }
            pageDragSourceRef.current = pageIndex;
            setPageDragSource(pageIndex);
            e.dataTransfer.effectAllowed = "move";
            e.dataTransfer.setData(
                "application/x-page-drag",
                String(pageIndex),
            );
        },
        [pageCount],
    );

    const handlePageDragOverPage = useCallback(
        (e: React.DragEvent, pageIndex: number) => {
            if (pageDragSourceRef.current === null) return;
            if (pageIndex === 0 || pageIndex === pageCount - 1) return;
            e.preventDefault();
            e.dataTransfer.dropEffect = "move";
            setPageDragTarget(pageIndex);
        },
        [pageCount],
    );

    const handlePageDropOnPage = useCallback(
        (e: React.DragEvent, pageIndex: number) => {
            e.preventDefault();
            e.stopPropagation();
            const source = pageDragSourceRef.current;
            if (
                source !== null &&
                source !== pageIndex &&
                pageIndex > 0 &&
                pageIndex < pageCount - 1
            ) {
                reorderPages(source, pageIndex);
            }
            pageDragSourceRef.current = null;
            setPageDragSource(null);
            setPageDragTarget(null);
        },
        [reorderPages, pageCount],
    );

    const handlePageDragEndCleanup = useCallback(() => {
        pageDragSourceRef.current = null;
        setPageDragSource(null);
        setPageDragTarget(null);
    }, []);

    return {
        pageDragSource,
        pageDragTarget,
        pageDragSourceRef,
        handlePageDragStart,
        handlePageDragOverPage,
        handlePageDropOnPage,
        handlePageDragEndCleanup,
    };
}
