import {
    CollectionSelector,
    type CollectionSelectorAttributes,
} from "@/components/CollectionSelector";
import type { CollectionOp } from "@/components/SelectedFileOptions";
import {
    findCollectionCreatingIfNeeded,
    performCollectionOp,
} from "@/components/gallery/helpers";
import type { GalleryBarMode } from "@/components/gallery/reducer";
import { notifyOthersFilesDialogAttributes } from "@/components/utils/dialog-attributes";
import { getSelectedFiles, type SelectedState } from "@/utils/file";
import { Notification } from "ente-base/components/Notification";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    canAddFilesToCollection,
    createAlbum,
    createHiddenAlbum,
    removeFromCollection,
} from "ente-new/photos/services/collection";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import { useCallback, useRef, useState } from "react";
import type { RemotePullOpts } from "..";
import type { GalleryState } from "../reducer";
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
    const { user, normalCollectionSummaries } = state;
    const { showMiniDialog, onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar, showNotification } =
        usePhotosAppContext();
    const pendingSingleFileAdd = useRef<
        { file: EnteFile; sourceCollectionSummaryID?: number } | undefined
    >(undefined);
    const [openCollectionSelector, setOpenCollectionSelector] = useState(false);
    const [collectionSelectorAttributes, setCollectionSelectorAttributes] =
        useState<CollectionSelectorAttributes | undefined>();
    const [postCreateAlbumOp, setPostCreateAlbumOp] = useState<
        CollectionOp | undefined
    >(undefined);
    const postCreateAlbumHidden = useRef(false);
    const { show: showAlbumNameInput, props: albumNameInputVisibilityProps } =
        useModalVisibility();
    const [albumAddedNotification, setAlbumAddedNotification] = useState<{
        open: boolean;
        albumName?: string;
    }>({ open: false });
    const handleRemoveFilesFromCollection = (collection: Collection) => {
        void (async () => {
            showLoadingBar();
            let notifyOthersFiles = false;
            try {
                setOpenCollectionSelector(false);
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
                    setOpenCollectionSelector(false);
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

            void (async () => {
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
        ],
    );
    const createOnCreateForCollectionOp = useCallback(
        (op: CollectionOp) => {
            setPostCreateAlbumOp(op);
            postCreateAlbumHidden.current =
                (op == "add" || op == "move") && barMode == "hidden-albums";
            return showAlbumNameInput;
        },
        [showAlbumNameInput, barMode],
    );
    const handleAlbumNameSubmit = useCallback(
        async (name: string) => {
            try {
                const collection = postCreateAlbumHidden.current
                    ? await createHiddenAlbum(name)
                    : await createAlbum(name);

                if (pendingSingleFileAdd.current) {
                    await performCollectionOp(
                        "add",
                        collection,
                        [pendingSingleFileAdd.current.file],
                        pendingSingleFileAdd.current.sourceCollectionSummaryID,
                    );

                    await remotePull({
                        silent: true,
                        source: "single-file-add-new-album",
                    });
                    setAlbumAddedNotification({
                        open: true,
                        albumName: collection.name,
                    });
                    setOpenCollectionSelector(false);
                    setPostCreateAlbumOp(undefined);
                    postCreateAlbumHidden.current = false;
                    return;
                }

                if (postCreateAlbumOp === undefined) {
                    await remotePull();
                    showNotification({
                        color: "primary",
                        title: t("album_created"),
                    });
                    return;
                }

                createOnSelectForCollectionOp(postCreateAlbumOp)(collection);
                setPostCreateAlbumOp(undefined);
                postCreateAlbumHidden.current = false;
            } finally {
                pendingSingleFileAdd.current = undefined;
            }
        },
        [
            createOnSelectForCollectionOp,
            postCreateAlbumOp,
            remotePull,
            showNotification,
        ],
    );
    const handleOpenCollectionSelector = useCallback(
        (attributes: CollectionSelectorAttributes) => {
            setCollectionSelectorAttributes(attributes);
            setOpenCollectionSelector(true);
        },
        [],
    );
    const handleCloseCollectionSelector = useCallback(
        () => setOpenCollectionSelector(false),
        [],
    );
    const handleCollectionSelectorExited = useCallback(
        () => setCollectionSelectorAttributes(undefined),
        [],
    );
    const handleAddSingleFileToCollection = useCallback(
        (file: EnteFile, sourceCollectionSummaryID?: number) => {
            pendingSingleFileAdd.current = { file, sourceCollectionSummaryID };

            const handleSelect = async (collection: Collection) => {
                try {
                    setAlbumAddedNotification({ open: false });
                    showLoadingBar();
                    await performCollectionOp(
                        "add",
                        collection,
                        [file],
                        sourceCollectionSummaryID,
                    );
                    await remotePull({
                        silent: true,
                        source: "single-file-add-to-album",
                    });
                    setAlbumAddedNotification({
                        open: true,
                        albumName: collection.name,
                    });
                } catch (e) {
                    onGenericError(e);
                } finally {
                    pendingSingleFileAdd.current = undefined;
                    hideLoadingBar();
                }
            };

            const handleCreate = () => {
                setPostCreateAlbumOp("add");
                postCreateAlbumHidden.current = false;
                showAlbumNameInput();
            };

            handleOpenCollectionSelector({
                action: "add",
                sourceCollectionSummaryID,
                onSelectCollection: (collection) =>
                    void handleSelect(collection),
                onCreateCollection: handleCreate,
                onCancel: () => {
                    pendingSingleFileAdd.current = undefined;
                },
            });
        },
        [
            handleOpenCollectionSelector,
            remotePull,
            onGenericError,
            hideLoadingBar,
            showAlbumNameInput,
            showLoadingBar,
        ],
    );
    const collectionOperationDialogs = (
        <>
            {" "}
            <CollectionSelector
                open={openCollectionSelector}
                onClose={handleCloseCollectionSelector}
                onExited={handleCollectionSelectorExited}
                attributes={collectionSelectorAttributes}
                collectionSummaries={
                    collectionSelectorAttributes?.showHiddenCollections
                        ? state.hiddenCollectionSummaries
                        : normalCollectionSummaries
                }
                collectionForCollectionSummaryID={(id) =>
                    findCollectionCreatingIfNeeded(state.collections, id)
                }
            />{" "}
            <SingleInputDialog
                {...albumNameInputVisibilityProps}
                title={t("new_album")}
                label={t("album_name")}
                submitButtonTitle={t("create")}
                onClose={() => {
                    // Do not leak a cancelled add into the next album creation.
                    pendingSingleFileAdd.current = undefined;
                    postCreateAlbumHidden.current = false;
                    setPostCreateAlbumOp(undefined);
                    albumNameInputVisibilityProps.onClose();
                }}
                onSubmit={handleAlbumNameSubmit}
            />{" "}
            <Notification
                open={albumAddedNotification.open}
                onClose={() =>
                    setAlbumAddedNotification((s) => ({ ...s, open: false }))
                }
                keepOpenOnClick
                attributes={{
                    color: "inherit",
                    startIcon: null,
                    title: t("added_to_album"),
                    caption: albumAddedNotification.albumName,
                }}
            />{" "}
        </>
    );
    return {
        openCollectionSelector,
        showAlbumNameInput,
        albumNameInputVisibilityProps,
        setPostCreateAlbumOp,
        postCreateAlbumHidden,
        handleRemoveFilesFromCollection,
        createOnSelectForCollectionOp,
        createOnCreateForCollectionOp,
        handleOpenCollectionSelector,
        handleCloseCollectionSelector,
        handleAddSingleFileToCollection,
        collectionOperationDialogs,
    };
};
