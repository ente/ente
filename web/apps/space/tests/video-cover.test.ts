import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
    prepareSpaceVideo,
    spaceVideoCover,
    spaceVideoFrames,
    spaceVideoInfo,
    startSpaceVideoExport,
} from "../src/utils/post-video";

const mocks = vi.hoisted(() => ({
    frames: vi.fn(),
    info: vi.fn(),
    log: vi.fn(),
    transcode: vi.fn(),
    duration: vi.fn(),
}));
vi.mock("../src/utils/video-encoding/web", () => ({
    extractVideoFramesWeb: mocks.frames,
    determineVideoInfoWeb: mocks.info,
    transcodeVideoWeb: mocks.transcode,
    determineVideoDurationWeb: mocks.duration,
}));
vi.mock("ente-base/log-web", () => ({ logToDisk: mocks.log }));
vi.mock("utils/thumbhash", () => ({ thumbHashBase64FromCanvas: () => "hash" }));

let alpha: number;
let bitmapClose: ReturnType<typeof vi.fn>;
let createElement: ReturnType<typeof vi.fn>;

beforeEach(() => {
    vi.resetAllMocks();
    alpha = 255;
    bitmapClose = vi.fn();
    vi.stubGlobal("navigator", {
        userAgent:
            "Mozilla/5.0 (Android 16; Mobile; rv:143.0) Gecko/143.0 Firefox/143.0",
    });
    mocks.frames.mockResolvedValue([new Blob(["png"], { type: "image/png" })]);
    mocks.info.mockResolvedValue({ duration: 3.45, width: 1080, height: 1920 });
    mocks.transcode.mockResolvedValue(new Uint8Array([1, 2, 3]));
    mocks.duration.mockResolvedValue(3.45);
    vi.stubGlobal(
        "createImageBitmap",
        vi
            .fn()
            .mockImplementation(() =>
                Promise.resolve({
                    width: 540,
                    height: 960,
                    close: bitmapClose,
                }),
            ),
    );
    createElement = vi.fn((tag: string) => {
        if (tag != "canvas")
            throw new Error(
                "Must not decode through a video element on Firefox Android",
            );
        return {
            width: 0,
            height: 0,
            getContext: () => ({
                drawImage: vi.fn(),
                getImageData: () => ({
                    data: new Uint8ClampedArray([0, 0, 0, alpha]),
                }),
            }),
            toBlob: (callback: BlobCallback) =>
                callback(new Blob(["cover"], { type: "image/webp" })),
        };
    });
    vi.stubGlobal("document", { createElement });
});
afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    vi.useRealTimers();
});

const nativeVideo = () => {
    vi.stubGlobal("navigator", {
        userAgent:
            "Mozilla/5.0 (Android 16) Chrome/140.0.0.0 Mobile Safari/537.36",
    });
    vi.stubGlobal("window", { setTimeout, clearTimeout });
    let frameReady!: VideoFrameRequestCallback;
    const video = Object.assign(new EventTarget(), {
        duration: 3.45,
        videoWidth: 540,
        videoHeight: 960,
        currentTime: 0,
        pause: vi.fn(),
        removeAttribute: vi.fn(),
        load: vi.fn(),
        requestVideoFrameCallback: vi.fn(
            (callback: VideoFrameRequestCallback) => {
                frameReady = callback;
                return 7;
            },
        ),
        cancelVideoFrameCallback: vi.fn(),
        presentFrame: () => {
            alpha = 255;
            frameReady(0, {} as VideoFrameCallbackMetadata);
        },
    });
    createElement.mockImplementationOnce(() => video);
    return video;
};

test("cellular metadata preload does not draw an empty cover before the first frame is decoded", async () => {
    const video = nativeVideo();
    const revoke = vi.spyOn(URL, "revokeObjectURL");
    alpha = 0;
    const pending = spaceVideoCover(new Blob(["video"]), 0);
    const settled = vi.fn();
    void pending.then(settled, settled);
    video.dispatchEvent(new Event("loadeddata"));
    await vi.waitFor(() =>
        expect(video.requestVideoFrameCallback).toHaveBeenCalledOnce(),
    );
    expect(settled).not.toHaveBeenCalled();
    expect(createElement).not.toHaveBeenCalledWith("canvas");
    video.presentFrame();
    await expect(pending).resolves.toMatchObject({ width: 540, height: 960 });
    expect(mocks.frames).not.toHaveBeenCalled();
    expect(video.pause).toHaveBeenCalledOnce();
    expect(revoke).toHaveBeenCalledOnce();
});

