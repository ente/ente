import type { PreUploadSkippedFile } from "ente-base/types/ipc";
import type { UploadPhase, UploadResult } from "ente-gallery/services/upload";

export interface UploadCounter {
    finished: number;
    total: number;
}

export interface InProgressUpload {
    localFileID: number;
    progress: number;
}

export type FinishedUploadType = Exclude<UploadResult["type"], "addedSymlink">;

export type SegregatedFinishedUploads = Map<FinishedUploadType, number[]>;

export type UploadFileNames = Map<number, string>;

// These are terminal outcomes, including skipped and failed attempts.
export const finishedStatKinds = ["completed", "skipped", "failed"] as const;

export type FinishedStatKind = (typeof finishedStatKinds)[number];

// "inProgress" includes every file until it reaches pre-upload.
export type UploadStatKind = "inProgress" | FinishedStatKind;

export const uploadStatColors: Record<FinishedStatKind, string> = {
    completed: "#08c225",
    skipped: "#2c83ff",
    failed: "#ff8a1f",
};

// "failed" may be retryable; "skipped" cannot be uploaded.
export const statFinishedTypes: Record<FinishedStatKind, FinishedUploadType[]> =
    {
        completed: ["uploaded", "uploadedWithStaticThumbnail"],
        skipped: [
            "alreadyUploaded",
            "partnerShared",
            "largerThanAvailableStorage",
            "tooLarge",
            "unsupported",
            "zeroSize",
        ],
        failed: ["blocked", "failed"],
    };

export const uploadCompletionCounts = (
    finishedUploads: SegregatedFinishedUploads,
    preUploadSkippedFiles: PreUploadSkippedFile[],
): Record<FinishedStatKind, number> => {
    const countFinished = (types: FinishedUploadType[]) =>
        types.reduce(
            (count, type) => count + (finishedUploads.get(type)?.length ?? 0),
            0,
        );

    return {
        completed: countFinished(statFinishedTypes.completed),
        skipped:
            countFinished(statFinishedTypes.skipped) +
            preUploadSkippedFiles.length,
        failed: countFinished(statFinishedTypes.failed),
    };
};

export const uploadProgressStatCounts = ({
    uploadPhase,
    inProgressUploads,
    finishedUploads,
    preUploadSkippedFiles,
}: {
    uploadPhase: UploadPhase;
    inProgressUploads: InProgressUpload[];
    finishedUploads: SegregatedFinishedUploads;
    preUploadSkippedFiles: PreUploadSkippedFile[];
}): Record<UploadStatKind, number> => ({
    inProgress: uploadPhase == "done" ? 0 : inProgressUploads.length,
    ...uploadCompletionCounts(finishedUploads, preUploadSkippedFiles),
});
