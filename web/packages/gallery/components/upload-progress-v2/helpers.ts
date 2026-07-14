import { formattedListJoin } from "ente-base/i18n";
import type { PreUploadSkippedFile } from "ente-base/types/ipc";
import type { UploadPhase } from "ente-gallery/services/upload";
import { t } from "i18next";
import {
    finishedStatKinds,
    uploadCompletionCounts,
    uploadStatColors,
    type FinishedStatKind,
    type FinishedUploadType,
    type UploadStatKind,
} from "../uploadProgressStats";
import type { UploadProgressContextT } from "./context";

export const finishedTypeReasons: Partial<Record<FinishedUploadType, string>> =
    {
        alreadyUploaded: "Already on Ente",
        largerThanAvailableStorage: "Not enough storage",
        tooLarge: "File over 10 GB",
        unsupported: "File type not supported",
        zeroSize: "Empty file",
        blocked: "Upload blocked",
        failed: "Upload failed",
    };

export const finishedTypeReasonHints: Partial<
    Record<FinishedUploadType, string>
> = {
    uploadedWithStaticThumbnail:
        "The file was uploaded, but we could not generate a thumbnail for it.",
    blocked:
        "Your browser or an addon is preventing Ente from using eTags to upload large files.",
};

export const preUploadSkippedFileReasons: Record<
    PreUploadSkippedFile["type"],
    string
> = { hiddenFile: "Hidden file", failedZip: "Unreadable zip" };

const finishedStatLabels: Record<FinishedStatKind, string> = {
    completed: "Completed",
    skipped: "Skipped",
    failed: "Failed",
};

export const statConfigs = [
    { kind: "inProgress", color: "#d9d9d9", label: "In progress" },
    ...finishedStatKinds.map((kind) => ({
        kind,
        color: uploadStatColors[kind],
        label: finishedStatLabels[kind],
    })),
] satisfies { kind: UploadStatKind; color: string; label: string }[];

export const doneStatConfigs = statConfigs.slice(1) as {
    kind: FinishedStatKind;
    color: string;
    label: string;
}[];

export const statEmptyMessages: Record<FinishedStatKind, string> = {
    completed: "No completed uploads yet",
    skipped: "No skipped files yet",
    failed: "No failed uploads yet",
};

export const uploadStatusText = (uploadPhase: UploadPhase) => {
    switch (uploadPhase) {
        case "preparing":
            return t("preparing");
        case "readingMetadata":
            return t("upload_reading_metadata_files");
        case "uploading":
            return "Uploading";
        case "cancelling":
            return t("upload_cancelling");
        case "done":
            return "Upload complete";
    }
};

export const uploadCountsText = ({
    uploadPhase,
    uploadCounter,
    finishedUploads,
    preUploadSkippedFiles,
}: Pick<
    UploadProgressContextT,
    | "uploadPhase"
    | "uploadCounter"
    | "finishedUploads"
    | "preUploadSkippedFiles"
>) => {
    if (uploadPhase == "done") {
        const {
            completed: count,
            skipped,
            failed,
        } = uploadCompletionCounts(finishedUploads, preUploadSkippedFiles);
        const notCount = skipped + failed;
        const items: string[] = [];
        if (count) items.push(t("upload_done", { count }));
        if (notCount) items.push(t("upload_skipped", { count: notCount }));
        return items.length
            ? formattedListJoin(items)
            : t("upload_done", { count });
    }
    return uploadCounter.total
        ? `${uploadCounter.finished.toLocaleString()} of ${uploadCounter.total.toLocaleString()} items`
        : uploadStatusText(uploadPhase);
};

/**
 *
 * @param value The upload percent which has decimal places
 * @returns The value with the decimal places rounded.
 */
export const normalizePercent = (value: number) =>
    Math.min(100, Math.max(0, Math.round(value || 0)));
