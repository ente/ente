import type { SelectionContext } from "@/components/gallery";
import type { FileOp } from "@/components/SelectedFileOptions";
import { downloadAndSaveFiles } from "@/services/save";
import { isSameDay } from "ente-base/date";
import { formattedDate } from "ente-base/i18n-date";
import type { AddSaveGroup } from "ente-gallery/components/utils/save-groups";
import type { EnteFile } from "ente-media/file";
import {
    fileCreationPhotoDate,
    fileFileName,
    ItemVisibility,
} from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import {
    addToFavoritesCollection,
    deleteFromTrash,
    hideFiles,
    moveToTrash,
    removeFromFavoritesCollection,
} from "ente-new/photos/services/collection";
import { updateFilesVisibility } from "ente-new/photos/services/file";
import { t } from "i18next";

export interface SelectedState {
    [k: number]: boolean;
    ownCount: number;
    count: number;
    collectionID: number | undefined;
    // New selection code sets context; legacy callers still use collectionID.
    context: SelectionContext | undefined;
}
export type SetSelectedState = React.Dispatch<
    React.SetStateAction<SelectedState>
>;

export function getSelectedFiles(
    selected: SelectedState,
    files: EnteFile[],
): EnteFile[] {
    const selectedFilesIDs = new Set<number>();
    for (const [key, val] of Object.entries(selected)) {
        if (typeof val == "boolean" && val) {
            selectedFilesIDs.add(Number(key));
        }
    }

    return files.filter((file) => selectedFilesIDs.has(file.id));
}

export const fileTimelineDateString = (file: EnteFile) => {
    const date = fileCreationPhotoDate(file);
    return isSameDay(date, new Date())
        ? t("today")
        : isSameDay(date, new Date(Date.now() - 24 * 60 * 60 * 1000))
          ? t("yesterday")
          : formattedDate(date);
};

export const selectedFavoriteCount = (
    selected: SelectedState,
    favoriteFileIDs: Set<number> | undefined,
) => {
    if (!favoriteFileIDs || selected.count == 0) return 0;
    let count = 0;
    for (const [key, value] of Object.entries(selected)) {
        if (typeof value === "boolean" && value) {
            if (favoriteFileIDs.has(Number(key))) {
                count += 1;
            }
        }
    }
    return count;
};

export const performFileOp = async (
    op: FileOp,
    files: EnteFile[],
    onAddSaveGroup: AddSaveGroup,
    markTempDeleted: (files: EnteFile[]) => void,
    clearTempDeleted: () => void,
    markTempHidden: (files: EnteFile[]) => void,
    clearTempHidden: () => void,
    fixCreationTime: (files: EnteFile[]) => void,
) => {
    switch (op) {
        case "download": {
            const singleFile = files.length === 1 ? files[0] : undefined;
            const title =
                singleFile?.metadata.fileType === FileType.livePhoto
                    ? fileFileName(singleFile)
                    : t("files_count", { count: files.length });
            await downloadAndSaveFiles(files, title, onAddSaveGroup);
            break;
        }
        case "fixTime":
            fixCreationTime(files);
            break;
        case "favorite":
            await addToFavoritesCollection(files);
            break;
        case "unfavorite":
            await removeFromFavoritesCollection(files);
            break;
        case "archive":
            await updateFilesVisibility(files, ItemVisibility.archived);
            break;
        case "unarchive":
            await updateFilesVisibility(files, ItemVisibility.visible);
            break;
        case "hide":
            try {
                markTempHidden(files);
                await hideFiles(files);
            } catch (e) {
                clearTempHidden();
                throw e;
            }
            break;
        case "trash":
            try {
                markTempDeleted(files);
                await moveToTrash(files);
            } catch (e) {
                clearTempDeleted();
                throw e;
            }
            break;
        case "deletePermanently":
            try {
                markTempDeleted(files);
                await deleteFromTrash(files.map((file) => file.id));
            } catch (e) {
                clearTempDeleted();
                throw e;
            }
            break;
    }
};
