import shellescape from "any-shell-escape";
import { expose } from "comlink";
import { createHash, randomBytes } from "node:crypto";
import fs_ from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import { Readable } from "node:stream";
import { z } from "zod";
import type { FFmpegCommand } from "../../types/ipc";
import log from "../log-worker";
import { messagePortMainEndpoint } from "../utils/comlink";
import { nullToUndefined, wait } from "../utils/common";
import { execAsyncWorker } from "../utils/exec-worker";
import {
    authenticatedRequestHeaders,
    publicRequestHeaders,
} from "../utils/http";

const ffmpegPathPlaceholder = "FFMPEG";
const inputPathPlaceholder = "INPUT";
const outputPathPlaceholder = "OUTPUT";

export interface FFmpegUtilityProcess {
    ffmpegExec: (
        command: FFmpegCommand,
        inputFilePath: string,
        outputFilePath: string,
    ) => Promise<void>;

    ffmpegConvertToMP4: (
        inputFilePath: string,
        outputFilePath: string,
    ) => Promise<void>;

    ffmpegGenerateHLSPlaylistAndSegments: (
        inputFilePath: string,
        outputPathPrefix: string,
        fileID: number,
        fetchURL: string,
        authToken: string,
        previewUploadV2: boolean,
    ) => Promise<FFmpegGenerateHLSPlaylistAndSegmentsResult | undefined>;

    ffmpegDetermineVideoDuration: (inputFilePath: string) => Promise<number>;
}

log.debugString("Started ffmpeg utility process");

process.on("uncaughtException", (e, origin) => log.error(origin, e));

process.parentPort.once("message", (e) => {
    parseInitData(e.data);
    expose(
        {
            ffmpegExec,
            ffmpegConvertToMP4,
            ffmpegGenerateHLSPlaylistAndSegments,
            ffmpegDetermineVideoDuration,
        } satisfies FFmpegUtilityProcess,
        messagePortMainEndpoint(e.ports[0]!),
    );
    mainProcess("ack", undefined);
});

let _desktopAppVersion: string | undefined;
let _ffmpegPath: string | undefined;

const desktopAppVersion = () => _desktopAppVersion!;

const FFmpegWorkerInitData = z.object({
    appVersion: z.string(),
    ffmpegPath: z.string(),
});

const parseInitData = (data: unknown) => {
    const init = FFmpegWorkerInitData.parse(data);
    _desktopAppVersion = init.appVersion;
    _ffmpegPath = init.ffmpegPath;
};

const mainProcess = (method: string, param: unknown) =>
    process.parentPort.postMessage({ method, p: param });

const ffmpegExec = async (
    command: FFmpegCommand,
    inputFilePath: string,
    outputFilePath: string,
): Promise<void> => {
    let resolvedCommand: string[];
    if (Array.isArray(command)) {
        resolvedCommand = command;
    } else {
        const isHDR = await isHDRVideo(inputFilePath);
        resolvedCommand = isHDR ? command.hdr : command.default;
    }

    const cmd = substitutePlaceholders(
        resolvedCommand,
        inputFilePath,
        outputFilePath,
    );

    await execAsyncWorker(cmd);
};

const substitutePlaceholders = (
    command: string[],
    inputFilePath: string,
    outputFilePath: string,
) =>
    command.map((segment) => {
        if (segment == ffmpegPathPlaceholder) {
            return ffmpegBinaryPath();
        } else if (segment == inputPathPlaceholder) {
            return inputFilePath;
        } else if (segment == outputPathPlaceholder) {
            return outputFilePath;
        } else {
            return segment;
        }
    });

const ffmpegBinaryPath = () => _ffmpegPath!;

const ffmpegConvertToMP4 = async (
    inputFilePath: string,
    outputFilePath: string,
): Promise<void> => {
    const command = [
        ffmpegPathPlaceholder,
        "-i",
        inputPathPlaceholder,
        "-preset",
        "ultrafast",
        outputPathPlaceholder,
    ];

    const cmd = substitutePlaceholders(command, inputFilePath, outputFilePath);

    await execAsyncWorker(cmd);
};

export interface FFmpegGenerateHLSPlaylistAndSegmentsResult {
    playlistPath: string;
    dimensions: { width: number; height: number };
    videoSize: number;
    videoObjectID: string;
}

