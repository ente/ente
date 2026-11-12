import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import type { GalleryState } from "../reducer";
import type { GalleryDestination } from "./navigation-state";

export const createGalleryHistory = () => {
    let pending:
        | { as: string; from: GalleryDestination; collectionID: number }
        | undefined;

    return {
        restore: (
            as: string,
            from: GalleryDestination,
            library: GalleryState,
            navigate: (collectionID: number) => void,
        ) => {
            pending = undefined;
            const url = new URL(as, "https://photos.ente.io");
            if (url.pathname !== "/gallery" || !library.user) return;
            const values = url.searchParams.getAll("collection");
            const value = values.length === 0 ? "0" : values[0]!;
            if (values.length > 1 || !/^[0-9]+$/.test(value)) return;
            const collectionID = Number(value);
            if (!Number.isSafeInteger(collectionID)) return;
            if (collectionID !== PseudoCollectionID.all) {
                const summary =
                    library.normalCollectionSummaries.get(collectionID);
                if (
                    !summary ||
                    summary.attributes.has("archived") ||
                    library.hiddenCollectionSummaries.has(collectionID) ||
                    library.archivedCollectionSummaries.has(collectionID)
                )
                    return;
            }
            pending = { as, from, collectionID };
            navigate(collectionID);
        },
        isRestoring: (asPath: string, destination: GalleryDestination) => {
            if (!pending) return false;
            const restored =
                destination.section === "albums" &&
                destination.albumMode === "albums" &&
                destination.albumFilter === undefined &&
                destination.collectionID === pending.collectionID;
            if (destination !== pending.from && !restored) {
                pending = undefined;
                return false;
            }
            if (asPath === pending.as && restored) pending = undefined;
            return true;
        },
    };
};
