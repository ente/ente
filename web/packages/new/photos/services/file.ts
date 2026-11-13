import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import type { EnteFile } from "ente-media/file";
import type {
    FilePrivateMagicMetadataData,
    FilePublicMagicMetadataData,
    ItemVisibility,
} from "ente-media/file-metadata";
import {
    createMagicMetadata,
    encryptMagicMetadata,
    type RemoteMagicMetadata,
} from "ente-media/magic-metadata";
import { batch } from "ente-utils/array";
import { savedHiddenCollections } from "./collection";
import { savedCollectionFiles } from "./photos-fdb";

// Museum rejects oversized mutation payloads.
const requestBatchSize = 1000;

export const batched = async <T, U>(
    items: T[],
    op: (batchItems: T[]) => Promise<U>,
): Promise<U[]> => {
    // Preserve request order and avoid multiplying server load.
    const result: U[] = [];
    for (const b of batch(items, requestBatchSize)) result.push(await op(b));
    return result;
};

export const computeAllCollectionFilesFromSaved = async () =>
    savedCollectionFiles();

export const computeNormalCollectionFilesFromSaved = async (
    currentUserID?: number,
) => {
    const hiddenCollections = await savedHiddenCollections(currentUserID);
    const hiddenCollectionIDs = new Set(hiddenCollections.map((c) => c.id));

    const collectionFiles = await savedCollectionFiles();
    const hiddenFileIDs = new Set(
        collectionFiles
            .filter((f) => hiddenCollectionIDs.has(f.collectionID))
            .map((f) => f.id),
    );

    return collectionFiles.filter((f) => !hiddenFileIDs.has(f.id));
};

// Mutations below are remote-only; callers must pull or overlay local state.
export const updateFilesVisibility = async (
    files: EnteFile[],
    visibility: ItemVisibility,
) => batched(files, (b) => updateFilesPrivateMagicMetadata(b, { visibility }));

// Versioned merges require metadata fresh from remote.
const updateFilesPrivateMagicMetadata = async (
    files: EnteFile[],
    updates: FilePrivateMagicMetadataData,
) =>
    putFilesMagicMetadata({
        metadataList: await Promise.all(
            files.map(async ({ id, key, magicMetadata }) => ({
                id,
                magicMetadata: await encryptMagicMetadata(
                    createMagicMetadata(
                        { ...magicMetadata?.data, ...updates },
                        magicMetadata?.version,
                    ),
                    key,
                ),
            })),
        ),
    });

export interface UpdateMagicMetadataRequest {
    id: number;
    // Version must match remote; count must not decrease.
    magicMetadata: RemoteMagicMetadata;
}

export interface UpdateMultipleMagicMetadataRequest {
    metadataList: UpdateMagicMetadataRequest[];
}

const putFilesMagicMetadata = async (
    updateRequest: UpdateMultipleMagicMetadataRequest,
) =>
    ensureOk(
        await fetch(await apiURL("/files/magic-metadata"), {
            method: "PUT",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify(updateRequest),
        }),
    );

export const updateFileFileName = (file: EnteFile, newFileName: string) =>
    updateFilePublicMagicMetadata(file, { editedName: newFileName });

// Magic metadata fields cannot be removed; blank resets the caption.
export const updateFileCaption = (file: EnteFile, caption: string) =>
    updateFilePublicMagicMetadata(file, { caption });

export const updateFilePublicMagicMetadata = async (
    file: EnteFile,
    updates: FilePublicMagicMetadataData,
) => updateFilesPublicMagicMetadata([file], updates);

const updateFilesPublicMagicMetadata = async (
    files: EnteFile[],
    updates: FilePublicMagicMetadataData,
) =>
    putFilesPublicMagicMetadata({
        metadataList: await Promise.all(
            files.map(async ({ id, key, pubMagicMetadata }) => ({
                id,
                magicMetadata: await encryptMagicMetadata(
                    createMagicMetadata(
                        { ...pubMagicMetadata?.data, ...updates },
                        pubMagicMetadata?.version,
                    ),
                    key,
                ),
            })),
        ),
    });

const putFilesPublicMagicMetadata = async (
    updateRequest: UpdateMultipleMagicMetadataRequest,
) =>
    ensureOk(
        await fetch(await apiURL("/files/public-magic-metadata"), {
            method: "PUT",
            headers: await authenticatedRequestHeaders(),
            body: JSON.stringify(updateRequest),
        }),
    );

export const updateFilesLocation = async (
    files: EnteFile[],
    lat: number,
    long: number,
): Promise<void> => {
    await batched(files, (b) =>
        updateFilesPublicMagicMetadata(b, { lat, long }),
    );
};
