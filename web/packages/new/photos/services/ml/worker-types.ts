/**
 * @file Types for the objects shared between the main thread and the ML worker.
 */

/**
 * Callbacks invoked by the worker at various points in the indexing and
 * clustering pipeline to notify the main thread of events it might be
 * interested in.
 */
export interface MLWorkerDelegate {
    /**
     * Called whenever the worker does some action that might need the UI state
     * indicating the indexing or clustering status to be updated.
     */
    workerDidUpdateStatus: () => void;
    /**
     * Called when the worker indexes some files, but then notices that the main
     * thread was not awaiting the indexing (e.g. it was not initiated by the
     * main thread during a sync, but happened because of a live upload).
     *
     * In such cases, it uses this method to inform the main thread that some
     * files were indexed, so that it can update any dependent state (e.g.
     * clusters).
     *
     * It doesn't always call this because otherwise the main thread would need
     * some extra code to avoid updating the dependent state twice.
     */
    workerDidUnawaitedIndex: () => void;
}

/**
 * The result of file ids that should be considered as matches for a particular
 * search phrase, each with their associated score.
 *
 * This is a map of file (IDs) that should be shown in the search results.
 * They're returned as a map from fileIDs to the scores they got (higher is
 * better). This map will only contains entries whose score was above our
 * minimum threshold.
 */
export type CLIPMatches = Map<number, number>;
