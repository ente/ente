import { logToDisk } from "ente-base/log-web";
import type { FFmpegCommand } from "ente-base/types/ipc";
import type { PreparedSpacePostImage } from "utils/post-image";
import { thumbHashBase64FromCanvas } from "utils/thumbhash";
import {
    inputPathPlaceholder,
    outputPathPlaceholder,
} from "./video-encoding/constants";

export interface SpacePostVideoEdit {
    start: number;
    end: number;
    coverTime: number;
    muted: boolean;
}

export interface SpaceVideoInfo {
    duration: number;
    width: number;
    height: number;
}

export const maxSpaceVideoDuration = 10;

const useSoftwareVideoFrames = () =>
    navigator.userAgent.includes("Android") &&
    navigator.userAgent.includes("Firefox/");

export const isSpaceVideoFile = (file: File) =>
    file.type.startsWith("video/") || /\.(mp4|mov|m4v|webm)$/i.test(file.name);

export const initialSpaceVideoEdit = (
    duration: number,
): SpacePostVideoEdit => ({
    start: 0,
    end: Math.min(duration, maxSpaceVideoDuration),
    coverTime: 0,
    muted: false,
});

export const clampVideoCover = (edit: SpacePostVideoEdit) => ({
    ...edit,
    coverTime: Math.max(edit.start, Math.min(edit.coverTime, edit.end - 0.001)),
});

const waitForVideo = (
    video: HTMLVideoElement,
    event: "loadeddata" | "seeked",
    signal?: AbortSignal,
) =>
    new Promise<void>((resolve, reject) => {
        let frameCallback: number | undefined;
        const finish = (error?: Error) => {
            window.clearTimeout(timer);
            if (frameCallback != undefined)
                video.cancelVideoFrameCallback(frameCallback);
            video.removeEventListener(event, ready);
            video.removeEventListener("error", failed);
            signal?.removeEventListener("abort", abort);
            if (error) {
                if (!signal?.aborted)
                    logToDisk(
                        `[error] Space video event=${event} failed code=${video.error?.code ?? 0} readyState=${video.readyState} networkState=${video.networkState}`,
                    );
                reject(error);
            } else resolve();
        };
        const ready = () => finish();
        const failed = () =>
            finish(new Error("This browser can't preview this video."));
        const abort = () => finish(new DOMException("Canceled", "AbortError"));
        const timer = window.setTimeout(
            () => finish(new Error("The video took too long to load.")),
            30_000,
        );
        if (
            event == "loadeddata" &&
            typeof video.requestVideoFrameCallback == "function"
        )
            frameCallback = video.requestVideoFrameCallback(ready);
        else video.addEventListener(event, ready, { once: true });
        video.addEventListener("error", failed, { once: true });
        signal?.addEventListener("abort", abort, { once: true });
        if (signal?.aborted) abort();
    });

const openSpaceVideo = async (file: Blob, signal?: AbortSignal) => {
    signal?.throwIfAborted();
    const video = document.createElement("video");
    const url = URL.createObjectURL(file);
    video.muted = true;
    video.playsInline = true;
    video.preload = "auto";
    const dispose = () => {
        video.pause();
        video.removeAttribute("src");
        video.load();
        URL.revokeObjectURL(url);
    };
    try {
        const ready = waitForVideo(video, "loadeddata", signal);
        video.src = url;
        video.load();
        await ready;
        return { video, dispose };
    } catch (error) {
        dispose();
        throw error;
    }
};

const seekSpaceVideo = async (
    video: HTMLVideoElement,
    time: number,
    signal?: AbortSignal,
) => {
    signal?.throwIfAborted();
    const target = Math.max(0, Math.min(time, video.duration - 0.001));
    if (video.currentTime == target) return;
    const ready = waitForVideo(video, "seeked", signal);
    video.currentTime = target;
    await ready;
};

