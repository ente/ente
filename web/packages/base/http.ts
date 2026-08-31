import { desktopAppVersion, isDesktop } from "ente-base/app";
import { wait } from "ente-utils/promise";
import { z } from "zod";
import { clientPackageName } from "./app";
import log from "./log";
import { ensureAuthToken } from "./token";

export const authenticatedRequestHeaders = async () => ({
    "X-Auth-Token": await ensureAuthToken(),
    "X-Client-Package": clientPackageName,
    ...(isDesktop && { "X-Client-Version": desktopAppVersion }),
});

export const publicRequestHeaders = () => ({
    "X-Client-Package": clientPackageName,
    ...(isDesktop && { "X-Client-Version": desktopAppVersion }),
});

export interface PublicAlbumsCredentials {
    accessToken: string;
    accessTokenJWT?: string | undefined;
    linkDeviceToken?: string | undefined;
}

export const linkDeviceTokenRequestHeader = "X-Auth-Link-Device-Token";

export const linkDeviceTokenResponseHeader = "X-Link-Device-Token";

export const linkDeviceTokenFromResponse = (res: Response) =>
    res.headers.get(linkDeviceTokenResponseHeader) ?? undefined;

export const authenticatedPublicAlbumsRequestHeaders = ({
    accessToken,
    accessTokenJWT,
}: PublicAlbumsCredentials) => ({
    "X-Auth-Access-Token": accessToken,
    ...(accessTokenJWT && { "X-Auth-Access-Token-JWT": accessTokenJWT }),
    "X-Client-Package": clientPackageName,
});

export const authenticatedPublicAlbumsDeviceLimitRequestHeaders = (
    credentials: PublicAlbumsCredentials,
) => ({
    ...authenticatedPublicAlbumsRequestHeaders(credentials),
    ...(credentials.linkDeviceToken && {
        [linkDeviceTokenRequestHeader]: credentials.linkDeviceToken,
    }),
});

export const authenticatedPublicAlbumsInfoRequestHeaders =
    authenticatedPublicAlbumsDeviceLimitRequestHeaders;

export class HTTPError extends Error {
    res: Response;
    details: Record<string, string>;

    constructor(res: Response) {
        // Query parameters can contain auth tokens; never put them in logs.
        const url = new URL(res.url);
        url.search = "";
        super(`HTTP ${res.status} ${res.statusText} (${url.pathname})`);

        const requestID = res.headers.get("x-request-id");
        const details = { url: url.href, ...(requestID && { requestID }) };

        Error.captureStackTrace?.(this, HTTPError);

        this.name = this.constructor.name;
        this.res = res;
        this.details = details;
    }
}

export const ensureOk = (res: Response) => {
    if (!res.ok) {
        const e = new HTTPError(res);
        log.error(`${e.message} ${JSON.stringify(e.details)}`);
        throw e;
    }
};

export const isHTTPErrorWithStatus = (e: unknown, httpStatus: number) =>
    e instanceof HTTPError && e.res.status == httpStatus;

export const isHTTP4xxError = (e: unknown) =>
    e instanceof HTTPError && e.res.status >= 400 && e.res.status <= 499;

export const isHTTP401Error = (e: unknown) =>
    e instanceof HTTPError && e.res.status == 401;

export const isMuseumHTTPError = async (
    e: unknown,
    httpStatus: number,
    code: string,
) => {
    if (e instanceof HTTPError && e.res.status == httpStatus) {
        try {
            const payload = z
                .object({ code: z.string() })
                .parse(await e.res.json());
            return payload.code == code;
        } catch (e) {
            log.warn("Ignoring error when parsing error payload", e);
            return false;
        }
    }
    return false;
};

interface RetryAsyncOperationOpts {
    retryProfile?: "background";
    abortIfNeeded?: (error: unknown) => void;
}

// Only retry operations whose repeated execution is safe.
export const retryAsyncOperation = async <T>(
    op: () => Promise<T>,
    opts?: RetryAsyncOperationOpts,
): Promise<T> => {
    const { retryProfile, abortIfNeeded } = opts ?? {};
    const waitTimeBeforeNextTry =
        retryProfile == "background"
            ? [10000, 30000, 120000]
            : [2000, 5000, 10000];

    while (true) {
        try {
            return await op();
        } catch (e) {
            if (abortIfNeeded) {
                abortIfNeeded(e);
            }
            const t = waitTimeBeforeNextTry.shift();
            if (!t) throw e;
            log.warn("Will retry potentially transient request failure", e);
            await wait(t);
        }
    }
};

export type HTTPRequestRetrier = (
    request: () => Promise<Response>,
    opts?: HTTPRequestRetrierOpts,
) => Promise<Response>;

type HTTPRequestRetrierOpts = Pick<RetryAsyncOperationOpts, "retryProfile">;

export const retryEnsuringHTTPOk: HTTPRequestRetrier = (
    request: () => Promise<Response>,
    opts?: HTTPRequestRetrierOpts,
) =>
    retryAsyncOperation(async () => {
        const r = await request();
        ensureOk(r);
        return r;
    }, opts);

export const retryEnsuringHTTPOkOr4xx: HTTPRequestRetrier = (
    request: () => Promise<Response>,
    opts?: HTTPRequestRetrierOpts,
) =>
    retryAsyncOperation(
        async () => {
            const r = await request();
            ensureOk(r);
            return r;
        },
        {
            ...opts,
            abortIfNeeded(e) {
                if (isHTTP4xxError(e)) throw e;
            },
        },
    );
