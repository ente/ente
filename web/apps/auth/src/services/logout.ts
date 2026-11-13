import { accountLogout } from "ente-accounts/services/logout";
import { clearAuthenticatedSession } from "./authenticated-session";

export const authLogout = async () => {
    clearAuthenticatedSession();
    await accountLogout();
    window.location.replace("/");
};
