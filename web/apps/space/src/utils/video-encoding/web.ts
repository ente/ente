import { logToDisk } from "ente-base/log-web";
import { PromiseQueue } from "ente-utils/promise";
import {
    ALL_FORMATS,
    BlobSource,
    BufferSource,
    BufferTarget,
    canEncodeAudio,
    CanvasSink,
    Conversion,
    Input,
    Mp4OutputFormat,
    Output,
    Quality,
    type ConversionAudioOptions,
    type ConversionVideoOptions,
} from "mediabunny";
import type { SpacePostVideoEdit } from "../post-video";

const videoTaskQueue = new PromiseQueue<unknown>();

const canUseSoftwareVideo = () =>
    !navigator.userAgent.includes("AppleWebKit/") ||
    navigator.userAgent.includes("Chrome/");

export const determineVideoDurationWeb = (blob: Blob, signal?: AbortSignal) =>
    runVideoTask("duration", blob, (input) => input.computeDuration(), signal);

export const determineVideoInfoWeb = (blob: Blob, signal?: AbortSignal) =>
    runVideoTask(
        "metadata",
        blob,
        async (input) => {
            const track = await input.getPrimaryVideoTrack();
            if (!track) throw new Error("This file has no readable video.");
            const [endTimestamp, firstTimestamp, width, height] =
                await Promise.all([
                    track.computeDuration(),
                    track.getFirstTimestamp(),
                    track.getDisplayWidth(),
                    track.getDisplayHeight(),
                ]);
            const startTime = Math.max(0, firstTimestamp);
            const duration = endTimestamp - startTime;
            if (!Number.isFinite(duration) || duration <= 0)
                throw new Error("This video has no readable duration.");
            return { duration, width, height, startTime };
        },
        signal,
    );

export const extractVideoFramesWeb = (
    blob: Blob,
    times: number[],
    maxDimension: number,
    signal?: AbortSignal,
) =>
    runVideoTask(
        "frames",
        blob,
        async (input, signal) => {
            const track = await input.getPrimaryVideoTrack();
            if (!track)
                throw new Error("This browser can't preview this video.");
            const [firstTimestamp, endTimestamp] = await Promise.all([
                track.getFirstTimestamp(),
                track.computeDuration(),
            ]);
            const start = Math.max(0, firstTimestamp);
            const timestamps = times.map((time) =>
                Math.max(start, Math.min(start + time, endTimestamp - 0.001)),
            );
            try {
                if (!(await track.canDecode()))
                    throw new Error("This browser can't preview this video.");
                const [width, height] = await Promise.all([
                    track.getDisplayWidth(),
                    track.getDisplayHeight(),
                ]);
                const scale = Math.min(
                    1,
                    maxDimension / Math.max(width, height),
                );
                const sink = new CanvasSink(track, {
                    width: Math.max(1, Math.round(width * scale)),
                    height: Math.max(1, Math.round(height * scale)),
                    fit: "contain",
                });
                const frames: HTMLCanvasElement[] = [];
                for await (const frame of sink.canvasesAtTimestamps(
                    timestamps,
                )) {
                    signal.throwIfAborted();
                    if (!frame)
                        throw new Error(
                            "Couldn't read a video frame. Please try again.",
                        );
                    frames.push(frame.canvas as HTMLCanvasElement);
                }
                return frames;
            } catch (error) {
                signal.throwIfAborted();
                if (
                    !canUseSoftwareVideo() ||
                    (error instanceof Error &&
                        (error.name === "AbortError" ||
                            error.name === "TimeoutError"))
                )
                    throw error;
                const hdr = await track.hasHighDynamicRange();
                input.dispose();
                const { extractSoftwareVideoFrames } =
                    await import("./software");
                signal.throwIfAborted();
                return extractSoftwareVideoFrames(
                    blob,
                    timestamps,
                    maxDimension,
                    hdr,
                    signal,
                );
            }
        },
        signal,
    );

