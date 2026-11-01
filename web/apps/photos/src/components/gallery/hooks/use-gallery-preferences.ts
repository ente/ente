import type { GalleryBarMode } from "@/components/gallery/reducer";
import { useCollectionsSortBy } from "@/components/gallery/use-collections-sort-by";
import type { AlbumFilter } from "@/utils/album-filters";
import type { PeopleSortBy } from "@/utils/people-sort";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";

import { useEffect, useRef, useState } from "react";

export const useGalleryPreferences = ({
    barMode,
    activeCollectionID,
    navigationAvailable,
}: {
    barMode: GalleryBarMode;
    activeCollectionID: number | undefined;
    navigationAvailable: boolean;
}) => {
    const [albumFilter, setAlbumFilter] = useState<AlbumFilter>("ente");
    const [albumSearchQuery, setAlbumSearchQuery] = useState("");
    const [albumOpenedFromOverview, setAlbumOpenedFromOverview] = useState<{
        collectionID: number;
        filter: AlbumFilter;
        searchQuery: string;
    }>();
    const [peopleSortBy, setPeopleSortBy] =
        useState<PeopleSortBy>("count-desc");
    const { collectionsSortBy, onChangeCollectionsSortBy } =
        useCollectionsSortBy();
    const [expandedAlbumFilter, setExpandedAlbumFilter] = useState<
        AlbumFilter | undefined
    >("ente");
    const lastAlbumFilter = useRef(albumFilter);
    useEffect(() => {
        if (lastAlbumFilter.current != albumFilter || !navigationAvailable) {
            lastAlbumFilter.current = albumFilter;
            setExpandedAlbumFilter(albumFilter);
        }
    }, [albumFilter, navigationAvailable]);
    useEffect(() => {
        setAlbumSearchQuery("");
    }, [barMode]);

    useEffect(() => {
        if (barMode == "albums" && activeCollectionID == PseudoCollectionID.all)
            setAlbumSearchQuery("");
    }, [barMode, activeCollectionID]);

    return {
        albumFilter,
        setAlbumFilter,
        albumSearchQuery,
        setAlbumSearchQuery,
        albumOpenedFromOverview,
        setAlbumOpenedFromOverview,
        peopleSortBy,
        setPeopleSortBy,
        collectionsSortBy,
        onChangeCollectionsSortBy,
        albumExpansion: {
            value: expandedAlbumFilter,
            onChange: (
                value: AlbumFilter | undefined,
                selectedFilter?: AlbumFilter,
            ) => {
                if (selectedFilter) lastAlbumFilter.current = selectedFilter;
                setExpandedAlbumFilter(value);
            },
        },
    };
};
