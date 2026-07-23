import type { PreUploadSkippedFile } from "ente-base/types/ipc";
import type { UploadPhase } from "ente-gallery/services/upload";
import { useEffect, useState } from "react";
import { UploadCompletionV2 } from "../UploadCompletionV2";
import type {
    InProgressUpload,
    SegregatedFinishedUploads,
    UploadCounter,
    UploadFileNames,
} from "../uploadProgressStats";
import { UploadProgressContext, type DragPosition } from "./context";
import { MinimizedUploadProgress } from "./MinimizedUploadProgress";
import { StopUploadConfirmationDialog } from "./StopUploadConfirmationDialog";
import { UploadProgressDialog } from "./UploadProgressDialog";

interface UploadProgressProps {
    open: boolean;
    onClose: () => void;
    uploadCounter: UploadCounter;
    uploadPhase: UploadPhase;
    percentComplete: number;
    retryFailed: () => void;
    inProgressUploads: InProgressUpload[];
    uploadFileNames: UploadFileNames;
    finishedUploads: SegregatedFinishedUploads;
    preUploadSkippedFiles?: PreUploadSkippedFile[];
    hasLivePhotos: boolean;
    cancelUploads: () => void;
}

const emptyPreUploadSkippedFiles: PreUploadSkippedFile[] = [];

export function UploadProgressV2(props: UploadProgressProps) {
    if (!props.open) return null;

    return <UploadProgress {...props} />;
}

function UploadProgress({
    onClose,
    uploadCounter,
    uploadPhase,
    percentComplete,
    retryFailed,
    uploadFileNames,
    hasLivePhotos,
    inProgressUploads,
    finishedUploads,
    preUploadSkippedFiles = emptyPreUploadSkippedFiles,
    cancelUploads,
}: UploadProgressProps) {
    /**
     * expanded: This variable decides whether the full upload progress
     * modal should be shown or just the compact one is fine.
     *
     * dragPosition: For facilitating the drag of the compact upload widget
     * across the screen.
     *
     * showStopConfirmation: If the user tries to close the upload, we show
     * a confirmation modal, and this variable is the decider for that.
     */
    const [expanded, setExpanded] = useState(false);
    const [dragPosition, setDragPosition] = useState<DragPosition>();
    const [showStopConfirmation, setShowStopConfirmation] = useState(false);
    const [summaryMode, setSummaryMode] = useState<"review" | "cancelling">();

    useEffect(() => {
        if (uploadPhase == "preparing") setSummaryMode(undefined);
    }, [uploadPhase]);

    const handleClose = () =>
        uploadPhase == "done" ? onClose() : setShowStopConfirmation(true);

    const handleReviewFailed = () => {
        setShowStopConfirmation(false);
        setExpanded(true);
        setSummaryMode("review");
    };

    const handleRetryFailed = () => {
        setSummaryMode(undefined);
        retryFailed();
    };

    const handleStopConfirmationClose = () => setShowStopConfirmation(false);

    const handleStopConfirmationConfirm = () => {
        setShowStopConfirmation(false);
        setExpanded(true);
        setSummaryMode("cancelling");
        cancelUploads();
    };

    if (uploadPhase == "done" && expanded && !summaryMode) {
        return (
            <UploadCompletionV2
                open
                onClose={onClose}
                onReviewFailed={handleReviewFailed}
                finishedUploads={finishedUploads}
                preUploadSkippedFiles={preUploadSkippedFiles}
            />
        );
    }

    const contextValue = {
        onClose: handleClose,
        uploadCounter,
        uploadPhase,
        percentComplete,
        retryFailed: handleRetryFailed,
        inProgressUploads,
        uploadFileNames,
        finishedUploads,
        preUploadSkippedFiles,
        hasLivePhotos,
        setExpanded,
        dragPosition,
        setDragPosition,
    };

    return (
        <UploadProgressContext.Provider value={contextValue}>
            {expanded ? (
                <UploadProgressDialog closeOnly={summaryMode == "cancelling"} />
            ) : (
                <MinimizedUploadProgress />
            )}
            <StopUploadConfirmationDialog
                open={showStopConfirmation}
                onClose={handleStopConfirmationClose}
                onConfirm={handleStopConfirmationConfirm}
            />
        </UploadProgressContext.Provider>
    );
}
