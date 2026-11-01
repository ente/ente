import { useCollectionOperations } from "@/components/gallery/media/use-collection-operations";
import { useSelectedFileOperations } from "@/components/gallery/media/use-selected-file-operations";
import type { GalleryBarMode } from "@/components/gallery/reducer";
import type { FileContextAction } from "@/utils/file-actions";
import { useBaseContext } from "ente-base/context";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import type { CollectionSummary } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import { useCallback } from "react";
export const useFileContextActions = ({
    collectionOperations,
    selectedOperations,
    activeCollection,
    activeCollectionSummary,
    barMode,
}: {
    collectionOperations: Pick<
        ReturnType<typeof useCollectionOperations>,
        | "createOnCreateForCollectionOp"
        | "createOnSelectForCollectionOp"
        | "handleOpenCollectionSelector"
        | "handleRemoveFilesFromCollection"
    >;
    selectedOperations: Pick<
        ReturnType<typeof useSelectedFileOperations>,
        | "createFileOpHandler"
        | "handleDeleteFiles"
        | "showContextMenuAssignPerson"
        | "showEditLocation"
        | "selectedCount"
        | "selectedOwnCount"
    >;
    activeCollection: Collection | undefined;
    activeCollectionSummary: CollectionSummary | undefined;
    barMode: GalleryBarMode;
}) => {
    const {
        createOnCreateForCollectionOp,
        createOnSelectForCollectionOp,
        handleOpenCollectionSelector,
        handleRemoveFilesFromCollection,
    } = collectionOperations;
    const {
        createFileOpHandler,
        handleDeleteFiles,
        showContextMenuAssignPerson,
        showEditLocation,
        selectedCount,
        selectedOwnCount,
    } = selectedOperations;
    const { showMiniDialog } = useBaseContext();
    const handleContextMenuAction = useCallback(
        (
            action: FileContextAction,
            _targetFile?: EnteFile,
            meta?: { isEphemeralSingleSelection: boolean },
        ) => {
            const suppressSelectionBar = !!meta?.isEphemeralSingleSelection;
            switch (action) {
                case "sendLink":
                case "download":
                case "favorite":
                case "unfavorite":
                case "archive":
                case "unarchive":
                case "hide":
                case "fixTime":
                    void createFileOpHandler(action, {
                        suppressSelectionBar,
                    })();
                    break;
                case "trash":
                    handleDeleteFiles(suppressSelectionBar);
                    break;
                case "deletePermanently":
                    showMiniDialog({
                        title: t("delete_files_title"),
                        kind: "warning",
                        message: t("delete_files_message"),
                        continue: {
                            text: t("delete"),
                            color: "critical",
                            action: createFileOpHandler("deletePermanently", {
                                suppressSelectionBar,
                            }),
                        },
                    });
                    break;
                case "restore":
                    handleOpenCollectionSelector({
                        action: "restore",
                        onCreateCollection:
                            createOnCreateForCollectionOp("restore"),
                        onSelectCollection: (collection) =>
                            void createOnSelectForCollectionOp("restore")(
                                collection,
                            ),
                    });
                    break;
                case "addToAlbum":
                    handleOpenCollectionSelector({
                        action: "add",
                        sourceCollectionSummaryID: activeCollectionSummary?.id,
                        showHiddenCollections: barMode == "hidden-albums",
                        onCreateCollection:
                            createOnCreateForCollectionOp("add"),
                        onSelectCollection: (collection) =>
                            void createOnSelectForCollectionOp("add")(
                                collection,
                            ),
                    });
                    break;
                case "moveToAlbum":
                    handleOpenCollectionSelector({
                        action: "move",
                        sourceCollectionSummaryID: activeCollectionSummary?.id,
                        showHiddenCollections: barMode == "hidden-albums",
                        onCreateCollection:
                            createOnCreateForCollectionOp("move"),
                        onSelectCollection: (collection) =>
                            void createOnSelectForCollectionOp("move")(
                                collection,
                            ),
                    });
                    break;
                case "removeFromAlbum": {
                    if (!activeCollection) break;
                    const isSharedIncoming =
                        activeCollectionSummary?.attributes.has(
                            "sharedIncoming",
                        );
                    const isSharedOutgoing =
                        activeCollectionSummary?.attributes.has(
                            "sharedOutgoing",
                        );
                    const isRemovingOthers = selectedCount != selectedOwnCount;
                    const remove = () =>
                        handleRemoveFilesFromCollection(activeCollection);

                    if (isSharedIncoming) {
                        if (isRemovingOthers) {
                            showMiniDialog({
                                title: t("remove_from_album"),
                                message: t("remove_from_album_others_message"),
                                continue: {
                                    text: t("remove"),
                                    color: "critical",
                                    action: remove,
                                },
                                cancel: t("cancel"),
                            });
                        } else {
                            remove();
                        }
                        break;
                    }

                    if (isSharedOutgoing && isRemovingOthers) {
                        showMiniDialog({
                            title: t("remove_from_album"),
                            message: t("remove_from_album_others_message"),
                            continue: {
                                text: t("remove"),
                                color: "critical",
                                action: remove,
                            },
                        });
                        break;
                    }

                    const onlyUserFiles = !isRemovingOthers;
                    showMiniDialog({
                        title: t("remove_from_album"),
                        message: onlyUserFiles
                            ? t("confirm_remove_message")
                            : t("confirm_remove_incl_others_message"),
                        continue: {
                            text: t("yes_remove"),
                            color: onlyUserFiles ? "primary" : "critical",
                            action: remove,
                        },
                    });
                    break;
                }
                case "unhide":
                    handleOpenCollectionSelector({
                        action: "unhide",
                        onCreateCollection:
                            createOnCreateForCollectionOp("unhide"),
                        onSelectCollection: (collection) =>
                            void createOnSelectForCollectionOp("unhide")(
                                collection,
                            ),
                    });
                    break;
                case "addPerson":
                    showContextMenuAssignPerson();
                    break;
                case "editLocation":
                    showEditLocation();
                    break;
            }
        },
        [
            createFileOpHandler,
            createOnCreateForCollectionOp,
            createOnSelectForCollectionOp,
            handleOpenCollectionSelector,
            handleRemoveFilesFromCollection,
            handleDeleteFiles,
            showMiniDialog,
            showContextMenuAssignPerson,
            showEditLocation,
            activeCollectionSummary,
            activeCollection,
            barMode,
            selectedCount,
            selectedOwnCount,
        ],
    );
    return handleContextMenuAction;
};
