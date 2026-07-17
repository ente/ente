import type { PreUploadSkippedFile } from "ente-base/types/ipc";
import type { UploadPhase } from "ente-gallery/services/upload";
import { createContext, useContext } from "react";
import type {
    InProgressUpload,
    SegregatedFinishedUploads,
    UploadCounter,
    UploadFileNames,
} from "../uploadProgressStats";

/**
 * Coordinates for positioning the draggable minimized upload progress widget.
 */
export interface DragPosition {
    x: number;
    y: number;
}

/**
 * This the main prop type facilitating the variour actions
 * which are currently available to the UploadProgress UI
 */
export interface UploadProgressContextT {
    onClose: () => void;
    uploadCounter: UploadCounter;
    uploadPhase: UploadPhase;
    percentComplete: number;
    retryFailed: () => void;
    inProgressUploads: InProgressUpload[];
    uploadFileNames: UploadFileNames;
    finishedUploads: SegregatedFinishedUploads;
    preUploadSkippedFiles: PreUploadSkippedFile[];
    hasLivePhotos: boolean;
    setExpanded: (expanded: boolean) => void;
    dragPosition: DragPosition | undefined;
    setDragPosition: (dragPosition: DragPosition | undefined) => void;
}

export const UploadProgressContext = createContext<
    UploadProgressContextT | undefined
>(undefined);

export const useUploadProgressContext = () =>
    useContext(UploadProgressContext)!;
