import { savedLocalUser } from "ente-accounts/services/accounts-db";
import { accountLogout } from "ente-accounts/services/logout";
import log from "ente-base/log";
import { clearAuthenticatedSession } from "./authenticated-session";
import { clearLockerDB } from "./locker-db";
import { clearLockerCache } from "./remote-cache";

export const lockerLogout = async () => {
    const ignoreError = (label: string, error: unknown) =>
        log.error(`Ignoring error during logout (${label})`, error);

    log.info("logout (locker)");

    const userID = savedLocalUser()?.id;

    try {
        clearAuthenticatedSession();
    } catch (error) {
        ignoreError("Authenticated session", error);
    }

    try {
        clearLockerCache();
    } catch (error) {
        ignoreError("Locker in-memory cache", error);
    }

    try {
        if (userID !== undefined) {
            await clearLockerDB(userID);
        }
    } catch (error) {
        ignoreError("Locker DB", error);
    }

    await accountLogout();
};
