import { QuickLinkCreatedNotification } from "@/components/QuickLinkCreatedNotification";
import { GalleryDownloadNotifications } from "@/components/gallery/GalleryDownloadNotifications";
import { useFileMutations } from "@/components/gallery/hooks/use-file-mutations";
import type { useGalleryLibrary } from "@/components/gallery/hooks/use-gallery-library";
import { useGalleryUploads } from "@/components/gallery/hooks/use-gallery-uploads";
import type { GalleryBarMode } from "@/components/gallery/reducer";
import type { GallerySectionOperations } from "@/components/gallery/section-types";
import { TranslucentLoadingOverlay } from "ente-base/components/loaders";
import { useSaveGroups } from "ente-gallery/components/utils/save-groups";
import { ItemVisibility } from "ente-media/file-metadata";
import { haveOnlySystemCollections } from "ente-new/photos/services/collection-summary";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { useCallback, useState } from "react";
import type { GalleryNavigationState } from "../navigation-state";
import { useCollectionDialogs } from "./use-collection-dialogs";
export const useGalleryOperations = (
    libraryOwner: ReturnType<typeof useGalleryLibrary>,
    navigation: GalleryNavigationState,
    authenticateOpen: boolean,
    showSettings: (action?: SidebarActionID) => void,
) => {
    const {
        state,
        dispatch,
        peopleState,
        remotePull,
        remoteFilesPull,
        showSessionExpiredDialog,
    } = libraryOwner;
    const { user, normalCollectionSummaries } = state;
    const barMode: GalleryBarMode =
        navigation.destination.albumMode ?? "albums";
    const activeCollection = state.collections.find(
        (collection) => collection.id === navigation.destination.collectionID,
    );
    const isCleanupViewOpen =
        navigation.overlay?.section === "duplicates" ||
        navigation.overlay?.section === "large-files";
    const { showLoadingBar, hideLoadingBar } = usePhotosAppContext();
    const [sectionActivity, setSectionActivity] = useState({
        selection: false,
        drop: false,
    });
    const [blockingLoad, setBlockingLoad] = useState(false);
    const { saveGroups, onAddSaveGroup, onRemoveSaveGroup } = useSaveGroups();
    const quickLinkVisibility =
        barMode == "hidden-albums"
            ? ItemVisibility.hidden
            : ItemVisibility.visible;
    const {
        publicLinkToast,
        setPublicLinkToast,
        handleFavoriteFileOp,
        onSendLinkError,
        handleFileViewerToggleFavorite,
        handleFileViewerFileVisibilityUpdate,
        handleFileViewerSendLink,
        handleMarkTempDeleted,
    } = useFileMutations({ state, dispatch, remotePull, quickLinkVisibility });
    const handleVisualFeedback = useCallback(() => {
        showLoadingBar();
        setTimeout(hideLoadingBar, 0);
    }, [showLoadingBar, hideLoadingBar]);
    const {
        openCollectionSelector,
        albumNameInputVisibilityProps,
        showCreateAlbum,
        handleOpenCollectionSelector,
        handleCloseCollectionSelector,
        handleAddSingleFileToCollection,
        collectionOperationDialogs,
    } = useCollectionDialogs({ state, remotePull });
    const { openUploader, uploadTypeSelectorView, uploadUI, dropzoneProps } =
        useGalleryUploads({
            user,
            activeCollection,
            isFirstUpload: haveOnlySystemCollections(normalCollectionSummaries),
            isInHiddenSection: barMode == "hidden-albums",
            onUploadFile: (file) => dispatch({ type: "uploadFile", file }),
            onShowSubscription: () => showSettings("subscription"),
            onRemotePull: remotePull,
            onRemoteFilesPull: remoteFilesPull,
            onOpenCollectionSelector: handleOpenCollectionSelector,
            onCloseCollectionSelector: handleCloseCollectionSelector,
            onShowSessionExpiredDialog: showSessionExpiredDialog,
            setLoading: setBlockingLoad,
        });
    const sectionOperations: GallerySectionOperations = {
        dispatch,
        peopleState,
        mutations: {
            setPublicLinkToast,
            handleFavoriteFileOp,
            onSendLinkError,
            handleMarkTempDeleted,
        },
        selectionDisabled:
            uploadTypeSelectorView ||
            openCollectionSelector ||
            albumNameInputVisibilityProps.open ||
            authenticateOpen ||
            sectionActivity.selection,
        onAddSaveGroup,
        onToggleFavorite: handleFileViewerToggleFavorite,
        onFileVisibilityUpdate: handleFileViewerFileVisibilityUpdate,
        onSendLink: handleFileViewerSendLink,
        onMarkTempDeleted: handleMarkTempDeleted,
        onRemotePull: remotePull,
        onRemoteFilesPull: remoteFilesPull,
        onVisualFeedback: handleVisualFeedback,
        onAddFileToCollection: handleAddSingleFileToCollection,
        onPendingNavigationConsumed: () => undefined,
        setBlockingLoad,
        onUpload: openUploader,
        onCreateAlbum: () => showCreateAlbum(),
        saveGroups,
        setSectionActivity,
    };

    return {
        operations: sectionOperations,
        dropzoneProps: {
            ...dropzoneProps,
            disabled:
                dropzoneProps.disabled ||
                sectionActivity.drop ||
                isCleanupViewOpen,
        },
        ui: (
            <>
                {blockingLoad && <TranslucentLoadingOverlay />}
                {collectionOperationDialogs}
                <GalleryDownloadNotifications
                    {...{ saveGroups, onRemoveSaveGroup }}
                />
                {uploadUI}
                <QuickLinkCreatedNotification
                    open={publicLinkToast.open}
                    onCopy={() => {
                        if (publicLinkToast.url)
                            void navigator.clipboard.writeText(
                                publicLinkToast.url,
                            );
                    }}
                    onClose={() =>
                        setPublicLinkToast((prev) => ({ ...prev, open: false }))
                    }
                />
            </>
        ),
    };
};
