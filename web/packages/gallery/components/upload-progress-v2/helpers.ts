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

export const finishedTypeReasonKeys: Partial<
    Record<FinishedUploadType, string>
> = {
    alreadyUploaded: "upload_reason_already_on_ente",
    partnerShared: "upload_reason_shared_by_partner",
    largerThanAvailableStorage: "upload_reason_not_enough_storage",
    tooLarge: "upload_reason_file_too_large",
    unsupported: "upload_reason_unsupported_file",
    zeroSize: "upload_reason_empty_file",
    blocked: "upload_reason_blocked",
    failed: "upload_reason_failed",
    uploadedWithStaticThumbnail: "thumbnail_generation_failed",
};

export const finishedTypeReasonHintKeys: Partial<
    Record<FinishedUploadType, string>
> = {
    uploadedWithStaticThumbnail: "thumbnail_generation_failed_hint",
    blocked: "upload_reason_blocked_hint",
};

export const preUploadSkippedFileReasonKeys: Record<
    PreUploadSkippedFile["type"],
    string
> = {
    hiddenFile: "upload_reason_hidden_file",
    failedZip: "upload_reason_unreadable_zip",
};

const finishedStatLabelKeys: Record<FinishedStatKind, string> = {
    completed: "upload_stat_completed",
    skipped: "upload_stat_skipped",
    failed: "upload_stat_failed",
};

export const statConfigs = [
    {
        kind: "inProgress",
        color: "#d9d9d9",
        labelKey: "upload_stat_in_progress",
    },
    ...finishedStatKinds.map((kind) => ({
        kind,
        color: uploadStatColors[kind],
        labelKey: finishedStatLabelKeys[kind],
    })),
] satisfies { kind: UploadStatKind; color: string; labelKey: string }[];

export const doneStatConfigs = statConfigs.slice(1) as {
    kind: FinishedStatKind;
    color: string;
    labelKey: string;
}[];

export const statEmptyMessageKeys: Record<FinishedStatKind, string> = {
    completed: "upload_empty_completed",
    skipped: "upload_empty_skipped",
    failed: "upload_empty_failed",
};

export const uploadStatusText = (uploadPhase: UploadPhase) => {
    switch (uploadPhase) {
        case "preparing":
            return t("preparing");
        case "readingMetadata":
            return t("upload_reading_metadata_files");
        case "uploading":
            return t("uploading");
        case "cancelling":
            return t("upload_cancelling");
        case "done":
            return t("upload_complete");
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
        ? t("upload_items_progress", {
              count: uploadCounter.finished,
              total: uploadCounter.total,
          })
        : uploadStatusText(uploadPhase);
};

/**
 *
 * @param value The upload percent which has decimal places
 * @returns The value with the decimal places rounded.
 */
export const normalizePercent = (value: number) =>
    Math.min(100, Math.max(0, Math.round(value || 0)));
