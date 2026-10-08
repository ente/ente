import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { queueFeedVideoLoad } from "../src/components/feed-video-preloading";

let viewport: { innerHeight: number; scrollY: number };
let frames: Map<number, FrameRequestCallback>;
let requests: (ReturnType<typeof queueFeedVideoLoad> & {
    download: PromiseWithResolvers<string>;
})[];
let started: string[];

beforeEach(() => {
    viewport = { innerHeight: 800, scrollY: 0 };
    frames = new Map();
    requests = [];
    started = [];
    let nextFrame = 0;
    vi.stubGlobal("window", viewport);
    vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
        frames.set(++nextFrame, callback);
        return nextFrame;
    });
    vi.stubGlobal("cancelAnimationFrame", (id: number) => frames.delete(id));
});

afterEach(async () => {
    for (const request of requests) {
        request.cancel();
        request.download.resolve("blob:cleanup");
    }
    await Promise.allSettled(requests.map((request) => request.promise));
    vi.unstubAllGlobals();
});

const flush = () => {
    const callbacks = [...frames.values()];
    frames.clear();
    callbacks.forEach((callback) => callback(0));
};

const enqueue = (name: string, top: number, slideOffset = 0) => {
    const position = { top, slideOffset, isConnected: true };
    const element = {
        get isConnected() {
            return position.isConnected;
        },
        getBoundingClientRect: () => ({
            top: position.top - viewport.scrollY,
            bottom: position.top + 300 - viewport.scrollY,
            left: 100 + position.slideOffset,
        }),
        closest: () =>
            position.isConnected
                ? { getBoundingClientRect: () => ({ left: 100 }) }
                : null,
    } as unknown as HTMLElement;
    const download = Promise.withResolvers<string>();
    const load = vi.fn(() => {
        started.push(name);
        return download.promise;
    });
    const control = queueFeedVideoLoad(element, load);
    void control.promise.catch(() => undefined);
    const request = { ...control, download, load, position };
    requests.push(request);
    return request;
};

test("downloads the nearest videos first and limits simultaneous loads to two", async () => {
    const far = enqueue("far", 2400);
    const next = enqueue("next", 1000);
    const visible = enqueue("visible", 100);
    flush();
    expect(started).toEqual(["visible", "next"]);
    expect(far.load).not.toHaveBeenCalled();
    visible.download.resolve("blob:visible");
    await visible.promise;
    flush();
    expect(started).toEqual(["visible", "next", "far"]);
    expect(next.load).toHaveBeenCalledTimes(1);
});

test("updates the priority of queued videos after scrolling", async () => {
    const first = enqueue("first", 100);
    enqueue("second", 500);
    enqueue("earlier", 1000);
    enqueue("later", 2500);
    flush();
    viewport.scrollY = 2300;
    first.download.resolve("blob:first");
    await first.promise;
    flush();
    expect(started).toEqual(["first", "second", "later"]);
});

test("active playback starts while both background downloads are still busy", async () => {
    enqueue("first", 100);
    enqueue("second", 500);
    const active = enqueue("active", 900);
    enqueue("background", 1200);
    flush();
    const ready = active.prioritize();
    flush();
    await ready;
    expect(started).toEqual(["first", "second", "active"]);
    expect(active.load).toHaveBeenCalledTimes(1);
    active.download.resolve("blob:active");
    await active.promise;
    flush();
    expect(started).toEqual(["first", "second", "active"]);
});

test("rapid scrolling keeps downloads bounded and starts the latest active video next", async () => {
    const first = enqueue("first", 100);
    enqueue("second", 500);
    const previous = enqueue("previous", 900);
    const skipped = enqueue("skipped", 1200);
    const active = enqueue("active", 1500);
    flush();
    const previousReady = previous.prioritize();
    flush();
    await previousReady;
    const skippedReady = skipped.prioritize();
    const ready = active.prioritize();
    flush();
    expect(started).toEqual(["first", "second", "previous"]);
    first.download.resolve("blob:first");
    await first.promise;
    flush();
    await ready;
    expect(started).toEqual(["first", "second", "previous", "active"]);
    skipped.cancel();
    await expect(skippedReady).rejects.toMatchObject({ name: "AbortError" });
});

test("an inactive video no longer uses the reserved playback slot", () => {
    enqueue("first", 100);
    enqueue("second", 500);
    const previous = enqueue("previous", 900);
    flush();
    void previous.prioritize().catch(() => undefined);
    previous.deprioritize();
    flush();
    expect(started).toEqual(["first", "second"]);
});

test("promoting an in-flight preload joins its existing download", async () => {
    const active = enqueue("active", 100);
    flush();
    await active.prioritize();
    expect(active.load).toHaveBeenCalledTimes(1);
});

test("prioritizes a visible slide and the next post over distant carousel slides", () => {
    enqueue("fifth slide", 100, 1200);
    enqueue("next post", 900);
    enqueue("visible slide", 100);
    flush();
    expect(started).toEqual(["visible slide", "next post"]);
});

test("swiping a queued carousel video into view moves it ahead in the queue", async () => {
    const first = enqueue("first", 100);
    enqueue("second", 400);
    const carousel = enqueue("carousel", 500, 1500);
    enqueue("lower post", 1500);
    flush();
    carousel.position.slideOffset = 0;
    first.download.resolve("blob:first");
    await first.promise;
    flush();
    expect(started).toEqual(["first", "second", "carousel"]);
});

test("canceling a queued preload prevents its network request", async () => {
    const canceled = enqueue("canceled", 100);
    canceled.cancel();
    await expect(canceled.promise).rejects.toMatchObject({
        name: "AbortError",
    });
    flush();
    expect(started).toEqual([]);
    expect(frames.size).toBe(0);
});

test("detaching a queued video before cleanup does not block other downloads", async () => {
    const detached = enqueue("detached", 100);
    enqueue("next", 500);
    enqueue("last", 900);
    detached.position.isConnected = false;
    flush();
    expect(started).toEqual(["next", "last"]);
    expect(detached.load).not.toHaveBeenCalled();
    await expect(detached.promise).rejects.toMatchObject({
        name: "AbortError",
    });
});

test("a detached video is canceled even when it is the only queued request", async () => {
    const detached = enqueue("detached", 100);
    detached.position.isConnected = false;
    flush();
    expect(started).toEqual([]);
    await expect(detached.promise).rejects.toMatchObject({
        name: "AbortError",
    });
});

test("an in-flight download retains its slot when its post is unmounted", async () => {
    const first = enqueue("first", 100);
    enqueue("second", 500);
    enqueue("third", 900);
    flush();
    first.cancel();
    flush();
    expect(started).toEqual(["first", "second"]);
    first.download.resolve("blob:first");
    await expect(first.promise).resolves.toBe("blob:first");
    flush();
    expect(started).toEqual(["first", "second", "third"]);
});

test("a failed download releases its slot for the next video", async () => {
    const first = enqueue("first", 100);
    enqueue("second", 500);
    enqueue("third", 900);
    flush();
    first.download.reject(new Error("offline"));
    await expect(first.promise).rejects.toThrow("offline");
    flush();
    expect(started).toEqual(["first", "second", "third"]);
});
