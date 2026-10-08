import { afterEach, beforeEach, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
    encode: vi.fn(),
    load: vi.fn(),
    logToDisk: vi.fn(),
    workers: [] as {
        loaded: boolean;
        terminate: ReturnType<typeof vi.fn<() => void>>;
        exec: ReturnType<typeof vi.fn>;
        unmount: ReturnType<typeof vi.fn>;
        readFile: ReturnType<typeof vi.fn>;
    }[],
}));
vi.mock("ente-base/log", () => ({
    default: { debug: vi.fn(), info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));
vi.mock("ente-base/log-web", () => ({ logToDisk: mocks.logToDisk }));
vi.mock("../src/utils/video-encoding/web-codecs", () => ({
    encodeVideoWithWebCodecs: mocks.encode,
}));
vi.mock("@ffmpeg/ffmpeg", () => ({
    FFFSType: { WORKERFS: "WORKERFS" },
    FFmpeg: class {
        loaded = true;
        constructor() {
            mocks.workers.push(this);
        }
        rejectLoad: ((error: Error) => void) | undefined;
        load = (...args: unknown[]) =>
            new Promise((resolve, reject) => {
                this.rejectLoad = reject;
                Promise.resolve(mocks.load(...args)).then(resolve, reject);
            });
        terminate = vi.fn(() => {
            this.loaded = false;
            this.rejectLoad?.(new Error("Terminated"));
        });
        on = vi.fn();
        off = vi.fn();
        createDir = vi.fn();
        deleteDir = vi.fn();
        mount = vi.fn();
        unmount = vi.fn();
        deleteFile = vi.fn();
        listDir = vi.fn().mockResolvedValue([]);
        ffprobe = vi.fn().mockResolvedValue(0);
        exec = vi.fn().mockResolvedValue(0);
        readFile = vi.fn().mockResolvedValue(new Uint8Array([7]));
    },
}));

beforeEach(() => {
    vi.resetModules();
    mocks.encode.mockReset();
    mocks.load.mockReset().mockResolvedValue(true);
    mocks.workers.length = 0;
    mocks.logToDisk.mockClear();
    vi.stubGlobal("VideoEncoder", {});
    vi.stubGlobal("VideoDecoder", {});
});
afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
});

const exporter = async () => {
    const { transcodeVideoWeb } =
        await import("../src/utils/video-encoding/web");
    return (signal?: AbortSignal) =>
        transcodeVideoWeb(
            new Blob(["video"]),
            { start: 0, end: 10, muted: false },
            ["fallback"],
            signal,
        );
};

test("uses WebCodecs output without running the software encoder", async () => {
    const bytes = new Uint8Array([1, 2]);
    mocks.encode.mockResolvedValue(bytes);
    expect(await (await exporter())()).toBe(bytes);
    expect(mocks.workers[0]!.exec).not.toHaveBeenCalled();
    expect(mocks.workers[0]!.unmount).toHaveBeenCalled();
});

test("preloading and posting share the same in-flight engine load", async () => {
    let finish!: () => void;
    mocks.load.mockImplementationOnce(
        () =>
            new Promise<void>((resolve) => {
                finish = resolve;
            }),
    );
    const { preloadVideoEncoderWeb } =
        await import("../src/utils/video-encoding/web");
    const first = preloadVideoEncoderWeb();
    const second = preloadVideoEncoderWeb();
    const bytes = new Uint8Array([1, 2]);
    mocks.encode.mockResolvedValue(bytes);
    const posted = (await exporter())();
    expect(mocks.load).toHaveBeenCalledTimes(1);
    expect(mocks.encode).not.toHaveBeenCalled();
    finish();
    await Promise.all([first, second]);
    expect(await posted).toBe(bytes);
    expect(mocks.load).toHaveBeenCalledTimes(1);
    expect(mocks.workers).toHaveLength(1);
});

test("posting can retry after a failed preload", async () => {
    mocks.load.mockRejectedValueOnce(new Error("Offline"));
    const { preloadVideoEncoderWeb } =
        await import("../src/utils/video-encoding/web");
    await expect(preloadVideoEncoderWeb()).rejects.toThrow("Offline");
    mocks.encode.mockResolvedValue(new Uint8Array([2]));
    expect(await (await exporter())()).toEqual(new Uint8Array([2]));
    expect(mocks.workers[0]!.terminate).toHaveBeenCalled();
    expect(mocks.load).toHaveBeenCalledTimes(2);
});

