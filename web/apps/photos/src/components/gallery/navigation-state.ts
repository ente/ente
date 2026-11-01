import type { AlbumFilter } from "@/utils/album-filters";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import type { SearchSuggestion } from "ente-new/photos/services/search/types";
import type { PlaceSelection } from "./PlacesList";
type GallerySectionID =
    | "albums"
    | "people"
    | "links"
    | "places"
    | "search"
    | "duplicates"
    | "large-files";

export interface GalleryDestination {
    section: GallerySectionID;
    albumMode?: "albums" | "hidden-albums" | "archive-albums";
    collectionID?: number;
    albumFilter?: AlbumFilter;
    personID?: string;
    extraVisiblePersonID?: string;
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
