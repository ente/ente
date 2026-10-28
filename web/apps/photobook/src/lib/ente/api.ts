import { deriveArgonKey } from "./crypto";
import type {
    EnteCredentials,
    EntePasswordParams,
    EntePublicCollectionInfo,
    EnteRemoteFile,
} from "./types";

const CLIENT_PACKAGE = "io.ente.photobook.web";

function authHeaders(creds: {
    accessToken: string;
    accessTokenJWT?: string;
}): Record<string, string> {
    const h: Record<string, string> = {
        "X-Client-Package": CLIENT_PACKAGE,
        "X-Auth-Access-Token": creds.accessToken,
    };
    if (creds.accessTokenJWT)
        h["X-Auth-Access-Token-JWT"] = creds.accessTokenJWT;
    return h;
}

export class EnteApiError extends Error {
    constructor(
        message: string,
        public status: number,
    ) {
        super(message);
        this.name = "EnteApiError";
    }
    get isPasswordRequired(): boolean {
        return this.status === 401;
    }
}

async function ensureOk(res: Response): Promise<Response> {
    if (res.ok) return res;
    const body = await res.text().catch(() => "");
    throw new EnteApiError(
        `Ente API returned ${res.status}${body ? `: ${body.slice(0, 200)}` : ""}`,
        res.status,
    );
}

interface RawPublicCollectionInfo {
    collection: {
        id: number;
        encryptedName?: string | null;
        nameDecryptionNonce?: string | null;
        name?: string | null;
        publicURLs?:
            | {
                  url: string;
                  passwordEnabled?: boolean;
                  nonce?: string | null;
                  opsLimit?: number | null;
                  memLimit?: number | null;
                  enableDownload?: boolean | null;
                  validTill?: number | null;
                  deviceLimit?: number | null;
              }[]
            | null;
        updationTime: number;
    };
    referralCode?: string;
}

export async function fetchCollectionInfo(
    apiOrigin: string,
    accessToken: string,
    accessTokenJWT?: string,
    signal?: AbortSignal,
): Promise<EntePublicCollectionInfo> {
    const res = await fetch(`${apiOrigin}/public-collection/info`, {
        headers: authHeaders({ accessToken, accessTokenJWT }),
        signal,
    });
    await ensureOk(res);
    const raw = (await res.json()) as RawPublicCollectionInfo;
    const pu = raw.collection.publicURLs?.[0];
    if (!pu) {
        throw new EnteApiError("Public album share has no active URL.", 500);
    }
    const passwordEnabled = pu.passwordEnabled ?? false;
    let password: EntePasswordParams | undefined;
    if (passwordEnabled && pu.nonce && pu.opsLimit && pu.memLimit) {
        password = {
            nonce: pu.nonce,
            opsLimit: pu.opsLimit,
            memLimit: pu.memLimit,
        };
    }
    return {
        referralCode: raw.referralCode,
        publicURL: {
            passwordEnabled,
            password,
            enableDownload: pu.enableDownload ?? true,
            validTill: pu.validTill ?? 0,
            deviceLimit: pu.deviceLimit ?? 0,
        },
        encryptedName: raw.collection.encryptedName ?? undefined,
        nameDecryptionNonce: raw.collection.nameDecryptionNonce ?? undefined,
        plainName: raw.collection.name ?? undefined,
        updationTime: raw.collection.updationTime,
    };
}

export async function verifyAlbumPassword(
    apiOrigin: string,
    accessToken: string,
    password: string,
    params: EntePasswordParams,
    signal?: AbortSignal,
): Promise<string> {
    const passHash = await deriveArgonKey(
        password,
        params.nonce,
        params.opsLimit,
        params.memLimit,
    );
    const res = await fetch(`${apiOrigin}/public-collection/verify-password`, {
        method: "POST",
        headers: {
            ...authHeaders({ accessToken }),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({ passHash }),
        signal,
    });
    await ensureOk(res);
    const json = (await res.json()) as { jwtToken?: string };
    if (!json.jwtToken) {
        throw new EnteApiError("Password verified but no JWT returned.", 500);
    }
    return json.jwtToken;
}

export async function fetchAllFiles(
    creds: EnteCredentials,
    onPage?: (running: EnteRemoteFile[]) => void,
    signal?: AbortSignal,
): Promise<EnteRemoteFile[]> {
    const filesById = new Map<number, EnteRemoteFile>();
    let sinceTime = 0;
    while (true) {
        const url = new URL(`${creds.apiOrigin}/public-collection/diff`);
        url.searchParams.set("sinceTime", String(sinceTime));
        const res = await fetch(url.toString(), {
            headers: authHeaders(creds),
            signal,
        });
        await ensureOk(res);
        const json = (await res.json()) as {
            diff?: EnteRemoteFile[];
            hasMore: boolean;
        };
        if (!json.diff?.length) break;
        for (const f of json.diff) {
            if (f.isDeleted) {
                filesById.delete(f.id);
            } else {
                filesById.set(f.id, f);
            }
            if (f.updationTime > sinceTime) sinceTime = f.updationTime;
        }
        onPage?.([...filesById.values()]);
        if (!json.hasMore) break;
    }
    return [...filesById.values()];
}

export async function downloadEncryptedThumbnail(
    creds: EnteCredentials,
    fileId: number,
    signal?: AbortSignal,
): Promise<Uint8Array> {
    const res = await fetch(`${creds.albumsOrigin}/preview/?fileID=${fileId}`, {
        headers: authHeaders(creds),
        signal,
    });
    await ensureOk(res);
    return new Uint8Array(await res.arrayBuffer());
}

export async function downloadEncryptedFile(
    creds: EnteCredentials,
    fileId: number,
    signal?: AbortSignal,
): Promise<Uint8Array> {
    const res = await fetch(
        `${creds.albumsOrigin}/download/?fileID=${fileId}`,
        { headers: authHeaders(creds), signal },
    );
    await ensureOk(res);
    return new Uint8Array(await res.arrayBuffer());
}