test.each(["unsupported", "failed", "missing API"])(
    "keeps the software exporter available when WebCodecs is %s",
    async (mode) => {
        if (mode === "failed")
            mocks.encode.mockRejectedValue(new Error("Codec unavailable"));
        else mocks.encode.mockResolvedValue(undefined);
        if (mode === "missing API") vi.stubGlobal("VideoEncoder", undefined);
        expect(await (await exporter())()).toEqual(new Uint8Array([7]));
        expect(mocks.workers[0]!.exec).toHaveBeenCalledWith(["fallback"]);
        if (mode === "missing API") expect(mocks.encode).not.toHaveBeenCalled();
    },
);

test("cancellation stops the active export without starting the software fallback", async () => {
    mocks.encode.mockImplementation(
        (_ffmpeg, _path, _blob, _edit, signal: AbortSignal) =>
            new Promise((_, reject) =>
                signal.addEventListener(
                    "abort",
                    () => reject(new DOMException("Canceled", "AbortError")),
                    { once: true },
                ),
            ),
    );
    const controller = new AbortController();
    const pending = (await exporter())(controller.signal);
    const rejected = expect(pending).rejects.toMatchObject({
        name: "AbortError",
    });
    await vi.waitFor(() => expect(mocks.encode).toHaveBeenCalled());
    controller.abort();
    await rejected;
    expect(mocks.workers[0]!.terminate).toHaveBeenCalled();
    expect(mocks.workers[0]!.exec).not.toHaveBeenCalled();
});

test("a queued export can be cancelled without waiting for or stopping another export", async () => {
    let finish!: (bytes: Uint8Array) => void;
    mocks.encode.mockImplementation(
        () =>
            new Promise((resolve) => {
                finish = resolve;
            }),
    );
    const run = await exporter();
    const first = run();
    await vi.waitFor(() => expect(mocks.encode).toHaveBeenCalledTimes(1));
    const controller = new AbortController();
    const second = run(controller.signal);
    const rejected = expect(second).rejects.toMatchObject({
        name: "AbortError",
    });
    controller.abort();
    await rejected;
    expect(mocks.workers[0]!.terminate).not.toHaveBeenCalled();
    finish(new Uint8Array([1]));
    await first;
    expect(mocks.encode).toHaveBeenCalledTimes(1);
});

test("canceling active and queued draft exports frees the software encoder for editor frames and restart", async () => {
    vi.stubGlobal("VideoEncoder", undefined);
    mocks.load.mockImplementation(() => {
        const worker = mocks.workers.at(-1)!;
        worker.readFile.mockImplementation((path: string) => {
            if (path == "output.json")
                return JSON.stringify({
                    format: { duration: "2" },
                    streams: [{}],
                });
            if (path == "frame.json")
                return JSON.stringify({
                    format: {},
                    packets: [{ pts_time: "0" }, { pts_time: "1" }],
                });
            return new Uint8Array([7]);
        });
        if (mocks.workers.length == 1) {
            const terminate = worker.terminate.getMockImplementation()!;
            worker.exec.mockImplementationOnce(
                () =>
                    new Promise<number>((_, reject) => {
                        worker.terminate.mockImplementation(() => {
                            terminate();
                            reject(new Error("Terminated"));
                        });
                    }),
            );
        }
        return Promise.resolve(true);
    });
    const { startSpaceVideoExport } = await import("../src/utils/post-video");
    const { extractVideoFramesWeb } =
        await import("../src/utils/video-encoding/web");
    const files = [
        new File(["first"], "first.mp4"),
        new File(["second"], "second.mp4"),
    ];
    const edit = { start: 0, end: 2, coverTime: 0, muted: false };
    const jobs = files.map((file) => startSpaceVideoExport(file, edit));
    const canceled = Promise.all(
        jobs.map((job) =>
            expect(job.promise).rejects.toMatchObject({ name: "AbortError" }),
        ),
    );
    await vi.waitFor(() =>
        expect(mocks.workers[0]?.exec).toHaveBeenCalledOnce(),
    );
    jobs.forEach((job) => job.cancel());
    const frames = extractVideoFramesWeb(files[0]!, [0, 1], 128);
    await canceled;
    expect(await frames).toHaveLength(2);
    expect(mocks.workers).toHaveLength(2);
    expect(mocks.workers[0]!.terminate).toHaveBeenCalledOnce();
    expect(mocks.workers[1]!.exec).toHaveBeenCalledTimes(2);
    const restarted = await Promise.all(
        files.map((file) => startSpaceVideoExport(file, edit).promise),
    );
    expect(restarted.map((video) => video.durationMs)).toEqual([2000, 2000]);
});

