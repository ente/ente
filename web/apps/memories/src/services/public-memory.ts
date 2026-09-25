import { decryptBoxBytes } from "ente-base/crypto";
import { ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { authenticatedPublicMemoryRequestHeaders } from "ente-base/public-memory";
import {
    decryptRemoteFile,
    RemoteEnteFile,
    type EnteFile,
} from "ente-media/file";
import { gunzipWithLimit } from "ente-new/photos/utils/gzip";
import { z } from "zod";

const maxMemoryShareMetadataBytes = 1024 * 1024;

export interface PublicMemoryShareInfo {
    id: number;
    type: "share" | "lane";
    memoryHash?: string;
    metadataCipher: string;
    metadataNonce: string;
    encryptedKey: string;
    keyDecryptionNonce: string;
}

const PublicMemoryShareInfoResponse = z.object({
    memoryShare: z.object({
        id: z.number(),
        type: z.enum(["share", "lane"]).optional().default("share"),
        memoryHash: z.string().optional(),
        metadataCipher: z.string().optional().default(""),
        metadataNonce: z.string().optional().default(""),
        encryptedKey: z.string(),
        keyDecryptionNonce: z.string(),
    }),
});

export const getPublicMemoryInfo = async (
    accessToken: string,
): Promise<PublicMemoryShareInfo> => {
    const res = await fetch(await apiURL("/public-memory/info"), {
        headers: authenticatedPublicMemoryRequestHeaders({ accessToken }),
    });
    ensureOk(res);
    const { memoryShare } = PublicMemoryShareInfoResponse.parse(
        await res.json(),
    );
    return memoryShare;
};

const PublicMemoryShareFile = z.object({
    file: RemoteEnteFile,
    position: z.number(),
    encryptedKey: z.string(),
    keyDecryptionNonce: z.string(),
});

const PublicMemoryShareFilesResponse = z.object({
    files: PublicMemoryShareFile.array(),
});

export interface PublicMemoryFile {
    file: EnteFile;
    position: number;
}

export interface PublicMemoryShareFrameCrop {
    x: number;
    y: number;
    width: number;
    height: number;
}

export interface PublicMemoryShareFrame {
    fileID: number;
    position?: number;
    faceID?: string;
    faceBox?: PublicMemoryShareFrameCrop;
    crop?: PublicMemoryShareFrameCrop;
    creationTime?: number;
    year?: number;
}

export interface PublicMemoryShareMetadata {
    name: string;
    kind?: "share" | "lane";
    captionType?: "age" | "yearsAgo";
    personID?: string;
    personName?: string;
    birthDate?: string;
    frames: PublicMemoryShareFrame[];
}

const PublicMemoryShareFrameCropSchema = z.object({
    x: z.number(),
    y: z.number(),
    width: z.number(),
    height: z.number(),
});

const PublicMemoryShareFrameSchema = z.object({
    fileID: z.number(),
    position: z.number().optional(),
    faceID: z.string().optional(),
    faceBox: PublicMemoryShareFrameCropSchema.optional(),
    crop: PublicMemoryShareFrameCropSchema.optional(),
    creationTime: z.number().optional(),
    year: z.number().optional(),
});

const PublicMemoryShareMetadataBaseSchema = z.looseObject({
    name: z.string().optional(),
    kind: z.enum(["share", "lane"]).optional(),
    captionType: z.enum(["age", "yearsAgo"]).optional(),
    personID: z.string().optional(),
    personName: z.string().optional(),
    birthDate: z.string().optional(),
    frames: z.array(z.unknown()).optional(),
});

export const getPublicMemoryFiles = async (
    accessToken: string,
    shareKey: string,
): Promise<PublicMemoryFile[]> => {
    const res = await fetch(await apiURL("/public-memory/files"), {
        headers: authenticatedPublicMemoryRequestHeaders({ accessToken }),
    });
    ensureOk(res);
    const { files } = PublicMemoryShareFilesResponse.parse(await res.json());

    const publicFiles: PublicMemoryFile[] = [];
    for (const { file, position, encryptedKey, keyDecryptionNonce } of files) {
        const remoteFile = { ...file, encryptedKey, keyDecryptionNonce };
        const decrypted = await decryptRemoteFile(remoteFile, shareKey);
        publicFiles.push({ file: decrypted, position });
    }
    return publicFiles.sort((a, b) => a.position - b.position);
};

const decryptMemoryShareMetadataJSON = async (
    metadataCipher: string,
    metadataNonce: string,
    shareKey: string,
): Promise<string> => {
    const metadataBytes = await decryptBoxBytes(
        { encryptedData: metadataCipher, nonce: metadataNonce },
        shareKey,
    );
    // The plaintext is plain JSON for share memories but gzipped JSON for
    // lanes; a failed parse below falls through to decompression.
    if (metadataBytes.byteLength > maxMemoryShareMetadataBytes) {
        throw new Error("Memory share metadata exceeds the allowed size");
    }
    let metadataJson: string;
    try {
        metadataJson = new TextDecoder().decode(metadataBytes);
        JSON.parse(metadataJson);
    } catch {
        metadataJson = await gunzipWithLimit(
            metadataBytes,
            maxMemoryShareMetadataBytes,
        );
    }
    return metadataJson;
};

export const decryptMemoryShareMetadata = async (
    metadataCipher: string,
    metadataNonce: string,
    shareKey: string,
): Promise<PublicMemoryShareMetadata> => {
    const metadataJson = await decryptMemoryShareMetadataJSON(
        metadataCipher,
        metadataNonce,
        shareKey,
    );
    const metadata = PublicMemoryShareMetadataBaseSchema.parse(
        JSON.parse(metadataJson),
    );
    const frames = (metadata.frames ?? []).flatMap((frame) => {
        const parsed = PublicMemoryShareFrameSchema.safeParse(frame);
        return parsed.success ? [parsed.data] : [];
    });

    return {
        name: metadata.name ?? "",
        kind: metadata.kind,
        captionType: metadata.captionType,
        personID: metadata.personID,
        personName: metadata.personName,
        birthDate: metadata.birthDate,
        frames,
    };
};
