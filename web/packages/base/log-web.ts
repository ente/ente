import { buildEnvGitSHA, isDevBuild } from "ente-base/env";
import log from "ente-base/log";
import { appName, appNames } from "./app";

/**
 * Log a standard startup banner.
 *
 * This helps us identify app starts and other environment details in the logs.
 *
 * @param userID The uid for the currently logged in user, if any.
 */
export const logStartupBanner = (userID?: number) => {
    // Log a warning if appName isn't what it claims to be. See the
    // documentation of `appName` for why this is needed.
    if (!appNames.includes(appName)) {
        log.warn(
            `App name "${appName}" is not one of the known app names: ${JSON.stringify(appNames)}`,
        );
    }

    const sha = buildEnvGitSHA;
    const buildID = isDevBuild ? "dev " : sha ? `git ${sha} ` : "";
    log.info(`Starting ente-${appName}-web ${buildID}uid ${userID ?? 0}`);
};

/**
 * Attach handlers to log any unhandled exceptions and promise rejections.
 *
 * @param attach If true, attach handlers, and if false, remove them. This
 * allows us to use this in a React hook that cleans up after itself.
 */
export const logUnhandledErrorsAndRejections = (attach: boolean) => {
    const handleError = (event: ErrorEvent) => {
        // [Note: Spurious media chrome resize observer errors]
        //
        // When attaching media chrome controls to the DOM, we get an (AFAICT)
        // spurious error in the log. Ignore it. FWIW, the media control tests
        // themselves do the same.
        // https://github.com/muxinc/elements/blob/f602519f544509f15add8fcc8cbbf7379843dcd3/packages/mux-player/test/player.test.js#L6-L12C5
        if (
            event.message ==
            "ResizeObserver loop completed with undelivered notifications."
        ) {
            return;
        }

        log.error("Unhandled error", event.error ?? event.message);
    };

    const handleUnhandledRejection = (event: PromiseRejectionEvent) => {
        log.error("Unhandled promise rejection", event.reason);
    };

    if (attach) {
        window.addEventListener("error", handleError);
        window.addEventListener("unhandledrejection", handleUnhandledRejection);
    } else {
        window.removeEventListener("error", handleError);
        window.removeEventListener(
            "unhandledrejection",
            handleUnhandledRejection,
        );
    }
};

/**
 * Attach handlers to log any unhandled exceptions and promise rejections in web
 * workers.
 *
 * This is a variant of {@link logUnhandledErrorsAndRejections} that works in
 * web workers. It should be called at the top level of the main worker script.
 *
 * Note: When I tested this, attaching the onerror handler to the worker outside
 * the worker (e.g. when creating it in comlink-worker.ts) worked, but attaching
 * the "unhandledrejection" event there did not work. Attaching them to `self`
 * (the {@link WorkerGlobal}) worked.
 */
export const logUnhandledErrorsAndRejectionsInWorker = () => {
    const handleError = (event: ErrorEvent) => {
        log.error("Unhandled error", event.error);
    };

    const handleUnhandledRejection = (event: PromiseRejectionEvent) => {
        log.error("Unhandled promise rejection", event.reason);
    };

    self.addEventListener("error", handleError);
    self.addEventListener("unhandledrejection", handleUnhandledRejection);
};

interface LogEntry {
    timestamp: number;
    logLine: string;
}

const lsKey = "logs";

/**
 * Record {@link message} in a persistent log storage.
 *
 * These strings, alongwith associated timestamps, get added to a small ring
 * buffer, whose contents can be later be retrieved by using {@link savedLogs}.
 *
 * This ring buffer is persisted in the browser's local storage.
 */
export const logToDisk = (message: string) => {
    const maxCount = 1000;
    const log: LogEntry = { logLine: message, timestamp: Date.now() };
    try {
        let logs = logEntries();
        if (logs.length > maxCount) {
            logs = logs.slice(logs.length - maxCount / 4);
        }
        logs.push(log);
        localStorage.setItem(lsKey, JSON.stringify({ logs }));
    } catch (e) {
        console.error("Failed to persist log", e);
        if (e instanceof Error && e.name == "QuotaExceededError") {
            localStorage.removeItem(lsKey);
        }
    }
};

const logEntries = (): unknown[] => {
    const s = localStorage.getItem("logs");
    if (!s) return [];
    const o: unknown = JSON.parse(s);
    if (!(o && typeof o == "object" && "logs" in o && Array.isArray(o.logs))) {
        console.error("Unexpected log entries obtained from local storage", o);
        return [];
    }
    return o.logs;
};

/**
 * Return a string containing all recently saved log messages.
 *
 * @see {@link persistLog}.
 */
export const savedLogs = () => logEntries().map(formatEntry).join("\n");

const formatEntry = (e: unknown) => {
    if (e && typeof e == "object" && "timestamp" in e && "logLine" in e) {
        const timestamp = e.timestamp;
        const logLine = e.logLine;
        if (typeof timestamp == "number" && typeof logLine == "string") {
            return `[${new Date(timestamp).toISOString()}] ${logLine}`;
        }
    }
    return String(e);
};
