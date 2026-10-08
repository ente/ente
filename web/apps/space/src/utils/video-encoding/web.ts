import { FFFSType, FFmpeg } from "@ffmpeg/ffmpeg";
import { joinPath } from "ente-base/file-name";
import { newID } from "ente-base/id";
import log from "ente-base/log";
import { logToDisk } from "ente-base/log-web";
import type { FFmpegCommand } from "ente-base/types/ipc";
import { ensureArrayBufferBacked } from "ente-utils/bytes";
import { PromiseQueue } from "ente-utils/promise";
import { z } from "zod";
import { inputPathPlaceholder, outputPathPlaceholder } from "./constants";
import type { VideoTranscodeEdit } from "./web-codecs";

let _ffmpeg: { instance: FFmpeg; ready: Promise<void> } | undefined;

const _ffmpegTaskQueue = new PromiseQueue<unknown>();

const ffmpegLazy = () => {
    if (!_ffmpeg) {
        const instance = new FFmpeg();
        _ffmpeg = { instance, ready: loadFFmpeg(instance) };
    }
    return _ffmpeg;
};

const loadFFmpeg = async (ffmpeg: FFmpeg) => {
    const startedAt = Date.now();
    const timeout = new AbortController();
    const timer = setTimeout(() => {
        timeout.abort();
        ffmpeg.terminate();
    }, 60_000);
    logToDisk("[info] Space video encoder loading");
    try {
        await ffmpeg.load({
            coreURL:
                "https://assets.ente.com/ffmpeg-core-0.12.10/ffmpeg-core.js",
            wasmURL:
                "https://assets.ente.com/ffmpeg-core-0.12.10/ffmpeg-core.wasm",
        });
        logToDisk(
            `[info] Space video encoder loaded elapsedMs=${Date.now() - startedAt}`,
        );
    } catch (error) {
        ffmpeg.terminate();
        if (_ffmpeg?.instance == ffmpeg) _ffmpeg = undefined;
        logToDisk(
            `[error] Space video encoder load ${timeout.signal.aborted ? "timeout" : "failed"} elapsedMs=${Date.now() - startedAt}`,
        );
        if (timeout.signal.aborted)
            throw new Error(
                "The video processor took too long to load. Please try again.",
                { cause: error },
            );
        throw error;
    } finally {
        clearTimeout(timer);
    }
};

export const preloadVideoEncoderWeb = async () => {
    await ffmpegLazy().ready;
};

export const determineVideoDurationWeb = async (
    blob: Blob,
    signal?: AbortSignal,
): Promise<number> =>
    runFFmpegTask(
        "duration",
        blob.size,
        (ffmpeg) => ffprobeExecVideoDuration(ffmpeg, blob),
        signal,
    );

export const determineVideoInfoWeb = (blob: Blob, signal?: AbortSignal) =>
    runFFmpegTask(
        "metadata",
        blob.size,
        (ffmpeg) =>
            withInputMount(ffmpeg, blob, async (inputPath) => {
                const json = await ffprobeOutput(
                    ffmpeg,
                    [
                        "-v",
                        "error",
                        "-select_streams",
                        "v:0",
                        "-show_entries",
                        "format=duration:stream=width,height:stream_side_data=rotation",
                        "-of",
                        "json",
                        "-o",
                        "output.json",
                        inputPath,
                    ],
                    "output.json",
                );
                const info = z
                    .object({
                        format: z.object({
                            duration: z.coerce.number().positive(),
                        }),
                        streams: z
                            .array(
                                z.object({
                                    width: z.number().positive(),
                                    height: z.number().positive(),
                                    side_data_list: z
                                        .array(
                                            z.object({
                                                rotation: z.number().optional(),
                                            }),
                                        )
                                        .optional(),
                                }),
                            )
                            .nonempty(),
                    })
                    .parse(JSON.parse(json));
                const stream = info.streams[0]!;
                const rotation =
                    stream.side_data_list?.find(
                        (data) => data.rotation != undefined,
                    )?.rotation ?? 0;
                const sideways = Math.abs(rotation % 180) == 90;
                return {
                    duration: info.format.duration,
                    width: sideways ? stream.height : stream.width,
                    height: sideways ? stream.width : stream.height,
                };
            }),
        signal,
    );

