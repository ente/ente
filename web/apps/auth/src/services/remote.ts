import { codeFromURIString, type Code } from "@/services/code";
import { decryptBox, decryptMetadataJSON } from "ente-base/crypto";
import {
    authenticatedRequestHeaders,
    ensureOk,
    HTTPError,
} from "ente-base/http";
import log from "ente-base/log";
import { apiURL } from "ente-base/origins";
import { ensureString } from "ente-utils/ensure";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";

export interface AuthCodesAndTimeOffset {
    codes: Code[];
    /**
     * An optional and approximate correction (milliseconds) which should be
     * applied to the current client's time when deriving TOTPs.
     */
    timeOffset?: number;
}

/**
 * Fetch the user's auth codes from remote and decrypt them using the user's
 * master key.
 *
 * @param masterKey The user's base64 encoded master key.
 */
export const getAuthCodesAndTimeOffset = async (
    masterKey: string,
): Promise<AuthCodesAndTimeOffset> => {
    const authenticatorEntityKey = await getAuthenticatorEntityKey();
    if (!authenticatorEntityKey) {
        // The user might not have stored any codes yet from the mobile app.
        return { codes: [] };
    }

    const authenticatorKey = await decryptAuthenticatorKey(
        authenticatorEntityKey,
        masterKey,
    );

    const { entities, timeOffset } =
        await authenticatorEntityDiff(authenticatorKey);

    const codes = entities
        .map((entity) => {
            try {
                return codeFromURIString(entity.id, ensureString(entity.data));
            } catch (e) {
                log.error(`Failed to parse codeID ${entity.id}`, e);
                return undefined;
            }
        })
        .filter((f) => f !== undefined)
        .filter((f) => {
            // Do not show trashed entries in the web interface.
            return !f.codeDisplay?.trashed;
        })
        .sort((a, b) => {
            // If only one of them is pinned, prefer it.
            if (a.codeDisplay?.pinned && !b.codeDisplay?.pinned) return -1;
            if (!a.codeDisplay?.pinned && b.codeDisplay?.pinned) return 1;
            // If we get here, either both are pinned, or none are...

            // Sort by issuer, alphabetically.
            if (a.issuer && b.issuer) {
                return a.issuer.localeCompare(b.issuer);
            }
            if (a.issuer) {
                return -1;
            }
            if (b.issuer) {
                return 1;
            }
            return 0;
        });

    return { codes, timeOffset };
};

/**
 * Authenticator entities obtained from remote.
 */
interface AuthenticatorEntity {
    id: string;
    data: unknown;
}

/**
 * Zod schema for a item in the user entity diff.
 */
const RemoteAuthenticatorEntityChange = z.object({
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

const AuthenticatorEntityDiffResponse = z.object({
    /**
     * Changes to entities.
     */
    diff: z.array(RemoteAuthenticatorEntityChange),
    /**
     * An optional epoch microseconds indicating the remote time when it
     * generated the response.
     */
    timestamp: z.number().nullish().transform(nullToUndefined),
});

export interface AuthenticatorEntityDiffResult {
    /**
     * The decrypted {@link AuthenticatorEntity} values.
     */
    entities: AuthenticatorEntity[];
    /**
     * An optional and approximate offset (in milliseconds) by which the time on
     * the current client is out of sync.
     *
     * This offset is computed by calculated by comparing the timestamp when the
     * remote generated the response to the time we received it. As such
     * (because of network delays etc) this will not be an accurate offset,
     * neither is it meant to be - it is only meant to help users whose devices
     * have wildly off times to still see the correct codes.
     *
     * Note that, for various reasons, remote might not send us a timestamp when
     * fetching the diff, so this is a best effort correction, and is not
     * guaranteed to be present.
     */
    timeOffset: number | undefined;
}

/**
 * Fetch all the authenticator entities for the user, and an estimated time
 * drift for the current client.
 *
 * @param authenticatorKey The (base64 encoded) key that should be used for
 * decrypting the authenticator entities received from remote.
 */
export const authenticatorEntityDiff = async (
    authenticatorKey: string,
): Promise<AuthenticatorEntityDiffResult> => {
    const decrypt = (encryptedData: string, decryptionHeader: string) =>
        decryptMetadataJSON(
            { encryptedData, decryptionHeader },
            authenticatorKey,
        );

    // Fetch all the entities, paginating the requests.
    const encryptedEntities = new Map<
        string,
        { id: string; encryptedData: string; header: string }
    >();
    let sinceTime = 0;
    const batchSize = 2500;

    let timeOffset: number | undefined = undefined;

    while (true) {
        const res = await fetch(
            await apiURL("/authenticator/entity/diff", {
                sinceTime,
                limit: batchSize,
            }),
            { headers: await authenticatedRequestHeaders() },
        );
        ensureOk(res);

        const { diff, timestamp } = AuthenticatorEntityDiffResponse.parse(
            await res.json(),
        );

        if (timestamp) {
            // - timestamp is in epoch microseconds.
            // - Date.now and timeOffset are in epoch milliseconds.
            timeOffset = Date.now() - Math.floor(timestamp / 1e3);
        }

        if (diff.length == 0) break;

        for (const change of diff) {
            sinceTime = Math.max(sinceTime, change.updatedAt);
            if (change.isDeleted) {
                encryptedEntities.delete(change.id);
            } else {
                encryptedEntities.set(change.id, {
                    id: change.id,
                    encryptedData: change.encryptedData!,
                    header: change.header!,
                });
            }
        }
    }

    const entities = await Promise.all(
        [...encryptedEntities.values()].map(
            async ({ id, encryptedData, header }) => ({
                id,
                data: await decrypt(encryptedData, header),
            }),
        ),
    );

    return { entities, timeOffset };
};

export const AuthenticatorEntityKey = z.object({
    /**
     * The authenticator entity key (base64 string), encrypted with the user's
     * master key.
     */
    encryptedKey: z.string(),
    /**
     * Base64 encoded nonce used during encryption of the authenticator key.
     */
    header: z.string(),
});

export type AuthenticatorEntityKey = z.infer<typeof AuthenticatorEntityKey>;

/**
 * Fetch the encryption key for the authenticator entities from remote.
 *
 * This is a special case of an entity key for use with "authenticator"
 * entities. See: [Note: User entity keys].
 *
 * @returns the authenticator key, or undefined if there is no authenticator key
 * yet created on remote for the user.
 */
export const getAuthenticatorEntityKey = async (): Promise<
    AuthenticatorEntityKey | undefined
> => {
    const res = await fetch(await apiURL("/authenticator/key"), {
        headers: await authenticatedRequestHeaders(),
    });
    if (!res.ok) {
        // Remote says HTTP 404 Not Found if there is no key yet for the user.
        if (res.status == 404) return undefined;
        throw new HTTPError(res);
    } else {
        return AuthenticatorEntityKey.parse(await res.json());
    }
};

/**
 * Decrypt an encrypted authenticator key using the user's master key.
 */
const decryptAuthenticatorKey = async (
    remote: AuthenticatorEntityKey,
    masterKey: string,
) =>
    decryptBox(
        {
            encryptedData: remote.encryptedKey,
            // Remote calls it the header, but it really is the nonce.
            nonce: remote.header,
        },
        masterKey,
    );
