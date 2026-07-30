import { useRef, type PointerEvent, type RefObject } from "react";
import { useUploadProgressContext } from "./context";

/**
 * Returns pointer handlers that move `dragSurfaceRef` from a dedicated drag
 * handle. Expand and close actions remain in `MinimizedUploadProgress`.
 *
 * This file currently only has the functions and the interface which are
 * required for the drag implementation.
 */
export function useMinimizedUploadDrag(
    dragSurfaceRef: RefObject<HTMLDivElement | null>,
) {
    const { dragPosition, setDragPosition } = useUploadProgressContext();
    const dragState = useRef<DragState | undefined>(undefined);

    const handlePointerDown = (event: PointerEvent<HTMLElement>) => {
        const surface = dragSurfaceRef.current;
        if (event.button != 0 || !surface) return;

        const rect = surface.getBoundingClientRect();
        dragState.current = {
            pointerStartX: event.clientX,
            pointerStartY: event.clientY,
            positionStartX: rect.left,
            positionStartY: rect.top,
            currentX: rect.left,
            currentY: rect.top,
            moved: false,
            surface,
            surfaceWidth: rect.width,
            surfaceHeight: rect.height,
        };

        event.currentTarget.setPointerCapture(event.pointerId);
        event.preventDefault();
    };

    const handlePointerMove = (event: PointerEvent<HTMLElement>) => {
        if (!dragState.current) {
            return;
        }

        const dx = event.clientX - dragState.current.pointerStartX;
        const dy = event.clientY - dragState.current.pointerStartY;
        if (!dragState.current.moved && Math.abs(dx) <= 4 && Math.abs(dy) <= 4)
            return;

        if (!dragState.current.moved) {
            dragState.current.moved = true;
            const { surface } = dragState.current;
            surface.style.position = "fixed";
            surface.style.left = `${dragState.current.positionStartX}px`;
            surface.style.top = `${dragState.current.positionStartY}px`;
            surface.style.right = "auto";
            surface.style.bottom = "auto";
            surface.style.margin = "0";
        }

        const x = clamp(
            dragState.current.positionStartX + dx,
            0,
            window.innerWidth - dragState.current.surfaceWidth,
        );
        const y = clamp(
            dragState.current.positionStartY + dy,
            0,
            window.innerHeight - dragState.current.surfaceHeight,
        );

        dragState.current.currentX = x;
        dragState.current.currentY = y;
        dragState.current.surface.style.left = `${x}px`;
        dragState.current.surface.style.top = `${y}px`;
    };

    const handlePointerUp = (event: PointerEvent<HTMLElement>) => {
        if (dragState.current) {
            if (dragState.current.moved) {
                setDragPosition({
                    x: dragState.current.currentX,
                    y: dragState.current.currentY,
                });
            }
        }
        dragState.current = undefined;
        if (event.currentTarget.hasPointerCapture(event.pointerId)) {
            event.currentTarget.releasePointerCapture(event.pointerId);
        }
    };

    return {
        dragPosition,
        dragHandleProps: {
            onPointerCancel: handlePointerUp,
            onPointerDown: handlePointerDown,
            onPointerMove: handlePointerMove,
            onPointerUp: handlePointerUp,
        },
    };
}

interface DragState {
    pointerStartX: number;
    pointerStartY: number;
    positionStartX: number;
    positionStartY: number;
    currentX: number;
    currentY: number;
    moved: boolean;
    surface: HTMLDivElement;
    surfaceWidth: number;
    surfaceHeight: number;
}

const clamp = (value: number, min: number, max: number) =>
    Math.min(Math.max(value, min), Math.max(min, max));
