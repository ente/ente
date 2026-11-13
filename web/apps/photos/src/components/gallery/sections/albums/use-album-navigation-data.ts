import {
    filterAlbumSummaries,
    visibleAlbumFilters as getVisibleAlbumFilters,
    type AlbumFilter,
} from "@/utils/album-filters";
import {
    PseudoCollectionID,
    sortCollectionSummaries,
    type CollectionSummaries,
    type CollectionsSortBy,
} from "ente-new/photos/services/collection-summary";
import { useMemo } from "react";
import type { GalleryBarMode } from "../../reducer";

interface AlbumNavigationDataOptions {
    mode: Exclude<GalleryBarMode, "links"> | undefined;
    collectionSummaries: CollectionSummaries;
    uncategorizedCollectionSummaryID: number;
    albumFilter: AlbumFilter;
    albumSearchQuery: string;
    collectionsSortBy: CollectionsSortBy;
}

// Prepare the shared album ordering and the sidebar and overview lists.
export const useAlbumNavigationData = ({
    mode,
    collectionSummaries,
    uncategorizedCollectionSummaryID,
    albumFilter,
    albumSearchQuery,
    collectionsSortBy,
}: AlbumNavigationDataOptions) => {
    const sortedCollectionSummaries = useMemo(
        () =>
            mode === undefined
                ? []
                : sortCollectionSummaries(
                      [...collectionSummaries.values()],
                      collectionsSortBy,
                  ).sort((a, b) => b.sortPriority - a.sortPriority),
        [mode, collectionsSortBy, collectionSummaries],
    );
    const eligibleCollectionSummaries = useMemo(
        () =>
            sortedCollectionSummaries.filter(
                (cs) =>
                    cs.id !== uncategorizedCollectionSummaryID &&
                    cs.id !== PseudoCollectionID.hiddenItems &&
                    cs.id !== PseudoCollectionID.archiveItems &&
                    cs.id !== PseudoCollectionID.trash &&
                    (mode == "albums"
                        ? !cs.attributes.has("system") ||
                          (cs.id > 0 && cs.type == "uncategorized")
                        : !cs.attributes.has("hideFromCollectionBar")),
            ),
        [sortedCollectionSummaries, uncategorizedCollectionSummaryID, mode],
    );
    const visibleAlbumFilters = useMemo(
        () =>
            getVisibleAlbumFilters(
                eligibleCollectionSummaries,
                albumSearchQuery,
            ),
        [eligibleCollectionSummaries, albumSearchQuery],
    );
    // Sidebar searches span groups; the overview follows its selected group.
    const sidebarCollectionSummaries = useMemo(
        () =>
            eligibleCollectionSummaries.filter((album) =>
                album.name
                    .toLowerCase()
                    .includes(albumSearchQuery.trim().toLowerCase()),
            ),
        [eligibleCollectionSummaries, albumSearchQuery],
    );
    const overviewAlbums = useMemo(
        () =>
            filterAlbumSummaries(
                eligibleCollectionSummaries,
                albumFilter,
                albumSearchQuery,
            ),
        [eligibleCollectionSummaries, albumFilter, albumSearchQuery],
    );

    return { sidebarCollectionSummaries, overviewAlbums, visibleAlbumFilters };
};
