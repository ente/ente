import { ensureElectron } from "ente-base/electron";
import log from "ente-base/log";
import type { Electron } from "ente-base/types/ipc";
import {
    toPathOrZipEntry,
    type FileSystemUploadItem,
    type UploadItem,
} from "ente-gallery/services/upload";
import {
    initiateConvertToMP4,
    readVideoStream,
    videoStreamDone,
} from "ente-gallery/utils/native-stream";
import {
    parseMetadataDate,
    type ParsedMetadata,
} from "ente-media/file-metadata";
import {
    ffmpegPathPlaceholder,
    inputPathPlaceholder,
    outputPathPlaceholder,
} from "./constants";
import { determineVideoDurationWeb, ffmpegExecWeb } from "./web";

export const generateVideoThumbnailWeb = async (blob: Blob) =>
    _generateVideoThumbnail((seekTime: number) =>
        ffmpegExecWeb(makeGenThumbnailCommand(seekTime), blob, "jpeg"),
    );

const _generateVideoThumbnail = async (
    thumbnailAtTime: (seekTime: number) => Promise<Uint8Array<ArrayBuffer>>,
): Promise<Uint8Array<ArrayBuffer>> => {
    try {
        return await thumbnailAtTime(1);
    } catch {
        return await thumbnailAtTime(0);
    }
};

export const generateVideoThumbnailNative = async (
    electron: Electron,
    fsUploadItem: FileSystemUploadItem,
) =>
    _generateVideoThumbnail((seekTime: number) =>
        electron.ffmpegExec(
            makeGenThumbnailCommand(seekTime),
            toPathOrZipEntry(fsUploadItem),
            "jpeg",
        ),
    );

const makeGenThumbnailCommand = (seekTime: number) => ({
    default: _makeGenThumbnailCommand(seekTime, false),
    hdr: _makeGenThumbnailCommand(seekTime, true),
});

const _makeGenThumbnailCommand = (seekTime: number, forHDR: boolean) => [
    ffmpegPathPlaceholder,
    "-i",
    inputPathPlaceholder,
    "-ss",
    `00:00:0${seekTime}`,
    "-vframes",
    "1",
    "-vf",
    [
        // Scale it down to a maximum height of 720 keeping aspect ratio,
        // ensuring that the dimensions are even (subsequent filters require
        // this).
        "scale=-2:'min(720,trunc(ih/2)*2)'",
        forHDR
            ? // Tone-map HDR frames so thumbnails are not washed out.
              [
                  "zscale=transfer=linear",
                  "tonemap=tonemap=hable:desat=0",
                  "zscale=primaries=709:transfer=709:matrix=709",
              ]
            : [],
    ]
        .flat()
        .join(","),
    outputPathPlaceholder,
];

export const extractVideoMetadata = async (
    uploadItem: UploadItem,
): Promise<ParsedMetadata> => {
    const command = extractVideoMetadataCommand;
    return parseFFmpegExtractedMetadata(
        uploadItem instanceof File
            ? await ffmpegExecWeb(command, uploadItem, "txt")
            : await ensureElectron().ffmpegExec(
                  command,
                  toPathOrZipEntry(uploadItem),
                  "txt",
              ),
    );
};

const extractVideoMetadataCommand = [
    ffmpegPathPlaceholder,
    "-i",
    inputPathPlaceholder,
    "-c",
    "copy",
    "-map_metadata",
    "0",
    "-f",
    "ffmetadata",
    outputPathPlaceholder,
];

const parseFFmpegExtractedMetadata = (ffmpegOutput: Uint8Array) => {
    // Accept both line endings across FFmpeg builds.
    const lines = new TextDecoder().decode(ffmpegOutput).split(/\r?\n/);
    const isPair = (xs: string[]): xs is [string, string] => xs.length == 2;
    const kvPairs = lines.map((property) => property.split("=")).filter(isPair);

    const kv = new Map(kvPairs);

    const result: ParsedMetadata = {};

    const creationDate = parseFFMetadataDate(
        kv.get("com.apple.quicktime.creationdate"),
    );
    if (creationDate) {
        result.creationDate = creationDate;
    } else {
        const creationTime = parseFFMetadataDate(
            kv.get("creation_time"),
        )?.timestamp;
        if (creationTime) result.creationTime = creationTime;
    }

    const location =
        parseFFMetadataLocation(
            kv.get("com.apple.quicktime.location.ISO6709"),
        ) ?? parseFFMetadataLocation(kv.get("location"));
    if (location) result.location = location;

    return result;
};

const parseFFMetadataLocation = (s: string | undefined) => {
    if (!s) return undefined;

    const m = s.match(/(\+|-)\d+\.*\d+/g);
    if (!m) {
        log.warn(`Ignoring unparseable location string "${s}"`);
        return undefined;
    }

    const [latitude, longitude] = m.map(parseFloat);
    if (!latitude || !longitude) {
        log.warn(`Ignoring unparseable video metadata location string "${s}"`);
        return undefined;
    }

    return { latitude, longitude };
};

const parseFFMetadataDate = (s: string | undefined) => {
    if (!s) return undefined;

    const d = parseMetadataDate(s);
    if (!d) {
        log.warn(`Ignoring unparseable video metadata date string "${s}"`);
        return undefined;
    }

    // Match the image parser by rejecting the Unix epoch.
    if (!d.timestamp) {
        log.warn(`Ignoring zero video metadata date string "${s}"`);
        return undefined;
    }

    return d;
};

export const determineVideoDuration = async (
    uploadItem: UploadItem,
): Promise<number> =>
    uploadItem instanceof File
        ? determineVideoDurationWeb(uploadItem)
        : ensureElectron().ffmpegDetermineVideoDuration(
              toPathOrZipEntry(uploadItem),
          );

export const convertToMP4 = async (
    blob: Blob,
): Promise<Blob | Uint8Array<ArrayBuffer>> => {
    const electron = globalThis.electron;
    if (electron) {
        return convertToMP4Native(electron, blob);
    } else {
        const command = [
            ffmpegPathPlaceholder,
            "-i",
            inputPathPlaceholder,
            "-preset",
            "ultrafast",
            outputPathPlaceholder,
        ];
        return ffmpegExecWeb(command, blob, "mp4");
    }
};

const convertToMP4Native = async (electron: Electron, blob: Blob) => {
    const token = await initiateConvertToMP4(electron, blob);
    try {
        return await readVideoStream(electron, token).then((res) => res.blob());
    } finally {
        await videoStreamDone(electron, token);
    }
};