export const extractVideoFramesWeb = (
    blob: Blob,
    times: number[],
    maxDimension: number,
    signal?: AbortSignal,
) =>
    runFFmpegTask(
        "frames",
        blob.size,
        async (ffmpeg, signal) => {
            const frames: Blob[] = [];
            await withInputMount(ffmpeg, blob, async (inputPath) => {
                const outputPath = newID("frame_") + ".png";
                const hdr = await isHDRVideo(ffmpeg, inputPath);
                try {
                    for (const time of times) {
                        signal.throwIfAborted();
                        const json = await ffprobeOutput(
                            ffmpeg,
                            [
                                "-v",
                                "error",
                                "-select_streams",
                                "v:0",
                                "-read_intervals",
                                `${time}%${time + 1}`,
                                "-show_entries",
                                "packet=pts_time:format=start_time",
                                "-of",
                                "json",
                                "-o",
                                "frame.json",
                                inputPath,
                            ],
                            "frame.json",
                        );
                        const probe = z
                            .object({
                                format: z.object({
                                    start_time: z.coerce.number().optional(),
                                }),
                                packets: z
                                    .array(
                                        z.object({
                                            pts_time: z.coerce.number(),
                                        }),
                                    )
                                    .nonempty(),
                            })
                            .parse(JSON.parse(json));
                        const start = probe.format.start_time ?? 0;
                        const timestamps = probe.packets.map(
                            (packet) => packet.pts_time - start,
                        );
                        const frameTime = timestamps.reduce(
                            (closest, timestamp) =>
                                Math.abs(timestamp - time) <
                                Math.abs(closest - time)
                                    ? timestamp
                                    : closest,
                        );
                        const status = await ffmpeg.exec([
                            "-ss",
                            String(Math.max(0, frameTime - 0.000001)),
                            "-i",
                            inputPath,
                            "-map",
                            "0:v:0",
                            "-frames:v",
                            "1",
                            "-an",
                            "-vf",
                            [
                                `scale=w='min(${maxDimension},iw)':h='min(${maxDimension},ih)':force_original_aspect_ratio=decrease`,
                                ...(hdr
                                    ? [
                                          "zscale=transfer=linear",
                                          "tonemap=tonemap=hable:desat=0",
                                          "zscale=primaries=709:transfer=709:matrix=709",
                                      ]
                                    : []),
                                "format=rgb24",
                                "setsar=1",
                            ].join(","),
                            "-map_metadata",
                            "-1",
                            "-update",
                            "1",
                            outputPath,
                        ]);
                        if (status != 0)
                            throw new Error("Couldn't extract a video frame.");
                        const bytes = await ffmpeg.readFile(outputPath);
                        if (typeof bytes == "string")
                            throw new Error("Expected a video frame.");
                        frames.push(
                            new Blob([ensureArrayBufferBacked(bytes)], {
                                type: "image/png",
                            }),
                        );
                        await ffmpeg.deleteFile(outputPath);
                    }
                } finally {
                    if (ffmpeg.loaded) {
                        const files = await ffmpeg.listDir("/");
                        if (files.some((file) => file.name == outputPath))
                            await ffmpeg.deleteFile(outputPath);
                    }
                }
            });
            return frames;
        },
        signal,
    );

export const transcodeVideoWeb = (
    blob: Blob,
    edit: VideoTranscodeEdit,
    fallbackCommand: FFmpegCommand,
    signal?: AbortSignal,
) =>
    runFFmpegTask(
        "export",
        blob.size,
        async (ffmpeg, signal) => {
            if (
                typeof VideoDecoder !== "undefined" &&
                typeof VideoEncoder !== "undefined"
            ) {
                try {
                    const { encodeVideoWithWebCodecs } =
                        await import("./web-codecs");
                    const result = await withInputMount(
                        ffmpeg,
                        blob,
                        (inputPath) =>
                            encodeVideoWithWebCodecs(
                                ffmpeg,
                                inputPath,
                                blob,
                                edit,
                                signal,
                            ),
                    );
                    if (result) {
                        logToDisk(
                            `[info] Space video encoded encoder=webcodecs bytes=${result.byteLength}`,
                        );
                        return result;
                    }
                } catch {
                    signal.throwIfAborted();
                    logToDisk(
                        "[warn] Space video WebCodecs export failed, using software encoder",
                    );
                }
            }
            signal.throwIfAborted();
            logToDisk("[info] Space video encoding encoder=wasm");
            const result = await ffmpegExec(
                ffmpeg,
                fallbackCommand,
                "mp4",
                blob,
            );
            logToDisk(
                `[info] Space video encoded encoder=wasm bytes=${result.byteLength}`,
            );
            return result;
        },
        signal,
        300_000,
    );

