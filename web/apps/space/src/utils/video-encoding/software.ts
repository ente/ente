import { FFFSType, FFmpeg } from "@ffmpeg/ffmpeg";
import { logToDisk } from "ente-base/log-web";
import { ensureArrayBufferBacked } from "ente-utils/bytes";
import { z } from "zod";
import type { SpacePostVideoEdit } from "../post-video";

const hdrFilters = [
    "zscale=transfer=linear",
    "tonemap=tonemap=hable:desat=0",
    "zscale=primaries=709:transfer=709:matrix=709",
];

export const extractSoftwareVideoFrames = (
    blob: Blob,
    times: number[],
    maxDimension: number,
    hdr: boolean,
    signal: AbortSignal,
) =>
    withSoftwareVideo(blob, signal, async (ffmpeg, inputPath) => {
        const frames: HTMLCanvasElement[] = [];
        for (const time of times) {
            signal.throwIfAborted();
            const status = await ffmpeg.ffprobe([
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-read_intervals",
                `${time}%${time + 1}`,
                "-show_entries",
                "packet=pts_time",
                "-of",
                "json",
                "-o",
                "frame.json",
                inputPath,
            ]);
            if (status !== 0) throw new Error("Couldn't locate a video frame.");
            const json = await ffmpeg.readFile("frame.json", "utf8");
            await ffmpeg.deleteFile("frame.json");
            if (typeof json !== "string")
                throw new Error("Expected video timestamps.");
            const probe = z
                .object({
                    packets: z
                        .array(z.object({ pts_time: z.coerce.number() }))
                        .nonempty(),
                })
                .parse(JSON.parse(json));
            const frameTime = probe.packets
                .map((packet) => packet.pts_time)
                .reduce((closest, timestamp) =>
                    Math.abs(timestamp - time) < Math.abs(closest - time)
                        ? timestamp
                        : closest,
                );
            const bytes = await execute(
                ffmpeg,
                [
                    "-seek_timestamp",
                    "1",
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
                        ...(hdr ? hdrFilters : []),
                        "format=rgb24",
                        "setsar=1",
                    ].join(","),
                    "-map_metadata",
                    "-1",
                    "-update",
                    "1",
                ],
                "frame.png",
            );
            const bitmap = await createImageBitmap(
                new Blob([bytes], { type: "image/png" }),
            );
            try {
                signal.throwIfAborted();
                const canvas = document.createElement("canvas");
                canvas.width = bitmap.width;
                canvas.height = bitmap.height;
                const context = canvas.getContext("2d");
                if (!context)
                    throw new Error("Couldn't prepare the video frames.");
                context.drawImage(bitmap, 0, 0);
                frames.push(canvas);
            } finally {
                bitmap.close();
            }
        }
        return frames;
    });

export const transcodeSoftwareVideo = (
    blob: Blob,
    edit: SpacePostVideoEdit,
    hdr: boolean,
    signal: AbortSignal,
) =>
    withSoftwareVideo(blob, signal, (ffmpeg, inputPath) =>
        execute(
            ffmpeg,
            [
                "-seek_timestamp",
                "1",
                "-ss",
                String(edit.start),
                "-i",
                inputPath,
                "-t",
                String(edit.end - edit.start),
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
                    ...(hdr ? hdrFilters : []),
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
            ],
            "video.mp4",
        ),
    );

const execute = async (ffmpeg: FFmpeg, args: string[], outputPath: string) => {
    const status = await ffmpeg.exec([...args, outputPath]);
    if (status !== 0) throw new Error("Couldn't process this video.");
    const bytes = await ffmpeg.readFile(outputPath);
    await ffmpeg.deleteFile(outputPath);
    if (typeof bytes === "string")
        throw new Error("Expected encoded video data.");
    return ensureArrayBufferBacked(bytes);
};

const withSoftwareVideo = async <T>(
    blob: Blob,
    signal: AbortSignal,
    task: (ffmpeg: FFmpeg, inputPath: string) => Promise<T>,
): Promise<T> => {
    signal.throwIfAborted();
    const ffmpeg = new FFmpeg();
    const cancel = () => ffmpeg.terminate();
    signal.addEventListener("abort", cancel, { once: true });
    try {
        logToDisk("[info] Space video software processor loading");
        await ffmpeg.load({
            coreURL: "https://assets.ente.com/ffmpeg-core-9.0.2/ffmpeg-core.js",
            wasmURL:
                "https://assets.ente.com/ffmpeg-core-9.0.2/ffmpeg-core.wasm",
        });
        signal.throwIfAborted();
        await ffmpeg.createDir("/input");
        await ffmpeg.mount(
            FFFSType.WORKERFS,
            { files: [new File([blob], "video")] },
            "/input",
        );
        const result = await task(ffmpeg, "/input/video");
        signal.throwIfAborted();
        return result;
    } catch (error) {
        signal.throwIfAborted();
        throw error;
    } finally {
        signal.removeEventListener("abort", cancel);
        ffmpeg.terminate();
    }
};
