import { getKV, getKVN, setKV } from "ente-base/kv";
import { z } from "zod";
import type { EntityType } from ".";
import { RemoteUserEntityKey } from "./remote";

// Our DB footprint---
//
// All these are stored in the kv db.

const entitiesKey = (type: EntityType) => `entity/${type}`;
const entityKeyKey = (type: EntityType) => `entity/${type}/key`;
const latestUpdatedAtKey = (type: EntityType) => `entity/${type}/time`;

// ^---

/**
 * A locally persisted user entity.
 */
export interface LocalUserEntity {
    /**
     * The UUID or nanoid of the entity.
     */
    id: string;
    /**
     * Arbitrary (decrypted) data associated with the entity. The format of this
     * data is specific to each entity type, but it is guaranteed to be JSON
     * serializable.
     */
    data: unknown;
    /**
     * Epoch microseconds denoting when this entity was last changed (created or
     * updated).
     */
    updatedAt: number;
}

const LocalUserEntity = z.object({
    id: z.string(),
    // Retain the data verbatim.
    data: z.looseObject({}),
    updatedAt: z.number(),
});

/**
 * Update the list of locally persisted user entities of the given {@link type}.
 */
export const saveEntities = (type: EntityType, items: LocalUserEntity[]) =>
    setKV(entitiesKey(type), items);

/**
 * Return the list of locally persisted user entities of the given {@link type}.
 */
export const savedEntities = async (
    type: EntityType,
): Promise<LocalUserEntity[]> =>
    LocalUserEntity.array().parse((await getKV(entitiesKey(type))) ?? []);

/**
 * Save the {@link entityKey} for the given user entity {@link type} to our
 * local database.
 */
export const saveRemoteUserEntityKey = (
    type: EntityType,
    entityKey: RemoteUserEntityKey,
) => setKV(entityKeyKey(type), entityKey);

/**
 * Return the locally persisted {@link RemoteUserEntityKey}, if any,
 * corresponding the given user entity {@link type}.
 */
export const savedRemoteUserEntityKey = (
    type: EntityType,
): Promise<RemoteUserEntityKey | undefined> =>
    getKV(entityKeyKey(type)).then((s) =>
        s ? RemoteUserEntityKey.parse(s) : undefined,
    );

/**
 * Save the latest `updatedAt` {@link value} for the given user entity
 * {@link type} to our local database.
 */
export const saveLatestUpdatedAt = (type: EntityType, value: number) =>
    setKV(latestUpdatedAtKey(type), value);

/**
 * Return the locally persisted value for the latest `updatedAt` time for the
 * given user entity {@link type}.
 *
 * This is used to checkpoint diffs, so that we can resume fetching from the
 * last time we did a fetch.
 */
export const savedLatestUpdatedAt = (type: EntityType) =>
    getKVN(latestUpdatedAtKey(type));
