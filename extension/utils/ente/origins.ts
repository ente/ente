// Adapted from `web/packages/base/origins.ts`.

import { getKVS, kvKeys, setKV } from "./storage";

export const defaultAPIOrigin = "https://api.ente.com";

export const apiOrigin = async () =>
    (await getKVS(kvKeys.apiOrigin)) ?? defaultAPIOrigin;

// path must begin with "/".
export const apiURL = async (
    path: string,
    queryParams?: Record<string, string | number | boolean>,
) => {
    let url = (await apiOrigin()) + path;
    if (queryParams) {
        const stringQP = Object.fromEntries(
            Object.entries(queryParams).map(([k, v]) => [k, v.toString()]),
        );
        url = `${url}?${new URLSearchParams(stringQP).toString()}`;
    }
    return url;
};

export const customAPIOrigin = async () => getKVS(kvKeys.apiOrigin);

export const customAPIHost = async () => {
    const origin = await customAPIOrigin();
    return origin ? new URL(origin).host : undefined;
};

// Persist a user supplied self-hosted server URL and ensure the extension is
// allowed to reach it. Returns the normalised origin.
export const setCustomAPIOrigin = async (origin: string | undefined) => {
    if (!origin) {
        await setKV(kvKeys.apiOrigin, undefined);
        return;
    }

    const normalized = new URL(origin).origin;
    await requestHostPermission(normalized);
    await setKV(kvKeys.apiOrigin, normalized);
};

const requestHostPermission = async (origin: string) => {
    const pattern = `${origin}/*`;
    if (await browser.permissions.contains({ origins: [pattern] })) return;
    const granted = await browser.permissions.request({ origins: [pattern] });
    if (!granted) {
        throw new Error(`Permission to access ${origin} was denied`);
    }
};
