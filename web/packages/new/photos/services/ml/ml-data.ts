import { decryptBlobBytes } from "ente-base/crypto";
import log from "ente-base/log";
import { fetchFilesData, putFileData } from "ente-gallery/services/file-data";
import type { EnteFile } from "ente-media/file";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import { gunzip, gzip } from "../../utils/gzip";
import type { RemoteCLIPIndex } from "./clip";
import type { RemoteFaceIndex } from "./face";

export interface RemoteMLData {
    // Keep raw data when updating so unknown top-level keys survive.
    raw: RawRemoteMLData;
    parsed: ParsedRemoteMLData | undefined;
    updatedAt: number | undefined;
}

export type RawRemoteMLData = Record<string, unknown>;

type ParsedRemoteMLData = Partial<{
    face: RemoteFaceIndex;
    clip: RemoteCLIPIndex;
}>;

const RemoteFaceIndex = z.object({
    version: z.number(),
    client: z.string(),
    flags: z.number().int().default(0),
    width: z.number(),
    height: z.number(),
    faces: z.array(
        z.object({
            faceID: z.string(),
            detection: z.object({
                box: z.object({
                    x: z.number(),
                    y: z.number(),
                    width: z.number(),
                    height: z.number(),
                }),
                landmarks: z.array(z.object({ x: z.number(), y: z.number() })),
            }),
            score: z.number(),
            blur: z.number(),
            embedding: z.array(z.number()),
        }),
    ),
});

const RemoteCLIPIndex = z.object({
    version: z.number(),
    client: z.string(),
    flags: z.number().int().default(0),
    embedding: z.array(z.number()),
});

const RawRemoteMLData = z.looseObject({});

const ParsedRemoteMLData = z.object({
    face: RemoteFaceIndex.nullish().transform(nullToUndefined),
    clip: RemoteCLIPIndex.nullish().transform(nullToUndefined),
});

export const fetchMLData = async (
    filesByID: Map<number, EnteFile>,
): Promise<Map<number, RemoteMLData>> => {
    const remoteFileDatas = await fetchFilesData("mldata", [
        ...filesByID.keys(),
    ]);

    const result = new Map<number, RemoteMLData>();
    for (const remoteFileData of remoteFileDatas) {
        const { fileID, updatedAt } = remoteFileData;
        const file = filesByID.get(fileID);
        if (!file) {
            log.warn(`Ignoring ML data for unknown file id ${fileID}`);
            continue;
        }

        try {
            const decryptedBytes = await decryptBlobBytes(
                remoteFileData,
                file.key,
            );
            const jsonString = await gunzip(decryptedBytes);
            result.set(
                fileID,
                remoteMLDataFromJSONString(jsonString, updatedAt),
            );
        } catch (e) {
            // Omit corrupt remote data so indexing replaces it.
            log.warn(`Ignoring unparseable ML data for file id ${fileID}`, e);
        }
    }
    log.debug(() => `Fetched ML data for ${result.size} files`);
    return result;
};

const remoteMLDataFromJSONString = (
    jsonString: string,
    updatedAt: number | undefined,
) => {
    const raw = RawRemoteMLData.parse(JSON.parse(jsonString));
    const parseResult = ParsedRemoteMLData.safeParse(raw);
    const parsed = parseResult.success
        ? (parseResult.data as ParsedRemoteMLData)
        : undefined;
    return { raw, parsed, updatedAt };
};

export const putMLData = async (
    file: EnteFile,
    mlData: RawRemoteMLData,
    lastUpdatedAt: number,
) =>
    putFileData(
        file,
        "mldata",
        await gzip(JSON.stringify(mlData)),
        lastUpdatedAt,
    );
