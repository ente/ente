import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import type { Collection } from "ente-media/collection";
import { z } from "zod";

export const revokeAllCastTokens = async () =>
    ensureOk(
        await fetch(await apiURL("/cast/revoke-all-tokens"), {
            method: "DELETE",
            headers: await authenticatedRequestHeaders(),
        }),
    );

const publicKeyForPairingCode = async (code: string) => {
    const res = await fetch(await apiURL(`/cast/device-info/${code}`), {
        headers: await authenticatedRequestHeaders(),
    });
    if (res.status == 404) return undefined;
    ensureOk(res);
    return z.object({ publicKey: z.string() }).parse(await res.json())
        .publicKey;
};

// AlbumCastDialog matches this exact message.
export const unknownDeviceCodeErrorMessage = "Unknown device code";

export const publishCastPayload = async (
    deviceCode: string,
    collection: Collection,
) => {
    const publicKey = await publicKeyForPairingCode(deviceCode);
    if (!publicKey) throw new Error(unknownDeviceCodeErrorMessage);

    const { preparePayload } = await import("ente-cast-wasm");
    const { castToken, encryptedPayload } = preparePayload(
        publicKey,
        BigInt(collection.id),
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