const ffmpegGenerateHLSPlaylistAndSegments = async (
    inputFilePath: string,
    outputPathPrefix: string,
    fileID: number,
    fetchURL: string,
    authToken: string,
    previewUploadV2: boolean,
): Promise<FFmpegGenerateHLSPlaylistAndSegmentsResult | undefined> => {
    const { isH264, isHDR, bitrate } =
        await detectVideoCharacteristics(inputFilePath);

    log.debugString(JSON.stringify({ isH264, isHDR, bitrate }));

    // Never skip HEVC: it can be audio-only on Linux, and Chromium can ignore
    // iPhone HEVC+HDR rotation metadata.
    if (isH264) {
        const inputVideoSize = await fs
            .stat(inputFilePath)
            .then((st) => st.size);
        if (inputVideoSize <= 10 * 1024 * 1024) {
            return undefined;
        }
    }

    // Re-encoding is by far the dominant cost of generating the stream.
    const reencodeVideo = !(isH264 && bitrate && bitrate <= 4000 * 1000);
    // Avoid shrinking video whose bitrate is already modest.
    const rescaleVideo = !(bitrate && bitrate <= 2000 * 1000);
    // HDR needs BT.709 tonemapping; applying it to SDR reduces brightness.
    const tonemap = isHDR;

    await fs.mkdir(outputPathPrefix);

    const playlistPath = path.join(outputPathPrefix, "output.m3u8");
    const videoPath = path.join(outputPathPrefix, "output.ts");

    // Avoid child_process's stderr buffer limit on large videos.
    const stderrPath = path.join(outputPathPrefix, "stderr.txt");

    const keyBytes = randomBytes(16);
    const keyB64 = keyBytes.toString("base64");

    const keyURI = `data:text/plain;base64,${keyB64}`;

    const keyPath = playlistPath + ".key";
    const keyInfoPath = playlistPath + ".key-info";

    // FFmpeg key-info is the playlist URI followed by the local key path.
    const keyInfo = [keyURI, keyPath].join("\n");

    const command = [
        ffmpegBinaryPath(),
        ["-hide_banner"],
        "-i",
        inputFilePath,
        reencodeVideo
            ? [
                  "-vf",
                  [
                      // Tonemapping requires dimensions divisible by chroma
                      // subsampling, so it also forces the even-size scale.
                      rescaleVideo || tonemap
                          ? [
                                "scale='if(lt(iw,ih),min(720,iw),-2)':'if(lt(iw,ih),-2,min(720,ih))'",
                                "fps=30",
                            ]
                          : [],
                      // tonemap requires linear input; the final zscale emits
                      // the broadly supported BT.709 color space.
                      tonemap
                          ? [
                                "zscale=transfer=linear",
                                "tonemap=tonemap=hable:desat=0",
                                "zscale=primaries=709:transfer=709:matrix=709",
                            ]
                          : [],
                      "format=yuv420p",
                  ]
                      .flat()
                      .join(","),
              ]
            : [],
        reencodeVideo
            ? ["-c:v", "libx264", "-maxrate", "2000k", "-bufsize", "4000k"]
            : ["-c:v", "copy"],
        ["-c:a", "aac"],
        ["-f", "hls"],
        ["-hls_key_info_file", keyInfoPath],
        ["-hls_list_size", "0"],
        ["-hls_flags", "single_file"],
        playlistPath,
    ].flat();

    let dimensions: { width: number; height: number };
    let videoSize: number;
    let videoObjectID: string;

    try {
        await Promise.all([
            fs.writeFile(keyPath, keyBytes),
            fs.writeFile(keyInfoPath, keyInfo, { encoding: "utf8" }),
        ]);

        const commandWithRedirection = `${shellescape(command)} 2>${shellescape([stderrPath])}`;

        await execAsyncWorker(commandWithRedirection);

        // FFmpeg-generated HLS uses LF even on Windows; fail if that changes.
        if (process.platform == "win32") {
            const playlistText = await fs.readFile(playlistPath, "utf-8");
            if (playlistText.includes("\r\n"))
                throw new Error("Unexpected Windows newlines in playlist");
        }

        dimensions = await detectVideoDimensions(stderrPath);

        videoSize = await fs.stat(videoPath).then((st) => st.size);

        videoObjectID = await uploadVideoSegments(
            videoPath,
            videoSize,
            fileID,
            fetchURL,
            authToken,
            previewUploadV2,
        );
    } catch (e) {
        log.error("HLS generation failed", e);
        await Promise.all([deletePathIgnoringErrors(playlistPath)]);
        throw e;
    } finally {
        await Promise.all([
            deletePathIgnoringErrors(stderrPath),
            deletePathIgnoringErrors(keyInfoPath),
            deletePathIgnoringErrors(keyPath),
            deletePathIgnoringErrors(videoPath),
            // FFmpeg can leave this beside the output after failures.
            deletePathIgnoringErrors(videoPath + ".tmp"),
        ]);
    }

    return { playlistPath, dimensions, videoSize, videoObjectID };
};

