import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { useDragDraft } from "./useDragDraft";

let root: Root;
let drag: ReturnType<typeof useDragDraft<number>>;
let frames: Map<number, FrameRequestCallback>;
let nextFrame: number;
const commit = vi.fn();

beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    frames = new Map();
    nextFrame = 0;
    vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
        frames.set(++nextFrame, callback);
        return nextFrame;
    });
    vi.stubGlobal("cancelAnimationFrame", (id: number) => frames.delete(id));
    root = createRoot(document.createElement("div"));
    function Harness() {
        drag = useDragDraft<number>();
        return null;
    }
    act(() => root.render(<Harness />));
    commit.mockClear();
});
afterEach(() => {
    act(() => root.unmount());
    vi.unstubAllGlobals();
});

const move = (x: number) =>
    act(() => {
        document.dispatchEvent(new MouseEvent("mousemove", { clientX: x }));
    });
const release = (x: number) =>
    act(() => {
        document.dispatchEvent(new MouseEvent("mouseup", { clientX: x }));
    });

test("coalesces movement into one frame and commits only the final position", () => {
    act(() => drag.startDrag((event) => event.clientX, commit));
    for (let i = 1; i <= 100; i++) move(i);
    expect(frames.size).toBe(1);
    expect(commit).not.toHaveBeenCalled();
    act(() => {
        const callbacks = [...frames.values()];
        frames.clear();
        callbacks.forEach((callback) => callback(16));
    });
    expect(drag.draft).toBe(100);
    move(110);
    release(120);
    expect(commit).toHaveBeenCalledExactlyOnceWith(120);
    expect(frames.size).toBe(0);
    expect(drag.draft).toBeNull();
});

test("a click creates no commit, and unmount cancels a pending drag", () => {
    act(() => drag.startDrag((event) => event.clientX, commit));
    release(0);
    expect(commit).not.toHaveBeenCalled();
    act(() => drag.startDrag((event) => event.clientX, commit));
    move(20);
    act(() => root.render(null));
    expect(frames.size).toBe(0);
    release(30);
    expect(commit).not.toHaveBeenCalled();
});