test("registers the first-frame callback before loading a video on Wi-Fi", async () => {
    const video = nativeVideo();
    video.load.mockImplementationOnce(() => {
        expect(video.requestVideoFrameCallback).toHaveBeenCalledOnce();
        video.presentFrame();
        video.dispatchEvent(new Event("loadeddata"));
    });
    await expect(
        spaceVideoCover(new Blob(["video"]), 0),
    ).resolves.toBeDefined();
});

test.each(["abort", "error", "timeout"])(
    "releases a pending frame callback and local video URL on %s",
    async (reason) => {
        vi.useFakeTimers();
        const video = nativeVideo();
        const revoke = vi.spyOn(URL, "revokeObjectURL");
        const controller = new AbortController();
        const pending = spaceVideoCover(
            new Blob(["video"]),
            0,
            controller.signal,
        );
        const rejected = expect(pending).rejects.toThrow(
            reason == "abort"
                ? "Canceled"
                : reason == "error"
                  ? "can't preview"
                  : "too long to load",
        );
        if (reason == "abort") controller.abort();
        else if (reason == "error") video.dispatchEvent(new Event("error"));
        else await vi.advanceTimersByTimeAsync(30_000);
        await rejected;
        expect(video.cancelVideoFrameCallback).toHaveBeenCalledWith(7);
        expect(video.pause).toHaveBeenCalledOnce();
        expect(revoke).toHaveBeenCalledOnce();
        expect(createElement).not.toHaveBeenCalledWith("canvas");
        expect(vi.getTimerCount()).toBe(0);
    },
);

test.each([
    [
        "Mozilla/5.0 (Android 16; Mobile; rv:143.0) Gecko/143.0 Firefox/143.0",
        true,
    ],
    ["Mozilla/5.0 (Android 16) Chrome/140.0.0.0 Mobile Safari/537.36", false],
    [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:143.0) Gecko/20100101 Firefox/143.0",
        false,
    ],
])(
    "selects software frames only for Firefox Android (%s)",
    async (userAgent, software) => {
        vi.stubGlobal("navigator", { userAgent });
        if (!software) {
            vi.stubGlobal("window", { setTimeout, clearTimeout });
            const video = Object.assign(new EventTarget(), {
                duration: 3.45,
                videoWidth: 540,
                videoHeight: 960,
                currentTime: 0,
                pause: vi.fn(),
                removeAttribute: vi.fn(),
                load: () => video.dispatchEvent(new Event("loadeddata")),
            });
            createElement.mockImplementationOnce(() => video);
        }
        const file = new Blob(["video"]);
        expect(await spaceVideoFrames(file, [0], 960)).toHaveLength(1);
        expect(mocks.frames).toHaveBeenCalledTimes(software ? 1 : 0);
        expect(createElement).toHaveBeenCalledWith(
            software ? "canvas" : "video",
        );
    },
);

test("Firefox Android gets metadata and a cover without creating a video element", async () => {
    const file = new File(["video"], "private-video.mp4");
    const controller = new AbortController();
    expect(await spaceVideoInfo(file, controller.signal)).toMatchObject({
        width: 1080,
        height: 1920,
    });
    const cover = await spaceVideoCover(file, 1.25, controller.signal);
    expect(mocks.frames).toHaveBeenCalledWith(
        file,
        [1.25],
        960,
        controller.signal,
    );
    expect(cover).toMatchObject({ width: 540, height: 960, thumbHash: "hash" });
    expect(cover.file.type).toBe("image/webp");
    expect(bitmapClose).toHaveBeenCalledOnce();
    expect(JSON.stringify(mocks.log.mock.calls)).not.toContain("private-video");
});

test("opaque black frames are valid covers, but unreadable transparent frames fail", async () => {
    const file = new Blob(["video"]);
    await expect(spaceVideoCover(file, 0)).resolves.toBeDefined();
    alpha = 0;
    await expect(spaceVideoCover(file, 0)).rejects.toThrow(
        "Couldn't read a video frame",
    );
    expect(bitmapClose).toHaveBeenCalledTimes(2);
    expect(mocks.log).toHaveBeenCalledWith(
        expect.stringContaining("frames failed backend=wasm"),
    );
});

