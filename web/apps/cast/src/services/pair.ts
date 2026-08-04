import { boxSealOpenBytes, generateKeyPair } from "ente-base/crypto";
import { ensureOk, publicRequestHeaders } from "ente-base/http";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import { wait } from "ente-utils/promise";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";

export interface Registration {
    pairingCode: string;
    publicKey: string;
    privateKey: string;
}

export const register = async (): Promise<Registration> => {
    const { publicKey, privateKey } = await generateKeyPair();

    let pairingCode: string | undefined;
    while (true) {
        try {
            pairingCode = await registerDevice(publicKey);
        } catch (e) {
            log.error("Failed to register public key with server", e);
        }
        if (pairingCode) break;
        await wait(10000);
    }

    return { pairingCode, publicKey, privateKey };
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

const CastPayload = z.object({
    castToken: z.string(),
    collectionID: z.number(),
    collectionKey: z.string(),
});

export type CastPayload = z.infer<typeof CastPayload>;

export const getCastPayload = async (
    registration: Registration,
): Promise<CastPayload | undefined> => {
    const { pairingCode, publicKey, privateKey } = registration;

    const encryptedCastData = await getEncryptedCastData(pairingCode);
    if (!encryptedCastData) return undefined;

    const jsonString = new TextDecoder().decode(
        await boxSealOpenBytes(encryptedCastData, { publicKey, privateKey }),
    );
    return CastPayload.parse(JSON.parse(jsonString));
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