const deletePathIgnoringErrors = async (tempFilePath: string) => {
    try {
        await fs.rm(tempFilePath, { force: true });
    } catch (e) {
        log.error(`Could not delete item at path ${tempFilePath}`, e);
    }
};

const videoStreamLineRegex = /Stream #.+: Video:(.+)\r?\n/;

const videoStreamLinesRegex = /Stream #.+: Video:(.+)\r?\n/g;

const videoBitrateRegex = / ([1-9]\d*) kb\/s/;

// Leading nonzero digits avoid matching hexadecimal constants in stream info.
const videoDimensionsRegex = / ([1-9]\d*)x([1-9]\d*)/;

interface VideoCharacteristics {
    isH264: boolean;
    isHDR: boolean;
    bitrate: number | undefined;
}

// We do not bundle ffprobe, so this parses ffmpeg stderr. Failed parses fall
// back to re-encoding instead of incorrectly skipping conversion.
const detectVideoCharacteristics = async (inputFilePath: string) => {
    const videoInfo = await pseudoFFProbeVideo(inputFilePath);
    const videoStreamLine = videoStreamLineRegex.exec(videoInfo)?.at(1)?.trim();

    const res: VideoCharacteristics = {
        isH264: false,
        isHDR: false,
        bitrate: undefined,
    };
    if (!videoStreamLine) return res;

    res.isH264 = videoStreamLine.startsWith("h264 ");

    res.isHDR =
        videoStreamLine.includes("smpte2084") ||
        videoStreamLine.includes("arib-std-b67");

    const brs = videoBitrateRegex.exec(videoStreamLine)?.at(0);
    if (brs) {
        const br = parseInt(brs, 10);
        if (br) res.bitrate = br * 1000;
    }

    return res;
};

const detectVideoDimensions = async (stderrPath: string) => {
    const conversionStderr = await fs.readFile(stderrPath, "utf-8");

    // Conversion output lists the input stream before the output stream.
    const videoStreamLine = Array.from(
        conversionStderr.matchAll(videoStreamLinesRegex),
    )
        .at(-1)
        ?.at(1);
    if (videoStreamLine) {
        const [, ws, hs] = videoDimensionsRegex.exec(videoStreamLine) ?? [];
        if (ws && hs) {
            const w = parseInt(ws, 10);
            const h = parseInt(hs, 10);
            if (w && h) {
                return { width: w, height: h };
            }
        }
    }
    throw new Error(
        `Unable to detect video dimensions from stream line [${videoStreamLine ?? ""}]`,
    );
};

// False positives fail zscale with "code 3074: no path between colorspaces";
// false negatives only miss tonemapping, so allow-list known HDR transfers.
const isHDRVideo = async (inputFilePath: string) => {
    try {
        const videoInfo = await pseudoFFProbeVideo(inputFilePath);
        const vs = videoStreamLineRegex.exec(videoInfo)?.at(1);
        if (!vs) return false;
        return vs.includes("smpte2084") || vs.includes("arib-std-b67");
    } catch (e) {
        log.warn(`Could not detect HDR status of ${inputFilePath}`, e);
        return false;
    }
};

// Extract stream metadata from ffmpeg stderr because ffprobe is not bundled.
const pseudoFFProbeVideo = async (inputFilePath: string) => {
    const command = [
        ffmpegPathPlaceholder,
        ["-hide_banner"],
        ["-i", inputPathPlaceholder],
        "-an",
        ["-frames:v", "0"],
        ["-f", "null"],
        "-",
    ].flat();

    const cmd = substitutePlaceholders(command, inputFilePath, "");

    const { stderr } = await execAsyncWorker(cmd);

    return stderr;
};

