/**
 * @file ffmpeg invocations. This code runs in a utility process.
 */

// See [Note: Using Electron APIs in UtilityProcess] about what we can and
// cannot import.
import shellescape from "any-shell-escape";
import { expose } from "comlink";
import pathToFfmpeg from "ffmpeg-static";
import { randomBytes } from "node:crypto";
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

/* Ditto in the web app's code (used by the Wasm FFmpeg invocation). */
const ffmpegPathPlaceholder = "FFMPEG";
const inputPathPlaceholder = "INPUT";
const outputPathPlaceholder = "OUTPUT";

/**
 * The interface of the object exposed by `ffmpeg-worker.ts` on the message port
 * pair that the main process creates to communicate with it.
 *
 * @see {@link ffmpegUtilityProcessEndpoint}.
 */
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
    ) => Promise<FFmpegGenerateHLSPlaylistAndSegmentsResult | undefined>;

    ffmpegDetermineVideoDuration: (inputFilePath: string) => Promise<number>;
}

log.debugString("Started ffmpeg utility process");

process.on("uncaughtException", (e, origin) => log.error(origin, e));

process.parentPort.once("message", (e) => {
    // Initialize ourselves with the data we got from our parent.
    parseInitData(e.data);
    // Expose an instance of `FFmpegUtilityProcess` on the port we got from our
    // parent.
    expose(
        {
            ffmpegExec,
            ffmpegConvertToMP4,
            ffmpegGenerateHLSPlaylistAndSegments,
            ffmpegDetermineVideoDuration,
        } satisfies FFmpegUtilityProcess,
        messagePortMainEndpoint(e.ports[0]!),
    );
    // Let the main process know we're ready.
    mainProcess("ack", undefined);
});

/**
 * We cannot access Electron's {@link app} object within a utility process, so
 * we pass the value of `app.getVersion()` during initialization, and it can be
 * subsequently retrieved from here.
 */
let _desktopAppVersion: string | undefined;

/** Equivalent to `app.getVersion()` */
const desktopAppVersion = () => _desktopAppVersion!;

const FFmpegWorkerInitData = z.object({ appVersion: z.string() });

const parseInitData = (data: unknown) => {
    _desktopAppVersion = FFmpegWorkerInitData.parse(data).appVersion;
};

/**
 * Send a message to the main process using a barebones RPC protocol.
 */
const mainProcess = (method: string, param: unknown) =>
    process.parentPort.postMessage({ method, p: param });

/**
 * Run a FFmpeg command
 *
 * [Note: FFmpeg in Electron]
 *
 * There is a Wasm build of FFmpeg, but that is currently 10-20 times slower
 * that the native build. That is slow enough to be unusable for our purposes.
 * https://ffmpegwasm.netlify.app/docs/performance
 *
 * So the alternative is to bundle a FFmpeg executable binary with our app. e.g.
 *
 *     npm install fluent-ffmpeg ffmpeg-static ffprobe-static
 *
 * (we only use ffmpeg-static, the rest are mentioned for completeness' sake).
 *
 * Interestingly, Electron already bundles an binary FFmpeg library (it comes
 * from the ffmpeg fork maintained by Chromium).
 * https://chromium.googlesource.com/chromium/third_party/ffmpeg
 * https://stackoverflow.com/questions/53963672/what-version-of-ffmpeg-is-bundled-inside-electron
 *
 * This can be found in (e.g. on macOS) at
 *
 *     $ file ente.app/Contents/Frameworks/Electron\ Framework.framework/Versions/Current/Libraries/libffmpeg.dylib
 *     .../libffmpeg.dylib: Mach-O 64-bit dynamically linked shared library arm64
 *
 * But I'm not sure if our code is supposed to be able to use it, and how.
 */
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

/**
 * Return the path to the `ffmpeg` binary.
 *
 * At runtime, the FFmpeg binary is present in a path like (macOS example):
 * `ente.app/Contents/Resources/app.asar.unpacked/node_modules/ffmpeg-static/ffmpeg`
 */
const ffmpegBinaryPath = () => {
    // This substitution of app.asar by app.asar.unpacked is suggested by the
    // ffmpeg-static library author themselves:
    // https://github.com/eugeneware/ffmpeg-static/issues/16
    return pathToFfmpeg!.replace("app.asar", "app.asar.unpacked");
};

