import { ensureOk, publicRequestHeaders } from "ente-base/http";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import type { CastReceiver } from "ente-cast-wasm";
import { wait } from "ente-utils/promise";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";

export interface Registration {
    pairingCode: string;
    receiver: CastReceiver;
}

export const register = async (): Promise<Registration> => {
    const { CastReceiver } = await import("ente-cast-wasm");
    const receiver = new CastReceiver();

    let pairingCode: string | undefined;
    while (true) {
        try {
            pairingCode = await registerDevice(receiver.publicKey);
        } catch (e) {
            log.error("Failed to register public key with server", e);
        }
        if (pairingCode) break;
        await wait(10000);
    }

    return { pairingCode, receiver };
};

const registerDevice = async (publicKey: string) => {
    const res = await fetch(await apiURL("/cast/device-info"), {
        method: "POST",
        headers: publicRequestHeaders(),
        body: JSON.stringify({ publicKey }),
    });
    ensureOk(res);
    return z.object({ deviceCode: z.string() }).parse(await res.json())
        .deviceCode;
};

export interface CastPayload {
    castToken: string;
    collectionID: number;
    collectionKey: string;
}

export const getCastPayload = async (
    registration: Registration,
): Promise<CastPayload | undefined> => {
    const { pairingCode, receiver } = registration;

    const encryptedCastData = await getEncryptedCastData(pairingCode);
    if (!encryptedCastData) return undefined;

    const payload = receiver.openPayload(encryptedCastData);
    return {
        castToken: payload.castToken,
        collectionID: Number(payload.collectionID),
        collectionKey: payload.collectionKey,
    };
};

const getEncryptedCastData = async (code: string) => {
    const res = await fetch(await apiURL(`/cast/cast-data/${code}`), {
        headers: publicRequestHeaders(),
    });
    ensureOk(res);
    return z
        .object({
            encCastData: z.string().nullish().transform(nullToUndefined),
        })
        .parse(await res.json()).encCastData;
};
