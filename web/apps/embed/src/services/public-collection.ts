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

export const removePublicCollectionFileData = (accessToken: string) => {
    removePublicCollectionFiles(accessToken);
    removePublicCollectionLastSyncTime(accessToken);
    removePublicCollectionAccessTokenJWT(accessToken);
};
