import { haveWindow } from "ente-base/env";
import log from "ente-base/log";
import {
    CollectionPrivateMagicMetadataData,
    CollectionPublicMagicMetadataData,
    CollectionShareeMagicMetadataData,
    RemoteCollectionUser,
    RemotePublicURL,
} from "ente-media/collection";
import {
    RemoteFileInfo,
    RemoteFileObjectAttributes,
    transformDecryptedMetadataJSON,
    type EnteFile,
} from "ente-media/file";
import {
    FileMetadata,
    FilePrivateMagicMetadataData,
    FilePublicMagicMetadataData,
} from "ente-media/file-metadata";
import type { MagicMetadata } from "ente-media/magic-metadata";
import { nullishToEmpty, nullToUndefined } from "ente-utils/transform";
import localForage from "localforage";
import { z } from "zod";

// This localForage table remains core metadata storage, not a legacy store.
// Photos and public albums get separate origin-scoped instances.
if (haveWindow()) {
    localForage.config({
        name: "ente-files",
        version: 1.0,
        storeName: "files",
    });
}

export { localForage };

export const canAccessIndexedDB = async () => {
    try {
        await localForage.ready();
        return true;
    } catch (e) {
        log.error("IndexDB is not accessible", e);
        return false;
    }
};

export const clearFilesDB = () => localForage.clear();

const createMagicMetadataSchema = <T extends z.ZodType>(dataSchema: T) =>
    z
        .object({ version: z.number(), count: z.number(), data: dataSchema })
        .nullish()
        .transform(nullToUndefined);

const LocalCollection = z
    .looseObject({
        id: z.number(),
        owner: RemoteCollectionUser,
        key: z.string(),
        name: z.string(),
        type: z.string(),
        sharees: z
            .array(RemoteCollectionUser)
            .nullish()
            .transform(nullishToEmpty),
        publicURLs: z
            .array(RemotePublicURL)
            .nullish()
            .transform(nullishToEmpty),
        updationTime: z.number(),
        sharedAt: z.number().nullish().transform(nullToUndefined),
        magicMetadata: createMagicMetadataSchema(
            CollectionPrivateMagicMetadataData,
        ),
        pubMagicMetadata: createMagicMetadataSchema(
            CollectionPublicMagicMetadataData,
        ),
        sharedMagicMetadata: createMagicMetadataSchema(
            CollectionShareeMagicMetadataData,
        ),
    })
    .transform((c) => {
        // Old data stored locally contained fields which are no longer needed.
        // Do some zod gymnastics to drop these when reading (so that they're
        // not written back the next time). This code was added June 2025,
        // 1.7.14-beta, and can be removed after a bit (tag: Migration).
        const {
            encryptedKey,
            keyDecryptionNonce,
            encryptedName,
            nameDecryptionNonce,
            attributes,
            isDeleted,
            ...rest
        } = c;
        return rest;
    });

export const LocalCollections = z.array(LocalCollection);

export const LocalEnteFile = z.looseObject({
    id: z.number(),
    collectionID: z.number(),
    ownerID: z.number(),
    key: z.string(),
    file: RemoteFileObjectAttributes,
    thumbnail: RemoteFileObjectAttributes,
    info: RemoteFileInfo.nullish().transform(nullToUndefined),
    updationTime: z.number(),
    collectionAddedAt: z.number().nullish().transform(nullToUndefined),
    metadata: FileMetadata,
    magicMetadata: createMagicMetadataSchema(FilePrivateMagicMetadataData),
    pubMagicMetadata: createMagicMetadataSchema(FilePublicMagicMetadataData),
});

export const LocalEnteFiles = z.array(LocalEnteFile);

// Two transforms when reading files from the DB, both added June 2025,
// 1.7.14-beta, prune eventually (tag: Migration):
//
// 1. Patch metadata of legacy entries. Freshly fetched files get this
//    transform in decryptRemoteFile; this handles items that were already
//    present locally.
// 2. Drop fields we no longer forward when parsing the remote object. The
//    collections DB does this via its Zod read transform; files are not
//    routed through Zod when reading, so it happens here instead.
export const transformFilesIfNeeded = (files: EnteFile[]) =>
    isFilesTransformNeeded(files) ? files.map(transformFile) : files;

// Avoid running the per-file migration across 200k clean records.
const isFilesTransformNeeded = (
    files: (EnteFile & { isDeleted?: unknown })[],
) =>
    !!files.find(
        (file) =>
            "isDeleted" in file ||
            !file.metadata.modificationTime ||
            typeof file.metadata.fileType != "number",
    );

const transformFile = (file: EnteFile & { isDeleted?: unknown }) => {
    const {
        isDeleted,
        metadata: origMetadata,
        magicMetadata,
        pubMagicMetadata,
        ...rest
    } = file;
    const metadata = transformDecryptedMetadataJSON(
        file.id,
        origMetadata,
    ) as FileMetadata;
    if (magicMetadata) {
        delete (magicMetadata as MagicMetadata & { header?: unknown }).header;
    }
    if (pubMagicMetadata) {
        delete (pubMagicMetadata as MagicMetadata & { header?: unknown })
            .header;
    }
    return {
        ...rest,
        metadata,
        magicMetadata,
        pubMagicMetadata,
    } satisfies EnteFile;
};

export const LocalTimestamp = z.number().nullish().transform(nullToUndefined);
