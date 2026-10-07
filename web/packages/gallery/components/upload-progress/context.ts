import type { PreUploadSkippedFile } from "ente-base/types/ipc";
import { createContext, useContext } from "react";
import type { UploadProgressState } from "../upload-progress-stats";

export interface DragPosition {
    x: number;
    y: number;
}

export interface UploadProgressContextT extends UploadProgressState {
    onClose: () => void;
    retryFailed: () => void;
    preUploadSkippedFiles: PreUploadSkippedFile[];
    setExpanded: (expanded: boolean) => void;
    dragPosition: DragPosition | undefined;
    setDragPosition: (dragPosition: DragPosition | undefined) => void;
}

export const UploadProgressContext = createContext<
    UploadProgressContextT | undefined
>(undefined);

export const useUploadProgressContext = () =>
    useContext(UploadProgressContext)!;