export const transcodeVideoWeb = (
    blob: Blob,
    edit: SpacePostVideoEdit,
    signal?: AbortSignal,
) =>
    runVideoTask(
        "export",
        blob,
        async (input, signal) => {
            const videoTrack = await input.getPrimaryVideoTrack();
            if (!videoTrack)
                throw new Error("This file has no readable video.");
            const start = Math.max(0, await videoTrack.getFirstTimestamp());
            const trim = { start: start + edit.start, end: start + edit.end };
            const softwareExport = async () => {
                const hdr = await videoTrack.hasHighDynamicRange();
                input.dispose();
                const { transcodeSoftwareVideo } = await import("./software");
                signal.throwIfAborted();
                return transcodeSoftwareVideo(
                    blob,
                    { ...edit, ...trim },
                    hdr,
                    signal,
                );
            };
            try {
                if (!(await videoTrack.canDecode())) {
                    throw new Error("This browser can't decode this video.");
                }
                let audio: ConversionAudioOptions = edit.muted
                    ? { discard: true }
                    : { codec: "aac" };
                const audioTrack = edit.muted
                    ? null
                    : await input.getPrimaryAudioTrack();
                if (audioTrack && (await audioTrack.getCodec()) !== "aac") {
                    const quality = new Quality({ bitrate: 128_000 });
                    audio = { codec: "aac", quality };
                    if (
                        !(await canEncodeAudio("aac", {
                            numberOfChannels:
                                await audioTrack.getNumberOfChannels(),
                            sampleRate: await audioTrack.getSampleRate(),
                            quality,
                        }))
                    ) {
                        const { registerAacEncoder } =
                            await import("@mediabunny/aac-encoder");
                        signal.throwIfAborted();
                        registerAacEncoder();
                    }
                }
                let output = new Output({
                    format: new Mp4OutputFormat({ fastStart: "in-memory" }),
                    target: new BufferTarget(),
                });
                let conversion: Conversion | undefined;
                let encodedInput: Input | undefined;
                const cancel = () => {
                    void (conversion ? conversion.cancel() : output.cancel());
                    encodedInput?.dispose();
                };
                signal.addEventListener("abort", cancel, { once: true });
                try {
                    signal.throwIfAborted();
                    conversion = await Conversion.init({
                        input,
                        output,
                        tracks: "primary",
                        trim,
                        copy: { boundaryPolicy: "shrink" },
                        tags: {},
                        showWarnings: false,
                        video: async (
                            track,
                        ): Promise<ConversionVideoOptions> => {
                            const [width, height, hdr] = await Promise.all([
                                track.getDisplayWidth(),
                                track.getDisplayHeight(),
                                track.hasHighDynamicRange(),
                            ]);
                            const scale = Math.min(
                                1,
                                1920 / Math.max(width, height),
                                1080 / Math.min(width, height),
                            );
                            const outputWidth = Math.max(
                                2,
                                Math.floor((width * scale) / 2) * 2,
                            );
                            const outputHeight = Math.max(
                                2,
                                Math.floor((height * scale) / 2) * 2,
                            );
                            let context: CanvasRenderingContext2D | null = null;
                            if (hdr) {
                                const canvas = document.createElement("canvas");
                                canvas.width = outputWidth;
                                canvas.height = outputHeight;
                                context = canvas.getContext("2d", {
                                    colorSpace: "srgb",
                                });
                                if (!context)
                                    throw new Error(
                                        "Couldn't prepare the video frames.",
                                    );
                            }
                            const colorContext = context;
                            return {
                                codec: "avc",
                                width: outputWidth,
                                height: outputHeight,
                                fit: "contain",
                                frameRate: 30,
                                quality: new Quality({ bitrate: 4_000_000 }),
                                keyFrameInterval: 2,
                                allowTransformationMetadata: false,
                                process: colorContext
                                    ? (sample) => {
                                          sample.draw(
                                              colorContext,
                                              0,
                                              0,
                                              outputWidth,
                                              outputHeight,
                                          );
                                          return colorContext.canvas;
                                      }
                                    : undefined,
                            };
                        },
                        audio,
                    });
                    signal.throwIfAborted();
                    if (
                        !conversion.isValid ||
                        conversion.discardedTracks.some(
                            (track) => track.reason !== "discarded_by_user",
                        )
                    ) {
                        throw new Error(
                            "This browser can't export this video's format. Try another video or browser.",
                        );
                    }
                    await conversion.execute();
                    signal.throwIfAborted();
                    if (!output.target.buffer)
                        throw new Error("Couldn't export this video.");
                    encodedInput = new Input({
                        formats: ALL_FORMATS,
                        source: new BufferSource(output.target.buffer),
                    });
                    output = new Output({
                        format: new Mp4OutputFormat({ fastStart: "in-memory" }),
                        target: new BufferTarget(),
                    });
                    conversion = await Conversion.init({
                        input: encodedInput,
                        output,
                        tracks: "primary",
                        trim: { start: 0, end: edit.end - edit.start },
                        copy: { mode: "forced", boundaryPolicy: "shrink" },
                        tags: {},
                        showWarnings: false,
                    });
                    signal.throwIfAborted();
                    if (
                        !conversion.isValid ||
                        conversion.discardedTracks.length
                    )
                        throw new Error("Couldn't trim the exported video.");
                    for (const track of output.tracks)
                        delete track.metadata.name;
                    await conversion.execute();
                    signal.throwIfAborted();
                    if (!output.target.buffer)
                        throw new Error("Couldn't export this video.");
                    return new Uint8Array(output.target.buffer);
                } finally {
                    signal.removeEventListener("abort", cancel);
                    if (output.state !== "finalized") {
                        if (conversion?.state !== "canceled")
                            await conversion?.cancel();
                        await output.cancel();
                    }
                    encodedInput?.dispose();
                }
            } catch (error) {
                signal.throwIfAborted();
                if (
                    !canUseSoftwareVideo() ||
                    (error instanceof Error &&
                        (error.name === "AbortError" ||
                            error.name === "TimeoutError"))
                )
                    throw error;
                return softwareExport();
            }
        },
        signal,
        300_000,
    );