const uploadVideoSegments = async (
    videoFilePath: string,
    videoSize: number,
    fileID: number,
    fetchURL: string,
    authToken: string,
    previewUploadV2: boolean,
) => {
    // Leave headroom below Cloudflare's 100 MB limit for self-hosters.
    const partSize = 96 * 1024 * 1024;
    const partCount = Math.ceil(videoSize / partSize);

    if (previewUploadV2 && (videoSize <= 0 || videoSize > 10 * 1024 ** 3))
        throw new Error("Preview size must be between 1 byte and 10 GiB");

    const partMD5s = previewUploadV2
        ? await computeVideoPartMD5s(videoFilePath, videoSize, partSize)
        : undefined;

    const { objectID, url, partURLs, completeURL } = partMD5s
        ? await getPreviewUploadURLWithMetadata(
              fileID,
              videoSize,
              partSize,
              partMD5s,
              fetchURL,
              authToken,
          )
        : await getFilePreviewDataUploadURL(
              partCount,
              fileID,
              fetchURL,
              authToken,
          );

    if (url && partCount == 1) {
        await uploadVideoSegmentsSingle(
            videoFilePath,
            videoSize,
            url,
            partMD5s?.[0],
        );
    } else if (partURLs?.length == partCount && completeURL) {
        await uploadVideoSegmentsMultipart(
            videoFilePath,
            videoSize,
            partSize,
            partURLs,
            completeURL,
            partMD5s,
        );
    } else {
        throw new Error("Malformed upload URLs");
    }

    return objectID;
};

const computeVideoPartMD5s = async (
    videoFilePath: string,
    videoSize: number,
    partSize: number,
) => {
    const checksums: string[] = [];
    for (let start = 0; start < videoSize; start += partSize) {
        const end = Math.min(start + partSize, videoSize) - 1;
        const hash = createHash("md5");
        for await (const chunk of fs_.createReadStream(videoFilePath, {
            start,
            end,
        })) {
            hash.update(chunk as Buffer);
        }
        checksums.push(hash.digest("base64"));
    }
    return checksums;
};

const getPreviewUploadURLWithMetadata = async (
    fileID: number,
    contentLength: number,
    partLength: number,
    partMd5s: string[],
    fetchURL: string,
    authToken: string,
) => {
    const isMultipart = partMd5s.length > 1;
    const url = isMultipart
        ? new URL("multipart-preview-upload-url", fetchURL)
        : fetchURL;
    const body = JSON.stringify({
        fileID,
        type: "vid_preview",
        contentLength,
        ...(isMultipart
            ? { partLength, partMd5s }
            : { contentMD5: partMd5s[0] }),
    });
    const res = await retryEnsuringHTTPOk(() =>
        fetch(url, {
            method: "POST",
            headers: {
                ...authenticatedRequestHeaders(desktopAppVersion(), authToken),
                "Content-Type": "application/json",
            },
            body,
        }),
    );
    return FilePreviewDataUploadURLResponse.parse(await res.json());
};

const FilePreviewDataUploadURLResponse = z.object({
    objectID: z.string(),
    url: z.string().nullish().transform(nullToUndefined),
    partURLs: z.string().array().nullish().transform(nullToUndefined),
    completeURL: z.string().nullish().transform(nullToUndefined),
});

export const getFilePreviewDataUploadURL = async (
    partCount: number,
    fileID: number,
    fetchURL: string,
    authToken: string,
) => {
    const params = new URLSearchParams({
        fileID: fileID.toString(),
        type: "vid_preview",
        ts: Date.now().toString(),
    });
    if (partCount > 1) {
        params.set("isMultiPart", "true");
        params.set("count", partCount.toString());
    }

    const res = await retryEnsuringHTTPOk(() =>
        fetch(`${fetchURL}?${params.toString()}`, {
            headers: authenticatedRequestHeaders(
                desktopAppVersion(),
                authToken,
            ),
        }),
    );

    return FilePreviewDataUploadURLResponse.parse(await res.json());
};

