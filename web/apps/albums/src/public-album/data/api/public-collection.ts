import type { PublicAlbumsCredentials } from "ente-base/http";
import {
    decryptRemoteCollection,
    type Collection,
} from "ente-media/collection";
import { decryptRemoteFile, type EnteFile } from "ente-media/file";
import {
    getPublicCollectionDiff,
    getPublicCollectionInfo,
} from "ente-media/public-albums";
import {
    removePublicCollectionAccessTokenJWT,
    removePublicCollectionFiles,
    removePublicCollectionLastSyncTime,
    savedPublicCollectionFiles,
    savedPublicCollectionLastSyncTime,
    saveLastPublicCollectionReferralCode,
    savePublicCollection,
    savePublicCollectionFiles,
    savePublicCollectionLastSyncTime,
} from "../storage/public-albums-fdb";

export const pullCollection = async (
    credentials: PublicAlbumsCredentials,
    collectionKey: string,
): Promise<{
    collection: Collection;
    referralCode: string;
    linkDeviceToken?: string;
}> => {
    // The collection key comes from the URL fragment. Never send it to remote.
    const {
        collection: remoteCollection,
        referralCode,
        linkDeviceToken,
    } = await getPublicCollectionInfo(credentials);

    const collection = await decryptRemoteCollection(
        remoteCollection,
        collectionKey,
    );

    await savePublicCollection(collection);
    await saveLastPublicCollectionReferralCode(referralCode);

    return { collection, referralCode, linkDeviceToken };
};

export const pullPublicCollectionFiles = async (
    credentials: PublicAlbumsCredentials,
    collection: Collection,
    // Files passed here have no defined order.
    onSetFiles: (files: EnteFile[]) => void,
) => {
    const { accessToken } = credentials;

    let sinceTime = (await savedPublicCollectionLastSyncTime(accessToken)) ?? 0;

    // Remote advances collection.updationTime whenever a file changes.
    if (sinceTime == collection.updationTime) return;

    const files = await savedPublicCollectionFiles(accessToken);
    const filesByID = new Map(files.map((f) => [f.id, f]));
    let callbackInvoked = false;

    while (true) {
        const { diff, hasMore } = await getPublicCollectionDiff(
            credentials,
            sinceTime,
        );
        if (!diff.length) {
            // An empty first page must still publish the cached files.
            if (!callbackInvoked) {
                onSetFiles(files);
            }
            break;
        }
        for (const change of diff) {
            sinceTime = Math.max(sinceTime, change.updationTime);
            if (change.isDeleted) {
                filesByID.delete(change.id);
            } else {
                filesByID.set(
                    change.id,
                    await decryptRemoteFile(change, collection.key),
                );
            }
        }

        const updatedFiles = [...filesByID.values()];
        await savePublicCollectionFiles(accessToken, updatedFiles);
        await savePublicCollectionLastSyncTime(accessToken, sinceTime);
        onSetFiles(updatedFiles);
        callbackInvoked = true;

        if (!hasMore) break;
    }
};

export const removePublicCollectionFileData = async (accessToken: string) => {
    await Promise.all([
        removePublicCollectionAccessTokenJWT(accessToken),
        removePublicCollectionLastSyncTime(accessToken),
        removePublicCollectionFiles(accessToken),
    ]);
};
