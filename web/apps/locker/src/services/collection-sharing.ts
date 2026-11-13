import type { LockerCollectionParticipant } from "@/types";
import { getPublicKey } from "ente-accounts/services/user";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { boxSeal } from "ente-locker-wasm";
import { z } from "zod";
import {
    getCollectionRecord,
    updateCollectionShareesInCache,
} from "./locker-cache";
import {
    RemoteCollectionUserSchema,
    toLockerCollectionParticipant,
} from "./remote-types";
import { decryptCollectionKey } from "./sync/decrypt";

const RemoteShareesResponse = z.object({
    sharees: z.array(RemoteCollectionUserSchema),
});

const parseAndCacheSharees = (collectionID: number, responseBody: unknown) => {
    const { sharees } = RemoteShareesResponse.parse(responseBody);
    const parsedSharees = sharees.map(toLockerCollectionParticipant);
    updateCollectionShareesInCache(collectionID, parsedSharees);
    return parsedSharees;
};

export const fetchCollectionSharees = async (
    collectionID: number,
): Promise<LockerCollectionParticipant[]> => {
    const res = await fetch(
        await apiURL("/collections/sharees", { collectionID }),
        { headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
    return parseAndCacheSharees(collectionID, await res.json());
};

export const shareCollection = async (
    collectionID: number,
    email: string,
): Promise<LockerCollectionParticipant[]> => {
    const collectionRecord = getCollectionRecord(collectionID);
    if (!collectionRecord) {
        throw new Error(`Collection ${collectionID} not in cache`);
    }

    const collectionKey = await decryptCollectionKey(collectionRecord);
    const publicKey = await getPublicKey(email);
    const encryptedKey = await boxSeal(collectionKey, publicKey);

    const res = await fetch(await apiURL("/collections/share"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            collectionID,
            email,
            role: "VIEWER",
            encryptedKey,
        }),
    });
    ensureOk(res);
    return parseAndCacheSharees(collectionID, await res.json());
};

export const unshareCollection = async (
    collectionID: number,
    email: string,
): Promise<LockerCollectionParticipant[]> => {
    const res = await fetch(await apiURL("/collections/unshare"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ collectionID, email }),
    });
    ensureOk(res);
    return parseAndCacheSharees(collectionID, await res.json());
};

export const leaveCollection = async (collectionID: number): Promise<void> => {
    const res = await fetch(
        await apiURL(`/collections/leave/${collectionID}`),
        { method: "POST", headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
};
