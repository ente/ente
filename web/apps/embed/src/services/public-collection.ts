/**
 * @file Public collection service for embed app
 *
 * This is a copy of the public-collection service that uses the embed app's
 * in-memory storage instead of the original public-albums-fdb storage.
 */

import { deriveKey } from "ente-base/crypto";
import {
    authenticatedPublicAlbumsDeviceLimitRequestHeaders,
    authenticatedPublicAlbumsInfoRequestHeaders,
    authenticatedPublicAlbumsRequestHeaders,
    ensureOk,
    linkDeviceTokenFromResponse,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import { apiURL } from "ente-base/origins";
import {
    decryptRemoteCollection,
    RemoteCollection,
    type Collection,
    type PublicURL,
} from "ente-media/collection";
import {
    decryptRemoteFile,
    FileDiffResponse,
    type EnteFile,
} from "ente-media/file";
import { z } from "zod";
import {
    removePublicCollectionAccessTokenJWT,
    removePublicCollectionFiles,
    removePublicCollectionLastSyncTime,
    savedPublicCollectionFiles,
    savedPublicCollectionLastSyncTime,
    savePublicCollection,
    savePublicCollectionFiles,
    savePublicCollectionLastSyncTime,
} from "./public-albums-storage";

/**
 * Verify with remote that the password entered by the user is the same as the
 * password that was set by the person who shared the public album.
 *
 * The verification is done on a password hash that we check with remote. If
 * they match, remote will provide us with another token that can be used to
 * make API calls for this password protected public album.
 *
 * If they don't match, or if {@link accessToken} itself has expired, then
 * remote will return a HTTP 401.
 *
 * @param publicURL Data about the public album.
 *
 * @param password The password entered by the user.
 *
 * @param token The access token to make API requests for a particular public
 * album.
 *
 * @returns A accessTokenJWT.
 *
 * See [Note: Password token for public albums requests]
 */
export const verifyPublicAlbumPassword = async (
    publicURL: PublicURL,
    password: string,
    accessToken: string,
) => {
    const passwordHash = await deriveKey(
        password,
        // TODO: Fix the types to not require the bang.
        publicURL.nonce!,
        publicURL.opsLimit!,
        publicURL.memLimit!,
    );

    const res = await fetch(
        await apiURL("/public-collection/verify-password"),
        {
            method: "POST",
            headers: authenticatedPublicAlbumsRequestHeaders({ accessToken }),
            body: JSON.stringify({ passHash: passwordHash }),
        },
    );
    ensureOk(res);
    return z.object({ jwtToken: z.string() }).parse(await res.json()).jwtToken;
};

/**
 * Fetch a public collection from remote using its access key, decrypt it using
 * the provided key, save the collection in our local storage for subsequent
 * use, and return it.
 *
 * This function modifies local state.
 *
 * @param accessToken A public collection access key obtained from the public
 * URL path token, or from the legacy "t" query parameter.
 *
 * The access key serves to both identify the public collection, and also
 * authenticate the request. See: [Note: Public album access token].
 *
 * @param collectionKey The base64 encoded key that can be used to decrypt the
 * collection obtained from remote.
 *
 * The collection key is obtained from the fragment portion of the public URL
 * (the fragment is a client side only portion that can be used to have local
 * secrets that are not sent by the browser to the server).
 */
export const pullCollection = async (
    credentials: PublicAlbumsCredentials,
    collectionKey: string,
) => {
    const res = await fetch(await apiURL("/public-collection/info"), {
        method: "GET",
        headers: authenticatedPublicAlbumsInfoRequestHeaders(credentials),
    });
    ensureOk(res);

    const data = (await res.json()) as {
        collection: unknown;
        referralCode?: string;
    };
    const remoteCollection = RemoteCollection.parse(data.collection);
    const referralCode = data.referralCode ?? "";

    const collection = await decryptRemoteCollection(
        remoteCollection,
        collectionKey,
    );

    savePublicCollection(collection);

    return {
        collection,
        referralCode,
        linkDeviceToken: linkDeviceTokenFromResponse(res),
    } as const;
};

/**
 * Fetch files that are part of a public collection. Save them to our local
 * storage, invoking {@link onUpdate} with the files when they become available.
 *
 * This function is a stateful loop that incrementally fetches all files that
 * are part of the public collection.
 *
 * @param credentials Credentials that can be used to make API requests for the
 * public collection.
 *
 * @param collection The collection whose files we want to fetch.
 *
 * @param onUpdate A callback that will be invoked with the files when they
 * become available.
 */
export const pullPublicCollectionFiles = async (
    credentials: PublicAlbumsCredentials,
    collection: Collection,
    onUpdate: (files: EnteFile[]) => void,
) => {
    let time = savedPublicCollectionLastSyncTime(credentials.accessToken);
    let hasMore = true;

    while (hasMore) {
        const res = await fetch(
            await apiURL("/public-collection/diff", { sinceTime: time ?? 0 }),
            {
                headers:
                    authenticatedPublicAlbumsDeviceLimitRequestHeaders(
                        credentials,
                    ),
            },
        );
        ensureOk(res);

        const { diff, hasMore: hasMoreRemote } = FileDiffResponse.parse(
            await res.json(),
        );

        const files = await Promise.all(
            diff
                .filter((f) => !f.isDeleted)
                .map((f) => decryptRemoteFile(f, collection.key)),
        );

        const existingFiles = savedPublicCollectionFiles(
            credentials.accessToken,
        );

        // The files are returned in insertion order, not in the ascending
        // order of their creation time.
        const newFiles = [...existingFiles, ...files];

        savePublicCollectionFiles(credentials.accessToken, newFiles);

        if (diff.length > 0) {
            time = Math.max(...diff.map((f) => f.updationTime));
            savePublicCollectionLastSyncTime(credentials.accessToken, time);
        }

        hasMore = hasMoreRemote;
        onUpdate(newFiles);
    }
};

/**
 * Remove all data associated with the public collection (identified by the
 * given {@link accessToken}) from our local storage.
 */
export const removePublicCollectionFileData = (accessToken: string) => {
    removePublicCollectionFiles(accessToken);
    removePublicCollectionLastSyncTime(accessToken);
    removePublicCollectionAccessTokenJWT(accessToken);
};
