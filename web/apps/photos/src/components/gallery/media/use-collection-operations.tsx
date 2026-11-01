import type { CollectionOp } from "@/components/SelectedFileOptions";
import { performCollectionOp } from "@/components/gallery/helpers";
import type {
    GalleryBarMode,
    GalleryState,
} from "@/components/gallery/reducer";
import { notifyOthersFilesDialogAttributes } from "@/components/utils/dialog-attributes";
import { getSelectedFiles, type SelectedState } from "@/utils/file";
import { useBaseContext } from "ente-base/context";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    canAddFilesToCollection,
    removeFromCollection,
} from "ente-new/photos/services/collection";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import { useCallback } from "react";
import type { RemotePullOpts } from "..";
import { useCollectionDialogs } from "./use-collection-dialogs";
export const useCollectionOperations = ({
    state,
    selected,
    filteredFiles,
    barMode,
    clearSelection,
    remotePull,
}: {
    state: GalleryState;
    selected: SelectedState;
    filteredFiles: EnteFile[];
    barMode: GalleryBarMode;
    clearSelection: () => void;
    remotePull: (opts?: RemotePullOpts) => Promise<void>;
}) => {
    const { user } = state;
    const { showMiniDialog, onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar } = usePhotosAppContext();
    const dialogs = useCollectionDialogs({ state, remotePull });
    const { handleCloseCollectionSelector } = dialogs;
    const handleRemoveFilesFromCollection = (collection: Collection) => {
        void (async () => {
            showLoadingBar();
            let notifyOthersFiles = false;
            try {
                handleCloseCollectionSelector();
                const selectedFiles = getSelectedFiles(selected, filteredFiles);
                const processedCount = await removeFromCollection(
                    collection,
                    selectedFiles,
                );
                notifyOthersFiles = processedCount != selectedFiles.length;
                clearSelection();
                await remotePull({
                    silent: true,
                    source: "remove-from-collection",
                });
            } catch (e) {
                onGenericError(e);
            } finally {
                hideLoadingBar();
            }

            if (notifyOthersFiles) {
                showMiniDialog(notifyOthersFilesDialogAttributes());
            }
        })();
    };
    const createOnSelectForCollectionOp = useCallback(
        (op: CollectionOp) => (selectedCollection: Collection) => {
            const selectedFiles = getSelectedFiles(selected, filteredFiles);
            const userFiles = selectedFiles.filter(
                (f) => f.ownerID == user!.id,
            );
            const sourceCollectionID = selected.collectionID;

            const performSelectedCollectionOp = async (
                op: CollectionOp,
                filesToProcess: EnteFile[],
                notifySkippedFiles = false,
            ) => {
                showLoadingBar();
                try {
                    handleCloseCollectionSelector();
                    if (filesToProcess.length > 0) {
                        await performCollectionOp(
                            op,
                            selectedCollection,
                            filesToProcess,
                            sourceCollectionID,
                        );
                    }
                    if (notifySkippedFiles) {
                        showMiniDialog(notifyOthersFilesDialogAttributes());
                    }
                    clearSelection();
                    await remotePull({
                        silent: true,
                        source: `collection-op:${op}`,
                    });
                } finally {
                    hideLoadingBar();
                }
            };

            const shouldAddInsteadOfMove =
                op == "move" &&
                selectedCollection.owner.id != user!.id &&
                canAddFilesToCollection(selectedCollection);

            if (shouldAddInsteadOfMove) {
                showMiniDialog({
                    title: t("cannot_move_to_shared_albums"),
                    message: t("cannot_move_to_shared_albums_message"),
                    continue: {
                        text: t("add"),
                        action: () =>
                            performSelectedCollectionOp("add", selectedFiles),
                    },
                    cancel: t("cancel"),
                });
                return;
            }

            return (async () => {
                try {
                    const filesToProcess =
                        op == "add" ? selectedFiles : userFiles;
                    await performSelectedCollectionOp(
                        op,
                        filesToProcess,
                        op != "add" && userFiles.length != selectedFiles.length,
                    );
                } catch (e) {
                    onGenericError(e);
                }
            })();
        },
        [
            selected,
            filteredFiles,
            user,
            showLoadingBar,
            showMiniDialog,
            clearSelection,
            remotePull,
            hideLoadingBar,
            onGenericError,
            handleCloseCollectionSelector,
        ],
    );
    const createOnCreateForCollectionOp = (op: CollectionOp) => {
        const onCreate = createOnSelectForCollectionOp(op);
        const hidden =
            (op === "add" || op === "move") && barMode === "hidden-albums";
        return () => dialogs.showCreateAlbum(hidden, onCreate);
    };
    return {
        ...dialogs,
        handleRemoveFilesFromCollection,
        createOnSelectForCollectionOp,
        createOnCreateForCollectionOp,
    };
};