/**
 * A variant of {@link ffmpegExec} adapted to work with streams so that it can
 * handle the MP4 conversion of large video files.
 *
 * @param inputFilePath The path to a file on the user's local file system. This
 * is the video we want to convert.
 *
 * @param outputFilePath The path to a file on the user's local file system where
 * we should write the converted MP4 video.
 */
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

/**
 * A bespoke variant of {@link ffmpegExec} for generation of HLS playlists for
 * videos.
 *
 * Overview of the cases:
 *
 *     H.264, <= 10 MB              - Skip
 *     H.264, <= 4000 kb/s bitrate  - Don't re-encode video stream
 *     !HDR, <= 2000 kb/s bitrate   - Don't apply the scale+fps filter
 *     HDR                          - Apply tonemap (zscale+tonemap+zscale)
 *
 * Example invocation:
 *
 *     ffmpeg -i in.mov -vf "scale='if(lt(iw,ih),min(720,iw),-2)':'if(lt(iw,ih),-2,min(720,ih))',fps=30,zscale=transfer=linear,tonemap=tonemap=hable:desat=0,zscale=primaries=709:transfer=709:matrix=709,format=yuv420p" -c:v libx264 -c:a aac -f hls -hls_key_info_file out.m3u8.info -hls_list_size 0 -hls_flags single_file out.m3u8
 *
 * See: [Note: Preview variant of videos]
 *
 * @param inputFilePath The path to a file on the user's local file system. This
 * is the video we want to generate an streamable HLS playlist for.
 *
 * @param outputPathPrefix The path to unique, unused and temporary prefix on
 * the user's local file system. This function will write the generated HLS
 * playlist and video segments under this prefix.
 *
 * @param fileID The ID of the {@link EnteFile} whose HLS playlist we are
 * generating.
 *
 * @param fetchURL The fully resolved API URL for obtaining pre-signed S3 URLs
 * for uploading the generated video segment file.
 *
 * @param authToken A token that can be used to make API request to
 * {@link fetchURL}.
 *
 * @returns The path to the file on the user's file system containing the
 * generated HLS playlist, and other metadata about the generated video stream.
 *
 * If the video is such that it doesn't require stream generation, then this
 * function returns `undefined`.
 */
