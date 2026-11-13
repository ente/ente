import type { FSWatcher } from "chokidar";
import log from "../log";
import { clearPendingVideoResults } from "../stream";
import { clearStores } from "./store";
import { watchReset } from "./watch";
import { terminateUtilityProcesses } from "./workers";
import { clearOpenZipCache } from "./zip";

// Every cleanup must run even if an earlier one fails.
export const logout = (watcher: FSWatcher) => {
    const ignoreError = (label: string, e: unknown) =>
        log.error(`Ignoring error during logout (${label})`, e);

    try {
        watchReset(watcher);
    } catch (e) {
        ignoreError("FS watch", e);
    }
    try {
        clearPendingVideoResults();
    } catch (e) {
        ignoreError("video", e);
    }
    try {
        clearStores();
    } catch (e) {
        ignoreError("native stores", e);
    }
    try {
        clearOpenZipCache();
    } catch (e) {
        ignoreError("zip cache", e);
    }
    try {
        terminateUtilityProcesses();
    } catch (e) {
        ignoreError("utility processes", e);
    }
};
