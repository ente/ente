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

/**
 * Generate a thumbnail for the given video using a Wasm FFmpeg running in a web
 * worker.
 *
 * This function is called during upload, when we need to generate thumbnails
 * for the new files that the user is adding.
 *
 * @param blob The input video blob.
 *
 * @returns JPEG data of the generated thumbnail.
 *
 * See also {@link generateVideoThumbnailNative}.
 */
export const generateVideoThumbnailWeb = async (blob: Blob) =>
    _generateVideoThumbnail((seekTime: number) =>
        ffmpegExecWeb(makeGenThumbnailCommand(seekTime), blob, "jpeg"),
    );

const _generateVideoThumbnail = async (
    thumbnailAtTime: (seekTime: number) => Promise<Uint8Array<ArrayBuffer>>,
): Promise<Uint8Array<ArrayBuffer>> => {
    try {
        // Try generating thumbnail at seekTime 1 second.
        return await thumbnailAtTime(1);
    } catch {
        // If that fails, try again at the beginning. If even this throws, let
        // it fail.
        return await thumbnailAtTime(0);
    }
};

/**
 * Generate a thumbnail for the given video using a native FFmpeg binary bundled
 * with our desktop app.
 *
 * This function is called during upload, when we need to generate thumbnails
 * for the new files that the user is adding.
 *
 * @param dataOrPath The input video's data or the path to the video on the
 * user's local file system. See: [Note: Reading a UploadItem].
 *
 * @returns JPEG data of the generated thumbnail.
 *
 * See also {@link generateVideoThumbnailNative}.
 */
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
    // Seek to seekTime in the video.
    "-ss",
    `00:00:0${seekTime}`,
    // Take the first frame
    "-vframes",
    "1",
    // Apply a filter to this frame
    "-vf",
    [
        // Scale it to a maximum height of 720 keeping aspect ratio, ensuring
        // that the dimensions are even (subsequent filters require this).
        "scale=-2:720",
        forHDR
            ? // Apply a tonemap to ensure that thumbnails of HDR videos do
              // not look washed out. See: [Note: Tonemapping HDR to HD].
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

/**
 * Extract metadata from the given video.
 *
 * When we're running in the context of our desktop app _and_ we're passed an
 * upload item that resolves to a path of the user's file system, this uses the
 * native FFmpeg bundled with our desktop app. Otherwise it uses a Wasm build of
 * FFmpeg running in a web worker.
 *
 * This function is called during upload, when we need to extract the
 * "ffmetadata" of videos that the user is uploading.
 *
 * @param uploadItem The video item being uploaded.
 */
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

/**
 * The FFmpeg command to use to extract metadata from videos.
 *
 * Options:
 *
 * - `-c [short for codex] copy`
 * - copy is the [stream_specifier](ffmpeg.org/ffmpeg.html#Stream-specifiers)
 * - copies all the stream without re-encoding
 *
 * - `-map_metadata`
 * - http://ffmpeg.org/ffmpeg.html#Advanced-options (search for map_metadata)
 * - copies all stream metadata to the output
 *
 * - `-f ffmetadata`
 * - https://ffmpeg.org/ffmpeg-formats.html#Metadata-2
 * - dump metadata from media files into a simple INI-like utf-8 text file
 */
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

/**
 * Convert the output produced by running the FFmpeg
 * {@link extractVideoMetadataCommand} into a {@link ParsedMetadata}.
 *
 * @param ffmpegOutput The bytes containing the output of the FFmpeg command.
 */
const parseFFmpegExtractedMetadata = (ffmpegOutput: Uint8Array) => {
    // The output is a utf8 INI-like text file with key=value pairs interspersed
    // with comments and newlines.
    //
    // https://ffmpeg.org/ffmpeg-formats.html#Metadata-2
    //
    // On Windows, while I couldn't find it documented anywhere, the generated
    // ffmetadata file uses Unix line separators ("\n"). But for the sake of
    // extra (albeit possibly unnecessary) safety, handle both \r\n and \n
    // separators in the split. See: [Note: ffmpeg newlines]

    const lines = new TextDecoder().decode(ffmpegOutput).split(/\r?\n/);
    const isPair = (xs: string[]): xs is [string, string] => xs.length == 2;
    const kvPairs = lines.map((property) => property.split("=")).filter(isPair);

    const kv = new Map(kvPairs);

    const result: ParsedMetadata = {};

    const creationDate =
        parseFFMetadataDate(kv.get("com.apple.quicktime.creationdate")) ??
        parseFFMetadataDate(kv.get("creation_time"));
    if (creationDate) result.creationDate = creationDate;

    const location =
        parseFFMetadataLocation(
            kv.get("com.apple.quicktime.location.ISO6709"),
        ) ?? parseFFMetadataLocation(kv.get("location"));
    if (location) result.location = location;

    return result;
};

/**
 * Parse a location string found in the FFmpeg metadata attributes.
 *
 * This is meant to parse either the "com.apple.quicktime.location.ISO6709"
 * (preferable) or the "location" key (fallback).
 */
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

/**
 * Parse a date/time string found in the FFmpeg metadata attributes.
 *
 * This is meant to parse either the "com.apple.quicktime.creationdate"
 * (preferable) or the "creation_time" key (fallback).
 *
 * Both of these are expected to be ISO 8601 date/time strings, but we prefer
 * "com.apple.quicktime.creationdate" since it includes the time zone offset.
 */
const parseFFMetadataDate = (s: string | undefined) => {
    if (!s) return undefined;

    const d = parseMetadataDate(s);
    if (!d) {
        log.warn(`Ignoring unparseable video metadata date string "${s}"`);
        return undefined;
    }

    // While not strictly required, we retain the same behaviour as the image
    // Exif parser of ignoring dates whose epoch is 0.
    if (!d.timestamp) {
        log.warn(`Ignoring zero video metadata date string "${s}"`);
        return undefined;
    }

    return d;
};

/**
 * Extract the duration (in seconds) from the given video
 *
 * This is a sibling of {@link extractVideoMetadata}, except it tries to
 * determine the duration of the video. The duration is not part of the
 * "ffmetadata", and is instead a property of the video itself.
 *
 * @param uploadItem The video item being uploaded.
 *
 * @return the duration of the video in seconds (a floating point number).
 */
export const determineVideoDuration = async (
    uploadItem: UploadItem,
): Promise<number> =>
    uploadItem instanceof File
        ? determineVideoDurationWeb(uploadItem)
        : ensureElectron().ffmpegDetermineVideoDuration(
              toPathOrZipEntry(uploadItem),
          );

/**
 * Convert a video from a format that is not supported in the browser to MP4.
 *
 * This function is called when the user views a video or a live photo, and we
 * want to play it back. The idea is to convert it to MP4 which has much more
 * universal support in browsers.
 *
 * @param blob The video blob.
 *
 * @returns The mp4 video blob.
 */
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
    const mp4Blob = await readVideoStream(electron, token).then((res) =>
        res.blob(),
    );
    await videoStreamDone(electron, token);
    return mp4Blob;
};