test("timeline frame extraction is batched and releases each decoded image", async () => {
    const file = new Blob(["video"]);
    const times = [0.5, 1.5, 2.5];
    mocks.frames.mockResolvedValue(times.map(() => new Blob(["png"])));
    expect(await spaceVideoFrames(file, times, 128)).toHaveLength(3);
    expect(mocks.frames).toHaveBeenCalledWith(file, times, 128, undefined);
    expect(bitmapClose).toHaveBeenCalledTimes(3);
});

test("canceling frame extraction does not leave decoded bitmaps or return a cover", async () => {
    const controller = new AbortController();
    mocks.frames.mockImplementation(() => {
        controller.abort();
        return Promise.resolve([new Blob(["png"])]);
    });
    await expect(
        spaceVideoCover(new Blob(["video"]), 0, controller.signal),
    ).rejects.toMatchObject({ name: "AbortError" });
    expect(createImageBitmap).not.toHaveBeenCalled();
});

const videoEdit = { start: 0, end: 3.45, coverTime: 0, muted: false };

test("posting joins the draft export and uses the latest cover without encoding twice", async () => {
    let finish!: (bytes: Uint8Array) => void;
    mocks.transcode.mockImplementationOnce(
        () =>
            new Promise<Uint8Array>((resolve) => {
                finish = resolve;
            }),
    );
    const file = new File(["source"], "source.mov");
    const job = startSpaceVideoExport(file, videoEdit);
    await vi.waitFor(() => expect(mocks.transcode).toHaveBeenCalledOnce());
    const prepared = prepareSpaceVideo(
        file,
        { ...videoEdit, coverTime: 1.25 },
        undefined,
        job.promise,
    );
    finish(new Uint8Array([4, 5, 6]));
    const result = await prepared;
    expect(mocks.transcode).toHaveBeenCalledOnce();
    expect(result.video.file).toBe((await job.promise).file);
    expect(result.video.durationMs).toBe(3450);
    expect(mocks.frames).toHaveBeenCalledWith(
        result.video.file,
        [1.25],
        960,
        undefined,
    );
});

test("completed exports survive cover changes while trim and mute edits produce new exports", async () => {
    const file = new File(["source"], "source.mov");
    const job = startSpaceVideoExport(file, videoEdit);
    await job.promise;
    job.cancel();
    await prepareSpaceVideo(file, { ...videoEdit, coverTime: 1 });
    expect(mocks.transcode).toHaveBeenCalledOnce();
    await startSpaceVideoExport(file, { ...videoEdit, start: 1 }).promise;
    expect(mocks.transcode).toHaveBeenCalledTimes(2);
    await startSpaceVideoExport(file, { ...videoEdit, start: 1, muted: true })
        .promise;
    expect(mocks.transcode).toHaveBeenCalledTimes(3);
});

test("discarding a draft cancels its export and allows a fresh attempt", async () => {
    mocks.transcode.mockImplementationOnce(
        (_file, _edit, _command, signal: AbortSignal) =>
            new Promise((_, reject) => {
                signal.addEventListener("abort", () =>
                    reject(signal.reason as Error),
                );
            }),
    );
    const file = new File(["source"], "source.mov");
    const job = startSpaceVideoExport(file, videoEdit);
    const rejected = expect(job.promise).rejects.toMatchObject({
        name: "AbortError",
    });
    await vi.waitFor(() => expect(mocks.transcode).toHaveBeenCalledOnce());
    job.cancel();
    await rejected;
    await startSpaceVideoExport(file, videoEdit).promise;
    expect(mocks.transcode).toHaveBeenCalledTimes(2);
});

test("canceling during output validation does not cache an abandoned export", async () => {
    let finish!: (duration: number) => void;
    mocks.duration.mockImplementationOnce(
        () =>
            new Promise<number>((resolve) => {
                finish = resolve;
            }),
    );
    const file = new File(["source"], "source.mov");
    const job = startSpaceVideoExport(file, videoEdit);
    const rejected = expect(job.promise).rejects.toMatchObject({
        name: "AbortError",
    });
    await vi.waitFor(() => expect(mocks.duration).toHaveBeenCalledOnce());
    job.cancel();
    finish(3.45);
    await rejected;
    await startSpaceVideoExport(file, videoEdit).promise;
    expect(mocks.transcode).toHaveBeenCalledTimes(2);
});
