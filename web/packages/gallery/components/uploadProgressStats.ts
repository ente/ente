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

// The below types are considered as completed because the files are grouped
// to either of these after it was tried to upload the file.
export const finishedStatKinds = ["completed", "skipped", "failed"] as const;

export type FinishedStatKind = (typeof finishedStatKinds)[number];

// The inProgress here is more kind of a remaining value. When a bunch of files
// are uploaded all of them before the pre-upload stage are put under this
// inProgress state.
export type UploadStatKind = "inProgress" | FinishedStatKind;

export const uploadStatColors: Record<FinishedStatKind, string> = {
    completed: "#08c225",
    skipped: "#2c83ff",
    failed: "#ff8a1f",
};

/**
 * There are a total of 11 probable stats which is retruned after each
 * file upload and we are grouping them based on this, so that they
 * can be shown under the corresponding tab in the UI.
 *
 * The herustics for failed is there is a probablity that the files
 * can be uploaded whereas for the skipped it's sure that the files
 * can't be uploaded.
 */
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
