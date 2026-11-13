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

const canvas = () => ({
    width: 540,
    height: 960,
    toBlob: (callback: BlobCallback) =>
        callback(new Blob(["cover"], { type: "image/webp" })),
});

beforeEach(() => {
    vi.resetAllMocks();
    mocks.frames.mockImplementation(() => Promise.resolve([canvas()]));
    mocks.info.mockResolvedValue({ duration: 3.45, width: 1080, height: 1920 });
    mocks.transcode.mockResolvedValue(new Uint8Array([1, 2, 3]));
    mocks.duration.mockResolvedValue(3.45);
});
afterEach(() => {
    vi.restoreAllMocks();
});

test("prepares metadata and a cover from decoded media without exposing file names in logs", async () => {
    const file = new File(["video"], "private-video.mp4");
    const controller = new AbortController();
    expect(await spaceVideoInfo(file, controller.signal)).toEqual({
        duration: 3.45,
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
    expect(JSON.stringify(mocks.log.mock.calls)).not.toContain("private-video");
});

test("timeline frame extraction is batched", async () => {
    const file = new Blob(["video"]);
    const times = [0.5, 1.5, 2.5];
    mocks.frames.mockResolvedValue(times.map(canvas));
    expect(await spaceVideoFrames(file, times, 128)).toHaveLength(3);
    expect(mocks.frames).toHaveBeenCalledWith(file, times, 128, undefined);
});

test("canceling cover generation does not return a prepared cover", async () => {
    const controller = new AbortController();
    mocks.frames.mockImplementation(() => {
        controller.abort();
        return Promise.resolve([canvas()]);
    });
    await expect(
        spaceVideoCover(new Blob(["video"]), 0, controller.signal),
    ).rejects.toMatchObject({ name: "AbortError" });
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
        (_file, _edit, signal: AbortSignal) =>
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

test.each([0, Number.NaN, 10.04])(
    "rejects an invalid exported duration (%s)",
    async (duration) => {
        mocks.duration.mockResolvedValue(duration);
        const file = new File(["source"], "source.mov");
        await expect(
            startSpaceVideoExport(file, videoEdit).promise,
        ).rejects.toThrow("Couldn't export a video within 10 seconds");
    },
);

test("rejects an oversized export before preparing its cover", async () => {
    mocks.transcode.mockResolvedValue(new Uint8Array(15 * 1024 * 1024));
    const file = new File(["source"], "source.mov");
    await expect(prepareSpaceVideo(file, videoEdit)).rejects.toThrow(
        "too large",
    );
    expect(mocks.frames).not.toHaveBeenCalled();
});
