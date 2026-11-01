import { AlbumsSection } from "@/components/gallery/AlbumsSection";
import { GalleryDownloadNotifications } from "@/components/gallery/GalleryDownloadNotifications";
import { GalleryMedia } from "@/components/gallery/GalleryMedia";
import { GallerySectionLayout } from "@/components/gallery/GallerySectionLayout";
import { PeopleSection } from "@/components/gallery/PeopleSection";
import { PlacesSection } from "@/components/gallery/PlacesSection";
import { useCollectionOperations } from "@/components/gallery/hooks/use-collection-operations";
import { useFileContextActions } from "@/components/gallery/hooks/use-file-context-actions";
import { useFileMutations } from "@/components/gallery/hooks/use-file-mutations";
import { useGallerySelection } from "@/components/gallery/hooks/use-gallery-selection";
import { useGalleryUploads } from "@/components/gallery/hooks/use-gallery-uploads";
import { useMapEntry } from "@/components/gallery/hooks/use-map-entry";
import { usePeopleEntry } from "@/components/gallery/hooks/use-people-entry";
import { useSelectedFileOperations } from "@/components/gallery/hooks/use-selected-file-operations";
import type { GallerySectionOperations } from "@/components/gallery/section-types";
// TODO: Audit this file (the code here is mostly fine, but needs revisiting
// the file it depends on have been audited and their interfaces fixed).
/* eslint-disable react-hooks/exhaustive-deps */
import { AuthenticateUser } from "@/components/AuthenticateUser";
import { DesktopWhatsNew } from "@/components/DesktopWhatsNew";
import type { FileListHeaderOrFooter } from "@/components/FileList";
import { QuickLinkCreatedNotification } from "@/components/QuickLinkCreatedNotification";
import { SelectedFileOptions } from "@/components/SelectedFileOptions";
import { SearchResultsHeader } from "@/components/gallery";
import { DuplicatesView } from "@/components/gallery/DuplicatesView";
import { LargeFilesView } from "@/components/gallery/LargeFilesView";
import { LinksView } from "@/components/gallery/LinksView";
import {
    PhotosNavigationContext,
    type PhotosNavigationActions,
} from "@/components/gallery/PhotosNavigationContext";
import {
    PhotosNavigationShell,
    type PhotosNavigationShellHandle,
} from "@/components/gallery/PhotosNavigationShell";
import type { PlaceSelection } from "@/components/gallery/PlacesList";
import {
    albumShortcutCollectionID,
    showCollectionSummaryWithAuthentication,
} from "@/components/gallery/helpers";
import { useGalleryAuthentication } from "@/components/gallery/hooks/use-gallery-authentication";
import { useGalleryLibrary } from "@/components/gallery/hooks/use-gallery-library";
import { useGalleryPreferences } from "@/components/gallery/hooks/use-gallery-preferences";
import type { GalleryBarMode } from "@/components/gallery/reducer";
import type { AlbumFilter } from "@/utils/album-filters";
import { TranslucentLoadingOverlay } from "ente-base/components/loaders";
import { FullScreenDropZone } from "ente-gallery/components/FullScreenDropZone";
import { useSaveGroups } from "ente-gallery/components/utils/save-groups";
import type { FileViewerInitialSidebar } from "ente-gallery/components/viewer/FileViewer";
import { ItemVisibility } from "ente-media/file-metadata";
import {
    haveOnlySystemCollections,
    PseudoCollectionID,
} from "ente-new/photos/services/collection-summary";

import { getSelectedFiles, type SelectedState } from "@/utils/file";
import { filterSearchableFiles } from "ente-new/photos/services/search";
import type { SearchOption } from "ente-new/photos/services/search/types";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { useRouter } from "next/router";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

