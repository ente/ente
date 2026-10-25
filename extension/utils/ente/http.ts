// Adapted from `web/packages/base/http.ts`. The `X-Client-Package` value must
// start with `io.ente.auth` so the server routes us to the authenticator
// ("auth") app; see `server/pkg/utils/auth/auth.go: GetApp`.
import { ensureAuthToken } from "./token";

export const clientPackageName = "io.ente.auth.extension";

export const authenticatedRequestHeaders = async () => ({
    "X-Auth-Token": await ensureAuthToken(),
    "X-Client-Package": clientPackageName,
});

export const publicRequestHeaders = () => ({
    "X-Client-Package": clientPackageName,
});

export class HTTPError extends Error {
    res: Response;

    constructor(res: Response) {
        const url = new URL(res.url);
        url.search = "";
        super(`HTTP ${res.status} ${res.statusText} (${url.pathname})`);
        this.name = "HTTPError";
        this.res = res;
    }
}

export const ensureOk = (res: Response) => {
    if (!res.ok) throw new HTTPError(res);
};

export const isHTTPErrorWithStatus = (
    e: unknown,
    httpStatus: number,
): e is HTTPError => e instanceof HTTPError && e.res.status == httpStatus;
