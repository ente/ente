import { z } from "zod";
import {
    authenticatedPublicAlbumsRequestHeaders,
    authenticatedRequestHeaders,
    ensureOk,
    publicRequestHeaders,
    type PublicAlbumsCredentials,
} from "./http";
import { apiURL, customAPIOrigin } from "./origins";
import {
    authenticatedPublicMemoryRequestHeaders,
    type PublicMemoryCredentials,
} from "./public-memory";
import { ensureAuthToken } from "./token";

const FileURLResponse = z.object({ url: z.string() });
const V3_RETRY_DELAY_MS = 60 * 60 * 1000;
let v3RetryAfter = 0;

const tryFetchFileUsingV3 = async (
    path: string,
    headers: HeadersInit,
): Promise<Response | undefined> => {
    if (v3RetryAfter > Date.now()) {
        return undefined;
    }

    const response = await fetch(await apiURL(path), { headers });
    if (response.status === 404) {
        v3RetryAfter = Date.now() + V3_RETRY_DELAY_MS;
        return undefined;
    }

    ensureOk(response);
    const { url } = FileURLResponse.parse(await response.json());
    return fetch(url);
};

type FileKind = "file" | "thumbnail";

const filePath = (kind: FileKind) =>
    kind == "file" ? "download" : "thumbnail";

const legacyFilePath = (kind: FileKind) =>
    kind == "file" ? "download" : "preview";

export const fetchFile = async (fileID: number, kind: FileKind) => {
    const response = await tryFetchFileUsingV3(
        `/files/${filePath(kind)}/v3/${fileID}`,
        await authenticatedRequestHeaders(),
    );
    if (response) {
        return response;
    }

    // migration : 3 aug 2026
    const token = await ensureAuthToken();
    return fetch(
        await apiURL(`/files/${legacyFilePath(kind)}/${fileID}`, { token }),
        { headers: publicRequestHeaders() },
    );
};

export const fetchPublicCollectionFile = async (
    fileID: number,
    kind: FileKind,
    credentials: PublicAlbumsCredentials,
) => {
    const response = await tryFetchFileUsingV3(
        `/public-collection/files/${filePath(kind)}/v3/${fileID}`,
        authenticatedPublicAlbumsRequestHeaders(credentials),
    );
    if (response) {
        return response;
    }

    const path = `/public-collection/files/${legacyFilePath(kind)}/${fileID}`;
    if (await customAPIOrigin()) {
        const { accessToken, accessTokenJWT } = credentials;
        return fetch(
            await apiURL(path, {
                accessToken,
                ...(accessTokenJWT && { accessTokenJWT }),
            }),
            kind == "thumbnail"
                ? { headers: publicRequestHeaders() }
                : undefined,
        );
    }
    return fetch(await apiURL(path), {
        headers: authenticatedPublicAlbumsRequestHeaders(credentials),
    });
};

export const fetchPublicMemoryFile = async (
    fileID: number,
    kind: FileKind,
    credentials: PublicMemoryCredentials,
) => {
    const response = await tryFetchFileUsingV3(
        `/public-memory/files/${filePath(kind)}/v3/${fileID}`,
        authenticatedPublicMemoryRequestHeaders(credentials),
    );
    if (response) {
        return response;
    }

    const path = `/public-memory/files/${legacyFilePath(kind)}/${fileID}`;
    if (await customAPIOrigin()) {
        return fetch(
            await apiURL(path, { accessToken: credentials.accessToken }),
            kind == "thumbnail"
                ? { headers: publicRequestHeaders() }
                : undefined,
        );
    }
    return fetch(await apiURL(path), {
        headers: authenticatedPublicMemoryRequestHeaders(credentials),
    });
};

export const fetchCastFile = async (
    fileID: number,
    kind: FileKind,
    castToken: string,
) => {
    const response = await tryFetchFileUsingV3(
        `/cast/files/${filePath(kind)}/v3/${fileID}`,
        { ...publicRequestHeaders(), "X-Cast-Access-Token": castToken },
    );
    if (response) {
        return response;
    }

    return fetch(
        await apiURL(`/cast/files/${legacyFilePath(kind)}/${fileID}`, {
            castToken,
        }),
        { headers: publicRequestHeaders() },
    );
};

export const fetchFileLinkFile = async (accessToken: string) => {
    const response = await tryFetchFileUsingV3("/file-link/file/v3", {
        "X-Auth-Access-Token": accessToken,
    });
    if (response) {
        return response;
    }

    return fetch(await apiURL("/file-link/file"), {
        headers: { "X-Auth-Access-Token": accessToken },
    });
};
