import type { FileListHeaderOrFooter } from "@/components/FileList";
import { AlbumContentHeader } from "@/components/collections/AlbumContentHeader";
import { AlbumSlideshow } from "@/components/collections/AlbumSlideshow";
import { CollectionMap } from "@/components/collections/CollectionMap";
import {
    EditAlbumDetailsDialog,
    type AlbumDetails,
} from "@/components/collections/EditAlbumDetailsDialog";
import { GalleryEmptyState } from "@/components/gallery";
import { AlbumsOverview } from "@/components/gallery/AlbumsOverview";
import { useGallerySlideshow } from "@/components/gallery/hooks/use-gallery-slideshow";
import { useAlbumNavigationData } from "@/components/gallery/use-album-navigation-data";
import { albumFilters, visibleAlbumFilters } from "@/utils/album-filters";
import { useModalVisibility } from "ente-base/components/utils/modal";
import {
    isSaveCancelled,
    isSaveComplete,
} from "ente-gallery/components/utils/save-groups";
import { ItemVisibility } from "ente-media/file-metadata";
import {
    renameCollection,
    updateCollectionDetails,
} from "ente-new/photos/services/collection";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { useOperationSource } from "./hooks/use-operation-source";

import { uploadManager } from "@/services/upload-manager";
import { useCallback, useEffect, useMemo, useState } from "react";