const ffmpegGenerateHLSPlaylistAndSegments = async (
    inputFilePath: string,
    outputPathPrefix: string,
    fileID: number,
    fetchURL: string,
    authToken: string,
): Promise<FFmpegGenerateHLSPlaylistAndSegmentsResult | undefined> => {
    const { isH264, isHDR, bitrate } =
        await detectVideoCharacteristics(inputFilePath);

    log.debugString(JSON.stringify({ isH264, isHDR, bitrate }));

    // If the video is smaller than 10 MB, and already H.264 (the codec we are
    // going to use for the conversion), then a streaming variant is not much
    // use. Skip such cases.
    //
    // See also: [Note: Marking files which do not need video processing]
    //
    // ---
    //
    // [Note: HEVC/H.265 issues]
    //
    // We've observed two issues out in the wild with HEVC videos:
    //
    // 1. On Linux, HEVC video streams don't play. However, since the audio
    //    stream plays, the browser tells us that the "video" itself is
    //    playable, but the user sees a blank screen with only audio.
    //
    // 2. HEVC + HDR videos taken on an iPhone have a rotation (`Side data:
    //    displaymatrix` in the ffmpeg output) that Chrome (and thus Electron)
    //    doesn't take into account, so these play upside down.
    //
    // Not fully related to this case, but mentioning here as to why both the
    // size and codec need to be checked before skipping stream generation.
    if (isH264) {
        const inputVideoSize = await fs
            .stat(inputFilePath)
            .then((st) => st.size);
        if (inputVideoSize <= 10 * 1024 * 1024 /* 10 MB */) {
            return undefined;
        }
    }

    // If the video is already H.264 with a bitrate less than 4000 kbps, then we
    // do not need to reencode the video stream (by _far_ the costliest part of
    // the HLS stream generation).
    const reencodeVideo = !(isH264 && bitrate && bitrate <= 4000 * 1000);

    // If the bitrate is not too high, then we don't need to rescale the video
    // when generating the video stream. This is not a performance optimization,
    // but more for avoiding making the video size smaller unnecessarily.
    const rescaleVideo = !(bitrate && bitrate <= 2000 * 1000);

    // [Note: Tonemapping HDR to HD]
    //
    // BT.709 ("HD") is a standard that describes things like how color is
    // encoded, the range of values, and their "meaning" - i.e. how to map the
    // values in the video to the pixels on the screen.
    //
    // It is not the only such standard, there are three common examples:
    //
    // - BT.601 ("Standard-Definition" or SD)
    // - BT.709 ("High-Definition" or HD)
    // - BT.2020 ("Ultra-High-Definition" or UHD, aka HDR^).
    //
    // ^ HDR ("High-Dynamic-Range") is an addendum to BT.2020, but for the
    //   discussion here we can treat it as as alias. In particular, not all
    //   BT.2020 videos are HDR, the check we use instead looks for particular
    //   color transfers (see the `isHDRVideo` function below).
    //
    // BT.709 is the most common amongst these for older files out stored on
    // computers, and they conform mostly to the standard (one notable exception
    // is that the BT.709 standard also recommends using the yuv422p pixel
    // format, but de facto yuv420p is used because many video players only
    // support yuv420p).
    //
    // Since BT.709 is the most widely supported standard, we use it when
    // generating the HLS playlist so to allow playback across the widest
    // possible hardware/OS/browser combinations.
    //
    // If we convert HDR to HD without naively, then the colors look washed out
    // compared to the original. To resolve this, we use a ffmpeg filterchain
    // that uses the tonemap filter.
    //
    // However applying this tonemap to videos that are already HD leads to a
    // brightness drop. So we conditionally apply this filter chain only if we
    // can heuristically detect that the video is HDR.
    //
    // See also: [Note: Alternative FFmpeg command for HDR videos].
    //
    // Reference:
    // - https://trac.ffmpeg.org/wiki/colorspace
    const tonemap = isHDR;

    // We want the generated playlist to refer to the chunks as "output.ts".
    //
    // So we arrange things accordingly: We use the `outputPathPrefix` as our
    // working directory, and then ask ffmpeg to generate a playlist with the
    // name "output.m3u8".
    //
    // ffmpeg will automatically place the segments in a file with the same base
    // name as the playlist, but with a ".ts" extension. And since we use the
    // "single_file" option, all the segments will be placed in a file named
    // "output.ts".

    await fs.mkdir(outputPathPrefix);

    const playlistPath = path.join(outputPathPrefix, "output.m3u8");
    const videoPath = path.join(outputPathPrefix, "output.ts");

    // A file into which we'll redirect ffmpeg's stderr.
    //
    // [Note: ERR_CHILD_PROCESS_STDIO_MAXBUFFER]
    //
    // For very large videos, the stderr output of ffmpeg may cause the stdio
    // max buffer size limits to be exceeded, raising the following error:
    //
    //     RangeError [ERR_CHILD_PROCESS_STDIO_MAXBUFFER]: stderr maxBuffer length exceeded
    //
    // So instead of capturing the stderr normally, we redirect it to a
    // temporary file, and then read it from there to extract the video
    // dimensions.
    const stderrPath = path.join(outputPathPrefix, "stderr.txt");

    // Generate a cryptographically secure random key (16 bytes).
    const keyBytes = randomBytes(16);
    const keyB64 = keyBytes.toString("base64");

    // Convert it to a data: URI that will be added to the playlist.
    const keyURI = `data:text/plain;base64,${keyB64}`;

    // Determine two paths - one where we will write the key itself, and where
    // we will write the "key info" that provides ffmpeg the `keyURI` and the
    // `keyPath;.
    const keyPath = playlistPath + ".key";
    const keyInfoPath = playlistPath + ".key-info";

    // Generate a "key info":
    //
    // - the first line specifies the key URI that is written into the playlist.
    // - the second line specifies the path to the local file system file from
    //   where ffmpeg should read the key.
    //
    // [Note: ffmpeg newlines]
    //
    // Tested on Windows that ffmpeg recognizes these lines correctly. In
    // general, ffmpeg tends to expect input and write output the Unix way (\n),
    // even when we're running on Windows.
    //
    // - The ffmetadata and the HLS playlist file generated by ffmpeg uses \n
    //   separators, even on Windows.
    // - The HLS key info file, expected as an input by ffmpeg, works fine when
    //   \n separated even on Windows.
    //
    const keyInfo = [keyURI, keyPath].join("\n");

    // Overview:
    //
    // - Video H.264 HD 720p (max) 30fps.
    // - Audio AAC 128kbps.
    // - Encrypted HLS playlist with a single file containing all the chunks.
    //
    // Reference:
    // - `man ffmpeg-all`
    // - https://trac.ffmpeg.org/wiki/Encode/H.264
    //
    const command = [
        ffmpegBinaryPath(),
        // Reduce the amount of output lines we have to parse.
        ["-hide_banner"],
        // Input file. We don't need any extra options that apply to the input file.
        "-i",
        inputFilePath,
        // The remaining options apply to the next output file (`playlistPath`).
        reencodeVideo
            ? [
                  // `-vf` creates a filter graph for the video stream. It is a
                  // comma separated list of filters chained together, e.g.
                  // `filter1=key=value:key=value.filter2=key=value`.
                  "-vf",
                  [
                      // Do the rescaling to even number of pixels always if the
                      // tonemapping is going to be applied subsequently,
                      // otherwise the tonemapping will fail with "image
                      // dimensions must be divisible by subsampling factor".
                      //
                      // While we add the extra condition here for completeness,
                      // it won't usually matter since a non-BT.709 video is
                      // likely using a new codec, and as such would've a high
                      // enough bitrate to require rescaling anyways.
                      rescaleVideo || tonemap
                          ? [
                                // Scale smaller dimension to 720p (or keep
                                // original if less than 720p). Portrait videos
                                // scale width, landscape videos scale height.
                                // -2 keeps aspect ratio with even pixel count.
                                "scale='if(lt(iw,ih),min(720,iw),-2)':'if(lt(iw,ih),-2,min(720,ih))'",
                                // Convert the video to a constant 30 fps,
                                // duplicating or dropping frames as necessary.
                                "fps=30",
                            ]
                          : [],
                      // Convert the colorspace if the video is HDR. Before
                      // conversion, tone map colors so that they work the same
                      // across the change in the dyamic range.
                      //
                      // 1. The tonemap filter only works linear light, so we
                      //    first use zscale with transfer=linear to linearize
                      //    the input.
                      //
                      // 2. Then we use the tonemap, with the hable option that
                      //    is best for preserving details. desat=0 turns off
                      //    the default desaturation.
                      //
                      // 3. Use zscale again to "convert to BT.709" by asking it
                      //    to set the all three of color primaries, transfer
                      //    characteristics and colorspace matrix to 709 (Note:
                      //    the constants specified in the tonemap filter help
                      //    do not include the "bt" prefix)
                      //
                      // See: https://ffmpeg.org/ffmpeg-filters.html#tonemap-1
                      //
                      // See: [Note: Tonemapping HDR to HD]
                      tonemap
                          ? [
                                "zscale=transfer=linear",
                                "tonemap=tonemap=hable:desat=0",
                                "zscale=primaries=709:transfer=709:matrix=709",
                            ]
                          : [],
                      // Output using the well supported pixel format: 8-bit YUV
                      // planar color space with 4:2:0 chroma subsampling.
                      "format=yuv420p",
                  ]
                      .flat()
                      .join(","),
              ]
            : [],
        reencodeVideo
            ? // Video codec H.264
              //
              // - `-c:v libx264` converts the video stream to the H.264 codec.
              //
              // - We use CRF 23 (default) for quality, but cap the bitrate at
              //   2000 kbps using `-maxrate` to ensure smaller bitrates are
              //   preserved while preventing CRF from exceeding 2000 kbps.
              //
              // - `-bufsize` is set to 2x maxrate for smooth rate control.
              //
              // - We don't supply a preset, it'll use the default ("medium").
              ["-c:v", "libx264", "-maxrate", "2000k", "-bufsize", "4000k"]
            : // Keep the video stream unchanged
              ["-c:v", "copy"],
        // Audio codec AAC
        //
        // - `-c:a aac` converts the audio stream to use the AAC codec
        //
        // - We don't supply a bitrate, it'll use the AAC default 128k bps.
        ["-c:a", "aac"],
        // Generate a HLS playlist.
        ["-f", "hls"],
        // Tell ffmpeg where to find the key, and the URI for the key to write
        // into the generated playlist. Implies "-hls_enc 1".
        ["-hls_key_info_file", keyInfoPath],
        // Generate as many playlist entries as needed (default limit is 5).
        ["-hls_list_size", "0"],
        // Place all the video segments within the same .ts file (with the same
        // path as the playlist file but with a ".ts" extension).
        ["-hls_flags", "single_file"],
        // Output path where the playlist should be generated.
        playlistPath,
    ].flat();

    let dimensions: { width: number; height: number };
    let videoSize: number;
    let videoObjectID: string;

    try {
        // Write the key and the keyInfo to their desired paths.
        await Promise.all([
            fs.writeFile(keyPath, keyBytes),
            fs.writeFile(keyInfoPath, keyInfo, { encoding: "utf8" }),
        ]);

        // Tack on the redirection after constructing the command.
        const commandWithRedirection = `${shellescape(command)} 2>${stderrPath}`;

        // Run the ffmpeg command to generate the HLS playlist and segments.
        //
        // Note: Depending on the size of the input file, this may take long!
        await execAsyncWorker(commandWithRedirection);

        // While ffmpeg uses \n as the line separator in the generated playlist
        // file on Windows too, add an extra safety check that should fail the
        // HLS generation if this doesn't hold. See: [Note: ffmpeg newlines].
        if (process.platform == "win32") {
            const playlistText = await fs.readFile(playlistPath, "utf-8");
            if (playlistText.includes("\r\n"))
                throw new Error("Unexpected Windows newlines in playlist");
        }

        // Determine the dimensions of the generated video from the stderr
        // output produced by ffmpeg during the conversion.
        dimensions = await detectVideoDimensions(stderrPath);

        // Find the size of the generated video segments by reading the size of
        // the generated .ts file.
        videoSize = await fs.stat(videoPath).then((st) => st.size);

        videoObjectID = await uploadVideoSegments(
            videoPath,
            videoSize,
            fileID,
            fetchURL,
            authToken,
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
            // ffmpeg writes a /path/output.ts.tmp, clear it out too.
            deletePathIgnoringErrors(videoPath + ".tmp"),
        ]);
    }

    return { playlistPath, dimensions, videoSize, videoObjectID };
};

