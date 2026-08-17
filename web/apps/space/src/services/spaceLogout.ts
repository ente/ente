import { accountLogout } from "ente-accounts/services/logout";
import log from "ente-base/log";
import {
    clearSpaceBrowserSession,
    revokeSpaceBrowserSessions,
} from "services/spacePersistentSession";
import { forgetSpaceWebPushAccountTarget } from "services/spaceWebPush";

export const spaceLogout = async () => {
    await revokeSpaceBrowserSessions();
    try {
        await forgetSpaceWebPushAccountTarget();
    } catch (error) {
        log.warn("Failed to clear Space notification state on logout", error);
    }
    try {
        clearSpaceBrowserSession();
    } catch (error) {
        log.error(
            "Ignoring error during logout (Space browser session)",
            error,
        );
    }
    await accountLogout();
};
