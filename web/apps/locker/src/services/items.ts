import type { LockerItemType } from "@/types";
import { ensureLocalUser } from "ente-accounts/services/user";
import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import {
    decryptBox,
    decryptMetadataJSON,
    encryptBlob,
    encryptBox,
    generateKey,
} from "ente-locker-wasm";
import {
    addFileToCollections,
    createCollectionMutationDeps,
    updateItemCollectionsWithDeps,
} from "./collection-membership";
import {
    ensureFavoritesCollection,
    resolveCollectionIDsWithUncategorizedFallback,
} from "./collections";
import {
    findCollectionByType,
    getCollectionIDsForFile,
    getCollectionRecord,
    getEncryptedFileRecord,
    updateCachedPubMagicMetadata,
} from "./locker-cache";
import { RemoteIDResponseSchema } from "./remote-types";
import { decryptCollectionKey } from "./sync/decrypt";

const infoItemTitle = (
    infoType: LockerItemType,
    infoData: Record<string, unknown>,
) => {
    const namedTitle =
        (infoData.title as string | undefined)?.trim() ||
        (infoData.name as string | undefined)?.trim();
    if (namedTitle) {
        return namedTitle;
    }

    switch (infoType) {
        case "note":
            return "Note";
        case "physicalRecord":
            return "Location";
        case "accountCredential":
            return "Secret";
        case "emergencyContact":
            return "Emergency Contact";
        case "file":
            return "File";
    }
};

export const createInfoItem = async (
    collectionIDs: number[],
    infoType: LockerItemType,
    infoData: Record<string, unknown>,
    masterKey: string,
): Promise<void> => {
    const [collectionID, ...additionalCollectionIDs] =
        await resolveCollectionIDsWithUncategorizedFallback(
            collectionIDs,
            masterKey,
        );
    if (collectionID === undefined) {
        throw new Error("No collection selected");
    }
    const collectionRecord = getCollectionRecord(collectionID);
    if (!collectionRecord)
        throw new Error(`Collection ${collectionID} not in cache`);

    const collectionKey = await decryptCollectionKey(collectionRecord);

    const fileKey = await generateKey();

    const encryptedFileKey = await encryptBox(fileKey, collectionKey);

    // Locker timestamps are epoch milliseconds, unlike photos which uses
    // microseconds.
    const now = Date.now();
    const title = infoItemTitle(infoType, infoData);
    const metadata = {
        title,
        creationTime: now,
        modificationTime: now,
        fileType: 4, // FileType.info in the mobile client's enum
    };
    const metadataJSON = JSON.stringify(metadata);
    const encryptedMetadata = await encryptBlob(
        new TextEncoder().encode(metadataJSON),
        fileKey,
    );

    const pubMagicMetadata = {
        info: { type: infoType, data: infoData },
        noThumb: true,
    };
    const pubMMJSON = JSON.stringify(pubMagicMetadata);
    const encryptedPubMM = await encryptBlob(
        new TextEncoder().encode(pubMMJSON),
        fileKey,
    );

    const res = await fetch(await apiURL("/files/meta"), {
        method: "POST",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            collectionID,
            encryptedKey: encryptedFileKey.encryptedData,
            keyDecryptionNonce: encryptedFileKey.nonce,
            metadata: {
                encryptedData: encryptedMetadata.encryptedData,
                decryptionHeader: encryptedMetadata.decryptionHeader,
            },
            pubMagicMetadata: {
                version: 1,
                count: Object.keys(pubMagicMetadata).length,
                data: encryptedPubMM.encryptedData,
                header: encryptedPubMM.decryptionHeader,
            },
        }),
    });
    ensureOk(res);

    const created = RemoteIDResponseSchema.parse(await res.json());
    if (additionalCollectionIDs.length > 0) {
        await addFileToCollections(
            created.id,
            fileKey,
            additionalCollectionIDs,
        );
    }
};