/**
 * A variant of {@link deletePathIgnoringErrors} (which we can't directly use in
 * the utility process). It unconditionally removes the item at the provided
 * path; in particular, this will not raise any errors if there is no item at
 * the given path (as may be expected to happen when we run during catch
 * handlers).
 */
const deletePathIgnoringErrors = async (tempFilePath: string) => {
    try {
        await fs.rm(tempFilePath, { force: true });
    } catch (e) {
        log.error(`Could not delete item at path ${tempFilePath}`, e);
    }
};

/**
 * A regex that matches the first line of the form
 *
 *     Stream #0:0: Video: h264 (High 10) ([27][0][0][0] / 0x001B), yuv420p10le(tv, bt2020nc/bt2020/arib-std-b67), 1920x1080, 30 fps, 30 tbr, 90k tbn
 *
 * The part after Video: is the first capture group.
 *
 * Another example:
 *
 *     Stream #0:1[0x2](und): Video: h264 (Constrained Baseline) (avc1 / 0x31637661), yuv420p(progressive), 480x270 [SAR 1:1 DAR 16:9], 539 kb/s, 29.97 fps, 29.97 tbr, 30k tbn (default)
 */
const videoStreamLineRegex = /Stream #.+: Video:(.+)\r?\n/;

/** {@link videoStreamLineRegex}, but global. */
const videoStreamLinesRegex = /Stream #.+: Video:(.+)\r?\n/g;

