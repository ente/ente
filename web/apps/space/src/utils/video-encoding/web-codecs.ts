import type { FFmpeg } from "@ffmpeg/ffmpeg";
import { newID } from "ente-base/id";
import { ensureArrayBufferBacked } from "ente-utils/bytes";
import { z } from "zod";

export interface VideoTranscodeEdit {
    start: number;
    end: number;
    muted: boolean;
}

const Probe = z.object({
    format: z.object({ format_name: z.string() }),
    streams: z.array(
        z.object({
            codec_name: z.string(),
            codec_tag_string: z.string(),
            width: z.number().int().positive(),
            height: z.number().int().positive(),
            pix_fmt: z.string(),
            color_transfer: z.string().optional(),
            color_primaries: z.string().optional(),
            sample_aspect_ratio: z.string().optional(),
            start_time: z.string().optional(),
            side_data_list: z
                .array(
                    z.object({
                        rotation: z.number().optional(),
                        displaymatrix: z.string().optional(),
                    }),
                )
                .optional(),
        }),
    ),
    packets: z.array(
        z.object({
            pts_time: z.coerce.number(),
            duration_time: z.coerce.number().positive(),
            pos: z.coerce.number().int().nonnegative(),
            size: z.coerce.number().int().positive(),
            flags: z.string(),
        }),
    ),
});

type Packet = z.infer<typeof Probe>["packets"][number];

const frameRate = 30;
const frameTime = (index: number) =>
    Math.round((index * 1_000_000) / frameRate);

