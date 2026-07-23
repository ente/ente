import { desktopAppVersion, isDesktop } from "ente-base/app";
import { wait } from "ente-utils/promise";
import { z } from "zod";
import { clientPackageName } from "./app";
import log from "./log";
import { ensureAuthToken } from "./token";

/**
 * Return headers that should be passed alongwith (almost) all authenticated
 * `fetch` calls that we make to our API servers.
 *
 * - The auth token
 * - The client package name.
 */
export const authenticatedRequestHeaders = async () => ({
    "X-Auth-Token": await ensureAuthToken(),
    "X-Client-Package": clientPackageName,
    ...(isDesktop && { "X-Client-Version": desktopAppVersion }),
});

/**
 * Return headers that should be passed alongwith (almost) all unauthenticated
 * `fetch` calls that we make to our remotes like our API servers (museum), or
 * to pre-signed URLs that are handled by the S3 storage buckets themselves.
 *
 * - The client package name.
 */
export const publicRequestHeaders = () => ({
    "X-Client-Package": clientPackageName,
    ...(isDesktop && { "X-Client-Version": desktopAppVersion }),
});

/**
 * A set of credentials needed to make public collections related API requests.
 */
export interface PublicAlbumsCredentials {
    /**
     * [Note: Public album access token]
     *
     * The public album access is a token that serves a similar purpose as the
     * "X-Auth-Token" for usual authenticated API requests that happen for a
     * logged in user, except:
     *
     * - It will be passed as the "X-Auth-Access-Token" header, and
     * - It also tells remote about the public album under consideration.
     *
     * This access token is variously referred to as the album token, or the
     * auth token, when the context is clear. The client obtains this from the
     * "t" query parameter of a public album URL, and then uses it both to:
     *
     * 1. Identify and authenticate itself with remote (this header).
     *
     * 2. Scope local storage per public album by using this access token as a
     *    part of the local storage key. In this context it is sometimes also
     *    referred to as a "collectionUID" by old code.
     */
    accessToken: string;
    /**
     * [Note: Password token for public albums requests].
     *
     * A password protected access token. This is only needed for albums that
     * are behind a password. In such cases, the client needs to fetch this
     * extra token from remote (in exchange for the public album's password),
     * and then pass it as the "X-Auth-Access-Token-JWT" header in authenticated
     * public collections related API requests.
     */
    accessTokenJWT?: string | undefined;
    /**
     * A signed token issued after this browser has been admitted once for this
     * public link's device limit. It is separate from the password JWT.
     */
    linkDeviceToken?: string | undefined;
}

export const linkDeviceTokenRequestHeader = "X-Auth-Link-Device-Token";

export const linkDeviceTokenResponseHeader = "X-Ente-Link-Device-Token";

export const linkDeviceTokenFromResponse = (res: Response) =>
    res.headers.get(linkDeviceTokenResponseHeader) ?? undefined;

/**
 * Return headers that should be passed alongwith public collection related
 * authenticated `fetch` calls that we make to our API servers.
 *
 * - The auth token.
 * - The password protected auth token (if provided).
 * - The client package name.
 */
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

/**
 * A custom Error that is thrown if a fetch fails with a non-2xx HTTP status.
 */
export class HTTPError extends Error {
    res: Response;
    details: Record<string, string>;

    constructor(res: Response) {
        // Trim off any query parameters from the URL before logging, it may
        // have tokens.
        //
        // Nb: res.url is URL obtained after any redirects, and thus is not
        // necessarily the same as the request's URL.
        const url = new URL(res.url);
        url.search = "";
        super(`HTTP ${res.status} ${res.statusText} (${url.pathname})`);

        const requestID = res.headers.get("x-request-id");
        const details = { url: url.href, ...(requestID && { requestID }) };

        // Cargo culted from
        // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Error#custom_error_types
        Error.captureStackTrace?.(this, HTTPError);

        this.name = this.constructor.name;
        this.res = res;
        this.details = details;
    }
}

/**
 * A convenience method that throws an {@link HTTPError} if the given
 * {@link Response} does not have a HTTP 2xx status.
 */
export const ensureOk = (res: Response) => {
    if (!res.ok) {
        const e = new HTTPError(res);
        log.error(`${e.message} ${JSON.stringify(e.details)}`);
        throw e;
    }
};

/**
 * Return true if this is a HTTP error with the given {@link httpStatus}.
 */
export const isHTTPErrorWithStatus = (e: unknown, httpStatus: number) =>
    e instanceof HTTPError && e.res.status == httpStatus;