/**
 * A regex that matches "<digits> kb/s" preceded by a space. See
 * {@link videoStreamLineRegex} for the context in which it is used.
 */
const videoBitrateRegex = / ([1-9]\d*) kb\/s/;

/**
 * A regex that matches <digits>x<digits> pair preceded by a space. See
 * {@link videoStreamLineRegex} for the context in which it is used.
 *
 * We constrain the digit sequence not to begin with 0 to exclude hexadecimal
 * representations of various constants that ffmpeg prints on this line (e.g.
 * "avc1 / 0x31637661").
 */
const videoDimensionsRegex = / ([1-9]\d*)x([1-9]\d*)/;

interface VideoCharacteristics {
    isH264: boolean;
    isHDR: boolean;
    bitrate: number | undefined;
}

/**
 * Heuristically determine information about the video at the given
 * {@link inputFilePath}:
 *
 * - If is encoded using H.264 codec.
 * - If it is HDR.
 * - Its bitrate.
 *
 * The defaults are tailored for the cases in which these conditions are used,
 * so that even if we get the detection wrong we'll only end up encoding videos
 * that could've possibly been skipped as an optimization.
 *
 * [Note: Parsing CLI output might break on ffmpeg updates]
 *
 * This function tries to determine the these bits of information about the
 * given video by scanning the ffmpeg info output for the video stream line, and
 * doing various string matches and regex extractions.
 *
 * Needless to say, while this works currently, this is liable to break in the
 * future. So if something stops working after updating ffmpeg, look here!
 *
 * Ideally, we'd have done this using `ffprobe`, but we don't have the ffprobe
 * binary at hand, so we make do by grepping the log output of ffmpeg.
 *
 * For reference,
 *
 * - codec and colorspace are printed by the `avcodec_string` function in the
 *   ffmpeg source:
 *   https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/avcodec.c
 *
 * - bitrate is printed by the `dump_stream_format` function in `dump.c`.
 */
