import { clearSessionStorage } from "ente-accounts/services/session-storage";
import { clearBlobCaches } from "ente-base/blob-cache";
import { clearKVDB } from "ente-base/kv";
import { clearLocalStorage } from "ente-base/local-storage";
import log from "ente-base/log";
import { clearStashedRedirect } from "./redirect";
import { remoteLogoutIfNeeded } from "./user";

// This function must not throw. Each step runs independently and ignores
// errors so that logout completes even from a broken account state.
export const accountLogout = async () => {
    const ignoreError = (label: string, e: unknown) =>
        log.error(`Ignoring error during logout (${label})`, e);

    log.info("logout (account)");

    try {
        await remoteLogoutIfNeeded();
    } catch (e) {
        ignoreError("Remote", e);
    }
    try {
        clearStashedRedirect();
    } catch (e) {
        ignoreError("In-memory store", e);
    }
    try {
        clearSessionStorage();
    } catch (e) {
        ignoreError("Session storage", e);
    }
    try {
        clearLocalStorage();
    } catch (e) {
        ignoreError("Local storage", e);
    }
    try {
        await clearBlobCaches();
    } catch (e) {
        ignoreError("Blob cache", e);
    }
    try {
        await clearKVDB();
    } catch (e) {
        ignoreError("KV DB", e);
    }
};

// Called after the logout sequence completes to again clear state that
// in-flight requests may have persisted meanwhile. The caller then reloads
// the page so that remaining in-flight requests are discarded.
export const logoutClearStateAgain = async () => {
    const ignoreError = (label: string, e: unknown) =>
        log.error(`Ignoring error during logout (${label})`, e);

    log.info("logout (sweep)");

    try {
        clearLocalStorage();
    } catch (e) {
        ignoreError("Local storage", e);
    }
    try {
        await clearKVDB();
    } catch (e) {
        ignoreError("KV DB", e);
    }
};
