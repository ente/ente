import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";

export const getPublicKey = async (email: string) => {
    const res = await fetch(await apiURL("/users/public-key", { email }), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return z.object({ publicKey: z.string() }).parse(await res.json())
        .publicKey;
};

export const get2FAStatus = async () => {
    const res = await fetch(await apiURL("/users/two-factor/status"), {
        headers: await authenticatedRequestHeaders(),
    });
    ensureOk(res);
    return z.object({ status: z.boolean() }).parse(await res.json()).status;
};

export const disable2FA = async () =>
    ensureOk(
        await fetch(await apiURL("/users/two-factor/disable"), {
            method: "POST",
            headers: await authenticatedRequestHeaders(),
        }),
    );
