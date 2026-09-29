import { decryptBox, decryptMetadataJSON } from "ente-base/crypto";
import log from "ente-base/log";
import { nullishToBlank, nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import {
    fileFileName,
    FileMetadata,
    FilePrivateMagicMetadataData,
    FilePublicMagicMetadataData,
} from "./file-metadata";
import { FileType } from "./file-type";
import {
    decryptMagicMetadata,
    RemoteMagicMetadata,
    type MagicMetadata,
} from "./magic-metadata";

export interface EnteFile {
    id: number;
    // The same file id can appear in multiple collections, as a distinct
    // EnteFile instance per collection. The (id, collectionID) pair is the
    // primary key, not id on its own.
    collectionID: number;
    ownerID: number;
    key: string;
    file: FileObjectAttributes;
    thumbnail: FileObjectAttributes;
    info?: FileInfo;
    updationTime: number;
    metadata: FileMetadata;
    // Private to the owner; never visible to sharees.
    magicMetadata?: MagicMetadata<FilePrivateMagicMetadataData>;
    // Visible to everyone with whom the file is shared.
    pubMagicMetadata?: MagicMetadata<FilePublicMagicMetadataData>;
}

interface FileObjectAttributes {
    decryptionHeader: string;
}

export const RemoteFileObjectAttributes = z.looseObject({
    decryptionHeader: z.string(),
});

interface FileInfo {
    fileSize?: number;
    thumbSize?: number;
}

export const RemoteFileInfo = z.looseObject({
    fileSize: z.number().nullish().transform(nullToUndefined),
    thumbSize: z.number().nullish().transform(nullToUndefined),
});

const RemoteFileMetadata = z.object({
    // Remote scrubs the fields of permanently deleted files in trash diff
    // responses, so this can be missing there. Such entries are never
    // decrypted, so transform missing values to a blank string instead of
    // failing the parse.
    encryptedData: z.string().nullish().transform(nullishToBlank),
    decryptionHeader: z.string(),
});

export type RemoteFileMetadata = z.infer<typeof RemoteFileMetadata>;

export const RemoteEnteFile = z.looseObject({
    id: z.number(),
    collectionID: z.number(),
    ownerID: z.number(),
    encryptedKey: z.string(),
    keyDecryptionNonce: z.string(),
    file: RemoteFileObjectAttributes,
    thumbnail: RemoteFileObjectAttributes,
    info: RemoteFileInfo.nullish().transform(nullToUndefined),
    updationTime: z.number(),
    isDeleted: z.boolean().nullish().transform(nullToUndefined),
    metadata: RemoteFileMetadata,
    magicMetadata: RemoteMagicMetadata.nullish().transform(nullToUndefined),
    pubMagicMetadata: RemoteMagicMetadata.nullish().transform(nullToUndefined),
});

export type RemoteEnteFile = z.infer<typeof RemoteEnteFile>;

export const FileDiffResponse = z.object({
    diff: RemoteEnteFile.array(),
    hasMore: z.boolean(),
});

export const decryptRemoteFile = async (
    remoteFile: RemoteEnteFile,
    collectionKey: string,
): Promise<EnteFile> => {
    // Destructure and spread so that unknown fields from the loose remote
    // schema pass through into the persisted EnteFile.
    const {
        id,
        encryptedKey,
        keyDecryptionNonce,
        // isDeleted only matters in the diff response, and it has already been
        // acted on before we get here.
        isDeleted,
        metadata: encryptedMetadata,
        magicMetadata: encryptedMagicMetadata,
        pubMagicMetadata: encryptedPubMagicMetadata,
        ...rest
    } = remoteFile;

    const key = await decryptBox(
        { encryptedData: encryptedKey, nonce: keyDecryptionNonce },
        collectionKey,
    );

    const metadataJSON = await decryptMetadataJSON(encryptedMetadata, key);
    const metadata = FileMetadata.parse(
        transformDecryptedMetadataJSON(id, metadataJSON),
    );

    let magicMetadata: EnteFile["magicMetadata"];
    if (encryptedMagicMetadata) {
        const genericMM = await decryptMagicMetadata(
            encryptedMagicMetadata,
            key,
        );
        const data = FilePrivateMagicMetadataData.parse(genericMM.data);
        magicMetadata = { ...genericMM, data };
    }

    let pubMagicMetadata: EnteFile["pubMagicMetadata"];
    if (encryptedPubMagicMetadata) {
        const genericMM = await decryptMagicMetadata(
            encryptedPubMagicMetadata,
            key,
        );
        const data = FilePublicMagicMetadataData.parse(genericMM.data);
        pubMagicMetadata = { ...genericMM, data };
    }

    return { ...rest, id, key, metadata, magicMetadata, pubMagicMetadata };
};

export const transformDecryptedMetadataJSON = (
    fileID: number,
    metadataJSON: unknown,
) => {
    // The threshold is an arbitrary cutoff so that these patches for old files
    // do not mask new issues.
    if (fileID > 100000000) return metadataJSON;

    if (typeof metadataJSON != "object") return metadataJSON;
    if (!metadataJSON) return metadataJSON;

    // A few very old files, uploaded by initial dev builds of Ente, have no
    // modification time.
    if (
        !("modificationTime" in metadataJSON) ||
        !metadataJSON.modificationTime
    ) {
        if ("creationTime" in metadataJSON) {
            log.info(`Patching metadata modification time for file ${fileID}`);
            (metadataJSON as Record<string, unknown>).modificationTime =
                metadataJSON.creationTime;
        }
    }

    // Similarly, a few very old files uploaded by dev builds have no file
    // type.
    if (
        !("fileType" in metadataJSON) ||
        typeof metadataJSON.fileType != "number"
    ) {
        log.info(`Patching metadata file type for file ${fileID}`);
        (metadataJSON as Record<string, unknown>).fileType = FileType.image;
    }

    return metadataJSON;
};

export const fileLogID = (file: EnteFile) =>
    `file ${fileFileName(file)} (${file.id})`;
