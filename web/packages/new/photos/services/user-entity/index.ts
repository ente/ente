import {
    decryptBox,
    encryptBlob,
    encryptBox,
    generateBlobOrStreamKey,
} from "ente-base/crypto";
import { nullishToEmpty, nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import { gunzip, gzip } from "../../utils/gzip";
import type { CGroupUserEntityData } from "../ml/people";
import {
    savedEntities,
    savedLatestUpdatedAt,
    savedRemoteUserEntityKey,
    saveEntities,
    saveLatestUpdatedAt,
    saveRemoteUserEntityKey,
    type LocalUserEntity,
} from "./db";
import {
    getUserEntityKey,
    postUserEntity,
    postUserEntityKey,
    putUserEntity,
    RemoteUserEntityKey,
    userEntityDiff,
} from "./remote";

export type EntityType = "location" | "cgroup";

const RemoteLocationTagData = z.looseObject({
    name: z.string(),
    radius: z.number(),
    centerPoint: z.object({ latitude: z.number(), longitude: z.number() }),
});

export type LocationTag = z.infer<typeof RemoteLocationTagData>;

export const savedLocationTags = (): Promise<LocationTag[]> =>
    savedEntities("location").then((es) =>
        es.map((e) => RemoteLocationTagData.parse(e.data)),
    );

const RemoteFaceCluster = z.looseObject({
    id: z.string(),
    faces: z.string().array(),
});

const RemoteCGroupData = z.looseObject({
    name: z.string().nullish().transform(nullToUndefined),
    assigned: z
        .array(RemoteFaceCluster.nullish())
        .nullish()
        .transform((arr) =>
            (arr ?? []).filter(
                (x): x is z.infer<typeof RemoteFaceCluster> => x != null,
            ),
        ),
    rejectedFaceIDs: z.array(z.string()).nullish().transform(nullishToEmpty),
    manuallyAssigned: z.array(z.number()).nullish().transform(nullishToEmpty),
    isHidden: z.boolean(),
    avatarFaceID: z.string().nullish().transform(nullToUndefined),
    isPinned: z.boolean().nullish().transform(Boolean),
    hideFromMemories: z.boolean().nullish().transform(Boolean),
});

export type CGroup = Omit<LocalUserEntity, "data"> & {
    // Keep this aligned with RemoteCGroupData.
    data: CGroupUserEntityData;
};

export const savedCGroups = (): Promise<CGroup[]> =>
    savedEntities("cgroup").then((es) =>
        es.map((e) => ({ ...e, data: RemoteCGroupData.parse(e.data) })),
    );

export const pullUserEntities = async (type: EntityType, masterKey: string) => {
    const entityKey = await getOrCreateEntityKey(type, masterKey);

    let sinceTime = (await savedLatestUpdatedAt(type)) ?? 0;
    while (true) {
        const diff = await userEntityDiff(type, sinceTime, entityKey);
        if (diff.length == 0) break;

        const entityByID = new Map(
            (await savedEntities(type)).map((e) => [e.id, e]),
        );

        for (const { id, data, updatedAt } of diff) {
            if (data) {
                const s = isGzipped(type)
                    ? await gunzip(data)
                    : new TextDecoder().decode(data);
                entityByID.set(id, { id, data: JSON.parse(s), updatedAt });
            } else {
                entityByID.delete(id);
            }
            sinceTime = Math.max(sinceTime, updatedAt);
        }

        await saveEntities(type, [...entityByID.values()]);
        await saveLatestUpdatedAt(type, sinceTime);
    }
};

// Location encrypts JSON; cgroup encrypts gzipped JSON.
const isGzipped = (type: EntityType) => type == "cgroup";

export const addUserEntity = async (
    type: EntityType,
    data: unknown,
    masterKey: string,
) =>
    await postUserEntity(
        type,
        await encryptedUserEntityData(type, data, masterKey),
    );

const encryptedUserEntityData = async (
    type: EntityType,
    data: unknown,
    masterKey: string,
) => {
    const entityKey = await getOrCreateEntityKey(type, masterKey);

    const json = JSON.stringify(data);
    const bytes = isGzipped(type)
        ? await gzip(json)
        : new TextEncoder().encode(json);
    return encryptBlob(bytes, entityKey);
};

export const updateOrCreateUserEntities = async (
    type: EntityType,
    entities: LocalUserEntity[],
    masterKey: string,
) =>
    await Promise.all(
        entities.map(({ id, data }) =>
            encryptedUserEntityData(type, data, masterKey).then(
                (encryptedBlob) => putUserEntity(id, type, encryptedBlob),
            ),
        ),
    );

const getOrCreateEntityKey = async (type: EntityType, masterKey: string) => {
    const saved = await savedRemoteUserEntityKey(type);
    if (saved) return decryptEntityKey(saved, masterKey);

    const existing = await getUserEntityKey(type);
    if (existing) {
        // Decrypt before caching so malformed remote data cannot poison local
        // state.
        const result = await decryptEntityKey(existing, masterKey);
        await saveRemoteUserEntityKey(type, existing);
        return result;
    }

    // As a sanity check, generate the key but immediately encrypt it as if it
    // were fetched from remote and then try to decrypt it before doing anything
    // with it.
    const generated = await generateEncryptedEntityKey(masterKey);
    const result = await decryptEntityKey(generated, masterKey);
    await postUserEntityKey(type, generated);
    await saveRemoteUserEntityKey(type, generated);
    return result;
};

const generateEncryptedEntityKey = async (masterKey: string) => {
    const { encryptedData, nonce } = await encryptBox(
        await generateBlobOrStreamKey(),
        masterKey,
    );
    // Museum calls this nonce "header".
    return { encryptedKey: encryptedData, header: nonce };
};

const decryptEntityKey = async (
    remote: RemoteUserEntityKey,
    masterKey: string,
) =>
    decryptBox(
        { encryptedData: remote.encryptedKey, nonce: remote.header },
        masterKey,
    );
