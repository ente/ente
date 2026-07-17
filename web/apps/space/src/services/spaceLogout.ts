import { accountLogout } from "ente-accounts-rs/services/logout";
import {
    clearSpaceBrowserSession,
    revokeSpaceBrowserSessions,
} from "services/spacePersistentSession";

export const spaceLogout = async () => {
    try {
        await revokeSpaceBrowserSessions();
    } finally {
        clearSpaceBrowserSession();
        await accountLogout();
    }
};
