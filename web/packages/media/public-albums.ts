import { deriveKey } from "ente-base/crypto";
import { fetchPublicCollectionFile } from "ente-base/file-download";
import {
    authenticatedPublicAlbumsDeviceLimitRequestHeaders,
    authenticatedPublicAlbumsInfoRequestHeaders,
    authenticatedPublicAlbumsRequestHeaders,
    ensureOk,
    linkDeviceTokenFromResponse,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import { apiURL, customAPIOrigin } from "ente-base/origins";
import { z } from "zod";
import { RemoteCollection, type PublicURL } from "./collection";
import { FileDiffResponse } from "./file";

const PublicCollectionInfo = z.object({
    collection: RemoteCollection,
    referralCode: z.string(),
});

export const getPublicCollectionInfo = async (
    credentials: PublicAlbumsCredentials,
    signal?: AbortSignal,
) => {
    const res = await fetch(await apiURL("/public-collection/info"), {
        headers: authenticatedPublicAlbumsInfoRequestHeaders(credentials),
        signal,
    });
    ensureOk(res);
    const info = PublicCollectionInfo.parse(await res.json());
    return { ...info, linkDeviceToken: linkDeviceTokenFromResponse(res) };
};

export const verifyPublicCollectionPassword = async (
    credentials: PublicAlbumsCredentials,
    publicURL: PublicURL,
    password: string,
    signal?: AbortSignal,
) => {
    const passHash = await deriveKey(
        password,
        publicURL.nonce!,
        publicURL.opsLimit!,
        publicURL.memLimit!,
    );
    const res = await fetch(
        await apiURL("/public-collection/verify-password"),
        {
            method: "POST",
            headers: {
                ...authenticatedPublicAlbumsRequestHeaders(credentials),
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ passHash }),
            signal,
        },
    );
    ensureOk(res);
    return z.object({ jwtToken: z.string() }).parse(await res.json()).jwtToken;
};

export const getPublicCollectionDiff = async (
    credentials: PublicAlbumsCredentials,
    sinceTime: number,
    signal?: AbortSignal,
) => {
    const res = await fetch(
        await apiURL("/public-collection/diff", { sinceTime }),
        {
            headers:
                authenticatedPublicAlbumsDeviceLimitRequestHeaders(credentials),
            signal,
        },
    );
    ensureOk(res);
    return FileDiffResponse.parse(await res.json());
};

export const downloadPublicCollectionFile = async (
    credentials: PublicAlbumsCredentials,
    fileID: number,
    thumbnail: boolean,
    signal?: AbortSignal,
    downloadOrigin?: string,
) => {
    const customOrigin = await customAPIOrigin();
    const origin =
        downloadOrigin ?? customOrigin ?? "https://public-albums.ente.com";
    const path = thumbnail ? "preview" : "download";
    const res =
        customOrigin && origin === customOrigin
            ? await fetchPublicCollectionFile(
                  fileID,
                  thumbnail ? "thumbnail" : "file",
                  credentials,
                  signal,
              )
            : await fetch(`${origin}/${path}/?fileID=${fileID}`, {
                  headers: authenticatedPublicAlbumsRequestHeaders(credentials),
                  signal,
              });
    ensureOk(res);
    return new Uint8Array(await res.arrayBuffer());
};
