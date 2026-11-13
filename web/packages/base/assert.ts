import { isDevBuild } from "./env";
import log from "./log";

export const assertionFailed = (message?: string) => {
    message = message ?? "Assertion failed";
    if (isDevBuild) throw new Error(message);
    log.warn(message);
};
