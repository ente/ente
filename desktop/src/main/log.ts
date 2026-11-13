import log from "electron-log";
import util from "node:util";
import { isDev } from "./utils/electron";

export const initLogging = () => {
    log.transports.file.fileName = "ente.log";
    log.transports.file.maxSize = 50 * 1024 * 1024;
    log.transports.file.format = "[{y}-{m}-{d}T{h}:{i}:{s}{z}] {text}";

    log.transports.console.level = false;

    log.errorHandler.startCatching({
        onError: ({ error, errorName }) => {
            logError(errorName, error);
            // Suppress electron-log's default dialog.
            return false;
        },
    });
};

export const logToDisk = (message: string) => {
    log.info(`[rndr] ${message}`);
};

const messageWithError = (message: string, e?: unknown) => {
    if (!e) return message;

    let es: string;
    if (e instanceof Error) {
        es = [`${e.name}: ${e.message}`, e.stack].filter((x) => x).join("\n");
    } else {
        // eslint-disable-next-line @typescript-eslint/no-base-to-string
        es = String(e);
    }

    return `${message}: ${es}`;
};

const logError = (message: string, e?: unknown) => {
    const m = `[error] ${messageWithError(message, e)}`;
    console.error(m);
    log.error(`[main] ${m}`);
};

const logWarn = (message: string, e?: unknown) => {
    const m = `[warn] ${messageWithError(message, e)}`;
    console.error(m);
    log.error(`[main] ${m}`);
};

const logInfo = (...params: unknown[]) => {
    const message = params
        .map((p) => (typeof p == "string" ? p : util.inspect(p)))
        .join(" ");
    const m = `[info] ${message}`;
    if (isDev) console.log(m);
    log.info(`[main] ${m}`);
};

const logDebug = (param: () => unknown) => {
    if (isDev) {
        const p = param();
        console.log(`[debug] ${typeof p == "string" ? p : util.inspect(p)}`);
    }
};

export const processUtilityProcessLogMessage = (
    logTag: string,
    message: unknown,
) => {
    const m = message;
    if (m && typeof m == "object" && "method" in m && "p" in m) {
        const p = m.p;
        switch (m.method) {
            case "log.errorString":
                if (typeof p == "string") {
                    logError(`${logTag} ${p}`);
                    return true;
                }
                break;
            case "log.warnString":
                if (typeof p == "string") {
                    logWarn(`${logTag} ${p}`);
                    return true;
                }
                break;
            case "log.info":
                if (Array.isArray(p)) {
                    logInfo(logTag, ...(p as unknown[]));
                    return true;
                }
                break;
            case "log.debugString":
                if (typeof p == "string") {
                    logDebug(() => `${logTag} ${p}`);
                    return true;
                }
                break;
            default:
                break;
        }
    }
    return false;
};

export default {
    error: logError,
    warn: logWarn,
    info: logInfo,
    debug: logDebug,
};