const runFFmpegTask = <T>(
    stage: string,
    bytes: number,
    task: (ffmpeg: FFmpeg, signal: AbortSignal) => Promise<T>,
    signal?: AbortSignal,
    timeout = 60_000,
): Promise<T> => {
    const pending = _ffmpegTaskQueue.add(async () => {
        signal?.throwIfAborted();
        const engine = ffmpegLazy();
        const ffmpeg = engine.instance;
        const controller = new AbortController();
        const cancel = () => controller.abort(signal?.reason);
        const abort = () => {
            ffmpeg.terminate();
            if (_ffmpeg == engine) _ffmpeg = undefined;
        };
        const timer = setTimeout(
            () =>
                controller.abort(
                    new DOMException(
                        "Video processing took too long. Try a shorter clip.",
                        "TimeoutError",
                    ),
                ),
            timeout,
        );
        signal?.addEventListener("abort", cancel, { once: true });
        controller.signal.addEventListener("abort", abort, { once: true });
        const startedAt = Date.now();
        logToDisk(`[info] Space video stage=${stage} started bytes=${bytes}`);
        try {
            await engine.ready;
            controller.signal.throwIfAborted();
            const result = await task(ffmpeg, controller.signal);
            logToDisk(
                `[info] Space video stage=${stage} completed elapsedMs=${Date.now() - startedAt}`,
            );
            return result;
        } catch (error) {
            logToDisk(
                `[error] Space video stage=${stage} ${signal?.aborted ? "canceled" : controller.signal.aborted ? "timeout" : "failed"} elapsedMs=${Date.now() - startedAt}`,
            );
            controller.signal.throwIfAborted();
            throw error;
        } finally {
            clearTimeout(timer);
            signal?.removeEventListener("abort", cancel);
            controller.signal.removeEventListener("abort", abort);
        }
    }) as Promise<T>;
    if (!signal) return pending;
    return new Promise<T>((resolve, reject) => {
        const abort = () => reject(new DOMException("Canceled", "AbortError"));
        signal.addEventListener("abort", abort, { once: true });
        void pending
            .then(resolve, reject)
            .finally(() => signal.removeEventListener("abort", abort));
        if (signal.aborted) abort();
    });
};

const ffmpegExec = async (
    ffmpeg: FFmpeg,
    command: FFmpegCommand,
    outputFileExtension: string,
    blob: Blob,
): Promise<Uint8Array<ArrayBuffer>> => {
    const outputSuffix = outputFileExtension ? "." + outputFileExtension : "";
    const outputPath = newID("out_") + outputSuffix;

    let status: number | undefined;

    return withInputMount(ffmpeg, blob, async (inputPath) => {
        try {
            const startTime = Date.now();

            let resolvedCommand: string[];
            if (Array.isArray(command)) {
                resolvedCommand = command;
            } else {
                const isHDR = await isHDRVideo(ffmpeg, inputPath);
                resolvedCommand = isHDR ? command.hdr : command.default;
            }

            const cmd = substitutePlaceholders(
                resolvedCommand,
                inputPath,
                outputPath,
            );

            status = await ffmpeg.exec(cmd);
            if (status !== 0) {
                log.info(
                    `[wasm] ffmpeg command failed with exit code ${status}: ${cmd.join(" ")}`,
                );
                throw new Error(
                    `ffmpeg command failed with exit code ${status}`,
                );
            }

            const result = await ffmpeg.readFile(outputPath);
            if (typeof result == "string")
                throw new Error("Expected binary data");

            const ms = Date.now() - startTime;
            log.debug(() => `[wasm] ffmpeg ${cmd.join(" ")} (${ms} ms)`);
            return ensureArrayBufferBacked(result);
        } finally {
            try {
                if (ffmpeg.loaded) await ffmpeg.deleteFile(outputPath);
            } catch (e) {
                if (status === 0) {
                    log.error(`Failed to remove output ${outputPath}`, e);
                }
            }
        }
    });
};

