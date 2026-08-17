import { appName } from "ente-base/app";

// The page to redirect to after successful authentication. The cast, embed and
// share apps do not use this; their "/" entries are arbitrary values.
export const appHomeRoute: string = {
    accounts: "/passkeys",
    albums: "/",
    auth: "/auth",
    cast: "/",
    embed: "/",
    share: "/",
    photos: "/gallery",
    ensu: "/",
    locker: "/locker",
    legacy: "/",
    space: "/app",
}[appName];

let _stashedRedirect: string | undefined;

export const stashedRedirect = () => _stashedRedirect;

export const stashRedirect = (r: string) => (_stashedRedirect = r);

export const unstashRedirect = () => {
    const r = _stashedRedirect;
    _stashedRedirect = undefined;
    return r;
};

export const clearStashedRedirect = () => (_stashedRedirect = undefined);