export const encodeVideoWithWebCodecs = async (
    ffmpeg: FFmpeg,
    inputPath: string,
    blob: Blob,
    edit: VideoTranscodeEdit,
    signal?: AbortSignal,
): Promise<Uint8Array<ArrayBuffer> | undefined> => {
    signal?.throwIfAborted();
    const frameCount = Math.floor(
        (edit.end - edit.start) * frameRate + 0.000001,
    );
    if (frameCount < 1) return;
    const directory = newID("webcodecs_");
    await ffmpeg.createDir(directory);
    const probePath = `${directory}/probe.json`;
    const descriptionPath = `${directory}/codec.bin`;
    const videoPath = `${directory}/video.h264`;
    const outputPath = `${directory}/video.mp4`;
    const exec = async (command: string[]) => {
        signal?.throwIfAborted();
        const status = await ffmpeg.exec(command);
        if (status !== 0) throw new Error(`FFmpeg exited with ${status}`);
    };
    const readBytes = async (path: string) => {
        const bytes = await ffmpeg.readFile(path);
        if (typeof bytes === "string") throw new Error("Expected binary data");
        return ensureArrayBufferBacked(bytes);
    };
    try {
        const status = await ffmpeg.ffprobe([
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "format=format_name:stream=codec_name,codec_tag_string,width,height,pix_fmt,color_transfer,color_primaries,sample_aspect_ratio,start_time:stream_side_data=rotation,displaymatrix:packet=pts_time,duration_time,pos,size,flags",
            "-of",
            "json",
            "-o",
            probePath,
            inputPath,
        ]);
        if (status !== 0) throw new Error("Couldn't read video packets");
        const json = await ffmpeg.readFile(probePath, "utf8");
        if (typeof json !== "string")
            throw new Error("Expected video information");
        const probe = Probe.parse(JSON.parse(json));
        const stream = probe.streams[0];
        if (
            !probe.format.format_name.split(",").includes("mov") ||
            !stream ||
            !(stream.codec_name === "h264"
                ? ["avc1", "avc3"].includes(stream.codec_tag_string)
                : stream.codec_name === "hevc" &&
                  ["hvc1", "hev1"].includes(stream.codec_tag_string)) ||
            !["yuv420p", "yuvj420p", "yuv420p10le"].includes(stream.pix_fmt) ||
            (stream.sample_aspect_ratio &&
                stream.sample_aspect_ratio !== "1:1") ||
            Number(stream.start_time ?? 0) !== 0
        )
            return;
        const display = stream.side_data_list?.find(
            (data) => data.displaymatrix,
        );
        const rotation = display?.rotation ?? 0;
        if (![0, 90, -90, 180, -180].includes(rotation)) return;
        if (display?.displaymatrix) {
            const matrix = display.displaymatrix
                .trim()
                .split("\n")
                .flatMap((line) =>
                    line
                        .slice(line.indexOf(":") + 1)
                        .trim()
                        .split(/\s+/)
                        .map(Number),
                );
            const angle = (rotation * Math.PI) / 180;
            const expected = [
                Math.round(Math.cos(angle) * 65536),
                -Math.round(Math.sin(angle) * 65536),
                0,
                Math.round(Math.sin(angle) * 65536),
                Math.round(Math.cos(angle) * 65536),
                0,
                0,
                0,
                1073741824,
            ];
            if (
                matrix.length !== 9 ||
                matrix.some((value, index) => value !== expected[index])
            )
                return;
        }
        if (
            !probe.packets.length ||
            probe.packets.some((packet) => packet.pos + packet.size > blob.size)
        )
            return;
        await exec([
            "-dump_attachment:v:0",
            descriptionPath,
            "-i",
            inputPath,
            "-t",
            "0",
            "-c",
            "copy",
            "-f",
            "null",
            "-",
        ]);
        const description = await readBytes(descriptionPath);
        const hevc = stream.codec_name === "hevc";
        if (description.length < (hevc ? 23 : 7) || description[0] !== 1)
            return;
        let codec: string;
        if (hevc) {
            const profile = description[1]!;
            const compatibility = new DataView(
                description.buffer,
                description.byteOffset,
                description.byteLength,
            ).getUint32(2);
            const reversedCompatibility = parseInt(
                compatibility
                    .toString(2)
                    .padStart(32, "0")
                    .split("")
                    .reverse()
                    .join(""),
                2,
            );
            const constraints = Array.from(description.slice(6, 12), (value) =>
                value.toString(16).padStart(2, "0"),
            )
                .join(".")
                .replace(/(\.00)+$/, "");
            codec = `${stream.codec_tag_string}.${["", "A", "B", "C"][profile >> 6]}${profile & 31}.${reversedCompatibility.toString(16)}.${profile & 32 ? "H" : "L"}${description[12]}.${constraints}`;
        } else {
            codec =
                "avc1." +
                Array.from(description.slice(1, 4), (value) =>
                    value.toString(16).padStart(2, "0"),
                ).join("");
        }
        const decoderConfig: VideoDecoderConfig = {
            codec,
            description,
            hardwareAcceleration: "prefer-hardware",
        };
        const sideways = Math.abs(rotation) === 90;
        const width = sideways ? stream.height : stream.width;
        const height = sideways ? stream.width : stream.height;
        const scale = Math.min(
            1,
            1920 / Math.max(width, height),
            1080 / Math.min(width, height),
        );
        const encoderConfig: VideoEncoderConfig = {
            codec: "avc1.640028",
            width: Math.floor((width * scale) / 2) * 2,
            height: Math.floor((height * scale) / 2) * 2,
            bitrate: 4_000_000,
            bitrateMode: "variable",
            framerate: frameRate,
            latencyMode: "realtime",
            hardwareAcceleration: "prefer-hardware",
            avc: { format: "annexb" },
        };
        const [decoderSupport, encoderSupport] = await Promise.all([
            VideoDecoder.isConfigSupported(decoderConfig),
            VideoEncoder.isConfigSupported(encoderConfig),
        ]);
        if (!decoderSupport.supported || !encoderSupport.supported) return;
        const video = await encodeFrames(
            blob,
            probe.packets,
            edit.start,
            frameCount,
            rotation,
            stream.pix_fmt === "yuv420p10le" ||
                stream.color_primaries === "bt2020" ||
                ["smpte2084", "arib-std-b67"].includes(
                    stream.color_transfer ?? "",
                ),
            decoderConfig,
            encoderConfig,
            signal,
        );
        signal?.throwIfAborted();
        await ffmpeg.writeFile(
            videoPath,
            new Uint8Array(await video.arrayBuffer()),
        );
        await exec([
            "-ss",
            String(edit.start),
            "-i",
            inputPath,
            "-r",
            String(frameRate),
            "-i",
            videoPath,
            "-t",
            String(frameCount / frameRate),
            "-map",
            "1:v:0",
            "-c:v",
            "copy",
            "-bsf:v",
            `setts=ts=N:duration=1:time_base=1/${frameRate}`,
            "-video_track_timescale",
            "30000",
            ...(edit.muted
                ? ["-an"]
                : ["-map", "0:a:0?", "-c:a", "aac", "-b:a", "128k"]),
            "-map_metadata",
            "-1",
            "-map_metadata:s",
            "-1",
            "-map_chapters",
            "-1",
            "-movflags",
            "+faststart",
            outputPath,
        ]);
        return await readBytes(outputPath);
    } finally {
        if (ffmpeg.loaded) {
            for (const file of await ffmpeg.listDir(directory)) {
                if (!file.isDir)
                    await ffmpeg.deleteFile(`${directory}/${file.name}`);
            }
            await ffmpeg.deleteDir(directory);
        }
    }
};

