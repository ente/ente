import { codeFromURIString, type Code } from "@/services/code";
import { decryptBox, decryptMetadataJSON } from "ente-auth-wasm";
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
    timeOffset?: number;
}

export const getAuthCodesAndTimeOffset = async (
    masterKey: string,
): Promise<AuthCodesAndTimeOffset> => {
    const authenticatorEntityKey = await getAuthenticatorEntityKey();
    if (!authenticatorEntityKey) return { codes: [] };

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
        .filter((f) => !f.codeDisplay?.trashed)
        .sort((a, b) => {
            if (a.codeDisplay?.pinned && !b.codeDisplay?.pinned) return -1;
            if (!a.codeDisplay?.pinned && b.codeDisplay?.pinned) return 1;
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

interface AuthenticatorEntity {
    id: string;
    data: unknown;
}

const RemoteAuthenticatorEntityChange = z.object({
    id: z.string(),
    encryptedData: z.string().nullable(),
    header: z.string().nullable(),
    isDeleted: z.boolean(),
    updatedAt: z.number(),
});

const AuthenticatorEntityDiffResponse = z.object({
    diff: z.array(RemoteAuthenticatorEntityChange),
    timestamp: z.number().nullish().transform(nullToUndefined),
});

const authenticatorEntityDiffBatchSize = 2500;

interface AuthenticatorEntityDiffResult {
    entities: AuthenticatorEntity[];
    timeOffset: number | undefined;
}

const authenticatorEntityDiff = async (
    authenticatorKey: string,
): Promise<AuthenticatorEntityDiffResult> => {
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

    let timeOffset: number | undefined = undefined;

    while (true) {
        const res = await fetch(
            await apiURL("/authenticator/entity/diff", {
                sinceTime,
                limit: authenticatorEntityDiffBatchSize,
            }),
            { headers: await authenticatedRequestHeaders() },
        );
        ensureOk(res);

        const { diff, timestamp } = AuthenticatorEntityDiffResponse.parse(
            await res.json(),
        );

        if (timestamp) {
            // The remote timestamp is in epoch microseconds, while Date.now
            // and timeOffset are in epoch milliseconds.
            timeOffset = Math.floor(timestamp / 1e3) - Date.now();
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

const AuthenticatorEntityKey = z.object({
    encryptedKey: z.string(),
    header: z.string(),
});

type AuthenticatorEntityKey = z.infer<typeof AuthenticatorEntityKey>;

const getAuthenticatorEntityKey = async (): Promise<
    AuthenticatorEntityKey | undefined
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
    remote: AuthenticatorEntityKey,
    masterKey: string,
) =>
    decryptBox(
        {
            encryptedData: remote.encryptedKey,
            // Remote calls this field the header, but it really is the nonce.
            nonce: remote.header,
        },
        masterKey,
    );
