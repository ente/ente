import { accountLogout } from "ente-accounts-rs/services/logout";
import log from "ente-base/log";
import {
    clearSpaceBrowserSession,
    revokeSpaceBrowserSessions,
} from "services/spacePersistentSession";

export const spaceLogout = async () => {
    await revokeSpaceBrowserSessions();
    try {
        clearSpaceBrowserSession();
    } catch (error) {
        log.error(
            "Ignoring error during logout (Space browser session)",
            error,
        );
    }
    // accountLogout() is used to clear the remaining account state and browser caches
    await accountLogout();
};