const uploadVideoSegmentsSingle = (
    videoFilePath: string,
    videoSize: number,
    objectUploadURL: string,
    contentMD5?: string,
) =>
    retryEnsuringHTTPOk(() =>
        // Electron's net.fetch is 40-50x slower for this streaming PUT.
        fetch(objectUploadURL, {
            method: "PUT",
            // Node fetch does not infer Content-Length for streams.
            headers: {
                ...publicRequestHeaders(desktopAppVersion()),
                "Content-Length": `${videoSize}`,
                ...(contentMD5 ? { "Content-MD5": contentMD5 } : {}),
            },
            // @ts-expect-error Node fetch accepts duplex streaming.
            duplex: "half",
            // Node's ReadableStream type does not satisfy DOM BodyInit.
            body: Readable.toWeb(
                fs_.createReadStream(videoFilePath),
            ) as unknown as BodyInit,
        }),
    );

const retryEnsuringHTTPOk = async (request: () => Promise<Response>) => {
    const waitTimeBeforeNextTry = [10000, 30000, 120000];

    while (true) {
        try {
            const res = await request();
            if (res.ok) return res;
            throw new Error(
                `Request failed: HTTP ${res.status} ${res.statusText}`,
            );
        } catch (e) {
            const t = waitTimeBeforeNextTry.shift();
            if (!t) {
                throw e;
            } else {
                log.warn("Will retry potentially transient request failure", e);
                await wait(t);
            }
        }
    }
};

const uploadVideoSegmentsMultipart = async (
    videoFilePath: string,
    videoSize: number,
    partSize: number,
    partUploadURLs: string[],
    completionURL: string,
    partMD5s?: string[],
) => {
    let partNumber = 0;
    let start = 0;
    const completionXML = ["<CompleteMultipartUpload>"];
    for (const partUploadURL of partUploadURLs) {
        partNumber += 1;
        const size = Math.min(start + partSize, videoSize) - start;
        const end = start + size - 1;
        const contentMD5 = partMD5s?.[partNumber - 1];
        const res = await retryEnsuringHTTPOk(() =>
            fetch(partUploadURL, {
                method: "PUT",
                headers: {
                    ...publicRequestHeaders(desktopAppVersion()),
                    "Content-Length": `${size}`,
                    ...(contentMD5 ? { "Content-MD5": contentMD5 } : {}),
                },
                // @ts-expect-error Node fetch accepts duplex streaming.
                duplex: "half",
                // Node's ReadableStream type does not satisfy DOM BodyInit.
                body: Readable.toWeb(
                    fs_.createReadStream(videoFilePath, { start, end }),
                ) as unknown as BodyInit,
            }),
        );
        const eTag = res.headers.get("etag");
        if (!eTag) throw new Error("Response did not have an ETag");
        start += size;
        completionXML.push(
            `<Part><PartNumber>${partNumber}</PartNumber><ETag>${eTag}</ETag></Part>`,
        );
    }
    completionXML.push("</CompleteMultipartUpload>");
    const completionBody = completionXML.join("");
    return await retryEnsuringHTTPOk(() =>
        fetch(completionURL, {
            method: "POST",
            headers: {
                ...publicRequestHeaders(desktopAppVersion()),
                "Content-Type": "text/xml",
            },
            body: completionBody,
        }),
    );
};

const videoDurationLineRegex = /\s\sDuration: ([0-9:]+)(.[0-9]+)?/;

export const ffmpegDetermineVideoDuration = async (inputFilePath: string) => {
    const videoInfo = await pseudoFFProbeVideo(inputFilePath);
    const matches = videoDurationLineRegex.exec(videoInfo);

    const fail = () => {
        throw new Error(`Cannot parse video duration '${matches?.at(0)}'`);
    };

    const ints = (matches?.at(1) ?? "")
        .split(":")
        .map((s) => parseInt(s, 10) || 0);
    let [h, m, s] = [0, 0, 0];
    switch (ints.length) {
        case 1:
            s = ints[0]!;
            break;
        case 2:
            m = ints[0]!;
            s = ints[1]!;
            break;
        case 3:
            h = ints[0]!;
            m = ints[1]!;
            s = ints[2]!;
            break;
        default:
            fail();
    }

    const ss = parseFloat(`0${matches?.at(2) ?? ""}`);

    // Match the web implementation's rounding.
    const duration = Math.ceil(h * 3600 + m * 60 + s + ss);
    if (!duration) fail();
    return duration;
};