export const spaceVideoInfo = async (
    file: File,
    signal?: AbortSignal,
): Promise<SpaceVideoInfo> => {
    if (useSoftwareVideoFrames()) {
        const { determineVideoInfoWeb } = await import("./video-encoding/web");
        return determineVideoInfoWeb(file, signal);
    }
    const { video, dispose } = await openSpaceVideo(file, signal);
    try {
        if (!Number.isFinite(video.duration) || video.duration <= 0)
            throw new Error("This video has no readable duration.");
        return {
            duration: video.duration,
            width: video.videoWidth,
            height: video.videoHeight,
        };
    } finally {
        dispose();
    }
};

export const spaceVideoFrames = async (
    file: Blob,
    times: number[],
    maxDimension: number,
    signal?: AbortSignal,
) => {
    const startedAt = Date.now();
    const software = useSoftwareVideoFrames();
    const frames: HTMLCanvasElement[] = [];
    const draw = (source: CanvasImageSource, width: number, height: number) => {
        const scale = Math.min(1, maxDimension / Math.max(width, height));
        const canvas = document.createElement("canvas");
        canvas.width = Math.max(1, Math.round(width * scale));
        canvas.height = Math.max(1, Math.round(height * scale));
        const context = canvas.getContext("2d");
        if (!context) throw new Error("Couldn't prepare the video cover.");
        context.drawImage(source, 0, 0, canvas.width, canvas.height);
        const sample = document.createElement("canvas");
        sample.width = sample.height = 1;
        const sampleContext = sample.getContext("2d")!;
        sampleContext.drawImage(canvas, 0, 0, 1, 1);
        if (sampleContext.getImageData(0, 0, 1, 1).data[3] == 0)
            throw new Error("Couldn't read a video frame. Please try again.");
        frames.push(canvas);
    };
    try {
        if (software) {
            const { extractVideoFramesWeb } =
                await import("./video-encoding/web");
            const blobs = await extractVideoFramesWeb(
                file,
                times,
                maxDimension,
                signal,
            );
            for (const blob of blobs) {
                signal?.throwIfAborted();
                const bitmap = await createImageBitmap(blob);
                try {
                    draw(bitmap, bitmap.width, bitmap.height);
                } finally {
                    bitmap.close();
                }
            }
        } else {
            const { video, dispose } = await openSpaceVideo(file, signal);
            try {
                for (const time of times) {
                    await seekSpaceVideo(video, time, signal);
                    draw(video, video.videoWidth, video.videoHeight);
                }
            } finally {
                dispose();
            }
        }
        logToDisk(
            `[info] Space video frames backend=${software ? "wasm" : "browser"} count=${frames.length} bytes=${file.size} elapsedMs=${Date.now() - startedAt}`,
        );
        return frames;
    } catch (error) {
        if (!signal?.aborted)
            logToDisk(
                `[error] Space video frames failed backend=${software ? "wasm" : "browser"} count=${frames.length}/${times.length} bytes=${file.size} elapsedMs=${Date.now() - startedAt}`,
            );
        throw error;
    }
};

export const spaceVideoCover = async (
    file: Blob,
    time: number,
    signal?: AbortSignal,
): Promise<PreparedSpacePostImage> => {
    const [canvas] = await spaceVideoFrames(file, [time], 960, signal);
    if (!canvas) throw new Error("Couldn't prepare the video cover.");
    const thumbHash = thumbHashBase64FromCanvas(canvas);
    const blob = await new Promise<Blob>((resolve, reject) =>
        canvas.toBlob(
            (blob) =>
                blob
                    ? resolve(blob)
                    : reject(new Error("Couldn't prepare the video cover.")),
            "image/webp",
            0.8,
        ),
    );
    signal?.throwIfAborted();
    logToDisk(
        `[info] Space video cover prepared width=${canvas.width} height=${canvas.height} bytes=${blob.size}`,
    );
    return {
        file: new File([blob], "cover.webp", { type: blob.type }),
        width: canvas.width,
        height: canvas.height,
        thumbHash,
    };
};