const detectVideoCharacteristics = async (inputFilePath: string) => {
    const videoInfo = await pseudoFFProbeVideo(inputFilePath);
    const videoStreamLine = videoStreamLineRegex.exec(videoInfo)?.at(1)?.trim();

    // Since the checks are heuristic, start with defaults that would cause the
    // codec conversion to happen, even if it is unnecessary.
    const res: VideoCharacteristics = {
        isH264: false,
        isHDR: false,
        bitrate: undefined,
    };
    if (!videoStreamLine) return res;

    res.isH264 = videoStreamLine.startsWith("h264 ");

    // Same check as `isHDRVideo`.
    res.isHDR =
        videoStreamLine.includes("smpte2084") ||
        videoStreamLine.includes("arib-std-b67");

    // The regex matches "\d kb/s", but there can be other units for the
    // bitrate. However, (a) "kb/s" is the most common for videos out in the
    // wild, and (b) even if we guess wrong it we'll just do "-v:c x264" instead
    // of "-v:c copy", so only unnecessary processing but no change in output.
    const brs = videoBitrateRegex.exec(videoStreamLine)?.at(0);
    if (brs) {
        const br = parseInt(brs, 10);
        if (br) res.bitrate = br * 1000;
    }

    return res;
};

/**
 * Heuristically detect the dimensions of the given video from the log output of
 * the ffmpeg invocation during the HLS playlist generation.
 *
 * This function tries to determine the width and height of the generated video
 * from the output log written by ffmpeg on its stderr during the generation
 * process, scanning it for the last video stream line, and trying to match a
 * "<digits>x<digits>" regex.
 *
 * See: [Note: Parsing CLI output might break on ffmpeg updates].
 */
