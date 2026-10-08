import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { createVideoTrimPlayback } from "../src/components/video-trim/playback";

vi.mock("ente-base/log-web", () => ({ logToDisk: vi.fn() }));

class Video extends EventTarget {
    currentTime = 0;
    paused = true;
    seeking = false;
    readyState = 4;

    play() {
        this.paused = false;
        this.dispatchEvent(new Event("play"));
        return Promise.resolve();
    }

    pause() {
        if (this.paused) return;
        this.paused = true;
        this.dispatchEvent(new Event("pause"));
    }
}

let video: Video;
let range: { start: number; end: number };
let onError = vi.fn<() => void>();
let playback: ReturnType<typeof createVideoTrimPlayback>;
let frames: Map<number, FrameRequestCallback>;

beforeEach(() => {
    video = new Video();
    range = { start: 5, end: 8 };
    onError = vi.fn<() => void>();
    frames = new Map();
    let nextFrame = 0;
    vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
        frames.set(++nextFrame, callback);
        return nextFrame;
    });
    vi.stubGlobal("cancelAnimationFrame", (id: number) => frames.delete(id));
    playback = createVideoTrimPlayback(
        video as unknown as HTMLVideoElement,
        () => range,
        onError,
    );
});

afterEach(() => {
    playback.dispose();
    vi.unstubAllGlobals();
    vi.useRealTimers();
});

const renderFrame = () => {
    const callbacks = [...frames.values()];
    frames.clear();
    callbacks.forEach((callback) => callback(0));
};

test("Play previews the selected clip from its start after trimming either edge", () => {
    playback.seek(7.95);
    playback.toggle();
    expect(video.currentTime).toBe(5);
    expect(video.paused).toBe(false);
});

test("playback stops at the trim end without waiting for a timeupdate event", () => {
    playback.toggle();
    video.currentTime = 8.01;
    renderFrame();
    expect(video.paused).toBe(true);
    expect(video.currentTime).toBe(5);
    expect(frames.size).toBe(0);
    playback.toggle();
    expect(video.currentTime).toBe(5);
    expect(video.paused).toBe(false);
});

test("pause and resume inside the clip retain the playback position", () => {
    playback.toggle();
    video.currentTime = 6;
    playback.toggle();
    expect(video.paused).toBe(true);
    expect(frames.size).toBe(0);
    playback.toggle();
    expect(video.currentTime).toBe(6);
    expect(video.paused).toBe(false);
});

test("Play supersedes a preview seek that is still in progress", () => {
    video.currentTime = 6;
    video.seeking = true;
    playback.seek(7.95);
    playback.toggle();
    video.seeking = false;
    video.dispatchEvent(new Event("seeked"));
    expect(video.currentTime).toBe(5);
    expect(video.paused).toBe(false);
});

test("returning to the current frame cancels an older queued preview seek", () => {
    video.currentTime = 5;
    video.seeking = true;
    playback.seek(7);
    playback.seek(5);
    video.seeking = false;
    video.dispatchEvent(new Event("seeked"));
    expect(video.currentTime).toBe(5);
    video.currentTime = 6;
    video.dispatchEvent(new Event("seeked"));
    expect(video.currentTime).toBe(6);
});

test("the playback guard uses the latest trim bounds", () => {
    playback.toggle();
    range = { start: 5, end: 6 };
    video.currentTime = 6.01;
    renderFrame();
    expect(video.paused).toBe(true);
    expect(video.currentTime).toBe(5);
});

test("an out-of-range playback position is corrected to the trim start", () => {
    playback.toggle();
    video.currentTime = 0;
    renderFrame();
    expect(video.currentTime).toBe(5);
    expect(video.paused).toBe(false);
});

test("Play before metadata loads keeps the selected start and does not get paused", () => {
    video.readyState = 0;
    playback.seek(7);
    playback.toggle();
    video.readyState = 1;
    video.dispatchEvent(new Event("loadedmetadata"));
    expect(video.currentTime).toBe(5);
    expect(video.paused).toBe(false);
});

test("a second tap cancels pending playback without reporting an error", async () => {
    let rejectPlay: (error: Error) => void;
    vi.spyOn(video, "play").mockImplementation(
        () => new Promise((_, reject) => (rejectPlay = reject)),
    );
    playback.toggle();
    playback.toggle();
    rejectPlay!(new Error("Play interrupted"));
    await Promise.resolve();
    expect(video.paused).toBe(true);
    expect(onError).not.toHaveBeenCalled();
    expect(frames.size).toBe(0);
});

test("trimming cancels pending playback and the next Play uses the new range", async () => {
    let rejectPlay: (error: Error) => void;
    const play = vi
        .spyOn(video, "play")
        .mockImplementationOnce(
            () => new Promise((_, reject) => (rejectPlay = reject)),
        );
    playback.toggle();
    range = { start: 20, end: 22 };
    playback.seek(21.95);
    playback.toggle();
    rejectPlay!(new Error("Play interrupted"));
    await Promise.resolve();
    expect(play).toHaveBeenCalledTimes(2);
    expect(video.currentTime).toBe(20);
    expect(video.paused).toBe(false);
    expect(onError).not.toHaveBeenCalled();
});

test("reaching the source end resets the selected clip for replay", () => {
    playback.toggle();
    video.currentTime = 8;
    video.paused = true;
    video.dispatchEvent(new Event("ended"));
    expect(video.currentTime).toBe(5);
    expect(frames.size).toBe(0);
});

test("closing the editor pauses playback and removes the frame monitor", () => {
    playback.toggle();
    playback.dispose();
    expect(video.paused).toBe(true);
    expect(frames.size).toBe(0);
    video.currentTime = 12;
    video.dispatchEvent(new Event("timeupdate"));
    expect(video.currentTime).toBe(12);
});

test("a stuck preview reports an error and can be played again", async () => {
    vi.useFakeTimers();
    vi.spyOn(video, "play").mockImplementationOnce(
        () => new Promise(() => undefined),
    );
    playback.toggle();
    await vi.advanceTimersByTimeAsync(30_000);
    expect(onError).toHaveBeenCalledTimes(1);
    playback.toggle();
    expect(video.paused).toBe(false);
    video.dispatchEvent(new Event("playing"));
    await vi.advanceTimersByTimeAsync(30_000);
    expect(onError).toHaveBeenCalledTimes(1);
});

test("closing or pausing a loading preview cancels its timeout", async () => {
    vi.useFakeTimers();
    vi.spyOn(video, "play").mockImplementationOnce(
        () => new Promise(() => undefined),
    );
    playback.toggle();
    playback.dispose();
    await vi.advanceTimersByTimeAsync(30_000);
    expect(onError).not.toHaveBeenCalled();
});
