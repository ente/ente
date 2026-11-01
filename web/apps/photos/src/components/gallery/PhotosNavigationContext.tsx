import type { AlbumFilter } from "@/utils/album-filters";
import type { SearchOption } from "ente-new/photos/services/search/types";
import { createContext, useContext } from "react";
import type { PlaceSelection } from "./PlacesList";
import type { GalleryBarMode } from "./reducer";
import type { GallerySectionID } from "./sections";

export interface PhotosNavigationActions {
    openSection: (id: GallerySectionID) => boolean;
    goHome: () => void;
    changeMode: (mode: GalleryBarMode) => boolean;
    showLibraryMap: () => void;
    showCollectionMap: () => void;
    selectPlace: (place: PlaceSelection | undefined) => void;
    showCollectionSummary: (
        id: number | undefined,
        isHidden?: boolean,
    ) => Promise<boolean>;
    selectCollection: (id: number) => void;
    selectCollectionFromViewer: (id: number) => void;
    openOverviewAlbum: (id: number) => void;
    showAlbumOverview: (filter: AlbumFilter) => void;
    backToAlbums: () => void;
    showLinksOverview: () => boolean;
    showPeople: (onNavigate?: () => void) => boolean;
    selectPerson: (id: string) => void;
    backToPeople: () => void;
    selectSearchOption: (
        option: SearchOption | undefined,
        options?: { shouldExitSearchMode?: boolean },
    ) => void;
    showCleanupView: (view: "large-files" | "duplicates") => void;
}

export const PhotosNavigationContext = createContext<
    PhotosNavigationActions | undefined
>(undefined);

export const usePhotosNavigation = (): PhotosNavigationActions => {
    const actions = useContext(PhotosNavigationContext);
    if (!actions) {
        throw new Error(
            "usePhotosNavigation must be used within PhotosNavigationContext.Provider",
        );
    }
    return actions;
};
