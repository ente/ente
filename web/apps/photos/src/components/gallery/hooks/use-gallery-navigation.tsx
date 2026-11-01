import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import { useRouter } from "next/router";
import { useCallback, useEffect, useMemo, useReducer, useRef } from "react";
import type { PhotosNavigationActions } from "../PhotosNavigationContext";
import type { PhotosNavigationShellHandle } from "../PhotosNavigationShell";
import {
    activeSectionID,
    initialNavigationState,
    navigationReducer,
} from "../navigation-state";
import type { GalleryBarMode } from "../reducer";
import { sectionDefinition, type GallerySectionID } from "../sections";
import { useAlbumActions } from "./use-album-actions";
import type { useGalleryLibrary } from "./use-gallery-library";
import { useGalleryPreferences } from "./use-gallery-preferences";
import { useMapEntry } from "./use-map-entry";
import { usePeopleEntry } from "./use-people-entry";
import { useSearchNavigation } from "./use-search-navigation";

export const useGalleryNavigation = (
    libraryOwner: ReturnType<typeof useGalleryLibrary>,
    authenticateUser: () => Promise<boolean>,
) => {
    const [state, send] = useReducer(navigationReducer, initialNavigationState);
    const {
        state: library,
        remoteFilesPull,
        joinedCollectionID,
    } = libraryOwner;
    const navigationRef = useRef<PhotosNavigationShellHandle>(null);
    const { destination } = state;
    const sectionID = activeSectionID(state);
    const barMode: GalleryBarMode =
        destination.section === "people" || destination.section === "links"
            ? destination.section
            : (destination.albumMode ?? "albums");
    const activeCollectionID =
        destination.section === "albums" || destination.section === "places"
            ? destination.collectionID
            : undefined;
    const preferences = useGalleryPreferences({
        barMode,
        activeCollectionID,
        navigationAvailable: sectionDefinition(sectionID).hasNavigation,
    });
    const albums = useAlbumActions({
        library,
        navigation: state,
        send,
        preferences,
        authenticateUser,
        remoteFilesPull,
    });
    const { goHome, showAlbumOverview } = albums;
    const showSettings = useCallback(
        (action?: SidebarActionID) =>
            navigationRef.current?.showSettings(action),
        [],
    );
    const selectSearchOption = useSearchNavigation({
        library,
        navigation: state,
        send,
        showCollectionSummary: albums.showCollectionSummary,
        showSettings,
    });
    const onPeople = useCallback(() => send({ type: "showPeople" }), []);
    const { showPeople, dialog: peopleConsentDialog } = usePeopleEntry({
        isCurrentDestination: destination.section === "people",
        onUnavailable: goHome,
        onNavigate: onPeople,
    });
    const openMap = useCallback(() => send({ type: "showMap" }), []);
    const showCollectionMap = useMapEntry(openMap);
    const showLibraryMap = useCallback(() => {
        send({ type: "selectPlace", place: undefined, revise: false });
        goHome();
        showCollectionMap();
    }, [goHome, showCollectionMap]);
    const showLinksOverview = useCallback(() => {
        send({ type: "showLinks" });
        return true;
    }, []);
    const changeMode = useCallback(
        (mode: GalleryBarMode) => {
            if (mode === "people") return showPeople();
            if (mode === "links") return showLinksOverview();
            showAlbumOverview("ente");
            return true;
        },
        [showAlbumOverview, showLinksOverview, showPeople],
    );
    const selectPerson = useCallback(
        (personID: string) => send({ type: "showPerson", personID }),
        [],
    );
    const retainPerson = useCallback(
        (
            personID: string | undefined,
            extraVisiblePersonID: string | undefined,
        ) => send({ type: "retainPerson", personID, extraVisiblePersonID }),
        [],
    );
    const backToPeople = useCallback(() => {
        send({ type: "showPeople" });
    }, []);
    const selectPlace = useCallback<PhotosNavigationActions["selectPlace"]>(
        (place) => send({ type: "selectPlace", place }),
        [],
    );
    const showCleanupView = useCallback<
        PhotosNavigationActions["showCleanupView"]
    >((section) => {
        send({ type: "closeMap" });
        send({ type: "showCleanup", section });
    }, []);
    const actions = useMemo<PhotosNavigationActions>(() => {
        const actions: PhotosNavigationActions = {
            ...albums,
            changeMode,
            showPeople,
            selectPerson,
            backToPeople,
            showLinksOverview,
            showLibraryMap,
            showCollectionMap,
            selectPlace,
            selectSearchOption,
            showCleanupView,
            openSection: (id: GallerySectionID) => {
                const enter = sectionDefinition(id).enter;
                if (enter) return enter(actions);
                send({ type: "openSection", section: id });
                return true;
            },
        };
        return actions;
    }, [
        albums,
        changeMode,
        showPeople,
        selectPerson,
        backToPeople,
        showLinksOverview,
        showLibraryMap,
        showCollectionMap,
        selectPlace,
        selectSearchOption,
        showCleanupView,
    ]);
    useEffect(() => {
        const resolve = sectionDefinition(destination.section).resolve;
        const resolved = resolve?.(library, destination);
        if (resolved && resolved !== destination)
            send({ type: "resolveDestination", destination: resolved });
    }, [library, destination]);
    const handledJoin = useRef<number | undefined>(undefined);
    useEffect(() => {
        if (
            joinedCollectionID !== undefined &&
            joinedCollectionID !== handledJoin.current
        ) {
            handledJoin.current = joinedCollectionID;
            send({
                type: "showCollectionSummary",
                collectionSummaryID: joinedCollectionID,
                library,
            });
        }
    }, [joinedCollectionID, library]);
    const router = useRouter();
    const overview = destination.albumFilter !== undefined;
    useEffect(() => {
        if (
            !library.user ||
            (!overview && activeCollectionID === undefined) ||
            !router.isReady
        )
            return;
        const query =
            !overview && activeCollectionID !== PseudoCollectionID.all
                ? `?collection=${activeCollectionID}`
                : "";
        const href = `/gallery${query}`;
        if (router.asPath !== href)
            void router.push(href, undefined, { shallow: true });
    }, [activeCollectionID, overview, router, library.user]);
    return {
        state,
        sectionID,
        preferences,
        actions,
        navigationRef,
        peopleConsentDialog,
        showSettings,
        barMode,
        retainPerson,
    };
};
