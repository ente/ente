import type { AlbumFilter } from "@/utils/album-filters";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import type { SearchSuggestion } from "ente-new/photos/services/search/types";
import type { GalleryState } from "../reducer";
import type { PlaceSelection } from "../sections/places/PlacesList";
import type { GallerySectionID } from "../sections/registry";

export interface GalleryDestination {
    section: GallerySectionID;
    albumMode?: "albums" | "hidden-albums" | "archive-albums";
    collectionID?: number;
    albumFilter?: AlbumFilter;
    personIDs?: string[];
    peopleOnlyThem?: boolean;
    extraVisiblePersonIDs?: string[];
    collectionMap?: boolean;
}

export interface GalleryNavigationState {
    destination: GalleryDestination;
    overlay?: {
        section: "search" | "duplicates" | "large-files";
        suggestion?: SearchSuggestion;
        searchRevision?: number;
    };
    selectedPlace?: PlaceSelection;
    placeSelectionRevision: number;
}

export const homeDestination: GalleryDestination = {
    section: "albums",
    albumMode: "albums",
    collectionID: PseudoCollectionID.all,
};
export const initialNavigationState: GalleryNavigationState = {
    destination: homeDestination,
    placeSelectionRevision: 0,
};

export type NavigationAction =
    | { type: "openSection"; section: GallerySectionID }
    | { type: "showCleanup"; section: "duplicates" | "large-files" }
    | { type: "dismissCleanup" }
    | { type: "resolveDestination"; destination: GalleryDestination }
    | { type: "showAll" }
    | { type: "showHidden" }
    | { type: "showAlbumOverview"; albumFilter: AlbumFilter }
    | { type: "showLinks"; collectionID?: number }
    | { type: "selectLink"; collectionID: number }
    | { type: "showAlbums" }
    | {
          type: "showCollectionSummary";
          collectionSummaryID: number | undefined;
          library: GalleryState;
      }
    | { type: "showPeople" }
    | { type: "showPerson"; personID: string }
    | { type: "togglePerson"; personID: string }
    | { type: "togglePeopleOnlyThem" }
    | {
          type: "retainPeople";
          personIDs: string[];
          extraVisiblePersonIDs: string[];
      }
    | { type: "enterSearchMode"; searchSuggestion?: SearchSuggestion }
    | { type: "exitSearch"; shouldExitSearchMode?: boolean }
    | { type: "showMap" }
    | { type: "closeMap" }
    | {
          type: "selectPlace";
          place: PlaceSelection | undefined;
          revise?: boolean;
      };

export const navigationReducer = (
    state: GalleryNavigationState,
    action: NavigationAction,
): GalleryNavigationState => {
    const destination = state.destination;
    const navigate = (next: GalleryDestination): GalleryNavigationState => ({
        ...state,
        destination: next,
        overlay: undefined,
    });
    switch (action.type) {
        case "openSection":
            return navigate({ section: action.section });
        case "showCleanup":
            return { ...state, overlay: { section: action.section } };
        case "dismissCleanup":
            return state.overlay && state.overlay.section !== "search"
                ? { ...state, overlay: undefined }
                : state;
        case "resolveDestination":
            return { ...state, destination: action.destination };
        case "showAll":
            return navigate(homeDestination);
        case "showHidden":
            return navigate({
                section: "albums",
                albumMode: "hidden-albums",
                collectionID: PseudoCollectionID.hiddenItems,
            });
        case "showAlbumOverview":
            return navigate({
                section: "albums",
                albumFilter: action.albumFilter,
            });
        case "showLinks":
        case "selectLink":
            return navigate({
                section: "links",
                collectionID: action.collectionID,
            });
        case "showAlbums":
            return navigate(homeDestination);
        case "showCollectionSummary": {
            const id = action.collectionSummaryID ?? PseudoCollectionID.all;
            const mode = action.library.hiddenCollectionSummaries.has(id)
                ? "hidden-albums"
                : action.library.archivedCollectionSummaries.has(id) &&
                    (destination.albumMode === "archive-albums" ||
                        id === PseudoCollectionID.archiveItems)
                  ? "archive-albums"
                  : "albums";
            return navigate({
                section: "albums",
                albumMode: mode,
                collectionID: id,
            });
        }
        case "showPeople":
            return navigate({ section: "people" });
        case "showPerson":
            return navigate({
                section: "people",
                personIDs: [action.personID],
                extraVisiblePersonIDs: destination.extraVisiblePersonIDs,
            });
        case "togglePerson": {
            const previous = destination.personIDs ?? [];
            if (
                destination.section !== "people" ||
                !previous.length ||
                previous[0] === action.personID
            )
                return state;
            const personIDs = previous.includes(action.personID)
                ? previous.filter((id) => id !== action.personID)
                : [...previous, action.personID];
            return navigate({
                ...destination,
                personIDs,
                peopleOnlyThem: undefined,
            });
        }
        case "togglePeopleOnlyThem":
            if (
                destination.section !== "people" ||
                !destination.personIDs?.length ||
                destination.personIDs.length > 4
            )
                return state;
            return navigate({
                ...destination,
                peopleOnlyThem: !destination.peopleOnlyThem,
            });
        case "retainPeople":
            return destination.section !== "people" ||
                (JSON.stringify(destination.personIDs ?? []) ===
                    JSON.stringify(action.personIDs) &&
                    JSON.stringify(destination.extraVisiblePersonIDs ?? []) ===
                        JSON.stringify(action.extraVisiblePersonIDs))
                ? state
                : {
                      ...state,
                      destination: {
                          ...destination,
                          personIDs: action.personIDs,
                          peopleOnlyThem:
                              JSON.stringify(destination.personIDs) ===
                              JSON.stringify(action.personIDs)
                                  ? destination.peopleOnlyThem
                                  : undefined,
                          extraVisiblePersonIDs: action.extraVisiblePersonIDs,
                      },
                  };
        case "enterSearchMode":
            return {
                ...state,
                overlay: {
                    section: "search",
                    suggestion: action.searchSuggestion,
                    searchRevision: (state.overlay?.searchRevision ?? 0) + 1,
                },
            };
        case "exitSearch":
            return state.overlay?.section !== "search"
                ? state
                : {
                      ...state,
                      overlay:
                          action.shouldExitSearchMode === false
                              ? { section: "search" }
                              : undefined,
                  };
        case "showMap":
            return {
                ...state,
                destination:
                    destination.collectionID === PseudoCollectionID.all
                        ? { ...homeDestination, section: "places" }
                        : { ...destination, collectionMap: true },
            };
        case "closeMap":
            return destination.section === "places"
                ? { ...state, destination: homeDestination }
                : destination.collectionMap
                  ? {
                        ...state,
                        destination: { ...destination, collectionMap: false },
                    }
                  : state;
        case "selectPlace":
            return {
                ...state,
                selectedPlace: action.place,
                placeSelectionRevision:
                    state.placeSelectionRevision +
                    (action.revise === false ? 0 : 1),
            };
    }
};

export const activeSectionID = (
    state: GalleryNavigationState,
): GallerySectionID => state.overlay?.section ?? state.destination.section;