/**
 * Return true if this is a HTTP "client" error.
 *
 * This is a convenience matcher to check if {@link e} is an instance of
 * {@link HTTPError} with a 4xx status code. Such errors are client errors, and
 * (generally) retrying them will not help.
 */
export const isHTTP4xxError = (e: unknown) =>
    e instanceof HTTPError && e.res.status >= 400 && e.res.status <= 499;

/**
 * Return true if this is a HTTP 401 error.
 *
 * For authenticated requests, an HTTP "401 Unauthorized" indicates that the
 * credentials (auth token) is not valid.
 */
export const isHTTP401Error = (e: unknown) =>
    e instanceof HTTPError && e.res.status == 401;

/**
 * Return `true` if this is an error because of a HTTP failure response returned
 * by museum with the given "code" and HTTP status.
 *
 * > The function is async because it needs to parse the payload.
 *
 * For some known set of errors, museum returns a payload of the form
 *
 *     {"code":"USER_NOT_REGISTERED","message":"User is not registered"}
 *
 * where the code can be used to match a specific reason for the HTTP request
 * failing. This function can be used as a predicate to check both the HTTP
 * status code and the "code" within the payload.
 */
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
    /**
     * An optional modification to the default wait times between retries.
     *
     * - default       1 orig + 3 retries (2s, 5s, 10s)
     * - "background"  1 orig + 3 retries (5s, 25s, 120s)
     *
     * default is fine for most operations, including interactive ones where we
     * don't want to wait too long before giving up. "background" is suitable
     * for non-interactive operations where we can wait for longer (thus better
     * handle remote hiccups) without degrading the user's experience.
     */
    retryProfile?: "background";
    /**
     * An optional function that is called with the corresponding error whenever
     * {@link op} rejects. It should throw the error if the retries should
     * immediately be aborted.
     */
    abortIfNeeded?: (error: unknown) => void;
}

/**
 * Retry a async operation on failure up to 4 times (1 original + 3 retries)
 * with exponential backoff.
 *
 * [Note: Retries of network requests should be idempotent]
 *
 * When dealing with network requests, avoid using this function directly, use
 * one of its wrappers like {@link retryEnsuringHTTPOk} instead. Those wrappers
 * ultimately use this function only, and there is nothing wrong with this
 * function generally, however since this function allows retrying arbitrary
 * promises, it is easy accidentally try and attempt retries of non-idemponent
 * requests, while the more restricted API of {@link retryEnsuringHTTPOk} and
 * other {@link HTTPRequestRetrier}s makes such misuse less likely.
 *
 * @param op A function that performs the operation, returning the promise for
 * its completion.
 *
 * @param opts Optional tweaks to the default implementation. See
 * {@link RetryAsyncOperationOpts}.
 *
 * @returns A promise that fulfills with to the result of a first successfully
 * fulfilled promise of the 4 (1 + 3) attempts, or rejects with the error
 * obtained either when {@link abortIfNeeded} throws, or with the error from the
 * last attempt otherwise.
 */
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

/**
 * A function that wraps the request(s) in retries if needed.
 *
 * See {@link retryEnsuringHTTPOk} for the canonical example. This typedef is to
 * allow us to talk about and pass functions that behave similar to
 * {@link retryEnsuringHTTPOk}, but perhaps with other additional checks.
 *
 * See also: [Note: Retries of network requests should be idempotent]
 */
export type HTTPRequestRetrier = (
    request: () => Promise<Response>,
    opts?: HTTPRequestRetrierOpts,
) => Promise<Response>;

type HTTPRequestRetrierOpts = Pick<RetryAsyncOperationOpts, "retryProfile">;

/**
 * A helper function to adapt {@link retryAsyncOperation} for HTTP fetches.
 *
 * This extends {@link retryAsyncOperation} by treating any non-200 OK status
 * (as matched by {@link ensureOk}) as an error that should be retried.
 */
export const retryEnsuringHTTPOk: HTTPRequestRetrier = (
    request: () => Promise<Response>,
    opts?: HTTPRequestRetrierOpts,
) =>
    retryAsyncOperation(async () => {
        const r = await request();
        ensureOk(r);
        return r;
    }, opts);

/**
 * A helper function to adapt {@link retryAsyncOperation} for HTTP fetches, but
 * treating any 4xx HTTP responses as irrecoverable failures.
 *
 * This is similar to {@link retryEnsuringHTTPOk}, except it stops retrying if
 * remote responds with a 4xx HTTP status.
 */
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
