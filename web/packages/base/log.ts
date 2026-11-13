import { inWorker } from "ente-base/env";
import { isDevBuild } from "./env";
import { logToDisk as webLogToDisk } from "./log-web";
import { workerBridge } from "./worker/worker-bridge";

let shouldLogToDisk = true;

export const disableDiskLogs = () => (shouldLogToDisk = false);

export const logToDisk = (message: string) => {
    const electron = globalThis.electron;
    if (electron) electron.logToDisk(message);
    else if (inWorker()) workerLogToDisk(message);
    else webLogToDisk(message);
};

const workerLogToDisk = (message: string) => {
    workerBridge!.logToDisk(message).catch((e: unknown) => {
        console.error(
            "Failed to log a message from worker",
            e,
            "\nThe message was",
            message,
        );
    });
};

const messageWithError = (message: string, e?: unknown) => {
    if (!e) return message;

    let es: string;
    if (e instanceof Error) {
        es = `${e.name}: ${e.message}`;
        const st = e.stack;
        if (st) {
            // V8 stacks already start with "Name: message".
            es = st.startsWith(es) ? st : [es, st].join("\n");
        }
    } else {
        // Best-effort for arbitrary thrown values.
        // eslint-disable-next-line @typescript-eslint/no-base-to-string
        es = String(e);
    }

    return `${message}: ${es}`;
};

const logError = (message: unknown, e?: unknown) => {
    const m =
        typeof message == "string"
            ? `[error] ${messageWithError(message, e)}`
            : `[error] ${messageWithError("Error", message)}`;
    console.error(m);
    if (shouldLogToDisk) logToDisk(m);
};

const logWarn = (message: string, e?: unknown) => {
    const m = `[warn] ${messageWithError(message, e)}`;
    console.error(m);
    if (shouldLogToDisk) logToDisk(m);
};

const logInfo = (...params: unknown[]) => {
    const message = params
        .map((p) => (typeof p == "string" ? p : JSON.stringify(p)))
        .join(" ");
    const m = `[info] ${message}`;
    if (isDevBuild || !shouldLogToDisk) console.log(m);
    if (shouldLogToDisk) logToDisk(m);
};

const logDebug = (param: () => unknown) => {
    if (isDevBuild) {
        const p = param();
        if (Array.isArray(p)) {
            // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
            const [tag, ...rest] = p;
            // eslint-disable-next-line @typescript-eslint/no-unsafe-argument
            console.log(`[debug] ${tag}`, ...rest);
        } else {
            console.log("[debug]", p);
        }
    }
};

export default {
    error: logError,
    warn: logWarn,
    info: logInfo,
    debug: logDebug,
};

const rustLogGlobal = globalThis as typeof globalThis & {
    enteRustLog?: (level: string, target: string, message: string) => void;
};

export const attachRustLogHook = () => {
    rustLogGlobal.enteRustLog = (level, target, message) => {
        const m = `[rust] ${target}: ${message}`;
        switch (level) {
            case "ERROR":
                logError(m);
                break;
            case "WARN":
                logWarn(m);
                break;
            case "INFO":
                logInfo(m);
                break;
        }
    };
};
