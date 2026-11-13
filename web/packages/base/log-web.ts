import { buildEnvGitSHA, isDevBuild } from "ente-base/env";
import log, { attachRustLogHook } from "ente-base/log";
import { appName, appNames } from "./app";
import { isNamedError } from "./error";

export const logStartupBanner = (userID?: number) => {
    // appName is an unchecked build-time value.
    if (!appNames.includes(appName)) {
        log.warn(
            `App name "${appName}" is not one of the known app names: ${JSON.stringify(appNames)}`,
        );
    }

    const sha = buildEnvGitSHA;
    const buildID = isDevBuild ? "dev " : sha ? `git ${sha} ` : "";
    log.info(`Starting ente-${appName}-web ${buildID}uid ${userID ?? 0}`);
};

export const logUnhandledErrorsAndRejections = (attach: boolean) => {
    const handleError = (event: ErrorEvent) => {
        // Media Chrome triggers this benign ResizeObserver error.
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

// Worker promise rejections are only observed when attached inside the worker.
export const logUnhandledErrorsAndRejectionsInWorker = () => {
    attachRustLogHook();

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
        if (isNamedError(e, "QuotaExceededError")) {
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
