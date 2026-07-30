import type { AddSaveGroup } from "ente-gallery/components/utils/save-groups";
import { downloadAndSaveFiles } from "ente-gallery/services/save";
import type { EnteFile } from "ente-media/file";
import { fileFileName, ItemVisibility } from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import type { SelectionContext } from "ente-new/photos/components/gallery";
import type { FileOp } from "ente-new/photos/components/SelectedFileOptions";
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
    /**
     * The context in which the selection was made. Only set by newer code if
     * there is an active selection (older code continues to rely on the
     * {@link collectionID} logic).
     */
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
