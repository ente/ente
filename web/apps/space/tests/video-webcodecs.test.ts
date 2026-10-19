import type { FFmpeg } from "@ffmpeg/ffmpeg";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { encodeVideoWithWebCodecs } from "../src/utils/video-encoding/web-codecs";

let frames: Frame[];
let encodedSources: number[];
let encoderFailure: boolean;
let stallEncoder: (() => void) | undefined;
let supported: boolean;
let decoderConfig: VideoDecoderConfig;
let canvasOptions: CanvasRenderingContext2DSettings[];

class Canvas {
    sourceTime = 0;
    constructor(
        public width: number,
        public height: number,
    ) {}
    getContext(_type: string, options: CanvasRenderingContext2DSettings) {
        canvasOptions.push(options);
        return {
            setTransform: vi.fn(),
            rotate: vi.fn(),
            drawImage: (frame: Frame) => {
                this.sourceTime = frame.sourceTime;
            },
        };
    }
}

class Frame {
    timestamp: number;
    duration: number;
    sourceTime: number;
    closed = false;
    constructor(
        source: { timestamp: number; duration: number; sourceTime?: number },
        init?: VideoFrameInit,
    ) {
        this.timestamp = init?.timestamp ?? source.timestamp;
        this.duration = init?.duration ?? source.duration;
        this.sourceTime = source.sourceTime ?? source.timestamp;
        frames.push(this);
    }
    close() {
        this.closed = true;
    }
}

class Decoder extends EventTarget {
    static isConfigSupported = () => Promise.resolve({ supported });
    state = "unconfigured";
    decodeQueueSize = 0;
    constructor(private init: VideoDecoderInit) {
        super();
    }
    configure(config: VideoDecoderConfig) {
        decoderConfig = config;
        this.state = "configured";
    }
    decode(chunk: EncodedVideoChunk) {
        this.init.output(
            new Frame({
                timestamp: chunk.timestamp,
                duration: chunk.duration!,
            }) as unknown as VideoFrame,
        );
    }
    flush() {
        return Promise.resolve();
    }
    close() {
        this.state = "closed";
    }
}

class Encoder extends EventTarget {
    static isConfigSupported = () => Promise.resolve({ supported });
    state = "unconfigured";
    encodeQueueSize = 0;
    constructor(private init: VideoEncoderInit) {
        super();
    }
    configure() {
        this.state = "configured";
    }
    encode(frame: Frame) {
        if (encoderFailure) {
            this.init.error(new DOMException("Encoder failed"));
            return;
        }
        if (stallEncoder) {
            this.encodeQueueSize++;
            if (this.encodeQueueSize > 8) queueMicrotask(stallEncoder);
            return;
        }
        encodedSources.push(frame.sourceTime);
        this.init.output({
            timestamp: frame.timestamp,
            byteLength: 1,
            copyTo: (bytes: Uint8Array) => bytes.fill(1),
        } as unknown as EncodedVideoChunk);
    }
    flush() {
        return Promise.resolve();
    }
    close() {
        this.state = "closed";
    }
}

beforeEach(() => {
    frames = [];
    encodedSources = [];
    encoderFailure = false;
    stallEncoder = undefined;
    supported = true;
    canvasOptions = [];
    vi.stubGlobal("OffscreenCanvas", Canvas);
    vi.stubGlobal("VideoFrame", Frame);
    vi.stubGlobal("VideoEncoder", Encoder);
    vi.stubGlobal("VideoDecoder", Decoder);
    vi.stubGlobal(
        "EncodedVideoChunk",
        class {
            timestamp: number;
            duration?: number;
            constructor(init: EncodedVideoChunkInit) {
                this.timestamp = init.timestamp;
                this.duration = init.duration;
            }
        },
    );
});
afterEach(() => vi.unstubAllGlobals());

const fixture = (
    fps = 30,
    streamChanges = {},
    description = new Uint8Array([1, 100, 0, 40, 255, 225, 0]),
) => {
    const files = new Map<string, Uint8Array | string>();
    const packets = Array.from({ length: Math.ceil(fps * 20) }, (_, index) => ({
        pts_time: (index / fps).toFixed(6),
        duration_time: (1 / fps).toFixed(6),
        pos: index,
        size: 1,
        flags: index % 60 === 0 ? "K_" : "__",
    }));
    const ffmpeg = {
        loaded: true,
        createDir: vi.fn(),
        deleteDir: vi.fn(),
        deleteFile: vi.fn((path: string) => files.delete(path)),
        listDir: (directory: string) =>
            [...files.keys()]
                .filter((path) => path.startsWith(directory + "/"))
                .map((path) => ({
                    name: path.slice(directory.length + 1),
                    isDir: false,
                })),
        readFile: (path: string) => files.get(path),
        writeFile: (path: string, bytes: Uint8Array) => files.set(path, bytes),
        ffprobe: (args: string[]) => {
            files.set(
                args[args.indexOf("-o") + 1]!,
                JSON.stringify({
                    format: { format_name: "mov,mp4,m4a,3gp,3g2,mj2" },
                    streams: [
                        {
                            codec_name: "h264",
                            codec_tag_string: "avc1",
                            width: 320,
                            height: 240,
                            pix_fmt: "yuv420p",
                            ...streamChanges,
                        },
                    ],
                    packets,
                }),
            );
            return 0;
        },
        exec: vi.fn((args: string[]) => {
            if (args[0] === "-dump_attachment:v:0")
                files.set(args[1]!, description);
            else files.set(args.at(-1)!, new Uint8Array([1, 2, 3]));
            return 0;
        }),
    };
    const encode = (start: number, end: number, signal?: AbortSignal) =>
        encodeVideoWithWebCodecs(
            ffmpeg as unknown as FFmpeg,
            "/input",
            new Blob([new Uint8Array(packets.length)]),
            { start, end, muted: false },
            signal,
        );
    return { encode, files, ffmpeg };
};