const detectVideoDimensions = async (stderrPath: string) => {
    // Instead of reading the stderr directly off the child_process.exec, we
    // wrote it to a file to avoid hitting the max stdio buffer limits. Read it
    // from there.
    const conversionStderr = await fs.readFile(stderrPath, "utf-8");

    // There is a nicer way to do it - by running `pseudoFFProbeVideo` on the
    // generated playlist. However, that playlist includes a data URL that
    // specifies the encryption info, and ffmpeg refuses to read that unless we
    // specify the "-allowed_extensions ALL" or something to that effect.
    //
    // Unfortunately, our current ffmpeg binary (5.x) does not support that
    // option. So we instead parse the conversion output itself.
    //
    // This is also nice, since it saves on an extra ffmpeg invocation. But we
    // now need to be careful to find the right video stream line, since the
    // conversion output includes both the input and output video stream lines.
    //
    // To match the right (output) video stream line, we use a global regex, and
    // use the last match since that'd correspond to the single video stream
    // written in the output.
    const videoStreamLine = Array.from(
        conversionStderr.matchAll(videoStreamLinesRegex),
    )
        .at(-1) /* Last Stream...: Video: line in the output */
        ?.at(1); /* First capture group */
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

/**
 * Heuristically detect if the file at given path is a HDR video.
 *
 * This is similar to {@link detectVideoCharacteristics}, and see that
 * function's documentation for all the caveats. Specifically, this function
 * uses an allow-list, and considers any file with color transfer "smpte2084" or
 * "arib-std-b67" to be HDR. Caveats:
 *
 * 1. These particular constants are not guaranteed to be correct; these are
 *    from various internet posts as being used / recommended for detecting HDR.
 *
 * 2. Since we don't have ffprobe, we're not checking the color space value
 *    itself but a substring of the stream line in the ffmpeg stderr output.
 *
 * This check should generally not have false positives (unless something else
 * in the log line triggers #2), but it can have false negative. This is the
 * lesser of the two evils since if we apply the tonemapping to any non-BT.709
 * file, we start getting the "code 3074: no path between colorspaces" error
 * during the JPEG or H.264 conversion.
 *
 * - See: [Note: Alternative FFmpeg command for HDR videos]
 * - See: [Note: Tonemapping HDR to HD]
 *
 * @param inputFilePath The path to a video file on the user's machine.
 *
 * @returns `true` if this file is likely a HDR video. Exceptions are treated as
 * `false` to make this function safe to invoke without breaking the happy path.
 */
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

/**
 * Return the stderr of ffmpeg in an attempt to gain information about the video
 * at the given {@link inputFilePath}.
 *
 * We don't have the ffprobe binary at hand, which is why we need to use this
 * alternative. See: [Note: Parsing CLI output might break on ffmpeg updates]
 *
 * @returns the stderr of ffmpeg after running it on the input file. The exact
 * command we run is:
 *
 *     ffmpeg -i in.mov -an -frames:v 0 -f null - 2>info.txt
 *
 * And the returned string is the contents of the `info.txt` thus produced.
 */
const pseudoFFProbeVideo = async (inputFilePath: string) => {
    const command = [
        ffmpegPathPlaceholder,
        // Reduce the amount of output lines we have to parse.
        ["-hide_banner"],
        ["-i", inputPathPlaceholder],
        "-an",
        ["-frames:v", "0"],
        ["-f", "null"],
        "-",
    ].flat();

    const cmd = substitutePlaceholders(command, inputFilePath, /* NA */ "");

    const { stderr } = await execAsyncWorker(cmd);

    return stderr;
};

/**
 * Upload the file at the given {@link videoFilePath} to the provided pre-signed
 * URL(s) using a HTTP PUT request.
 *
 * All HTTP requests are retried up to 4 times (1 original + 3 retries) with
 * exponential backoff.
 *
 * See: [Note: Upload HLS video segment from node side].
 *
 * @param videoFilePath The path to the file on the user's file system to
 * upload.
 *
 * @param videoSize The size in bytes of the file at {@link videoFilePath}.
 *
 * @param fileID The ID of the {@link EnteFile} whose video segment this is.
 *
 * @param fetchURL The API URL for fetching pre-signed upload URLs.
 *
 * @param authToken The user's auth token for use with {@link fetchURL}.
 *
 * @return The object ID of the uploaded file on remote storage.
 */
const uploadVideoSegments = async (
    videoFilePath: string,
    videoSize: number,
    fileID: number,
    fetchURL: string,
    authToken: string,
) => {
    // Self hosters might be using Cloudflare's free plan which (currently) has
    // a maximum request size of 100 MB. Keeping a bit of margin for headers,
    const partSize = 96 * 1024 * 1024; /* 96 MB */
    const partCount = Math.ceil(videoSize / partSize);

    const { objectID, url, partURLs, completeURL } =
        await getFilePreviewDataUploadURL(
            partCount,
            fileID,
            fetchURL,
            authToken,
        );

    if (url) {
        await uploadVideoSegmentsSingle(videoFilePath, videoSize, url);
    } else if (partURLs && completeURL) {
        await uploadVideoSegmentsMultipart(
            videoFilePath,
            videoSize,
            partSize,
            partURLs,
            completeURL,
        );
    } else {
        throw new Error("Malformed upload URLs");
    }

    return objectID;
};

const FilePreviewDataUploadURLResponse = z.object({
    /**
     * The objectID with which this uploaded data can be referred to post upload
     * (e.g. when invoking {@link putVideoData}).
     */
    objectID: z.string(),
    /**
     * A pre-signed URL that can be used to upload the file.
     *
     * This will be present only if we requested a singular object upload URL.
     */
    url: z.string().nullish().transform(nullToUndefined),
    /**
     * A list of pre-signed URLs that can be used to upload parts of a multipart
     * upload of the uploaded data.
     *
     * This will be present only if we requested a multipart upload URLs for the
     * object by setting `isMultiPart` true in the request.
     */
    partURLs: z.string().array().nullish().transform(nullToUndefined),
    /**
     * A pre-signed URL that can be used to finalize the multipart upload.
     *
     * This will be present only if we requested a multipart upload URLs for the
     * object by setting `isMultiPart` true in the request.
     */
    completeURL: z.string().nullish().transform(nullToUndefined),
});

/**
 * Obtain a pre-signed URL(s) that can be used to upload the "file preview data"
 * of type "vid_preview".
 *
 * This will be the file containing the encrypted video segments which the
 * "vid_preview" HLS playlist for the file would refer to.
 *
 * @param partCount If greater than 1, then we request for a multipart upload.
 */
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
) =>
    retryEnsuringHTTPOk(() =>
        // net.fetch is 40-50x slower than the native fetch for this particular
        // PUT request. This is easily reproducible - replace `fetch` with
        // `net.fetch`, then even on localhost the PUT requests start taking a
        // minute or so, while they take second(s) with node's native fetch.
        fetch(objectUploadURL, {
            method: "PUT",
            // net.fetch deduces and inserts a content-length for us, when we
            // use the node native fetch then we need to provide it explicitly.
            headers: {
                ...publicRequestHeaders(desktopAppVersion()),
                "Content-Length": `${videoSize}`,
            },
            // See: [Note: duplex param required for stream body]
            // @ts-expect-error ^see note above
            duplex: "half",
            // The cast is needed because TS checks this against DOM fetch, but
            // at runtime this utility process calls Node fetch.
            // See: [Note: Node and web stream type mismatch].
            body: Readable.toWeb(
                fs_.createReadStream(videoFilePath),
            ) as unknown as BodyInit,
        }),
    );

