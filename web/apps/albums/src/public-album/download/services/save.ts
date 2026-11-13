import { downloadManager } from "@/public-album/download/services/download-manager";
import type { AddSaveGroup } from "ente-gallery/components/utils/save-groups";
import { downloadAndSaveFilesWeb } from "ente-gallery/services/save-core";
import type { EnteFile } from "ente-media/file";

export const downloadAndSaveFiles = (
    files: EnteFile[],
    title: string,
    onAddSaveGroup: AddSaveGroup,
) =>
    downloadAndSaveFilesWeb({
        downloader: downloadManager,
        files,
        title,
        onAddSaveGroup,
    });

export const downloadAndSaveCollectionFiles = async (
    collectionSummaryName: string,
    collectionSummaryID: number,
    files: EnteFile[],
    isHiddenCollectionSummary: boolean | undefined,
    onAddSaveGroup: AddSaveGroup,
) =>
    downloadAndSaveFilesWeb({
        downloader: downloadManager,
        files,
        title: collectionSummaryName,
        onAddSaveGroup,
        collectionSummaryID,
        isHiddenCollectionSummary,
    });