import { CreateAlbumDialog } from "@/components/collections/CreateAlbumDialog";
import { AlbumsNavigation } from "./AlbumsNavigation";
import { GalleryMedia } from "./GalleryMedia";
import { GallerySectionLayout } from "./GallerySectionLayout";
import { usePhotosNavigation } from "./PhotosNavigationContext";
import type { GallerySectionProps } from "./section-types";
export const AlbumsSection = ({
    library,
    operations,
    navigation,
    preferences,
    presentation,
}: GallerySectionProps) => {
    const state = library;
    const {
        user,
        filteredFiles,
        hiddenFileIDs,
        tempDeletedFileIDs,
        tempHiddenFileIDs,
        favoriteFileIDs,
        fileNormalCollectionIDs,
        collectionNameByID,
    } = library;
    const {
        onRemotePull: remotePull,
        onRemoteFilesPull: remoteFilesPull,
        onAddSaveGroup,
        setBlockingLoad,
        onMarkTempDeleted: handleMarkTempDeleted,
        onAddFileToCollection: handleAddSingleFileToCollection,
        onVisualFeedback: handleVisualFeedback,
    } = operations;
    const { isMapView, selectedPlace, placeSelectionRevision, isInSearchMode } =
        navigation;
    const {
        albumFilter,
        setAlbumFilter,
        albumSearchQuery,
        collectionsSortBy,
        onChangeCollectionsSortBy,
        albumExpansion,
        albumOpenedFromOverview,
        setAlbumSearchQuery,
    } = preferences;
    const view = navigation.view;
    const barMode =
        view?.type == "hidden-albums"
            ? "hidden-albums"
            : view?.type == "archive-albums"
              ? "archive-albums"
              : "albums";
    const isAlbumOverview = view?.type == "album-overview";
    const overviewFilter = isAlbumOverview ? view.albumFilter : undefined;
    const activeCollectionID =
        view?.type == "albums" ||
        view?.type == "hidden-albums" ||
        view?.type == "archive-albums"
            ? view.activeCollectionSummaryID
            : undefined;
    const activeCollection =
        view?.type == "albums" ||
        view?.type == "hidden-albums" ||
        view?.type == "archive-albums"
            ? view.activeCollection
            : undefined;
    const activeCollectionSummary =
        view?.type == "albums" ||
        view?.type == "hidden-albums" ||
        view?.type == "archive-albums"
            ? view.activeCollectionSummary
            : undefined;
    useOperationSource(
        isMapView
            ? {
                  mode: barMode,
                  modePlus: barMode,
                  files: filteredFiles,
                  activeCollectionID,
                  activeCollection,
                  activeCollectionSummary,
                  activePersonID: undefined,
                  disableGrouping: false,
              }
            : undefined,
        operations.setMediaSource,
    );
    const collectionSummary = activeCollectionSummary;
    const [fileListHeader, setFileListHeader] =
        useState<FileListHeaderOrFooter>();
    const {
        show: showEditAlbumDetails,
        props: editAlbumDetailsVisibilityProps,
    } = useModalVisibility();
    const createAlbum = useModalVisibility();
    const { selectCollection, showAlbumOverview } = usePhotosNavigation();
    const barCollectionSummaries =
        barMode == "hidden-albums"
            ? library.hiddenCollectionSummaries
            : barMode == "archive-albums"
              ? library.archivedCollectionSummaries
              : library.normalCollectionSummaries;
    const {
        sidebarCollectionSummaries,
        overviewAlbums,
        visibleAlbumFilters: sidebarAlbumFilters,
    } = useAlbumNavigationData({
        mode: barMode,
        collectionsSortBy,
        collectionSummaries: barCollectionSummaries,
        uncategorizedCollectionSummaryID:
            library.uncategorizedCollectionSummaryID,
        albumFilter,
        albumSearchQuery,
    });
    useEffect(() => {
        const available = visibleAlbumFilters([
            ...library.normalCollectionSummaries.values(),
        ]);
        if (!available.some(({ value }) => value == albumFilter)) {
            setAlbumFilter("ente");
            if (overviewFilter) showAlbumOverview("ente");
        }
    }, [
        library.normalCollectionSummaries,
        albumFilter,
        overviewFilter,
        setAlbumFilter,
        showAlbumOverview,
    ]);
    const isActiveCollectionDownloadInProgress = useCallback(() => {
        const group = operations.saveGroups.find(
            (g) => g.collectionSummaryID === activeCollectionID,
        );
        return !!group && !isSaveComplete(group) && !isSaveCancelled(group);
    }, [operations.saveGroups, activeCollectionID]);
    const hasActiveFileSelection =
        operations.selected.count > 0 &&
        operations.selected.collectionID === activeCollectionID;
    const activeCollectionFiles = useMemo(() => {
        if (!activeCollection) return [];
        if (barMode == "hidden-albums" || barMode == "archive-albums") {
            return filteredFiles;
        }

        return filteredFiles.filter(({ id, magicMetadata }) => {
            const visibility = magicMetadata?.data.visibility;
            const isVisible =
                visibility === undefined ||
                visibility === ItemVisibility.visible;

            return (
                isVisible &&
                !hiddenFileIDs.has(id) &&
                !tempDeletedFileIDs.has(id) &&
                !tempHiddenFileIDs.has(id)
            );
        });
    }, [
        activeCollection,
        barMode,
        filteredFiles,
        hiddenFileIDs,
        tempDeletedFileIDs,
        tempHiddenFileIDs,
    ]);
    const { slideshow, startSlideshow, closeSlideshow } = useGallerySlideshow({
        activeCollection,
        activeCollectionFiles,
        activeCollectionSummary,
        isInSearchMode,
        user,
    });

    const mapFileSource = useMemo(
        () => ({
            collectionFiles: state.collectionFiles,
            favoriteFileIDs,
            hiddenFileIDs,
            archivedFileIDs: state.archivedFileIDs,
            tempDeletedFileIDs,
            tempHiddenFileIDs,
        }),
        [
            favoriteFileIDs,
            hiddenFileIDs,
            state.archivedFileIDs,
            state.collectionFiles,
            tempDeletedFileIDs,
            tempHiddenFileIDs,
        ],
    );
    const handleEditAlbumDetails = useCallback(
        async ({ name, description, coverID }: AlbumDetails) => {
            if (!activeCollection) return;

            let didAttemptWrite = false;
            try {
                if (activeCollection.name != name) {
                    didAttemptWrite = true;
                    await renameCollection(activeCollection, name);
                }
                const descriptionChanged =
                    (
                        activeCollection.pubMagicMetadata?.data.caption ?? ""
                    ).trim() != description;
                if (descriptionChanged || coverID !== undefined) {
                    didAttemptWrite = true;
                    await updateCollectionDetails(activeCollection, {
                        description: descriptionChanged
                            ? description
                            : undefined,
                        coverID,
                    });
                }
            } finally {
                if (didAttemptWrite) {
                    await remotePull({
                        silent: true,
                        source: "update-album-details",
                    });
                }
            }
        },
        [activeCollection, remotePull],
    );

    const collectionMap = activeCollectionSummary && (
        <CollectionMap
            collectionSummary={activeCollectionSummary}
            files={activeCollection ? activeCollectionFiles : filteredFiles}
            selectedPlace={
                activeCollectionID === PseudoCollectionID.all
                    ? selectedPlace
                    : undefined
            }
            placeSelectionRevision={placeSelectionRevision}
            mapFileSource={mapFileSource}
            onRemotePull={remotePull}
            onAddSaveGroup={onAddSaveGroup}
            onMarkTempDeleted={handleMarkTempDeleted}
            onAddFileToCollection={handleAddSingleFileToCollection}
            onRemoteFilesPull={remoteFilesPull}
            onVisualFeedback={handleVisualFeedback}
            fileNormalCollectionIDs={fileNormalCollectionIDs}
            collectionNameByID={collectionNameByID}
            emailByUserID={state.emailByUserID}
        />
    );

    const { setSectionActivity } = operations;
    useEffect(() => {
        setSectionActivity({
            selection: !!slideshow || editAlbumDetailsVisibilityProps.open,
            drop: !!slideshow,
        });
        return () => setSectionActivity({ selection: false, drop: false });
    }, [slideshow, editAlbumDetailsVisibilityProps.open, setSectionActivity]);
    return (
        <GallerySectionLayout
            presentation={presentation}
            fullBleed={isMapView}
            navigation={
                <AlbumsNavigation
                    mode={barMode}
                    {...presentation}
                    albumExpansion={albumExpansion}
                    albumFilter={albumFilter}
                    albumSearchQuery={albumSearchQuery}
                    onAlbumSearchQueryChange={setAlbumSearchQuery}
                    collectionSummaries={sidebarCollectionSummaries}
                    visibleAlbumFilters={sidebarAlbumFilters}
                    uncategorizedCollectionSummaryID={
                        library.uncategorizedCollectionSummaryID
                    }
                    activeCollectionID={activeCollectionID}
                    onCreateAlbum={createAlbum.show}
                    collectionsSortBy={collectionsSortBy}
                    onChangeCollectionsSortBy={onChangeCollectionsSortBy}
                />
            }
        >
            {!isMapView && (
                <AlbumContentHeader
                    albums={sidebarCollectionSummaries}
                    user={user!}
                    activeCollection={activeCollection}
                    collectionSummary={collectionSummary}
                    setBlockingLoad={setBlockingLoad}
                    setFileListHeader={setFileListHeader}
                    hasActiveFileSelection={hasActiveFileSelection}
                    isActiveCollectionDownloadInProgress={
                        isActiveCollectionDownloadInProgress
                    }
                    onAddSaveGroup={onAddSaveGroup}
                    showBackToAlbums={
                        albumOpenedFromOverview !== undefined &&
                        albumOpenedFromOverview.collectionID ===
                            collectionSummary?.id
                    }
                    onEditAlbumDetails={showEditAlbumDetails}
                    onCollectionSlideshow={startSlideshow}
                    emailByUserID={library.emailByUserID}
                    shareSuggestionEmails={library.shareSuggestionEmails}
                    onRemotePull={remotePull}
                />
            )}
            {isMapView ? (
                collectionMap
            ) : !library.isFirstLoad &&
              !library.collectionFiles.length &&
              activeCollectionID === PseudoCollectionID.all ? (
                <GalleryEmptyState
                    isUploadInProgress={uploadManager.isUploadInProgress()}
                    onUpload={operations.onUpload}
                />
            ) : !library.isFirstLoad && isAlbumOverview ? (
                <AlbumsOverview
                    onRemotePull={remotePull}
                    albums={overviewAlbums}
                    title={(
                        albumFilters.find(
                            ({ value }) => value == overviewFilter,
                        ) ?? albumFilters[0]!
                    ).title()}
                    filter={overviewFilter!}
                    searchQuery={albumSearchQuery}
                    sortBy={collectionsSortBy}
                    onCreateAlbum={operations.onCreateAlbum}
                />
            ) : (
                <GalleryMedia
                    {...{ library, operations, navigation }}
                    header={fileListHeader}
                    source={{
                        mode: barMode,
                        modePlus: barMode,
                        files: filteredFiles,
                        activeCollectionID: activeCollectionID!,
                        activeCollectionSummary,
                        activeCollection,
                        activePersonID: undefined,
                        disableGrouping:
                            activeCollection?.pubMagicMetadata?.data.sortBy ==
                            "fileName",
                    }}
                />
            )}
            <CreateAlbumDialog
                {...createAlbum.props}
                isHidden={barMode == "hidden-albums"}
                onRemotePull={remotePull}
                onSelectCollectionID={(id) => {
                    selectCollection(id);
                    presentation.mobileDrawerProps.onClose();
                }}
            />
            {slideshow &&
                slideshow.collectionID === activeCollection?.id &&
                !isInSearchMode && (
                    <AlbumSlideshow
                        files={slideshow.files}
                        title={slideshow.title}
                        onClose={closeSlideshow}
                    />
                )}
            {activeCollection && editAlbumDetailsVisibilityProps.open && (
                <EditAlbumDetailsDialog
                    key={activeCollection.id}
                    {...editAlbumDetailsVisibilityProps}
                    collection={activeCollection}
                    files={activeCollectionFiles}
                    initialCoverFile={activeCollectionSummary?.coverFile}
                    onSubmit={handleEditAlbumDetails}
                />
            )}
        </GallerySectionLayout>
    );
};
