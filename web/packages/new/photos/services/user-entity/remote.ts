import { decryptBlobBytes } from "ente-base/crypto";
import type { EncryptedBlobB64 } from "ente-base/crypto/types";
import {
    authenticatedRequestHeaders,
    ensureOk,
    HTTPError,
} from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { z } from "zod";
import type { EntityType } from ".";

/**
 * The maximum number of items to fetch in a single diff
 *
 * [Note: Limit of returned items in /diff requests]
 *
 * The various GET /diff API methods, which tell the client what all has changed
 * since a timestamp (provided by the client) take a limit parameter.
 *
 * These diff API calls return all items whose updated at is greater
 * (non-inclusive) than the timestamp we provide. So there is no mechanism for
 * pagination of items which have the exact same updated at.
 *
 * Conceptually, it may happen that there are more items than the limit we've
 * provided, but there are practical safeguards.
 *
 * For file diff, the limit is advisory, and remote may return less, equal or
 * more items than the provided limit. The scenario where it returns more is
 * when more files than the limit have the same updated at. Theoretically it
 * would make the diff response unbounded, however in practice file
 * modifications themselves are all batched. Even if the user were to select all
 * the files in their library and updates them all in one go in the UI, their
 * client app is required (with server side enforcement) to use batched API
 * calls to make those updates. Thus, each of those batches would get distinct
 * updated at values.
 *
 * For entity diff, there are no bulk operations yet that can result in the
 * assignment of the same microsecond to hundreds of items.
 */
const defaultDiffLimit = 500;

/**
 * An entry in the user entity diff.
 *
 * Each change either contains the latest data associated with a particular user
 * entity that has been created or updated, or has a flag set to indicate that
 * the corresponding entity has been deleted.
 */
export interface UserEntityChange {
    /**
     * The UUID or nanoid of the entity.
     */
    id: string;
    /**
     * Arbitrary (decrypted) data associated with the entity. The format of this
     * data is specific to each entity type.
     *
     * This will not be present for entities that have been deleted on remote.
     */
    data: Uint8Array<ArrayBuffer> | undefined;
    /**
     * Epoch microseconds denoting when this entity was last changed (created or
     * updated or deleted).
     */
    updatedAt: number;
}

/**
 * Zod schema for a item in the user entity diff.
 */
const RemoteUserEntityChange = z.object({
    id: z.string(),
    /**
     * Base64 string containing the encrypted contents of the entity.
     *
     * Will be `null` when isDeleted is true.
     */
    encryptedData: z.string().nullable(),
    /**
     * Base64 string containing the decryption header.
     *
     * Will be `null` when isDeleted is true.
     */
    header: z.string().nullable(),
    /**
     * `true` if the corresponding entity was deleted.
     */
    isDeleted: z.boolean(),
    /**
     * Epoch microseconds when this entity was last updated.
     *
     * This value is suitable for being passed as the `sinceTime` in the diff
     * requests to implement pagination.
     */
    updatedAt: z.number(),
});

/**
 * Fetch the next set of changes (upserts or deletions) to user entities of the
 * given type since the given time.
 *
 * @param type The type of the entities to fetch.
 *
 * @param sinceTime Epoch microseconds. This is used to ask remote to provide us
 * only entities whose {@link updatedAt} is more than the given value. Set this
 * to zero to start from the beginning.
 *
 * @param entityKey The base64 encoded key to use for decrypting the encrypted
 * contents of the user entity.
 *
 * [Note: Diff response will have at most one entry for an id]
 *
 * Unlike git diffs which track all changes, the diffs we get from remote are
 * guaranteed to contain only one entry (upsert or delete) for a particular Ente
 * object. This holds true irrespective of the diff limit.
 *
 * For example, in a user entity diff, it is guaranteed that there will only be
 * at max one entry for a particular entity id. The entry will have no data to
 * indicate that the corresponding entity was deleted. Otherwise, when the data
 * is present, it is taken as the creation of a new entity or the updation of an
 * existing one.
 *
 * This behaviour comes from how remote stores the underlying, say, entities. A
 * diff returns just entities whose updation times greater than the provided
 * since time (limited to the given diff limit). So there will be at most one
 * row for a particular entity id. And if that entity has been deleted, then the
 * row will be a tombstone, so data be absent.
 */
