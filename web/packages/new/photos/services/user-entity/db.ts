import { getKV, getKVN, setKV } from "ente-base/kv";
import { z } from "zod";
import type { EntityType } from ".";
import { RemoteUserEntityKey } from "./remote";

const entitiesKey = (type: EntityType) => `entity/${type}`;
const entityKeyKey = (type: EntityType) => `entity/${type}/key`;
const latestUpdatedAtKey = (type: EntityType) => `entity/${type}/time`;

export interface LocalUserEntity {
    id: string;
    data: unknown;
    updatedAt: number;
}

const LocalUserEntity = z.object({
    id: z.string(),
    // Retain the data verbatim.
    data: z.looseObject({}),
    updatedAt: z.number(),
});

export const saveEntities = (type: EntityType, items: LocalUserEntity[]) =>
    setKV(entitiesKey(type), items);

export const savedEntities = async (
    type: EntityType,
): Promise<LocalUserEntity[]> =>
    LocalUserEntity.array().parse((await getKV(entitiesKey(type))) ?? []);

export const saveRemoteUserEntityKey = (
    type: EntityType,
    entityKey: RemoteUserEntityKey,
) => setKV(entityKeyKey(type), entityKey);

export const savedRemoteUserEntityKey = (
    type: EntityType,
): Promise<RemoteUserEntityKey | undefined> =>
    getKV(entityKeyKey(type)).then((s) =>
        s ? RemoteUserEntityKey.parse(s) : undefined,
    );

export const saveLatestUpdatedAt = (type: EntityType, value: number) =>
    setKV(latestUpdatedAtKey(type), value);

// This is the last fetched diff timestamp. The next pull resumes from it.
export const savedLatestUpdatedAt = (type: EntityType) =>
    getKVN(latestUpdatedAtKey(type));
