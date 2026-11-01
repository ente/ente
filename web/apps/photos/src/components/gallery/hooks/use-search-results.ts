import { useBaseContext } from "ente-base/context";
import type { EnteFile } from "ente-media/file";
import { filterSearchableFiles } from "ente-new/photos/services/search";
import type { SearchSuggestion } from "ente-new/photos/services/search/types";
import { useEffect, useRef, useState } from "react";
import { createSearchResultsQueue } from "../search-results-queue";

export const useSearchResults = (
    suggestion: SearchSuggestion | undefined,
    searchIndexRevision: number,
) => {
    const [results, setResults] = useState<EnteFile[]>();
    const { onGenericError } = useBaseContext();
    const queue =
        useRef<ReturnType<typeof createSearchResultsQueue>>(undefined);
    useEffect(() => {
        const current = createSearchResultsQueue(
            filterSearchableFiles,
            setResults,
            onGenericError,
        );
        queue.current = current;
        return () => current.dispose();
    }, [onGenericError]);
    useEffect(() => {
        if (!suggestion) setResults(undefined);
        queue.current?.enqueue(suggestion);
    }, [suggestion, searchIndexRevision, onGenericError]);
    return results;
};
