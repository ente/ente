// Adapted from `web/packages/accounts/services/session.ts` (validity check).
import { authenticatedRequestHeaders } from "./http";
import { apiURL } from "./origins";
import { savedAuthToken } from "./token";

export const isSessionValid = async (): Promise<boolean> => {
    const token = await savedAuthToken();
    if (!token) return false;

    const res = await fetch(await apiURL("/users/session-validity/v2"), {
        headers: await authenticatedRequestHeaders(),
    });
    if (res.status == 401) return false;
    if (!res.ok) {
        // Treat transient errors as "still valid" to avoid spurious logouts.
        return true;
    }
    return true;
};
