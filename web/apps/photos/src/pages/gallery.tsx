import { AlbumsSection } from "@/components/gallery/AlbumsSection";
import { GallerySectionLayout } from "@/components/gallery/GallerySectionLayout";
import { PeopleSection } from "@/components/gallery/PeopleSection";
import { PlacesSection } from "@/components/gallery/PlacesSection";
import { SearchSection } from "@/components/gallery/SearchSection";
import { useGalleryOperations } from "@/components/gallery/hooks/use-gallery-operations";
import { useMapEntry } from "@/components/gallery/hooks/use-map-entry";
import { usePeopleEntry } from "@/components/gallery/hooks/use-people-entry";
import type { GalleryNavigationState } from "@/components/gallery/navigation-state";
// TODO: Audit this file (the code here is mostly fine, but needs revisiting
// the file it depends on have been audited and their interfaces fixed).
/* eslint-disable react-hooks/exhaustive-deps */
import { AuthenticateUser } from "@/components/AuthenticateUser";
import { DesktopWhatsNew } from "@/components/DesktopWhatsNew";
import { DuplicatesView } from "@/components/gallery/DuplicatesView";
import { LargeFilesView } from "@/components/gallery/LargeFilesView";
import { LinksSection } from "@/components/gallery/LinksSection";
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
import { FullScreenDropZone } from "ente-gallery/components/FullScreenDropZone";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";

import type { SearchOption } from "ente-new/photos/services/search/types";
import { useRouter } from "next/router";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

const Page: React.FC = () => {
    const libraryOwner = useGalleryLibrary();
    const {
        state,
        dispatch,
        isFirstLoad,
        searchIndexRevision,
        remoteFilesPull,
    } = libraryOwner;

    const [cleanupView, setCleanupView] = useState<
        "large-files" | "duplicates"
    >();
    const isCleanupViewOpen = cleanupView !== undefined;
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
    const { user, collectionNameByID, isInSearchMode } = state;

    const isAlbumOverview = state.view?.type == "album-overview";
    const barMode =
        state.view?.type == "album-overview"
            ? "albums"
            : (state.view?.type ?? "albums");
    const overviewFilter =
        state.view?.type == "album-overview"
            ? state.view.albumFilter
            : undefined;
    const activeCollectionID =
        state.view?.type == "people" ||
        state.view?.type == "album-overview" ||
        state.view?.type == "links"
            ? undefined
            : state.view?.activeCollectionSummaryID;
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
    } = preferences;

    const barCollectionSummaries =
        barMode == "hidden-albums"
            ? state.hiddenCollectionSummaries
            : barMode == "archive-albums"
              ? state.archivedCollectionSummaries
              : state.normalCollectionSummaries;

    const collectionSummary = barCollectionSummaries.get(
        galleryBarActiveCollectionID!,
    );

    const navigationState: GalleryNavigationState = {
        destination: {
            section:
                isMapView && activeCollectionID === PseudoCollectionID.all
                    ? "places"
                    : barMode === "people" || barMode === "links"
                      ? barMode
                      : "albums",
            albumMode:
                barMode === "people" || barMode === "links"
                    ? undefined
                    : barMode,
            collectionID: galleryBarActiveCollectionID,
            albumFilter: overviewFilter,
            personID:
                state.view?.type === "people"
                    ? state.view.activePerson?.id
                    : undefined,
            extraVisiblePersonID: state.extraVisiblePerson?.id,
            collectionMap: isMapView,
        },
        overlay: isInSearchMode
            ? { section: "search", suggestion: state.searchSuggestion }
            : cleanupView
              ? { section: cleanupView }
              : undefined,
        selectedPlace,
        placeSelectionRevision,
    };
    const {
        operations: sectionOperations,
        dropzoneProps,
        ui,
    } = useGalleryOperations(
        libraryOwner,
        navigationState,
        authenticateUserDialogProps.open,
        (action) => navigationRef.current?.showSettings(action),
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
        dispatch({ type: "showPeople" });
    }, []);

    const handleShowAlbumOverview = useCallback(
        (filter: AlbumFilter) => {
            setCleanupView(undefined);
            setAlbumFilter(filter);
            dispatch({ type: "showAlbumOverview", albumFilter: filter });
        },
        [dispatch],
    );

    const handleBackToAlbums = useCallback(() => {
        setCleanupView(undefined);
        const origin =
            albumOpenedFromOverview?.collectionID === collectionSummary?.id
                ? albumOpenedFromOverview
                : undefined;
        const filter = origin?.filter ?? "ente";
        setAlbumSearchQuery(origin?.searchQuery ?? "");
        setAlbumFilter(filter);
        dispatch({ type: "showAlbumOverview", albumFilter: filter });
    }, [albumOpenedFromOverview, collectionSummary?.id]);

    const handleChangeBarMode = useCallback(
        (mode: GalleryBarMode) => {
            if (mode == "links") {
                setCleanupView(undefined);
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
        [dispatch, handleShowAlbumOverview, handleShowPeople],
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

    const sectionLibrary = { ...state, isFirstLoad, searchIndexRevision };
    const sectionNavigation = {
        view: state.view,
        searchSuggestion: state.searchSuggestion,
        isInSearchMode,
        isMapView,
        selectedPlace,
        placeSelectionRevision,
        pendingFileNavigation: undefined,
    };
    if (!user) {
        // Children rely on user after the mount dispatch.
        return <div></div>;
    }

    return (
        <PhotosNavigationContext.Provider value={navigationActions}>
            <FullScreenDropZone {...dropzoneProps}>
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
                    onUpload={sectionOperations.onUpload}
                    navigationAvailable={!isCleanupViewOpen}
                    activeCollectionID={galleryBarActiveCollectionID}
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
                            <LinksSection
                                library={sectionLibrary}
                                operations={sectionOperations}
                                navigation={sectionNavigation}
                                preferences={preferences}
                                presentation={presentation}
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
                        ) : cleanupView === "duplicates" ? (
                            <GallerySectionLayout presentation={presentation}>
                                <DuplicatesView
                                    onRemoteFilesPull={remoteFilesPull}
                                />
                            </GallerySectionLayout>
                        ) : cleanupView === "large-files" ? (
                            <GallerySectionLayout presentation={presentation}>
                                <LargeFilesView
                                    onRemoteFilesPull={remoteFilesPull}
                                />
                            </GallerySectionLayout>
                        ) : (
                            <SearchSection
                                library={sectionLibrary}
                                operations={sectionOperations}
                                navigation={sectionNavigation}
                                preferences={preferences}
                                presentation={presentation}
                            />
                        )
                    }
                </PhotosNavigationShell>
                {ui}
                <DesktopWhatsNew />
                {peopleConsentDialog}

                <AuthenticateUser {...authenticateUserDialogProps} />
            </FullScreenDropZone>
        </PhotosNavigationContext.Provider>
    );
};

export default Page;
