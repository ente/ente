import type { LockerCollectionParticipant } from "@/types";
import { getPublicKey } from "ente-accounts-rs/services/user";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";
import { boxSeal } from "./crypto";
import {
    RemoteCollectionUserSchema,
    toLockerCollectionParticipant,
} from "./remote-types";

const RemoteShareesResponse = z.object({
    sharees: z.array(RemoteCollectionUserSchema),
});

interface CollectionSharingDeps<TCollectionRecord> {
    getCollectionRecord: (
        collectionID: number,
    ) => TCollectionRecord | undefined;
    decryptCollectionKey: (
        collectionRecord: TCollectionRecord,
        masterKey: string,
    ) => Promise<string>;
    updateCollectionShareesInCache: (
        collectionID: number,
        sharees: LockerCollectionParticipant[],
    ) => void;
}

const parseAndCacheSharees = <TCollectionRecord>(
    collectionID: number,
    responseBody: unknown,
    deps: CollectionSharingDeps<TCollectionRecord>,
) => {
    const { sharees } = RemoteShareesResponse.parse(responseBody);
    const parsedSharees = sharees.map(toLockerCollectionParticipant);
    deps.updateCollectionShareesInCache(collectionID, parsedSharees);
    return parsedSharees;
};

export const fetchCollectionShareesWithDeps = async <TCollectionRecord>(
    collectionID: number,
    deps: CollectionSharingDeps<TCollectionRecord>,
): Promise<LockerCollectionParticipant[]> => {
    const res = await fetch(
        await apiURL("/collections/sharees", { collectionID }),
        { headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
    return parseAndCacheSharees(collectionID, await res.json(), deps);
};

export const shareCollectionWithDeps = async <TCollectionRecord>(
    collectionID: number,
    email: string,
    masterKey: string,
    deps: CollectionSharingDeps<TCollectionRecord>,
): Promise<LockerCollectionParticipant[]> => {
    const collectionRecord = deps.getCollectionRecord(collectionID);
    if (!collectionRecord) {
        throw new Error(`Collection ${collectionID} not in cache`);
    }

    const collectionKey = await deps.decryptCollectionKey(
        collectionRecord,
        masterKey,
    );
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
    return parseAndCacheSharees(collectionID, await res.json(), deps);
};

export const unshareCollectionWithDeps = async <TCollectionRecord>(
    collectionID: number,
    email: string,
    deps: CollectionSharingDeps<TCollectionRecord>,
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
    return parseAndCacheSharees(collectionID, await res.json(), deps);
};