const videoExportCommand = (
    edit: SpacePostVideoEdit,
    hdr: boolean,
): string[] => [
    "-ss",
    String(edit.start),
    "-i",
    inputPathPlaceholder,
    "-t",
    String(Math.min(maxSpaceVideoDuration, edit.end - edit.start)),
    "-map",
    "0:v:0",
    ...(edit.muted
        ? ["-an"]
        : ["-map", "0:a:0?", "-c:a", "aac", "-b:a", "128k"]),
    "-map_metadata",
    "-1",
    "-map_metadata:s",
    "-1",
    "-map_chapters",
    "-1",
    "-vf",
    [
        "fps=30:start_time=0",
        "scale=w='trunc(iw*min(1,min(1280/max(iw,ih),720/min(iw,ih)))/2)*2':h='trunc(ih*min(1,min(1280/max(iw,ih),720/min(iw,ih)))/2)*2'",
        ...(hdr
            ? [
                  "zscale=transfer=linear",
                  "tonemap=tonemap=hable:desat=0",
                  "zscale=primaries=709:transfer=709:matrix=709",
              ]
            : []),
        "format=yuv420p",
        "setsar=1",
    ].join(","),
    "-c:v",
    "libx264",
    "-preset",
    "veryfast",
    "-crf",
    "23",
    "-maxrate",
    "4M",
    "-bufsize",
    "8M",
    "-movflags",
    "+faststart",
    outputPathPlaceholder,
];

const exports = new WeakMap<
    File,
    { key: string; file: File; durationMs: number }
>();

const exportSpaceVideo = async (
    file: File,
    edit: SpacePostVideoEdit,
    signal?: AbortSignal,
) => {
    signal?.throwIfAborted();
    const duration = edit.end - edit.start;
    if (
        ![edit.start, edit.end, edit.coverTime].every(Number.isFinite) ||
        edit.start < 0 ||
        duration <= 0 ||
        duration > maxSpaceVideoDuration + 0.000001
    )
        throw new Error("Choose a video segment of up to 10 seconds.");
    const key = JSON.stringify([edit.start, edit.end, edit.muted]);
    let exported = exports.get(file);
    if (exported?.key != key) {
        const { transcodeVideoWeb, determineVideoDurationWeb } =
            await import("./video-encoding/web");
        const command: FFmpegCommand = {
            default: videoExportCommand(edit, false),
            hdr: videoExportCommand(edit, true),
        };
        const bytes = await transcodeVideoWeb(file, edit, command, signal);
        signal?.throwIfAborted();
        const output = new File([bytes], "video.mp4", { type: "video/mp4" });
        if (output.size > 15 * 1024 * 1024 - 42)
            throw new Error("This video is too large. Try a shorter trim.");
        const outputDuration = await determineVideoDurationWeb(output, signal);
        signal?.throwIfAborted();
        if (
            !Number.isFinite(outputDuration) ||
            outputDuration <= 0 ||
            outputDuration > 10.000001
        )
            throw new Error("Couldn't export a video within 10 seconds.");
        exported = {
            key,
            file: output,
            durationMs: Math.min(10_000, Math.ceil(outputDuration * 1000)),
        };
        exports.set(file, exported);
    }
    return { file: exported.file, durationMs: exported.durationMs };
};

export const startSpaceVideoExport = (file: File, edit: SpacePostVideoEdit) => {
    const controller = new AbortController();
    return {
        edit: { ...edit },
        promise: exportSpaceVideo(file, edit, controller.signal),
        cancel: () => controller.abort(),
    };
};

export type SpaceVideoExport = ReturnType<typeof startSpaceVideoExport>;

export const prepareSpaceVideo = async (
    file: File,
    edit: SpacePostVideoEdit,
    signal?: AbortSignal,
    pendingExport?: SpaceVideoExport["promise"],
) => {
    signal?.throwIfAborted();
    const exported = await (pendingExport ??
        exportSpaceVideo(file, edit, signal));
    signal?.throwIfAborted();
    const cover = await spaceVideoCover(
        exported.file,
        Math.max(0, edit.coverTime - edit.start),
        signal,
    );
    return {
        ...cover,
        video: { file: exported.file, durationMs: exported.durationMs },
    };
};
