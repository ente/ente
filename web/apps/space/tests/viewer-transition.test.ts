import { afterEach, expect, test, vi } from "vitest";
import {
    playViewerClose,
    playViewerOpen,
    viewerOriginKey,
    viewerVideoFrame,
} from "../src/components/viewer-transition";
import { fullPhotoState } from "../src/utils/viewer-geometry";

afterEach(() => vi.unstubAllGlobals());

test("tiles are matched by space and post", () => {
    expect(viewerOriginKey("space", 12)).toBe("space:12");
    expect(viewerOriginKey("space", 0)).toBe("space:0");
    expect(viewerOriginKey(undefined, 12)).toBeUndefined();
    expect(viewerOriginKey("space", undefined)).toBeUndefined();
});

const pendingFlight = (video?: HTMLVideoElement) => {
    let resolveDecode!: () => void;
    let rejectDecode!: (error: Error) => void;
    const decoded = new Promise<void>((resolve, reject) => {
        resolveDecode = resolve;
        rejectDecode = reject;
    });
    const flyer = {
        style: {} as Record<string, string>,
        setAttribute: vi.fn(),
        append: vi.fn(),
        remove: vi.fn(),
    };
    const image = { style: {}, src: "", decode: () => decoded };
    const drawFrame = vi.fn();
    const frame = {
        style: {},
        width: 0,
        height: 0,
        getContext: () => ({ drawImage: drawFrame }),
    };
    const origin = {
        style: { opacity: "" },
        closest: () => null,
        getBoundingClientRect: () => ({
            left: 10,
            top: 20,
            width: 100,
            height: 100,
        }),
        querySelector: (selector: string) =>
            selector == "video"
                ? (video ?? null)
                : selector == "img[aria-hidden]"
                  ? { currentSrc: "data:thumbnail" }
                  : null,
    };
    vi.stubGlobal("document", {
        createElement: (tag: string) =>
            tag == "canvas" ? frame : tag == "img" ? image : flyer,
    });
    vi.stubGlobal("window", {
        innerWidth: 390,
        innerHeight: 844,
        matchMedia: () => ({ matches: false }),
    });
    vi.stubGlobal("getComputedStyle", () => ({
        borderTopLeftRadius: "24px",
        borderTopRightRadius: "24px",
        borderBottomRightRadius: "0px",
        borderBottomLeftRadius: "0px",
    }));
    const requestFrame = vi.fn<(callback: FrameRequestCallback) => number>(
        () => 1,
    );
    vi.stubGlobal("requestAnimationFrame", requestFrame);
    vi.stubGlobal("cancelAnimationFrame", vi.fn());
    const onLanded = vi.fn();
    const flight = playViewerOpen(
        { dataset: {}, prepend: vi.fn() } as unknown as HTMLElement,
        {
            origin: origin as unknown as HTMLElement,
            src: "full-photo",
            photo: { width: 200, height: 100 },
        },
        { x: 0, y: 100, w: 390, h: 195 },
        vi.fn(),
        onLanded,
    )!;
    return {
        flight,
        flyer,
        frame,
        drawFrame,
        image,
        origin,
        requestFrame,
        resolveDecode,
        rejectDecode,
        onLanded,
    };
};

test("the tile stays visible until its flying thumbnail has decoded", async () => {
    const { flight, flyer, image, origin, requestFrame, resolveDecode } =
        pendingFlight();
    expect(image.src).toBe("data:thumbnail");
    expect(origin.style.opacity).toBe("");
    expect(flyer.style.visibility).toBe("hidden");
    expect(flight.current()).toBeUndefined();
    expect(requestFrame).not.toHaveBeenCalled();

    resolveDecode();
    await Promise.resolve();

    expect(origin.style.opacity).toBe("0");
    expect(flyer.style.visibility).toBe("");
    expect(flight.current()?.radii).toEqual([24, 24, 0, 0]);
    expect(requestFrame).toHaveBeenCalledOnce();
    flight.stop();
});

test("closing before decoding cannot hide the tile afterward", async () => {
    const { flight, flyer, origin, requestFrame, resolveDecode } =
        pendingFlight();
    flight.stop();
    resolveDecode();
    await Promise.resolve();

    expect(origin.style.opacity).toBe("");
    expect(flyer.remove).toHaveBeenCalledOnce();
    expect(requestFrame).not.toHaveBeenCalled();
});

test("a failed flyer leaves the tile visible and allows viewer handover", async () => {
    const { flight, origin, onLanded, rejectDecode } = pendingFlight();
    rejectDecode(new Error("decode failed"));
    await Promise.resolve();

    expect(origin.style.opacity).toBe("");
    expect(onLanded).toHaveBeenCalledOnce();
    flight.stop();
});

test("a playing video opens with its current frame without decoding the poster", async () => {
    const video = {
        readyState: 2,
        HAVE_CURRENT_DATA: 2,
        videoWidth: 1920,
        videoHeight: 1080,
    } as HTMLVideoElement;
    const { flight, flyer, frame, drawFrame, origin, requestFrame } =
        pendingFlight(video);

    expect(frame.width).toBe(1920);
    expect(frame.height).toBe(1080);
    expect(drawFrame).toHaveBeenCalledExactlyOnceWith(video, 0, 0);
    expect(flight.src).toBe(frame);
    expect(flyer.append).toHaveBeenCalledWith(frame);
    await Promise.resolve();
    expect(origin.style.opacity).toBe("0");
    expect(requestFrame).toHaveBeenCalledOnce();
    flight.stop();
});

