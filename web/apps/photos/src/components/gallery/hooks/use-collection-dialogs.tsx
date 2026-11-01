import {
    CollectionSelector,
    type CollectionSelectorAttributes,
} from "@/components/CollectionSelector";
import {
    findCollectionCreatingIfNeeded,
    performCollectionOp,
} from "@/components/gallery/helpers";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    createAlbum,
    createHiddenAlbum,
} from "ente-new/photos/services/collection";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import { useCallback, useState } from "react";
import type { RemotePullOpts } from "..";
import type { GalleryState } from "../reducer";

export const useCollectionDialogs = ({
    state,
    remotePull,
}: {
    state: GalleryState;
    remotePull: (opts?: RemotePullOpts) => Promise<void>;
}) => {
    const { onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar, showNotification } =
        usePhotosAppContext();
    const [openCollectionSelector, setOpenCollectionSelector] = useState(false);
    const [attributes, setAttributes] =
        useState<CollectionSelectorAttributes>();
    const [creation, setCreation] = useState<{
        hidden: boolean;
        onCreate?: (collection: Collection) => void | Promise<void>;
    }>();
    const { show, props: albumNameInputVisibilityProps } = useModalVisibility();
    const showCreateAlbum = useCallback(
        (
            hidden = false,
            onCreate?: (collection: Collection) => void | Promise<void>,
        ) => {
            setCreation({ hidden, onCreate });
            show();
        },
        [show],
    );
    const handleOpenCollectionSelector = useCallback(
        (next: CollectionSelectorAttributes) => {
            setAttributes(next);
            setOpenCollectionSelector(true);
        },
        [],
    );
    const handleCloseCollectionSelector = useCallback(
        () => setOpenCollectionSelector(false),
        [],
    );
    const handleAlbumNameSubmit = async (name: string) => {
        const request = creation;
        const collection = request?.hidden
            ? await createHiddenAlbum(name)
            : await createAlbum(name);
        if (request?.onCreate) await request.onCreate(collection);
        else {
            await remotePull();
            showNotification({ color: "primary", title: t("album_created") });
        }
        setCreation((previous) =>
            previous === request ? undefined : previous,
        );
    };
    const handleAddSingleFileToCollection = useCallback(
        (file: EnteFile, sourceCollectionSummaryID?: number) => {
            const add = async (collection: Collection) => {
                showLoadingBar();
                try {
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
                    showNotification({
                        color: "primary",
                        title: t("added_to_album"),
                        caption: collection.name,
                    });
                } catch (error) {
                    onGenericError(error);
                } finally {
                    hideLoadingBar();
                }
            };
            handleOpenCollectionSelector({
                action: "add",
                sourceCollectionSummaryID,
                onSelectCollection: (collection) => void add(collection),
                onCreateCollection: () => showCreateAlbum(false, add),
            });
        },
        [
            handleOpenCollectionSelector,
            showCreateAlbum,
            showLoadingBar,
            hideLoadingBar,
            remotePull,
            showNotification,
            onGenericError,
        ],
    );
    const collectionOperationDialogs = (
        <>
            <CollectionSelector
                open={openCollectionSelector}
                onClose={handleCloseCollectionSelector}
                onExited={() => setAttributes(undefined)}
                attributes={attributes}
                collectionSummaries={
                    attributes?.showHiddenCollections
                        ? state.hiddenCollectionSummaries
                        : state.normalCollectionSummaries
                }
                collectionForCollectionSummaryID={(id) =>
                    findCollectionCreatingIfNeeded(state.collections, id)
                }
            />
            <SingleInputDialog
                {...albumNameInputVisibilityProps}
                title={t("new_album")}
                label={t("album_name")}
                submitButtonTitle={t("create")}
                onClose={() => {
                    setCreation(undefined);
                    albumNameInputVisibilityProps.onClose();
                }}
                onSubmit={handleAlbumNameSubmit}
            />
        </>
    );
    return {
        openCollectionSelector,
        albumNameInputVisibilityProps,
        showCreateAlbum,
        handleOpenCollectionSelector,
        handleCloseCollectionSelector,
        handleAddSingleFileToCollection,
        collectionOperationDialogs,
    };
};