const encodeFrames = async (
    blob: Blob,
    packets: Packet[],
    start: number,
    frameCount: number,
    rotation: number,
    convertColor: boolean,
    decoderConfig: VideoDecoderConfig,
    encoderConfig: VideoEncoderConfig,
    signal?: AbortSignal,
) => {
    signal?.throwIfAborted();
    const startTime = Math.round(start * 1_000_000);
    const durations = new Map(
        packets.map((packet) => [
            Math.round(packet.pts_time * 1_000_000),
            Math.round(packet.duration_time * 1_000_000),
        ]),
    );
    let first = -1;
    for (const [index, packet] of packets.entries()) {
        if (
            packet.flags.includes("K") &&
            Math.round(packet.pts_time * 1_000_000) <= startTime
        )
            first = index;
    }
    if (first < 0) throw new Error("No keyframe before the selected clip");
    let failure: Error | undefined;
    let wake: (() => void) | undefined;
    const notify = () => {
        wake?.();
        wake = undefined;
    };
    const fail = (error: Error) => {
        failure = error;
        notify();
    };
    const checkError = () => {
        signal?.throwIfAborted();
        if (failure) throw failure;
    };
    let previous: VideoFrame | undefined;
    let encoded = 0;
    const chunks: Uint8Array<ArrayBuffer>[] = [];
    const canvas =
        rotation || convertColor
            ? new OffscreenCanvas(encoderConfig.width, encoderConfig.height)
            : undefined;
    const context = canvas?.getContext("2d", { colorSpace: "srgb" });
    if (canvas && !context)
        throw new Error("Couldn't prepare the video frames");
    const encoder = new VideoEncoder({
        output(chunk) {
            if (chunk.timestamp !== frameTime(chunks.length)) {
                fail(new Error("Video encoder reordered the output frames"));
                return;
            }
            const bytes = new Uint8Array(chunk.byteLength);
            chunk.copyTo(bytes);
            chunks.push(bytes);
            notify();
        },
        error: fail,
    });
    const encodeUntil = (time: number) => {
        if (!previous) return;
        while (encoded < frameCount && startTime + frameTime(encoded) < time) {
            checkError();
            const timestamp = frameTime(encoded);
            if (canvas && context) {
                const sideways = Math.abs(rotation) === 90;
                const width = sideways ? canvas.height : canvas.width;
                const height = sideways ? canvas.width : canvas.height;
                context.setTransform(
                    1,
                    0,
                    0,
                    1,
                    canvas.width / 2,
                    canvas.height / 2,
                );
                context.rotate((-rotation * Math.PI) / 180);
                context.drawImage(
                    previous,
                    -width / 2,
                    -height / 2,
                    width,
                    height,
                );
            }
            const frame = new VideoFrame(canvas ?? previous, {
                timestamp,
                duration: frameTime(encoded + 1) - timestamp,
            });
            try {
                encoder.encode(frame, { keyFrame: encoded % 60 === 0 });
                encoded++;
            } finally {
                frame.close();
            }
        }
    };
    const decoder = new VideoDecoder({
        output(frame) {
            if (failure || encoded === frameCount) {
                frame.close();
                return;
            }
            try {
                if (!previous && frame.timestamp > startTime)
                    throw new Error("Video starts after the selected clip");
                encodeUntil(frame.timestamp);
                previous?.close();
                previous = frame;
            } catch (error) {
                frame.close();
                fail(error as Error);
            }
            notify();
        },
        error: fail,
    });
    const abort = () => {
        fail(new DOMException("Canceled", "AbortError"));
        if (decoder.state !== "closed") decoder.close();
        if (encoder.state !== "closed") encoder.close();
    };
    decoder.addEventListener("dequeue", notify);
    encoder.addEventListener("dequeue", notify);
    signal?.addEventListener("abort", abort, { once: true });
    try {
        signal?.throwIfAborted();
        encoder.configure(encoderConfig);
        decoder.configure(decoderConfig);
        for (
            let index = first;
            index < packets.length && encoded < frameCount;
            index++
        ) {
            while (decoder.decodeQueueSize > 8 || encoder.encodeQueueSize > 8) {
                checkError();
                await new Promise<void>((resolve) => {
                    wake = resolve;
                });
            }
            checkError();
            const packet = packets[index]!;
            const data = await blob
                .slice(packet.pos, packet.pos + packet.size)
                .arrayBuffer();
            checkError();
            decoder.decode(
                new EncodedVideoChunk({
                    type: packet.flags.includes("K") ? "key" : "delta",
                    timestamp: Math.round(packet.pts_time * 1_000_000),
                    duration: Math.round(packet.duration_time * 1_000_000),
                    data,
                }),
            );
        }
        await decoder.flush();
        checkError();
        if (previous)
            encodeUntil(
                previous.timestamp + (durations.get(previous.timestamp) ?? 0),
            );
        await encoder.flush();
        checkError();
        if (chunks.length !== frameCount)
            throw new Error("Video export is missing frames");
        return new Blob(chunks);
    } finally {
        signal?.removeEventListener("abort", abort);
        decoder.removeEventListener("dequeue", notify);
        encoder.removeEventListener("dequeue", notify);
        previous?.close();
        if (decoder.state !== "closed") decoder.close();
        if (encoder.state !== "closed") encoder.close();
        if (canvas) {
            canvas.width = 1;
            canvas.height = 1;
        }
    }
};
