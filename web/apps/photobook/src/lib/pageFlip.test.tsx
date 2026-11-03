import { PageFlip } from "page-flip";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

let book: PageFlip;
let frames: Map<number, FrameRequestCallback>;
let nextFrame: number;
let host: HTMLDivElement;

beforeEach(() => {
    vi.useFakeTimers();
    frames = new Map();
    nextFrame = 0;
    vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
        frames.set(++nextFrame, callback);
        return nextFrame;
    });
    vi.stubGlobal("cancelAnimationFrame", (id: number) => frames.delete(id));
    vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockReturnValue(1000);
    vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockReturnValue(500);
    host = document.createElement("div");
    document.body.append(host);
    const pages = Array.from({ length: 300 }, () =>
        document.createElement("div"),
    );
    host.append(...pages);
    book = new PageFlip(host, {
        width: 500,
        height: 500,
        showCover: true,
        usePortrait: false,
    });
    book.loadFromHTML(pages);
    vi.advanceTimersByTime(1);
});
afterEach(() => {
    book.destroy();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    vi.useRealTimers();
});

function frame(time: number) {
    const callbacks = [...frames.values()];
    frames.clear();
    callbacks.forEach((callback) => callback(time));
}

test("300 idle pages stop producing DOM writes until navigation or resize", () => {
    frame(16);
    const observer = new MutationObserver(vi.fn());
    observer.observe(host, { attributes: true, subtree: true });
    frame(32);
    frame(48);
    expect(observer.takeRecords()).toHaveLength(0);
    book.turnToPage(200);
    frame(64);
    expect(observer.takeRecords().length).toBeGreaterThan(0);
    frame(80);
    expect(observer.takeRecords()).toHaveLength(0);
    book.update();
    frame(96);
    expect(observer.takeRecords().length).toBeGreaterThan(0);
    observer.disconnect();
});

test("destroy cancels the loop and an in-progress flip", () => {
    frame(16);
    book.flipNext("bottom");
    frame(32);
    const flipped = vi.fn();
    book.on("flip", flipped);
    book.destroy();
    expect(frames.size).toBe(0);
    frame(10000);
    expect(flipped).not.toHaveBeenCalled();
});

test("flipping touches only the active pages in a 300-page book", () => {
    frame(16);
    book.turnToPage(100);
    frame(32);
    const observer = new MutationObserver(vi.fn());
    observer.observe(host, { attributes: true, subtree: true });
    book.flipNext("bottom");
    frame(48);
    frame(64);
    const touched = new Set(
        observer
            .takeRecords()
            .map((record) =>
                (record.target as HTMLElement).closest(".stf__item"),
            )
            .filter(Boolean),
    );
    expect(touched.size).toBeGreaterThan(0);
    expect(touched.size).toBeLessThanOrEqual(6);
    observer.disconnect();
});
