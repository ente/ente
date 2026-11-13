export interface MLWorkerDelegate {
    workerDidUpdateStatus: () => void;
    // Awaited callers update dependent state themselves.
    workerDidUnawaitedIndex: () => void;
    // Losing the utility-process port makes this worker unusable.
    workerDidLoseElectronPort: () => void;
}

// File ID to score; higher is better, and entries are already thresholded.
export type CLIPMatches = Map<number, number>;
