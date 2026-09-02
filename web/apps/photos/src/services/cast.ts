import { namedError } from "ente-base/error";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { prepareCastPayload } from "ente-cast-wasm";
import type { Collection } from "ente-media/collection";
import { z } from "zod";

export const revokeAllCastTokens = async () =>
    ensureOk(
        await fetch(await apiURL("/cast/revoke-all-tokens"), {
            method: "DELETE",
            headers: await authenticatedRequestHeaders(),
        }),
    );

const publicKeysForPairingCode = async (code: string) => {
    const res = await fetch(await apiURL(`/cast/device-info/${code}`), {
        headers: await authenticatedRequestHeaders(),
    });
    if (res.status == 404) return undefined;
    ensureOk(res);
    return z
        .object({ publicKey: z.string(), pqPublicKey: z.string().optional() })
        .parse(await res.json());
};

export const publishCastPayload = async (
    deviceCode: string,
    collection: Collection,
) => {
    const publicKeys = await publicKeysForPairingCode(deviceCode);
    if (!publicKeys) {
        throw namedError("cast_device_not_found", "Unknown device code");
    }

    const { castToken, encryptedPayload } = await prepareCastPayload(
        publicKeys.publicKey,
        publicKeys.pqPublicKey,
        collection.id,
        collection.key,
    );
    const res = await fetch(await apiURL("/cast/cast-data"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify({
            castToken,
            deviceCode,
            encPayload: encryptedPayload,
            collectionID: collection.id,
        }),
    });
    ensureOk(res);
};
