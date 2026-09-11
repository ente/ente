import { z } from "zod";
import { RemoteCollectionUserSchema } from "../remote-types";

const RemoteMagicMetadata = z.object({
    version: z.number(),
    count: z.number().optional(),
    data: z.string(),
    header: z.string(),
});

export const RemoteCollection = z.object({
    id: z.number(),
    owner: RemoteCollectionUserSchema,
    encryptedKey: z.string(),
    keyDecryptionNonce: z.string().nullish(),
    encryptedName: z.string().nullish(),
    nameDecryptionNonce: z.string().nullish(),
    name: z.string().nullish(),
    type: z.string(),
    sharees: z.array(RemoteCollectionUserSchema).nullish(),
    publicURLs: z.array(z.unknown()).nullish(),
    updationTime: z.number(),
    isDeleted: z.boolean().nullish(),
    magicMetadata: RemoteMagicMetadata.nullish(),
    pubMagicMetadata: RemoteMagicMetadata.nullish(),
    sharedMagicMetadata: RemoteMagicMetadata.nullish(),
});

export type RemoteCollection = z.infer<typeof RemoteCollection>;

export const CollectionsResponse = z.object({
    collections: z.array(RemoteCollection),
});

const RemoteEncryptedMetadata = z.object({
    encryptedData: z.string(),
    decryptionHeader: z.string(),
});

const RemoteFileObjectAttributes = z.object({ decryptionHeader: z.string() });

export const RemoteFile = z.object({
    id: z.number(),
    collectionID: z.number(),
    ownerID: z.number().optional(),
    encryptedKey: z.string(),
    keyDecryptionNonce: z.string(),
    file: RemoteFileObjectAttributes,
    thumbnail: RemoteFileObjectAttributes.optional(),
    metadata: RemoteEncryptedMetadata,
    magicMetadata: z
        .object({
            version: z.number(),
            count: z.number().optional(),
            data: z.string(),
            header: z.string(),
        })
        .nullish(),
    pubMagicMetadata: z
        .object({
            version: z.number(),
            count: z.number().optional(),
            data: z.string(),
            header: z.string(),
        })
        .nullish(),
    updationTime: z.number(),
    isDeleted: z.boolean(),
    info: z.object({ fileSize: z.number().optional() }).nullish(),
});

export type RemoteFile = z.infer<typeof RemoteFile>;

export const FileDiffResponse = z.object({
    diff: z.array(RemoteFile),
    hasMore: z.boolean(),
});

export const RemoteTrashItem = z.object({
    file: RemoteFile,
    isDeleted: z.boolean(),
    isRestored: z.boolean(),
    updatedAt: z.number(),
    deleteBy: z.number(),
});

export const TrashDiffResponse = z.object({
    diff: z.array(RemoteTrashItem),
    hasMore: z.boolean(),
});