test("cancelling engine loading terminates it and allows the next export to load again", async () => {
    mocks.load.mockImplementationOnce(() => new Promise(() => undefined));
    const run = await exporter();
    const controller = new AbortController();
    const pending = run(controller.signal);
    const rejected = expect(pending).rejects.toMatchObject({
        name: "AbortError",
    });
    await vi.waitFor(() => expect(mocks.load).toHaveBeenCalled());
    controller.abort();
    await rejected;
    mocks.encode.mockResolvedValue(new Uint8Array([2]));
    expect(await run()).toEqual(new Uint8Array([2]));
    expect(mocks.workers[0]!.terminate).toHaveBeenCalled();
    expect(mocks.workers).toHaveLength(2);
});

test("a stalled engine load times out and can be retried", async () => {
    vi.useFakeTimers();
    mocks.load.mockImplementationOnce(() => new Promise(() => undefined));
    const { preloadVideoEncoderWeb } =
        await import("../src/utils/video-encoding/web");
    const rejected = expect(preloadVideoEncoderWeb()).rejects.toThrow(
        "took too long to load",
    );
    await vi.advanceTimersByTimeAsync(60_000);
    await rejected;
    await preloadVideoEncoderWeb();
    expect(mocks.workers).toHaveLength(2);
    expect(mocks.workers[0]!.terminate).toHaveBeenCalled();
});

test("a stalled export times out, closes the worker, and releases the queue for retry", async () => {
    vi.useFakeTimers();
    mocks.encode
        .mockImplementationOnce(
            (_ffmpeg, _path, _blob, _edit, signal: AbortSignal) =>
                new Promise((_, reject) =>
                    signal.addEventListener("abort", () =>
                        reject(signal.reason as Error),
                    ),
                ),
        )
        .mockResolvedValue(new Uint8Array([3]));
    const run = await exporter();
    const first = run();
    const rejected = expect(first).rejects.toMatchObject({
        name: "TimeoutError",
    });
    await vi.advanceTimersByTimeAsync(300_000);
    await rejected;
    expect(await run()).toEqual(new Uint8Array([3]));
    expect(mocks.workers[0]!.terminate).toHaveBeenCalled();
    expect(mocks.workers[0]!.exec).not.toHaveBeenCalled();
    expect(mocks.workers).toHaveLength(2);
    expect(mocks.logToDisk).toHaveBeenCalledWith(
        expect.stringContaining("stage=export timeout"),
    );
});

test("cover extraction near the clip end seeks to the last available frame", async () => {
    const { preloadVideoEncoderWeb, extractVideoFramesWeb } =
        await import("../src/utils/video-encoding/web");
    await preloadVideoEncoderWeb();
    const worker = mocks.workers[0]!;
    worker.readFile.mockImplementation((path: string) => {
        if (path == "output.json") return JSON.stringify({ streams: [{}] });
        if (path == "frame.json")
            return JSON.stringify({
                format: { start_time: "0" },
                packets: [
                    { pts_time: "3.38" },
                    { pts_time: "3.413667" },
                    { pts_time: "3.430322" },
                ],
            });
        return new Uint8Array([1, 2, 3]);
    });
    const frames = await extractVideoFramesWeb(
        new Blob(["video"]),
        [3.4499],
        960,
    );
    expect(frames).toHaveLength(1);
    expect(frames[0]!.type).toBe("image/png");
    const command = worker.exec.mock.calls[0]![0] as string[];
    expect(Number(command[command.indexOf("-ss") + 1])).toBeCloseTo(
        3.430321,
        6,
    );
    expect(worker.unmount).toHaveBeenCalled();
});
