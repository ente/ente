import {
    filterAlbumSummaries,
    visibleAlbumFilters as getVisibleAlbumFilters,
    type AlbumFilter,
} from "@/utils/album-filters";
import {
    PseudoCollectionID,
    sortCollectionSummaries,
    collectionsSortBy as supportedCollectionsSortBy,
    type CollectionSummaries,
    type CollectionsSortBy,
} from "ente-new/photos/services/collection-summary";
import { includes } from "ente-utils/type-guards";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { GalleryBarMode } from "./reducer";

interface AlbumNavigationDataOptions {
    mode: GalleryBarMode;
    collectionSummaries: CollectionSummaries;
    uncategorizedCollectionSummaryID: number;
    albumFilter: AlbumFilter;
    albumSearchQuery: string;
}

// Prepare the shared album ordering and the sidebar and overview lists.
export const useAlbumNavigationData = ({
    mode,
    collectionSummaries,
    uncategorizedCollectionSummaryID,
    albumFilter,
    albumSearchQuery,
}: AlbumNavigationDataOptions) => {
    const [collectionsSortBy, setCollectionsSortBy] =
        useState<CollectionsSortBy>("updation-time-desc");

    useEffect(() => {
        const value = localStorage.getItem("collectionsSortBy");
        if (value && includes(supportedCollectionsSortBy, value))
            setCollectionsSortBy(value);
    }, []);

    const onChangeCollectionsSortBy = useCallback(
        (value: CollectionsSortBy) => {
            localStorage.setItem("collectionsSortBy", value);
            setCollectionsSortBy(value);
        },
        [],
    );

    const sortedCollectionSummaries = useMemo(
        () =>
            sortCollectionSummaries(
                [...collectionSummaries.values()],
                collectionsSortBy,
            ).sort((a, b) => b.sortPriority - a.sortPriority),
        [collectionsSortBy, collectionSummaries],
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

    return {
        sidebarCollectionSummaries,
        overviewAlbums,
        visibleAlbumFilters,
        collectionsSortBy,
        onChangeCollectionsSortBy,
    };
};