test("a video without a decoded frame opens using its poster", async () => {
    const { flight, drawFrame, image, origin, resolveDecode } = pendingFlight({
        readyState: 1,
        HAVE_CURRENT_DATA: 2,
    } as HTMLVideoElement);

    expect(drawFrame).not.toHaveBeenCalled();
    expect(image.src).toBe("data:thumbnail");
    expect(origin.style.opacity).toBe("");
    resolveDecode();
    await Promise.resolve();
    expect(origin.style.opacity).toBe("0");
    flight.stop();
});

const closingFlight = (src: string | HTMLCanvasElement = "full-photo") => {
    const { flight, origin, requestFrame } = pendingFlight();
    flight.stop();
    vi.mocked(cancelAnimationFrame).mockClear();
    origin.querySelector = (selector) =>
        selector.startsWith("img") ? { currentSrc: "full-photo" } : null;
    const fade = { cancel: vi.fn(), addEventListener: vi.fn() };
    const elements: {
        style: Record<string, string>;
        inert: boolean;
        remove: ReturnType<typeof vi.fn>;
        animate: ReturnType<typeof vi.fn>;
    }[] = [];
    const after = vi.fn();
    vi.stubGlobal("document", {
        createElement: () => {
            const element = {
                style: {} as Record<string, string>,
                inert: false,
                setAttribute: vi.fn(),
                append: vi.fn(),
                prepend: vi.fn(),
                remove: vi.fn(),
                decode: () => Promise.resolve(),
                animate: vi.fn(() => fade),
            };
            elements.push(element);
            return element;
        },
    });
    let nextFrame: FrameRequestCallback | undefined;
    let now = performance.now();
    requestFrame.mockImplementation((callback: FrameRequestCallback) => {
        nextFrame = callback;
        return 1;
    });
    const target = {
        origin: origin as unknown as HTMLElement,
        src,
        photo: { width: 200, height: 100 },
    };
    const rect = { x: 0, y: 100, w: 390, h: 195 };
    playViewerClose(
        { after } as unknown as HTMLElement,
        target,
        fullPhotoState(rect),
        { x: 0, y: 0 },
        1,
    );
    const finishSpring = () => {
        for (let i = 0; nextFrame && i < 100; i++) {
            const frame = nextFrame;
            nextFrame = undefined;
            now += 16;
            frame(now);
        }
        expect(nextFrame).toBeUndefined();
    };
    const reopen = () =>
        playViewerOpen(
            { dataset: {}, prepend: vi.fn() } as unknown as HTMLElement,
            target,
            rect,
            vi.fn(),
            vi.fn(),
        )!;
    return { root: elements[0]!, after, origin, fade, finishSpring, reopen };
};

test("closing animates outside the viewer without intercepting feed taps", () => {
    const { root, after, origin, finishSpring } = closingFlight();
    expect(after).toHaveBeenCalledWith(root);
    expect(root.style.pointerEvents).toBe("none");
    expect(root.inert).toBe(true);
    expect(origin.style.opacity).toBe("0");
    finishSpring();
    expect(root.remove).toHaveBeenCalledOnce();
    expect(origin.style.opacity).toBe("");
});

test("reopening a photo cancels its unfinished close animation", () => {
    const { root, origin, reopen } = closingFlight();
    const flight = reopen();
    expect(root.remove).toHaveBeenCalledOnce();
    expect(cancelAnimationFrame).toHaveBeenCalledExactlyOnceWith(1);
    expect(origin.style.opacity).toBe("");
    flight.stop();
});

test("reopening during the thumbnail fade cancels the old overlay", () => {
    const { root, fade, finishSpring, reopen } = closingFlight("other-photo");
    finishSpring();
    expect(root.animate).toHaveBeenCalledOnce();
    expect(root.remove).not.toHaveBeenCalled();
    const flight = reopen();
    expect(fade.cancel).toHaveBeenCalledOnce();
    expect(root.remove).toHaveBeenCalledOnce();
    flight.stop();
});

test("closing a video keeps its captured frame until it fades into the tile", () => {
    const { flight, frame } = pendingFlight();
    flight.stop();
    const snapshot = viewerVideoFrame({
        readyState: 2,
        HAVE_CURRENT_DATA: 2,
        videoWidth: 1920,
        videoHeight: 1080,
    } as HTMLVideoElement)!;
    expect(snapshot).toBe(frame);

    const { root, origin, fade, finishSpring } = closingFlight(snapshot);
    expect(origin.style.opacity).toBe("0");
    expect(snapshot.style.transform).toBeDefined();
    finishSpring();
    expect(origin.style.opacity).toBe("");
    expect(root.animate).toHaveBeenCalledOnce();
    expect(root.remove).not.toHaveBeenCalled();
    const finish = fade.addEventListener.mock.calls[0]![1] as () => void;
    finish();
    expect(root.remove).toHaveBeenCalledOnce();
});
