import { visibleQuickLinks } from "../../utils/quick-links";
import type { GalleryDestination } from "./navigation-state";
import type { GalleryState } from "./reducer";

export const resolveLinksDestination = (
    library: GalleryState,
    destination: GalleryDestination,
): GalleryDestination => {
    const id = destination.collectionID;
    if (id === undefined || !library.user) return destination;
    return visibleQuickLinks(
        library.collections,
        library.user.id,
        library.hiddenCollectionIDs,
    ).some((link) => link.id === id)
        ? destination
        : { ...destination, collectionID: undefined };
};
