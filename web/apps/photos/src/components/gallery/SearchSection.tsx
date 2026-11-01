import type { FileListHeaderOrFooter } from "@/components/FileList";
import { sortFiles } from "ente-media/collection-sort";
import { useEffect, useMemo, useRef, useState } from "react";
import { SearchResultsHeader } from ".";
import { GalleryMedia } from "./GalleryMedia";
import { GallerySectionLayout } from "./GallerySectionLayout";
import { useSearchResults } from "./hooks/use-search-results";
import { suppressSharedFilesSavedByUser } from "./media-files";
import type { GallerySectionProps } from "./section-types";

export const SearchSection = ({
    library,
    operations,
    navigation,
    preferences,
    presentation,
}: GallerySectionProps) => {
    const view = navigation.view;
    const mode =
        view?.type == "album-overview" ? "albums" : (view?.type ?? "albums");
    const collectionView =
        view?.type == "albums" ||
        view?.type == "hidden-albums" ||
        view?.type == "archive-albums"
            ? view
            : undefined;
    const activeCollection = collectionView?.activeCollection;
    const activePersonID =
        view?.type == "people" ? view.activePerson?.id : undefined;
    const suggestion = navigation.searchSuggestion;
    const results = useSearchResults(suggestion, library.searchIndexRevision);
    const previousFiles = useRef(
        operations.mediaSource?.mode === mode
            ? operations.mediaSource.files
            : library.filteredFiles,
    );
    const { searchSortAsc, setSearchSortAsc } = preferences;
    const files = useMemo(() => {
        const visible = suppressSharedFilesSavedByUser(
            results ?? previousFiles.current,
            library.user?.id,
            activeCollection,
        );
        return searchSortAsc === undefined
            ? visible
            : sortFiles([...visible], searchSortAsc);
    }, [results, library.user?.id, activeCollection, searchSortAsc]);
    useEffect(() => {
        previousFiles.current = files;
    }, [files]);
    const [header, setHeader] = useState<FileListHeaderOrFooter>();
    useEffect(() => {
        if (suggestion)
            setHeader({
                component: (
                    <SearchResultsHeader
                        searchSuggestion={suggestion}
                        fileCount={results?.length ?? 0}
                        sortAsc={searchSortAsc}
                        onSortOrderChange={setSearchSortAsc}
                    />
                ),
                height: 104,
            });
    }, [suggestion, results, searchSortAsc, setSearchSortAsc]);
    return (
        <GallerySectionLayout presentation={presentation}>
            <GalleryMedia
                {...{ library, operations, navigation }}
                header={header}
                source={{
                    mode,
                    modePlus: "search",
                    files,
                    activeCollectionID:
                        collectionView?.activeCollectionSummaryID,
                    activeCollection,
                    activeCollectionSummary:
                        collectionView?.activeCollectionSummary,
                    activePersonID,
                    disableGrouping: suggestion?.type == "clip",
                }}
            />
        </GallerySectionLayout>
    );
};