export const updateInfoItem = async (
    fileID: number,
    infoType: LockerItemType,
    infoData: Record<string, unknown>,
): Promise<void> =>
    updateItemMetadata(fileID, {
        info: { type: infoType, data: infoData },
        editedName: infoItemTitle(infoType, infoData),
    });

export const updateFileItem = async (
    fileID: number,
    title: string,
): Promise<void> => updateItemMetadata(fileID, { editedName: title.trim() });

const updateItemMetadata = async (
    fileID: number,
    updates: Record<string, unknown>,
): Promise<void> => {
    const fileRecord = getEncryptedFileRecord(fileID);
    if (!fileRecord) throw new Error(`File ${fileID} not in cache`);

    const collectionRecord = getCollectionRecord(fileRecord.collectionID);
    if (!collectionRecord)
        throw new Error(`Collection ${fileRecord.collectionID} not in cache`);

    const collectionKey = await decryptCollectionKey(collectionRecord);
    const fileKey = await decryptBox(
        {
            encryptedData: fileRecord.encryptedKey,
            nonce: fileRecord.keyDecryptionNonce,
        },
        collectionKey,
    );

    const existingPubMagicMetadata = fileRecord.pubMagicMetadata
        ? ((await decryptMetadataJSON(
              {
                  encryptedData: fileRecord.pubMagicMetadata.data,
                  decryptionHeader: fileRecord.pubMagicMetadata.header,
              },
              fileKey,
          )) as Record<string, unknown>)
        : {};

    const pubMagicMetadata = {
        ...existingPubMagicMetadata,
        ...updates,
        noThumb: true,
        editedTime: Date.now(),
    };
    const pubMMJSON = JSON.stringify(pubMagicMetadata);
    const encryptedPubMM = await encryptBlob(
        new TextEncoder().encode(pubMMJSON),
        fileKey,
    );
    const version = fileRecord.pubMagicMetadata?.version ?? 1;

    const res = await fetch(await apiURL("/files/public-magic-metadata"), {
        method: "PUT",
        headers: {
            ...(await authenticatedRequestHeaders()),
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            metadataList: [
                {
                    id: fileID,
                    magicMetadata: {
                        version,
                        count: Object.keys(pubMagicMetadata).length,
                        data: encryptedPubMM.encryptedData,
                        header: encryptedPubMM.decryptionHeader,
                    },
                },
            ],
        }),
    });
    ensureOk(res);

    updateCachedPubMagicMetadata(fileID, {
        version: version + 1,
        data: encryptedPubMM.encryptedData,
        header: encryptedPubMM.decryptionHeader,
    });
};

export const setItemImportant = async (
    fileID: number,
    shouldBeImportant: boolean,
    masterKey: string,
): Promise<boolean> => {
    const currentUserID = ensureLocalUser().id;
    const currentCollectionIDs = getCollectionIDsForFile(fileID);
    if (currentCollectionIDs.length === 0) {
        throw new Error(`File ${fileID} not found in cache`);
    }

    const favoritesCollection = findCollectionByType(
        "favorites",
        currentUserID,
    );
    if (!shouldBeImportant && !favoritesCollection) {
        return false;
    }

    const favoritesCollectionID =
        favoritesCollection?.id ??
        (await ensureFavoritesCollection(masterKey)).id;
    const nextCollectionIDs = shouldBeImportant
        ? Array.from(new Set([...currentCollectionIDs, favoritesCollectionID]))
        : currentCollectionIDs.filter(
              (collectionID) => collectionID !== favoritesCollectionID,
          );

    const hasChanged =
        nextCollectionIDs.length !== currentCollectionIDs.length ||
        nextCollectionIDs.some(
            (collectionID) => !currentCollectionIDs.includes(collectionID),
        );
    if (!hasChanged) {
        return false;
    }

    await updateItemCollectionsWithDeps(fileID, nextCollectionIDs, {
        currentUserID,
        masterKey,
        deps: createCollectionMutationDeps(),
    });
    return true;
};