export const userEntityDiff = async (
    type: EntityType,
    sinceTime: number,
    entityKey: string,
): Promise<UserEntityChange[]> => {
    const decrypt = (encryptedData: string, decryptionHeader: string) =>
        decryptBlobBytes({ encryptedData, decryptionHeader }, entityKey);

    const res = await fetch(
        await apiURL("/user-entity/entity/diff", {
            type,
            sinceTime,
            limit: defaultDiffLimit,
        }),
        { headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
    const diff = z
        .object({ diff: z.array(RemoteUserEntityChange) })
        .parse(await res.json()).diff;
    return Promise.all(
        diff.map(
            async ({ id, encryptedData, header, isDeleted, updatedAt }) => ({
                id,
                data: !isDeleted
                    ? await decrypt(encryptedData!, header!)
                    : undefined,
                updatedAt,
            }),
        ),
    );
};

/**
 * Create a new user entity with the given {@link type} on remote.
 *
 * @returns The ID of the newly created entity.
 */
export const postUserEntity = async (
    type: EntityType,
    { encryptedData, decryptionHeader }: EncryptedBlobB64,
) => {
    const res = await fetch(await apiURL("/user-entity/entity"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify({
            type,
            encryptedData: encryptedData,
            header: decryptionHeader,
        }),
    });
    ensureOk(res);
    return z.object({ id: z.string() }).parse(await res.json()).id;
};

/**
 * Update an existing remote user entity with the given {@link id} and
 * {@link type}.
 */
export const putUserEntity = async (
    id: string,
    type: EntityType,
    { encryptedData, decryptionHeader }: EncryptedBlobB64,
) =>
    ensureOk(
        await fetch(await apiURL("/user-entity/entity"), {
            method: "PUT",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify({
                id,
                type,
                encryptedData: encryptedData,
                header: decryptionHeader,
            }),
        }),
    );

/**
 * Delete an existing remote user entity with the given {@link id}.
 */
export const deleteUserEntity = async (id: string) =>
    ensureOk(
        await fetch(await apiURL("/user-entity/entity", { id }), {
            method: "DELETE",
            headers: await authenticatedRequestHeaders(),
        }),
    );

export const RemoteUserEntityKey = z.object({
    /** Base64 encoded entity key, encrypted with the user's master key. */
    encryptedKey: z.string(),
    /** Base64 encoded nonce used during encryption of this entity key. */
    header: z.string(),
});

export type RemoteUserEntityKey = z.infer<typeof RemoteUserEntityKey>;

/**
 * Fetch the encryption key for the given user entity {@link type} from remote.
 *
 * [Note: User entity keys]
 *
 * There is one encryption key (itself encrypted with the user's master key) for
 * each user entity type. If the key doesn't exist on remote, then the client is
 * expected to create one on the user's behalf. Remote will disallow attempts to
 * multiple keys for the same user entity type.
 */
export const getUserEntityKey = async (
    type: EntityType,
): Promise<RemoteUserEntityKey | undefined> => {
    const res = await fetch(await apiURL("/user-entity/key", { type }), {
        headers: await authenticatedRequestHeaders(),
    });
    if (!res.ok) {
        // Remote says HTTP 404 Not Found if there is no key yet for the user.
        if (res.status == 404) return undefined;
        throw new HTTPError(res);
    } else {
        return RemoteUserEntityKey.parse(await res.json());
    }
};

/**
 * Create a new encryption key for the given user entity {@link type} on remote.
 *
 * See: [Note: User entity keys]
 */
export const postUserEntityKey = async (
    type: EntityType,
    entityKey: RemoteUserEntityKey,
) => {
    const url = await apiURL("/user-entity/key");
    const res = await fetch(url, {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify({ type, ...entityKey }),
    });
    ensureOk(res);
};
