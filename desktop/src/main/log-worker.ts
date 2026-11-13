// Utility processes cannot use Electron's logger or safely share its log file;
// proxy their records to the main process.
export default {
    error: (s: string, e?: unknown) =>
        mainProcess("log.errorString", messageWithError(s, e)),
    warn: (s: string, e?: unknown) =>
        mainProcess("log.warnString", messageWithError(s, e)),
    info: (...ms: unknown[]) => mainProcess("log.info", ms),
    debugString: (s: string) => mainProcess("log.debugString", s),
};

const mainProcess = (method: string, param: unknown) =>
    process.parentPort.postMessage({ method, p: param });

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