const runVideoTask = <T>(
    stage: string,
    blob: Blob,
    task: (input: Input, signal: AbortSignal) => Promise<T>,
    signal?: AbortSignal,
    timeout = 60_000,
): Promise<T> => {
    const pending = videoTaskQueue.add(async () => {
        signal?.throwIfAborted();
        const input = new Input({
            formats: ALL_FORMATS,
            source: new BlobSource(blob),
        });
        const controller = new AbortController();
        const cancel = () => controller.abort(signal?.reason);
        const dispose = () => input.dispose();
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
        controller.signal.addEventListener("abort", dispose, { once: true });
        const startedAt = Date.now();
        logToDisk(
            `[info] Space video stage=${stage} started bytes=${blob.size}`,
        );
        try {
            const result = await task(input, controller.signal);
            controller.signal.throwIfAborted();
            logToDisk(
                `[info] Space video stage=${stage} completed elapsedMs=${Date.now() - startedAt}`,
            );
            return result;
        } catch (error) {
            logToDisk(
                `[error] Space video stage=${stage} ${signal?.aborted ? "canceled" : controller.signal.aborted ? "timeout" : "failed"} elapsedMs=${Date.now() - startedAt} error=${JSON.stringify(error instanceof Error ? error.toString() : error)}`,
            );
            controller.signal.throwIfAborted();
            throw error;
        } finally {
            clearTimeout(timer);
            signal?.removeEventListener("abort", cancel);
            controller.signal.removeEventListener("abort", dispose);
            input.dispose();
        }
    }) as Promise<T>;
    if (!signal) return pending;
    return new Promise<T>((resolve, reject) => {
        const abort = () =>
            reject(
                new DOMException("Video processing canceled.", "AbortError"),
            );
        signal.addEventListener("abort", abort, { once: true });
        void pending
            .then(resolve, reject)
            .finally(() => signal.removeEventListener("abort", abort));
        if (signal.aborted) abort();
    });
};