const withInputMount = async <T>(
    ffmpeg: FFmpeg,
    blob: Blob,
    f: (inputPath: string) => Promise<T>,
): Promise<T> => {
    const mountDir = "/mount";
    const inputFileName = newID("in_");
    const inputPath = joinPath(mountDir, inputFileName);

    const inputFile = new File([blob], inputFileName);

    try {
        await ffmpeg.createDir(mountDir);
        await ffmpeg.mount(FFFSType.WORKERFS, { files: [inputFile] }, mountDir);

        return await f(inputPath);
    } finally {
        try {
            if (ffmpeg.loaded) await ffmpeg.unmount(mountDir);
        } catch (e) {
            log.error(`Failed to remove mount ${mountDir}`, e);
        }
        try {
            if (ffmpeg.loaded) await ffmpeg.deleteDir(mountDir);
        } catch (e) {
            log.error(`Failed to delete mount directory ${mountDir}`, e);
        }
    }
};

const substitutePlaceholders = (
    command: string[],
    inputFilePath: string,
    outputFilePath: string,
) =>
    command.map((segment) => {
        if (segment == inputPathPlaceholder) {
            return inputFilePath;
        } else if (segment == outputPathPlaceholder) {
            return outputFilePath;
        } else {
            return segment;
        }
    });

const FFProbeOutputIsHDR = z.object({
    streams: z.array(z.object({ color_transfer: z.string().optional() })),
});

const isHDRVideo = async (ffmpeg: FFmpeg, inputFilePath: string) => {
    let jsonString: string | undefined;
    try {
        jsonString = await ffprobeOutput(
            ffmpeg,
            [
                ["-i", inputFilePath],
                ["-show_entries", "stream=color_transfer"],
                ["-select_streams", "v:0"],
                ["-of", "json"],
                ["-o", "output.json"],
            ].flat(),
            "output.json",
        );

        const output = FFProbeOutputIsHDR.parse(JSON.parse(jsonString));
        switch (output.streams[0]?.color_transfer) {
            case "smpte2084":
            case "arib-std-b67":
                return true;
            default:
                return false;
        }
    } catch (e) {
        log.warn("Could not detect HDR status", e);
        if (jsonString) log.debug(() => ["ffprobe-output", jsonString]);
        return false;
    }
};

const ffprobeOutput = async (
    ffmpeg: FFmpeg,
    cmd: string[],
    outputPath: string,
) => {
    let status: number | undefined;

    try {
        status = await ffmpeg.ffprobe(cmd);
        if (status !== 0 && status != -1) {
            log.info(
                `[wasm] ffprobe command failed with exit code ${status}: ${cmd.join(" ")}`,
            );
            throw new Error(`ffprobe command failed with exit code ${status}`);
        }

        const result = await ffmpeg.readFile(outputPath, "utf8");
        if (typeof result != "string") throw new Error("Expected text data");

        return result;
    } finally {
        try {
            if (ffmpeg.loaded) await ffmpeg.deleteFile(outputPath);
        } catch (e) {
            if (status === 0 || status == -1) {
                log.error(`Failed to remove output ${outputPath}`, e);
            }
        }
    }
};

const FFProbeOutputDuration = z.object({
    format: z.object({ duration: z.string() }),
});

const ffprobeExecVideoDuration = async (ffmpeg: FFmpeg, blob: Blob) =>
    withInputMount(ffmpeg, blob, async (inputPath) => {
        const jsonString = await ffprobeOutput(
            ffmpeg,
            [
                ["-i", inputPath],
                ["-v", "error"],
                ["-show_entries", "format=duration"],
                ["-of", "json"],
                ["-o", "output.json"],
            ].flat(),
            "output.json",
        );

        const durationString = FFProbeOutputDuration.parse(
            JSON.parse(jsonString),
        ).format.duration;

        const duration = parseFloat(durationString);
        if (isNaN(duration)) {
            const msg = "Could not parse video duration";
            log.warn(msg, durationString);
            throw new Error(msg);
        }
        return duration;
    });
