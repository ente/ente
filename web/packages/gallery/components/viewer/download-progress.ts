import type { FileDownloadProgress } from "ente-gallery/services/download-core";
import type { ItemData } from "./data-source-core";

export type DownloadProgressPhase =
    | "preparing"
    | "downloading"
    | "decrypting"
    | "failed";

export interface DownloadProgressState {
    phase: DownloadProgressPhase;
    percentage: number | undefined;
    loaded?: number;
    total?: number;
}

export const downloadProgressState = (
    itemData: Pick<ItemData, "isContentLoading" | "fetchFailed">,
    entry: FileDownloadProgress | undefined,
    previous: DownloadProgressState | undefined,
): DownloadProgressState | undefined => {
    if (itemData.fetchFailed)
        return { phase: "failed", percentage: previous?.percentage ?? 0 };
    if (!itemData.isContentLoading) return undefined;

    if (entry) {
        const { loaded, total } = entry;
        if (total !== undefined && total > 0) {
            if (loaded >= total)
                return { phase: "decrypting", percentage: 100, loaded, total };
            if (loaded > 0)
                return {
                    phase: "downloading",
                    percentage: Math.floor((loaded * 100) / total),
                    loaded,
                    total,
                };
            return { phase: "preparing", percentage: 0 };
        }
        if (total === undefined && loaded > 0)
            return { phase: "downloading", percentage: undefined, loaded };
    } else if (
        previous?.phase == "downloading" ||
        previous?.phase == "decrypting"
    ) {
        return { phase: previous.phase, percentage: previous.percentage };
    }
    return { phase: "preparing", percentage: 0 };
};