const Page: React.FC = () => {
    const { showLoadingBar, hideLoadingBar } = usePhotosAppContext();

    const {
        state,
        dispatch,
        isFirstLoad,
        peopleState,
        remotePull,
        remoteFilesPull,
        showSessionExpiredDialog,
    } = useGalleryLibrary();

    const [cleanupView, setCleanupView] = useState<
        "large-files" | "duplicates"
    >();
    const isCleanupViewOpen = cleanupView !== undefined;
    const [isContextMenuOpen, setIsContextMenuOpen] = useState(false);
    const { selected, setSelected, clearSelection } = useGallerySelection();
    const [sectionActivity, setSectionActivity] = useState({
        selection: false,
        drop: false,
    });
    const [blockingLoad, setBlockingLoad] = useState(false);
    const [isFileViewerOpen, setIsFileViewerOpen] = useState(false);
    const [pendingFileNavigation, setPendingFileNavigation] = useState<{
        fileIndex: number;
        sidebar?: FileViewerInitialSidebar;
        commentID?: string;
    }>();
    const [fileListHeader, setFileListHeader] = useState<
        FileListHeaderOrFooter | undefined
    >(undefined);

    const { saveGroups, onAddSaveGroup, onRemoveSaveGroup } = useSaveGroups();
    const navigationRef = useRef<PhotosNavigationShellHandle>(null);

    const lastAuthenticationForHiddenTimestamp = useRef<number>(0);

    const { authenticateUser, authenticateUserDialogProps } =
        useGalleryAuthentication();
    const [selectedPlace, setSelectedPlace] = useState<PlaceSelection>();
    const [placeSelectionRevision, setPlaceSelectionRevision] = useState(0);
    const [isMapView, setIsMapView] = useState(false);
    const closeCollectionMap = useCallback(() => setIsMapView(false), []);

    const openMap = useCallback(() => setIsMapView(true), []);
    const handleShowCollectionMap = useMapEntry(openMap);
    const {
        user,
        collectionNameByID,
        hiddenCollectionIDs,
        normalCollectionSummaries,
        hiddenFileIDs,
        tempDeletedFileIDs,
        tempHiddenFileIDs,
        isInSearchMode,
        filteredFiles,
    } = state;

    const isAlbumOverview = state.view?.type == "album-overview";
    const barMode =
        state.view?.type == "album-overview"
            ? "albums"
            : (state.view?.type ?? "albums");
    const overviewFilter =
        state.view?.type == "album-overview"
            ? state.view.albumFilter
            : undefined;
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

    const activeCollectionID =
        state.view?.type == "people" ||
        state.view?.type == "album-overview" ||
        state.view?.type == "links"
            ? undefined
            : state.view?.activeCollectionSummaryID;
    const activeCollection =
        state.view?.type == "people" ||
        state.view?.type == "album-overview" ||
        state.view?.type == "links"
            ? undefined
            : state.view?.activeCollection;
    const activeCollectionSummary =
        state.view?.type == "people" ||
        state.view?.type == "album-overview" ||
        state.view?.type == "links"
            ? undefined
            : state.view?.activeCollectionSummary;
    const selectedLinkID =
        state.view?.type == "links" ? state.view.selectedLinkID : undefined;
    const galleryBarActiveCollectionID =
        barMode == "links" ? selectedLinkID : activeCollectionID;
    const preferences = useGalleryPreferences({
        barMode,
        activeCollectionID,
        navigationAvailable: !isCleanupViewOpen && !isInSearchMode,
    });
    const {
        setAlbumFilter,
        albumSearchQuery,
        setAlbumSearchQuery,
        albumOpenedFromOverview,
        setAlbumOpenedFromOverview,
        collectionsSortBy,
        onChangeCollectionsSortBy,
    } = preferences;

    const activePerson =
        state.view?.type == "people" ? state.view.activePerson : undefined;
    const activePersonID = activePerson?.id;
    const selectedFilesInView = useMemo(
        () => getSelectedFiles(selected, filteredFiles),
        [selected, filteredFiles],
    );
    const isAllSelectedInView =
        filteredFiles.length > 0 &&
        selectedFilesInView.length === filteredFiles.length;

    const barCollectionSummaries =
        barMode == "hidden-albums"
            ? state.hiddenCollectionSummaries
            : barMode == "archive-albums"
              ? state.archivedCollectionSummaries
              : state.normalCollectionSummaries;

    const collectionSummary = barCollectionSummaries.get(
        galleryBarActiveCollectionID!,
    );

    const router = useRouter();

    useEffect(() => {
        if (
            (!isAlbumOverview && typeof activeCollectionID == "undefined") ||
            !router.isReady
        ) {
            return;
        }
        let collectionURL = "";
        if (!isAlbumOverview && activeCollectionID !== PseudoCollectionID.all) {
            // TODO: Is this URL param even used?
            collectionURL = `?collection=${activeCollectionID}`;
        }
        const href = `/gallery${collectionURL}`;
        void router.push(href, undefined, { shallow: true });
    }, [activeCollectionID, isAlbumOverview, router.isReady]);

    useEffect(() => {
        if (!activeCollectionSummary) closeCollectionMap();
    }, [activeCollectionSummary, closeCollectionMap]);

    useEffect(() => {
        if (isInSearchMode && state.searchSuggestion) {
            setFileListHeader({
                component: (
                    <SearchResultsHeader
                        searchSuggestion={state.searchSuggestion}
                        fileCount={state.searchResults?.length ?? 0}
                        sortAsc={state.searchSortAsc}
                        onSortOrderChange={(asc) =>
                            dispatch({ type: "setSearchSortOrder", asc })
                        }
                    />
                ),
                height: 104,
            });
        }
    }, [
        isInSearchMode,
        state.searchSuggestion,
        state.searchResults,
        state.searchSortAsc,
    ]);

    useEffect(() => {
        const pendingSearchSuggestion = state.pendingSearchSuggestions.at(-1);
        if (!state.isRecomputingSearchResults && pendingSearchSuggestion) {
            dispatch({ type: "updatingSearchResults" });
            // TODO: A rejection leaves isRecomputingSearchResults stuck true,
            // and search stops until it is exited. Recovery needs a reducer
            // change.
            void filterSearchableFiles(pendingSearchSuggestion).then(
                (searchResults) => {
                    dispatch({ type: "setSearchResults", searchResults });
                },
            );
        }
    }, [state.isRecomputingSearchResults, state.pendingSearchSuggestions]);

    const selectAll = (e: KeyboardEvent) => {
        if (
            e.target instanceof HTMLInputElement ||
            e.target instanceof HTMLTextAreaElement
        ) {
            return;
        }

        e.preventDefault();

        if (
            !user ||
            !filteredFiles.length ||
            uploadTypeSelectorView ||
            openCollectionSelector ||
            fixCreationTimeVisibilityProps.open ||
            authenticateUserDialogProps.open ||
            albumNameInputVisibilityProps.open ||
            sectionActivity.selection ||
            isFileViewerOpen
        ) {
            return;
        }

        const selected: SelectedState = {
            ownCount: 0,
            count: 0,
            collectionID: activeCollectionID,
            context:
                barMode == "people" && activePersonID
                    ? { mode: "people", personID: activePersonID }
                    : {
                          mode: barMode as
                              "albums" | "hidden-albums" | "archive-albums",
                          collectionID: activeCollectionID!,
                      },
        };

        filteredFiles.forEach((item) => {
            if (item.ownerID === user.id) {
                selected.ownCount++;
            }
            selected.count++;
            selected[item.id] = true;
        });
        setSelected(selected);
    };

    const handleSelectAll = () => {
        if (!user || !filteredFiles.length) return;

        const selected: SelectedState = {
            ownCount: 0,
            count: 0,
            collectionID: activeCollectionID,
            context:
                barMode == "people" && activePersonID
                    ? { mode: "people", personID: activePersonID }
                    : {
                          mode: barMode as
                              "albums" | "hidden-albums" | "archive-albums",
                          collectionID: activeCollectionID!,
                      },
        };

        filteredFiles.forEach((item) => {
            if (item.ownerID === user.id) {
                selected.ownCount++;
            }
            selected.count++;
            selected[item.id] = true;
        });
        setSelected(selected);
    };

    const keyboardShortcutHandlerRef = useRef({
        selectAll,
        clearSelection,
        isCleanupViewOpen,
    });

    useEffect(() => {
        keyboardShortcutHandlerRef.current = {
            selectAll,
            clearSelection,
            isCleanupViewOpen,
        };
    }, [selectAll, clearSelection, isCleanupViewOpen]);

    const handleVisualFeedback = useCallback(() => {
        showLoadingBar();
        setTimeout(hideLoadingBar, 0);
    }, [showLoadingBar, hideLoadingBar]);

    const handlePendingNavigationConsumed = useCallback(() => {
        setPendingFileNavigation(undefined);
    }, []);

    const setupSelectAllKeyBoardShortcutHandler = () => {
        const handleKeyUp = (e: KeyboardEvent) => {
            if (keyboardShortcutHandlerRef.current.isCleanupViewOpen) return;
            switch (e.key) {
                case "Escape":
                    keyboardShortcutHandlerRef.current.clearSelection();
                    break;
                case "a":
                    if (e.ctrlKey || e.metaKey) {
                        keyboardShortcutHandlerRef.current.selectAll(e);
                    }
                    break;
            }
        };
        document.addEventListener("keydown", handleKeyUp);
        return () => {
            document.removeEventListener("keydown", handleKeyUp);
        };
    };

    useEffect(() => {
        return user ? setupSelectAllKeyBoardShortcutHandler() : undefined;
    }, [!!user]);

    const {
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
    } = useCollectionOperations({
        state,
        selected,
        filteredFiles,
        barMode,
        clearSelection,
        remotePull,
    });

    const {
        suppressContextSelectionBar,
        showAddPersonAction,
        fixCreationTimeVisibilityProps,
        showEditLocation,
        showContextMenuAssignPerson,
        createFileOpHandler,
        handleDeleteFiles,
        selectedFavoriteCount,
        selectedCount,
        selectedOwnCount,
        selectedFileOperationDialogs,
    } = useSelectedFileOperations({
        state,
        dispatch,
        peopleState,
        selected,
        filteredFiles,
        quickLinkVisibility,
        clearSelection,
        onAddSaveGroup,
        remotePull,
        mutations: {
            setPublicLinkToast,
            handleFavoriteFileOp,
            onSendLinkError,
            handleMarkTempDeleted,
        },
    });

    const { openUploader, uploadTypeSelectorView, uploadUI, dropzoneProps } =
        useGalleryUploads({
            user,
            activeCollection,
            isFirstUpload: haveOnlySystemCollections(normalCollectionSummaries),
            isInHiddenSection: barMode == "hidden-albums",
            onUploadFile: (file) => dispatch({ type: "uploadFile", file }),
            onShowSubscription: () =>
                navigationRef.current?.showSettings("subscription"),
            onRemotePull: remotePull,
            onRemoteFilesPull: remoteFilesPull,
            onOpenCollectionSelector: handleOpenCollectionSelector,
            onCloseCollectionSelector: handleCloseCollectionSelector,
            onShowSessionExpiredDialog: showSessionExpiredDialog,
            setLoading: setBlockingLoad,
        });

    const handleShowCollectionSummaryWithID = useCallback(
        (collectionSummaryID: number | undefined) => {
            setAlbumOpenedFromOverview(undefined);
            setIsMapView(false);
            setCleanupView(undefined);
            // Museum deletes collection contents asynchronously; pull on entry.
            if (collectionSummaryID == PseudoCollectionID.trash) {
                void remoteFilesPull();
            }

            dispatch({ type: "showCollectionSummary", collectionSummaryID });
        },
        [],
    );

    const showCollectionSummary = useCallback(
        (
            collectionSummaryID: number | undefined,
            isHiddenCollectionSummary?: boolean,
        ) =>
            showCollectionSummaryWithAuthentication(
                collectionSummaryID,
                !!isHiddenCollectionSummary && barMode != "hidden-albums",
                lastAuthenticationForHiddenTimestamp,
                authenticateUser,
                handleShowCollectionSummaryWithID,
            ),
        [authenticateUser, handleShowCollectionSummaryWithID, barMode],
    );

    const handleSelectSearchOption = useCallback(
        (
            searchOption: SearchOption | undefined,
            options?: { shouldExitSearchMode?: boolean },
        ) => {
            setIsMapView(false);
            if (searchOption) {
                const type = searchOption.suggestion.type;
                if (type == "sidebarAction") {
                    const collectionID = albumShortcutCollectionID(
                        searchOption.suggestion.actionID,
                        state.uncategorizedCollectionSummaryID,
                    );
                    if (collectionID !== undefined) {
                        void showCollectionSummary(
                            collectionID,
                            collectionID == PseudoCollectionID.hiddenItems,
                        );
                        return;
                    }
                }
                setCleanupView(undefined);
                if (type == "collection") {
                    dispatch({
                        type: "showCollectionSummary",
                        collectionSummaryID:
                            searchOption.suggestion.collectionID,
                    });
                } else if (type == "person") {
                    dispatch({
                        type: "showPerson",
                        personID: searchOption.suggestion.person.id,
                    });
                } else if (type == "sidebarAction") {
                    navigationRef.current?.showSettings(
                        searchOption.suggestion.actionID,
                    );

                    const shouldExitSearchMode =
                        options?.shouldExitSearchMode ?? true;
                    dispatch({ type: "exitSearch", shouldExitSearchMode });
                } else {
                    if (barMode === "hidden-albums") {
                        dispatch({ type: "showAlbums" });
                    }
                    dispatch({
                        type: "enterSearchMode",
                        searchSuggestion: searchOption.suggestion,
                    });
                }
            } else {
                const shouldExitSearchMode =
                    options?.shouldExitSearchMode ?? true;
                dispatch({ type: "exitSearch", shouldExitSearchMode });
            }
        },
        [
            barMode,
            dispatch,
            showCollectionSummary,
            state.uncategorizedCollectionSummaryID,
        ],
    );

    const handleShowCleanupView = useCallback(
        (view: "large-files" | "duplicates") => {
            setIsMapView(false);
            setSelected({
                ownCount: 0,
                count: 0,
                collectionID: 0,
                context: undefined,
            });
            closeCollectionMap();
            dispatch({ type: "exitSearch", shouldExitSearchMode: true });
            setCleanupView(view);
        },
        [closeCollectionMap],
    );

    const handlePeopleUnavailable = useCallback(
        () => handleShowCollectionSummaryWithID(PseudoCollectionID.all),
        [handleShowCollectionSummaryWithID],
    );
    const handleNavigateToPeople = useCallback(() => {
        setIsMapView(false);
        setCleanupView(undefined);
        dispatch({ type: "showPeople" });
    }, [dispatch]);
    const { showPeople: handleShowPeople, dialog: peopleConsentDialog } =
        usePeopleEntry({
            isCurrentDestination: barMode == "people",
            onUnavailable: handlePeopleUnavailable,
            onNavigate: handleNavigateToPeople,
        });
    const handleBackToPeople = useCallback(() => {
        setCleanupView(undefined);
        setSelected({
            ownCount: 0,
            count: 0,
            collectionID: 0,
            context: undefined,
        });
        dispatch({ type: "showPeople" });
    }, []);

    const handleShowAlbumOverview = useCallback(
        (filter: AlbumFilter) => {
            setCleanupView(undefined);
            clearSelection();
            setAlbumFilter(filter);
            dispatch({ type: "showAlbumOverview", albumFilter: filter });
        },
        [clearSelection, dispatch],
    );

    const handleBackToAlbums = useCallback(() => {
        setCleanupView(undefined);
        const origin =
            albumOpenedFromOverview?.collectionID === collectionSummary?.id
                ? albumOpenedFromOverview
                : undefined;
        const filter = origin?.filter ?? "ente";
        setAlbumSearchQuery(origin?.searchQuery ?? "");
        setSelected({
            ownCount: 0,
            count: 0,
            collectionID: 0,
            context: undefined,
        });
        setAlbumFilter(filter);
        dispatch({ type: "showAlbumOverview", albumFilter: filter });
    }, [albumOpenedFromOverview, collectionSummary?.id]);

    const handleChangeBarMode = useCallback(
        (mode: GalleryBarMode) => {
            if (mode == "links") {
                setCleanupView(undefined);
                clearSelection();
                dispatch({ type: "showLinks" });
                return true;
            }
            if (mode == "people") {
                return handleShowPeople();
            }
            setCleanupView(undefined);
            handleShowAlbumOverview("ente");
            return true;
        },
        [clearSelection, dispatch, handleShowAlbumOverview, handleShowPeople],
    );

    const handleSelectCollection = useCallback(
        (collectionID: number) => {
            setIsMapView(false);
            closeCollectionMap();
            dispatch({
                type: "showCollectionSummary",
                collectionSummaryID: collectionID,
            });
        },
        [closeCollectionMap],
    );

    const handleSelectPerson = useCallback(
        (personID: string) => {
            setCleanupView(undefined);
            setIsMapView(false);
            closeCollectionMap();
            dispatch({ type: "showPerson", personID });
        },
        [closeCollectionMap],
    );

    const handleContextMenuAction = useFileContextActions({
        collectionOperations: {
            createOnCreateForCollectionOp,
            createOnSelectForCollectionOp,
            handleOpenCollectionSelector,
            handleRemoveFilesFromCollection,
        },
        selectedOperations: {
            createFileOpHandler,
            handleDeleteFiles,
            showContextMenuAssignPerson,
            showEditLocation,
            selectedCount,
            selectedOwnCount,
        },
        activeCollection,
        activeCollectionSummary,
        barMode,
    });

    const hasActiveFileSelection =
        selected.count > 0 && selected.collectionID === activeCollectionID;
    const showSelectionBar =
        hasActiveFileSelection &&
        !suppressContextSelectionBar &&
        !(isContextMenuOpen && selected.count === 1);

    const selectGalleryCollection = useCallback(
        (collectionID: number) => {
            if (barMode == "links") {
                dispatch({ type: "selectLink", collectionID });
            } else {
                handleShowCollectionSummaryWithID(collectionID);
            }
        },
        [barMode, dispatch, handleShowCollectionSummaryWithID],
    );
    const handleGoHome = useCallback(() => {
        setIsMapView(false);
        handleShowCollectionSummaryWithID(PseudoCollectionID.all);
    }, [handleShowCollectionSummaryWithID]);
    const handleChangeMode = useCallback(
        (mode: GalleryBarMode) => {
            const changed = handleChangeBarMode(mode);
            if (changed) setIsMapView(false);
            return changed;
        },
        [handleChangeBarMode],
    );
    const handleShowLibraryMap = useCallback(() => {
        setSelectedPlace(undefined);
        handleShowCollectionSummaryWithID(PseudoCollectionID.all);
        handleShowCollectionMap();
    }, [handleShowCollectionSummaryWithID, handleShowCollectionMap]);
    const handleSelectPlace = useCallback(
        (place: PlaceSelection | undefined) => {
            setSelectedPlace(place);
            setPlaceSelectionRevision((revision) => revision + 1);
        },
        [],
    );
    const handleOpenOverviewAlbum = useCallback(
        (collectionID: number) => {
            handleShowCollectionSummaryWithID(collectionID);
            setAlbumOpenedFromOverview({
                collectionID,
                filter: overviewFilter!,
                searchQuery: albumSearchQuery,
            });
        },
        [handleShowCollectionSummaryWithID, overviewFilter, albumSearchQuery],
    );
    const handleShowLinksOverview = useCallback(
        () => handleChangeBarMode("links"),
        [handleChangeBarMode],
    );
    const navigationActions = useMemo<PhotosNavigationActions>(
        () => ({
            goHome: handleGoHome,
            changeMode: handleChangeMode,
            showLibraryMap: handleShowLibraryMap,
            showCollectionMap: handleShowCollectionMap,
            selectPlace: handleSelectPlace,
            showCollectionSummary,
            selectCollection: selectGalleryCollection,
            selectCollectionFromViewer: handleSelectCollection,
            openOverviewAlbum: handleOpenOverviewAlbum,
            showAlbumOverview: handleShowAlbumOverview,
            backToAlbums: handleBackToAlbums,
            showLinksOverview: handleShowLinksOverview,
            showPeople: handleShowPeople,
            selectPerson: handleSelectPerson,
            backToPeople: handleBackToPeople,
            selectSearchOption: handleSelectSearchOption,
            showCleanupView: handleShowCleanupView,
        }),
        [
            handleGoHome,
            handleChangeMode,
            handleShowLibraryMap,
            handleShowCollectionMap,
            handleSelectPlace,
            showCollectionSummary,
            selectGalleryCollection,
            handleSelectCollection,
            handleOpenOverviewAlbum,
            handleShowAlbumOverview,
            handleBackToAlbums,
            handleShowLinksOverview,
            handleShowPeople,
            handleSelectPerson,
            handleBackToPeople,
            handleSelectSearchOption,
            handleShowCleanupView,
        ],
    );

    const sectionLibrary = { ...state, isFirstLoad };
    const sectionNavigation = {
        view: state.view,
        isInSearchMode,
        isMapView,
        selectedPlace,
        placeSelectionRevision,
        pendingFileNavigation,
    };
    const sectionOperations: GallerySectionOperations = {
        selected,
        setSelected,
        onContextMenuAction: handleContextMenuAction,
        onContextMenuOpenChange: setIsContextMenuOpen,
        suppressSelectionUI: suppressContextSelectionBar,
        showAddPersonAction,
        onAddSaveGroup,
        onToggleFavorite: handleFileViewerToggleFavorite,
        onFileVisibilityUpdate: handleFileViewerFileVisibilityUpdate,
        onSendLink: handleFileViewerSendLink,
        onMarkTempDeleted: handleMarkTempDeleted,
        onSetOpenFileViewer: setIsFileViewerOpen,
        onRemotePull: remotePull,
        onRemoteFilesPull: remoteFilesPull,
        onVisualFeedback: handleVisualFeedback,
        onAddFileToCollection: handleAddSingleFileToCollection,
        onPendingNavigationConsumed: handlePendingNavigationConsumed,
        setBlockingLoad,
        onUpload: openUploader,
        onCreateAlbum: () => {
            setPostCreateAlbumOp(undefined);
            postCreateAlbumHidden.current = false;
            showAlbumNameInput();
        },
        saveGroups,
        setSectionActivity,
    };
    if (!user) {
        // Children rely on user after the mount dispatch.
        return <div></div>;
    }

    return (
        <PhotosNavigationContext.Provider value={navigationActions}>
            <FullScreenDropZone
                {...dropzoneProps}
                disabled={
                    dropzoneProps.disabled ||
                    sectionActivity.drop ||
                    isCleanupViewOpen
                }
            >
                {blockingLoad && <TranslucentLoadingOverlay />}
                {collectionOperationDialogs}
                {selectedFileOperationDialogs}
                <GalleryDownloadNotifications
                    {...{ saveGroups, onRemoveSaveGroup }}
                />

                <PhotosNavigationShell
                    ref={navigationRef}
                    isFirstLoad={isFirstLoad}
                    isInSearchMode={isInSearchMode}
                    collectionNameByID={collectionNameByID}
                    onAuthenticateUser={authenticateUser}
                    mode={barMode}
                    isMapView={isMapView}
                    isMapSelected={
                        isMapView &&
                        activeCollectionID === PseudoCollectionID.all
                    }
                    onUpload={openUploader}
                    navigationAvailable={!isCleanupViewOpen}
                    activeCollectionID={galleryBarActiveCollectionID}
                    alternateHeader={
                        showSelectionBar ? (
                            <SelectedFileOptions
                                barMode={barMode}
                                isInSearchMode={isInSearchMode}
                                collection={
                                    isInSearchMode
                                        ? undefined
                                        : activeCollection
                                }
                                collectionSummary={
                                    isInSearchMode
                                        ? undefined
                                        : activeCollectionSummary
                                }
                                selectedFileCount={selected.count}
                                selectedOwnFileCount={selected.ownCount}
                                selectedFavoriteCount={selectedFavoriteCount}
                                onClearSelection={clearSelection}
                                onDelete={() => handleDeleteFiles()}
                                onRemoveFilesFromCollection={
                                    handleRemoveFilesFromCollection
                                }
                                onOpenCollectionSelector={
                                    handleOpenCollectionSelector
                                }
                                onSelectAll={handleSelectAll}
                                isAllSelected={isAllSelectedInView}
                                {...{
                                    createOnCreateForCollectionOp,
                                    createOnSelectForCollectionOp,
                                    createFileOpHandler,
                                    onShowAssignPersonDialog:
                                        showAddPersonAction
                                            ? showContextMenuAssignPerson
                                            : undefined,
                                }}
                                onEditLocation={showEditLocation}
                            />
                        ) : null
                    }
                >
                    {(presentation) =>
                        !isInSearchMode &&
                        !isCleanupViewOpen &&
                        barMode != "people" &&
                        barMode != "links" &&
                        (!isMapView ||
                            activeCollectionID !== PseudoCollectionID.all) ? (
                            <AlbumsSection
                                library={sectionLibrary}
                                operations={sectionOperations}
                                navigation={sectionNavigation}
                                preferences={preferences}
                                presentation={presentation}
                            />
                        ) : !isInSearchMode &&
                          !isCleanupViewOpen &&
                          !isMapView &&
                          barMode == "links" ? (
                            <LinksView
                                presentation={presentation}
                                onSearchQueryChange={setAlbumSearchQuery}
                                onChangeSortBy={onChangeCollectionsSortBy}
                                user={user}
                                collections={state.collections}
                                collectionFiles={state.collectionFiles}
                                collectionSummaries={normalCollectionSummaries}
                                hiddenCollectionIDs={hiddenCollectionIDs}
                                hiddenFileIDs={hiddenFileIDs}
                                tempDeletedFileIDs={tempDeletedFileIDs}
                                tempHiddenFileIDs={tempHiddenFileIDs}
                                uncategorizedCollectionSummaryID={
                                    state.uncategorizedCollectionSummaryID
                                }
                                selectedLinkID={selectedLinkID}
                                searchQuery={albumSearchQuery}
                                sortBy={collectionsSortBy}
                                onCreateAlbum={showAlbumNameInput}
                                setBlockingLoad={setBlockingLoad}
                                onRemotePull={remotePull}
                            />
                        ) : !isInSearchMode &&
                          !isCleanupViewOpen &&
                          !isMapView &&
                          barMode == "people" ? (
                            <PeopleSection
                                library={sectionLibrary}
                                operations={sectionOperations}
                                navigation={sectionNavigation}
                                preferences={preferences}
                                presentation={presentation}
                            />
                        ) : isMapView ? (
                            <PlacesSection
                                library={sectionLibrary}
                                operations={sectionOperations}
                                navigation={sectionNavigation}
                                preferences={preferences}
                                presentation={presentation}
                            />
                        ) : (
                            <GallerySectionLayout presentation={presentation}>
                                {cleanupView === "duplicates" ? (
                                    <DuplicatesView
                                        onRemoteFilesPull={remoteFilesPull}
                                    />
                                ) : cleanupView === "large-files" ? (
                                    <LargeFilesView
                                        onRemoteFilesPull={remoteFilesPull}
                                    />
                                ) : (
                                    <GalleryMedia
                                        library={sectionLibrary}
                                        operations={sectionOperations}
                                        navigation={sectionNavigation}
                                        header={fileListHeader}
                                        source={{
                                            mode: barMode,
                                            modePlus: isInSearchMode
                                                ? "search"
                                                : barMode,
                                            files: filteredFiles,
                                            activeCollectionID:
                                                activeCollectionID!,
                                            activeCollectionSummary,
                                            activePersonID: activePerson?.id,
                                            disableGrouping:
                                                state.searchSuggestion?.type ==
                                                    "clip" ||
                                                (!isInSearchMode &&
                                                    activeCollection
                                                        ?.pubMagicMetadata?.data
                                                        .sortBy == "fileName"),
                                        }}
                                    />
                                )}
                            </GallerySectionLayout>
                        )
                    }
                </PhotosNavigationShell>
                {uploadUI}
                <DesktopWhatsNew />
                {peopleConsentDialog}

                <AuthenticateUser {...authenticateUserDialogProps} />
            </FullScreenDropZone>

            <QuickLinkCreatedNotification
                open={publicLinkToast.open}
                onCopy={() => {
                    if (publicLinkToast.url) {
                        void navigator.clipboard.writeText(publicLinkToast.url);
                    }
                }}
                onClose={() =>
                    setPublicLinkToast((prev) => ({ ...prev, open: false }))
                }
            />
        </PhotosNavigationContext.Provider>
    );
};

export default Page;
