import { logToDisk } from "ente-base/log-web";
import type { PreparedSpacePostImage } from "utils/post-image";
import { thumbHashBase64FromCanvas } from "utils/thumbhash";

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
    startTime: number;
}

export const maxSpaceVideoDuration = 10;

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

export const spaceVideoInfo = async (
    file: File,
    signal?: AbortSignal,
): Promise<SpaceVideoInfo> => {
    const { determineVideoInfoWeb } = await import("./video-encoding/web");
    return determineVideoInfoWeb(file, signal);
};

export const spaceVideoFrames = async (
    file: Blob,
    times: number[],
    maxDimension: number,
    signal?: AbortSignal,
) => {
    const { extractVideoFramesWeb } = await import("./video-encoding/web");
    return extractVideoFramesWeb(file, times, maxDimension, signal);
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
        const bytes = await transcodeVideoWeb(file, edit, signal);
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
