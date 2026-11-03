import type {
    CollectionSelector,
    CollectionSelectorAttributes,
} from "@/components/CollectionSelector";
import {
    findCollectionCreatingIfNeeded,
    performCollectionOp,
} from "@/components/gallery/helpers";
import type { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import {
    createAlbum,
    createHiddenAlbum,
    renameCollection,
} from "ente-new/photos/services/collection";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import { useCallback, useState, type ComponentProps } from "react";
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
        getOrCreate: (name: string) => Promise<Collection>;
        onCreate: (collection: Collection) => void | Promise<void>;
    }>();
    const { show, props: albumNameInputVisibilityProps } = useModalVisibility();
    const showCreateAlbum = useCallback(
        (
            hidden: boolean,
            onCreate: (collection: Collection) => void | Promise<void>,
        ) => {
            let collection: Collection | undefined;
            setCreation({
                getOrCreate: async (name) => {
                    if (!collection) {
                        collection = hidden
                            ? await createHiddenAlbum(name)
                            : await createAlbum(name);
                    } else if (collection.name !== name) {
                        await renameCollection(collection, name);
                        collection = { ...collection, name };
                    }
                    return collection;
                },
                onCreate,
            });
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
        if (!request) return;
        const collection = await request.getOrCreate(name);
        await request.onCreate(collection);
        setCreation((previous) =>
            previous === request ? undefined : previous,
        );
    };
    const handleAddSingleFileToCollection = useCallback(
        (file: EnteFile, sourceCollectionSummaryID?: number) => {
            let addedCollectionID: number | undefined;
            const add = async (collection: Collection) => {
                showLoadingBar();
                try {
                    if (addedCollectionID !== collection.id) {
                        await performCollectionOp(
                            "add",
                            collection,
                            [file],
                            sourceCollectionSummaryID,
                        );
                        addedCollectionID = collection.id;
                    }
                    await remotePull({
                        silent: true,
                        source: "single-file-add-to-album",
                    });
                    showNotification({
                        color: "primary",
                        title: t("added_to_album"),
                        caption: collection.name,
                    });
                } finally {
                    hideLoadingBar();
                }
            };
            handleOpenCollectionSelector({
                action: "add",
                sourceCollectionSummaryID,
                onSelectCollection: (collection) =>
                    void add(collection).catch(onGenericError),
                onCreateCollection: () =>
                    showCreateAlbum(false, async (collection) => {
                        await add(collection);
                        handleCloseCollectionSelector();
                    }),
            });
        },
        [
            handleOpenCollectionSelector,
            handleCloseCollectionSelector,
            showCreateAlbum,
            showLoadingBar,
            hideLoadingBar,
            remotePull,
            showNotification,
            onGenericError,
        ],
    );
    const collectionSelectorProps: ComponentProps<typeof CollectionSelector> = {
        open: openCollectionSelector,
        onClose: handleCloseCollectionSelector,
        onExited: () => setAttributes(undefined),
        attributes,
        collectionSummaries: attributes?.showHiddenCollections
            ? state.hiddenCollectionSummaries
            : state.normalCollectionSummaries,
        collectionForCollectionSummaryID: (id) =>
            findCollectionCreatingIfNeeded(state.collections, id),
    };
    const albumNameInputProps: ComponentProps<typeof SingleInputDialog> = {
        ...albumNameInputVisibilityProps,
        title: t("new_album"),
        label: t("album_name"),
        submitButtonTitle: t("create"),
        onClose: () => {
            setCreation(undefined);
            albumNameInputVisibilityProps.onClose();
        },
        onSubmit: handleAlbumNameSubmit,
    };
    return {
        openCollectionSelector,
        albumNameInputVisibilityProps,
        showCreateAlbum,
        handleOpenCollectionSelector,
        handleCloseCollectionSelector,
        handleAddSingleFileToCollection,
        collectionSelectorProps,
        albumNameInputProps,
    };
};
