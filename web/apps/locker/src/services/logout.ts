import { savedLocalUser } from "ente-accounts/services/accounts-db";
import {
    accountLogout,
    logoutClearStateAgain,
} from "ente-accounts/services/logout";
import log from "ente-base/log";
import { logoutContacts } from "ente-contacts";
import { clearAuthenticatedSession } from "./authenticated-session";
import { clearLockerCache } from "./locker-cache";
import { clearLockerDB } from "./locker-db";

export const lockerLogout = async () => {
    const ignoreError = (label: string, error: unknown) =>
        log.error(`Ignoring error during logout (${label})`, error);

    log.info("logout (locker)");

    const userID = savedLocalUser()?.id;

    // Session

    try {
        clearAuthenticatedSession();
    } catch (error) {
        ignoreError("Authenticated session", error);
    }

    // Remote logout and clear state

    await accountLogout();

    // Locker services

    try {
        if (userID !== undefined) {
            await clearLockerDB(userID);
        }
    } catch (error) {
        ignoreError("Locker DB", error);
    }

    try {
        clearLockerCache();
    } catch (error) {
        ignoreError("Locker in-memory cache", error);
    }

    try {
        logoutContacts();
    } catch (error) {
        ignoreError("Contacts", error);
    }

    // Final sweep and reload

    await logoutClearStateAgain();
    window.location.replace("/login");
};
