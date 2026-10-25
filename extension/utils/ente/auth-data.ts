// Adapted from `web/apps/auth/src/services/remote.ts`. Fetches and decrypts
// the account's authenticator items.
import { z } from "zod";
import { codeFromURIString, type Code } from "./code";
import { decryptMetadataJSON, decryptSecretBox } from "./crypto";
import { authenticatedRequestHeaders, ensureOk, HTTPError } from "./http";
import { apiURL } from "./origins";

export interface AuthCodesAndTimeOffset {
    codes: Code[];
    timeOffset: number;
}

// The account's authenticator key, encrypted with the master key.
const AuthenticatorEntityKey = z.object({
    encryptedKey: z.string(),
    header: z.string(),
});

const RemoteAuthenticatorEntityChange = z.object({
    id: z.string(),
    encryptedData: z.string().nullable(),
    header: z.string().nullable(),
    isDeleted: z.boolean(),
    updatedAt: z.number(),
});

const AuthenticatorEntityDiffResponse = z.object({
    diff: z.array(RemoteAuthenticatorEntityChange),
    timestamp: z
        .number()
        .nullish()
        .transform((v) => v ?? undefined),
});

const diffBatchSize = 2500;

export const getAuthCodesAndTimeOffset = async (
    masterKey: string,
): Promise<AuthCodesAndTimeOffset> => {
    const authenticatorEntityKey = await getAuthenticatorEntityKey();
    if (!authenticatorEntityKey) return { codes: [], timeOffset: 0 };

    const authenticatorKey = await decryptAuthenticatorKey(
        authenticatorEntityKey,
        masterKey,
    );

    const { entities, timeOffset } =
        await authenticatorEntityDiff(authenticatorKey);

    const codes = entities
        .map((entity) => {
            try {
                if (typeof entity.data == "string") {
                    return codeFromURIString(entity.id, entity.data);
                }
                return undefined;
            } catch {
                return undefined;
            }
        })
        .filter((f) => f !== undefined)
        .filter((f) => !f.codeDisplay?.trashed)
        .sort((a, b) => {
            if (a.codeDisplay?.pinned && !b.codeDisplay?.pinned) return -1;
            if (!a.codeDisplay?.pinned && b.codeDisplay?.pinned) return 1;
            if (a.issuer && b.issuer) return a.issuer.localeCompare(b.issuer);
            if (a.issuer) return -1;
            if (b.issuer) return 1;
            return 0;
        });

    return { codes, timeOffset };
};

interface AuthenticatorEntity {
    id: string;
    data: unknown;
}

const authenticatorEntityDiff = async (
    authenticatorKey: string,
): Promise<{ entities: AuthenticatorEntity[]; timeOffset: number }> => {
    const decrypt = (encryptedData: string, decryptionHeader: string) =>
        decryptMetadataJSON(
            { encryptedData, decryptionHeader },
            authenticatorKey,
        );

    const encryptedEntities = new Map<
        string,
        { id: string; encryptedData: string; header: string }
    >();
    let sinceTime = 0;
    let timeOffset = 0;

    while (true) {
        const res = await fetch(
            await apiURL("/authenticator/entity/diff", {
                sinceTime,
                limit: diffBatchSize,
            }),
            { headers: await authenticatedRequestHeaders() },
        );
        ensureOk(res);

        const { diff, timestamp } = AuthenticatorEntityDiffResponse.parse(
            await res.json(),
        );

        if (timestamp) {
            // Remote timestamp is epoch microseconds; timeOffset is millis.
            timeOffset = Math.floor(timestamp / 1e3) - Date.now();
        }

        if (diff.length == 0) break;

        for (const change of diff) {
            sinceTime = Math.max(sinceTime, change.updatedAt);
            if (change.isDeleted) {
                encryptedEntities.delete(change.id);
            } else if (change.encryptedData && change.header) {
                encryptedEntities.set(change.id, {
                    id: change.id,
                    encryptedData: change.encryptedData,
                    header: change.header,
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

const getAuthenticatorEntityKey = async (): Promise<
    z.infer<typeof AuthenticatorEntityKey> | undefined
> => {
    const res = await fetch(await apiURL("/authenticator/key"), {
        headers: await authenticatedRequestHeaders(),
    });
    if (!res.ok) {
        if (res.status == 404) return undefined;
        throw new HTTPError(res);
    }
    return AuthenticatorEntityKey.parse(await res.json());
};

const decryptAuthenticatorKey = async (
    remote: z.infer<typeof AuthenticatorEntityKey>,
    masterKey: string,
) =>
    decryptSecretBox(
        {
            encryptedData: remote.encryptedKey,
            // Remote calls this field the header, but it is the nonce.
            nonce: remote.header,
        },
        masterKey,
    );