/**
 * Retry a async operation on failure up to 4 times (1 original + 3 retries)
 * with exponential backoff.
 *
 * This is an inlined but bespoke reimplementation of `retryEnsuringHTTPOk` from
 * `web/packages/base/http.ts`
 *
 * - We don't have the rest of the scaffolding used by that function, which is
 *   why it is intially inlined bespoked.
 *
 * - It handles the specific use case of uploading videos since generating the
 *   HLS stream is a fairly expensive operation, so a retry to discount
 *   transient network issues is called for. The number of retries and their
 *   gaps are same as the "background" `retryProfile` of the web implementation.
 *
 * - Later it was discovered that net.fetch is much slower than node's native
 *   fetch, so this implementation has further diverged.
 *
 * - This also moved to a utility process, where we also have a more restricted
 *   ability to import electron API.
 */
const retryEnsuringHTTPOk = async (request: () => Promise<Response>) => {
    const waitTimeBeforeNextTry = [10000, 30000, 120000];

    while (true) {
        try {
            const res = await request();
            if (res.ok) /* Success. */ return res;
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
) => {
    // The part we're currently uploading.
    let partNumber = 0;
    // A rolling offset into the file.
    let start = 0;
    // See `createMultipartUploadRequestBody` in the web code for a more
    // expansive and documented version of this XML body construction.
    const completionXML = ["<CompleteMultipartUpload>"];
    for (const partUploadURL of partUploadURLs) {
        partNumber += 1;
        const size = Math.min(start + partSize, videoSize) - start;
        const end = start + size - 1;
        const res = await retryEnsuringHTTPOk(() =>
            fetch(partUploadURL, {
                method: "PUT",
                headers: {
                    ...publicRequestHeaders(desktopAppVersion()),
                    "Content-Length": `${size}`,
                },
                // See: [Note: duplex param required for stream body]
                // @ts-expect-error ^see note above
                duplex: "half",
                // The cast is needed because TS checks this against DOM fetch,
                // but at runtime this utility process calls Node fetch.
                // See: [Note: Node and web stream type mismatch].
                body: Readable.toWeb(
                    // start and end are inclusive 0-indexed range of bytes to
                    // read from the file.
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

/**
 * A regex that matches the first line of the form
 *
 *   Duration: 00:00:03.13, start: 0.000000, bitrate: 16088 kb/s
 *
 * The part after Duration: and until the first non-digit or colon is the first
 * capture group, while after the dot is an optional second capture group.
 */
const videoDurationLineRegex = /\s\sDuration: ([0-9:]+)(.[0-9]+)?/;

/**
 * Determine the duration of the video at the given {@link inputFilePath}.
 *
 * While the detection works for all known cases, it is still heuristic because
 * it uses ffmpeg output instead of ffprobe (which we don't have access to).
 * See: [Note: Parsing CLI output might break on ffmpeg updates].
 */
export const ffmpegDetermineVideoDuration = async (inputFilePath: string) => {
    const videoInfo = await pseudoFFProbeVideo(inputFilePath);
    const matches = videoDurationLineRegex.exec(videoInfo);

    const fail = () => {
        throw new Error(`Cannot parse video duration '${matches?.at(0)}'`);
    };

    // The HH:mm:ss.
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

    // Optional subseconds.
    const ss = parseFloat(`0${matches?.at(2) ?? ""}`);

    // Follow the same round up behaviour that the web side uses.
    const duration = Math.ceil(h * 3600 + m * 60 + s + ss);
    if (!duration) fail();
    return duration;
};
