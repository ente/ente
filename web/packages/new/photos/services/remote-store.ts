import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";

// Despite its name, this endpoint returns preferences as well as feature flags.
export const fetchFeatureFlags = async () => {
    const res = await fetch(await apiURL("/remote-store/feature-flags"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return res;
};

const getRemoteValue = async (key: string, defaultValue: string) => {
    const res = await fetch(
        await apiURL("/remote-store", { key, defaultValue }),
        { headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
    return GetRemoteStoreResponse.parse(await res.json())?.value;
};

const GetRemoteStoreResponse = z.object({ value: z.string() }).nullable();

export const getRemoteFlag = async (key: string) =>
    (await getRemoteValue(key, "false")) == "true";

export const updateRemoteValue = async (key: string, value: string) =>
    ensureOk(
        await fetch(await apiURL("/remote-store/update"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({ key, value }),
        }),
    );

export const updateRemoteFlag = (key: string, value: boolean) =>
    updateRemoteValue(key, JSON.stringify(value));
