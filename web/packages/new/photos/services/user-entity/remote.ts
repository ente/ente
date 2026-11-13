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

// Diffs paginate by non-inclusive updatedAt, so equal timestamps cannot span pages.
// Entity writes are not bulked, keeping same-timestamp groups below this limit.
const defaultDiffLimit = 500;

export interface UserEntityChange {
    id: string;
    // Deleted entities are represented by undefined data.
    data: Uint8Array<ArrayBuffer> | undefined;
    // Epoch microseconds.
    updatedAt: number;
}

const RemoteUserEntityChange = z.object({
    id: z.string(),
    encryptedData: z.string().nullable(),
    header: z.string().nullable(),
    isDeleted: z.boolean(),
    updatedAt: z.number(),
});

// Each diff contains at most one latest row or tombstone per entity ID.
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

export const deleteUserEntity = async (id: string) =>
    ensureOk(
        await fetch(await apiURL("/user-entity/entity", { id }), {
            method: "DELETE",
            headers: await authenticatedRequestHeaders(),
        }),
    );

export const RemoteUserEntityKey = z.object({
    encryptedKey: z.string(),
    header: z.string(),
});

export type RemoteUserEntityKey = z.infer<typeof RemoteUserEntityKey>;

// Each entity type has one key; clients create it when this returns 404.
export const getUserEntityKey = async (
    type: EntityType,
): Promise<RemoteUserEntityKey | undefined> => {
    const res = await fetch(await apiURL("/user-entity/key", { type }), {
        headers: await authenticatedRequestHeaders(),
    });
    if (!res.ok) {
        if (res.status == 404) return undefined;
        throw new HTTPError(res);
    } else {
        return RemoteUserEntityKey.parse(await res.json());
    }
};

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
