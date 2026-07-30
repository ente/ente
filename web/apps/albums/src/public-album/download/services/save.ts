import { downloadManager } from "@/public-album/download/services/download-manager";
import type { AddSaveGroup } from "ente-gallery/components/utils/save-groups";
import { downloadAndSaveFilesWeb } from "ente-gallery/services/save-core";
import type { EnteFile } from "ente-media/file";

/**
 * Save the given {@link files} to the user's device.
 *
 * Files are saved to the browser's download destination.
 *
 * @param files The files to save.
 *
 * @param title A title to show in the UI notification that indicates the
 * progress of the save.
 *
 * @param onAddSaveGroup A function that can be used to create a save group
 * associated with the save. The newly added save group will correspond to a
 * notification shown in the UI, and the progress and status of the save can be
 * communicated by updating the save group's state using the updater function
 * obtained when adding the save group.
 */
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

/**
 * Save all the files of a collection to the user's device.
 *
 * This is a variant of {@link downloadAndSaveFiles}, except instead of taking a
 * list of files to save, this variant is tailored for saving saves all the
 * files that belong to a collection. Otherwise, it broadly behaves similarly;
 * see that method's documentation for more details.
 *
 * @param isHiddenCollectionSummary `true` if the collection is associated with
 * a "hidden" collection or pseudo-collection in the app. Only relevant when
 * running in the context of the photos app, can be `undefined` otherwise.
 */
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