test("keeps every 30 fps frame without rounding duplicates", async () => {
    const { encode, files } = fixture();
    await encode(0, 10);
    expect(encodedSources).toEqual(
        Array.from({ length: 300 }, (_, index) =>
            Math.round((index * 1_000_000) / 30),
        ),
    );
    expect(frames.every((frame) => frame.closed)).toBe(true);
    expect(files.size).toBe(0);
});

test("a trim between keyframes begins at the frame visible at the selected start", async () => {
    const { encode } = fixture();
    await encode(7.125, 17.125);
    expect(encodedSources).toHaveLength(300);
    expect(encodedSources[0]).toBe(7_100_000);
    expect(encodedSources.at(-1)).toBe(17_066_667);
    expect(new Set(encodedSources).size).toBe(300);
});

test("29.97 fps and fractional selections never export more than the selected duration", async () => {
    const { encode } = fixture(30000 / 1001);
    await encode(1.125, 11.125);
    expect(encodedSources).toHaveLength(300);
    encodedSources.forEach((time, index) => {
        const target = 1_125_000 + Math.round((index * 1_000_000) / 30);
        expect(time).toBeLessThanOrEqual(target);
        expect(target - time).toBeLessThanOrEqual(33_367);
    });
    encodedSources = [];
    await encode(1.125, 11.115);
    expect(encodedSources).toHaveLength(299);
});

test("unsupported hardware is left to the existing exporter", async () => {
    supported = false;
    expect(await fixture().encode(0, 10)).toBeUndefined();
    expect(encodedSources).toHaveLength(0);
});

test("cancelling a stalled encoder releases frames and temporary files", async () => {
    const { encode, files, ffmpeg } = fixture();
    const controller = new AbortController();
    stallEncoder = () => controller.abort();
    await expect(encode(0, 10, controller.signal)).rejects.toMatchObject({
        name: "AbortError",
    });
    expect(frames.every((frame) => frame.closed)).toBe(true);
    expect(files.size).toBe(0);
    expect(ffmpeg.exec).toHaveBeenCalledTimes(1);
});

test("codec failures release resources and reject instead of leaving the export pending", async () => {
    const { encode, files } = fixture();
    encoderFailure = true;
    await expect(encode(0, 10)).rejects.toThrow("Encoder failed");
    expect(frames.every((frame) => frame.closed)).toBe(true);
    expect(files.size).toBe(0);
});

test("full-range 8-bit H.264 uses WebCodecs", async () => {
    const { encode, files } = fixture(30, { pix_fmt: "yuvj420p" });
    expect(await encode(0, 10)).toBeDefined();
    expect(encodedSources).toHaveLength(300);
    expect(frames.every((frame) => frame.closed)).toBe(true);
    expect(files.size).toBe(0);
});

test.each(["hvc1", "hev1"])(
    "decodes HEVC %s with its configuration record",
    async (tag) => {
        const description = new Uint8Array([
            1, 1, 96, 0, 0, 0, 176, 0, 0, 0, 0, 0, 153, 240, 0, 252, 253, 248,
            248, 0, 0, 15, 0,
        ]);
        const { encode } = fixture(
            60,
            { codec_name: "hevc", codec_tag_string: tag },
            description,
        );
        expect(await encode(0, 10)).toBeDefined();
        expect(decoderConfig.codec).toBe(`${tag}.1.6.L153.b0`);
        expect(decoderConfig.description).toBe(description);
        expect(encodedSources).toHaveLength(300);
        expect(canvasOptions).toHaveLength(0);
    },
);

test.each(["arib-std-b67", "smpte2084"])(
    "converts HEVC %s frames to SDR before encoding",
    async (transfer) => {
        const description = new Uint8Array([
            1, 2, 32, 0, 0, 0, 144, 0, 0, 0, 0, 0, 153, 240, 0, 252, 253, 250,
            250, 0, 0, 15, 0,
        ]);
        const { encode, files } = fixture(
            30,
            {
                codec_name: "hevc",
                codec_tag_string: "hvc1",
                pix_fmt: "yuv420p10le",
                color_primaries: "bt2020",
                color_transfer: transfer,
            },
            description,
        );
        expect(await encode(0, 10)).toBeDefined();
        expect(decoderConfig.codec).toBe("hvc1.2.4.L153.90");
        expect(canvasOptions).toEqual([{ colorSpace: "srgb" }]);
        expect(encodedSources).toEqual(
            Array.from({ length: 300 }, (_, i) =>
                Math.round((i * 1_000_000) / 30),
            ),
        );
        expect(frames.every((frame) => frame.closed)).toBe(true);
        expect(files.size).toBe(0);
    },
);

test("a truncated HEVC configuration is left to the existing exporter", async () => {
    const { encode } = fixture(30, {
        codec_name: "hevc",
        codec_tag_string: "hvc1",
    });
    expect(await encode(0, 10)).toBeUndefined();
    expect(encodedSources).toHaveLength(0);
});
