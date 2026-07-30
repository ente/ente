import { decryptBlobBytes } from "ente-base/crypto";
import type { EncryptedBlob } from "ente-base/crypto/types";
import type { PublicAlbumsCredentials } from "ente-base/http";
import log from "ente-base/log";
import {
    fetchFileData,
    fetchFilePreviewData,
} from "ente-gallery/services/file-data";
import { fileLogID, type EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { ensurePrecondition } from "ente-utils/ensure";
import { z } from "zod";

export interface HLSPlaylistData {
    playlistURL: string;
    width: number;
    height: number;
}

export type HLSPlaylistDataForFile = HLSPlaylistData | "skip" | undefined;

export const hlsPlaylistDataForFile = async (
    file: EnteFile,
    publicAlbumsCredentials?: PublicAlbumsCredentials,
): Promise<HLSPlaylistDataForFile> => {
    ensurePrecondition(file.metadata.fileType == FileType.video);

    if (file.pubMagicMetadata?.data.sv == 1) {
        return "skip";
    }

    const playlistFileData = await fetchFileData(
        "vid_preview",
        file.id,
        publicAlbumsCredentials,
    );
    if (!playlistFileData) return undefined;

    let playlistJSON: PlaylistJSON;
    try {
        playlistJSON = await decryptPlaylistJSON(playlistFileData, file);
    } catch (e) {
        log.error(`Failed to read HLS playlist for ${fileLogID(file)}`, e);
        return undefined;
    }

    const { type, playlist: playlistTemplate, width, height } = playlistJSON;
    if (type != "hls_video") return undefined;

    const videoURL = await fetchFilePreviewData(
        "vid_preview",
        file.id,
        publicAlbumsCredentials,
    );
    if (!videoURL) return undefined;

    const playlist = playlistTemplate.replaceAll(
        "\noutput.ts",
        `\n${videoURL}`,
    );

    const playlistURL = await blobToDataURL(
        new Blob([playlist], { type: "application/vnd.apple.mpegurl" }),
    );

    return { playlistURL, width, height };
};

const PlaylistJSON = z.object({
    type: z.string(),
    playlist: z.string(),
    width: z.number(),
    height: z.number(),
});

type PlaylistJSON = z.infer<typeof PlaylistJSON>;

const decryptPlaylistJSON = async (
    encryptedPlaylist: EncryptedBlob,
    file: EnteFile,
) => {
    const decryptedBytes = await decryptBlobBytes(encryptedPlaylist, file.key);
    const jsonString = await gunzip(decryptedBytes);
    return PlaylistJSON.parse(JSON.parse(jsonString));
};

const gunzip = async (data: Uint8Array<ArrayBuffer>) =>
    await new Response(
        new Blob([data]).stream().pipeThrough(new DecompressionStream("gzip")),
    ).text();

const blobToDataURL = (blob: Blob) =>
    new Promise<string>((resolve) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result as string);
        reader.readAsDataURL(blob);
    });
