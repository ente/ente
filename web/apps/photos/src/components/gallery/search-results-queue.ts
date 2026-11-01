import type { EnteFile } from "ente-media/file";
import type { SearchSuggestion } from "ente-new/photos/services/search/types";

export const createSearchResultsQueue = (
    search: (suggestion: SearchSuggestion) => Promise<EnteFile[]>,
    onResult: (files: EnteFile[]) => void,
    onError: (error: unknown) => void,
) => {
    let pending: SearchSuggestion | undefined;
    let revision = 0;
    let running = false;
    let disposed = false;
    const isCurrent = (requestRevision: number) =>
        !disposed && requestRevision === revision;
    const drain = async () => {
        if (running) return;
        running = true;
        try {
            while (pending && !disposed) {
                const suggestion = pending;
                const requestRevision = revision;
                pending = undefined;
                try {
                    const files = await search(suggestion);
                    if (isCurrent(requestRevision)) onResult(files);
                } catch (error) {
                    if (isCurrent(requestRevision)) onError(error);
                }
            }
        } finally {
            running = false;
        }
    };
    return {
        enqueue(suggestion: SearchSuggestion | undefined) {
            if (disposed) return;
            revision++;
            pending = suggestion;
            void drain();
        },
        dispose() {
            disposed = true;
            pending = undefined;
        },
    };
};
