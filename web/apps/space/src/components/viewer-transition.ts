import {
    fullPhotoState,
    mixPhotoState,
    photoStateTravel,
    tilePhotoState,
    viewerBackgroundOpacity,
    type ViewerCornerRadii,
    type ViewerPhotoState,
    type ViewerRect,
} from "utils/viewer-geometry";

const originAttribute = "data-space-viewer-origin";
const openDuration = 0.48;
const openBounce = 0.26;
const closeDuration = 0.36;
const swapFadeMs = 220;
const closingFlights = new WeakMap<HTMLElement, () => void>();

export const viewerOriginKey = (spaceId?: string, postId?: number) =>
    spaceId && postId != undefined ? `${spaceId}:${postId}` : undefined;

export const findViewerOrigin = (key: string | undefined) =>
    key
        ? document.querySelector<HTMLElement>(
              `[${originAttribute}="${CSS.escape(key)}"]`,
          )
        : null;

interface ViewerFlightTarget {
    origin: HTMLElement;
    src: string;
    photo: { width: number; height: number };
}

const rectOf = (element: Element): ViewerRect => {
    const { left, top, width, height } = element.getBoundingClientRect();
    return { x: left, y: top, w: width, h: height };
};

const isOnScreen = (element: Element) => {
    const { x, y, w, h } = rectOf(element);
    return (
        w > 0 &&
        h > 0 &&
        x + w > 0 &&
        y + h > 0 &&
        x < window.innerWidth &&
        y < window.innerHeight
    );
};

const prefersReducedMotion = () =>
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

export const viewerCornerRadii = (
    element: Element,
    scale = 1,
): ViewerCornerRadii => {
    const style = getComputedStyle(element);
    return [
        style.borderTopLeftRadius,
        style.borderTopRightRadius,
        style.borderBottomRightRadius,
        style.borderBottomLeftRadius,
    ].map((radius) => (parseFloat(radius) || 0) * scale) as ViewerCornerRadii;
};

const runSpring = ({
    from,
    to,
    velocity,
    duration,
    bounce,
    restDelta,
    onUpdate,
    onDone,
}: {
    from: number;
    to: number;
    velocity: number;
    duration: number;
    bounce: number;
    restDelta: number;
    onUpdate: (value: number) => void;
    onDone: () => void;
}) => {
    const stiffness = ((2 * Math.PI) / duration) ** 2;
    const damping = ((1 - bounce) * 4 * Math.PI) / duration;
    let value = from;
    let speed = velocity;
    let last = performance.now();
    let frame = requestAnimationFrame(function tick(now) {
        const dt = Math.min(0.064, Math.max(0, (now - last) / 1000));
        last = now;
        const steps = Math.max(1, Math.ceil(dt / 0.002));
        for (let i = 0; i < steps; i++) {
            speed +=
                (-stiffness * (value - to) - damping * speed) * (dt / steps);
            value += speed * (dt / steps);
        }
        if (
            Math.abs(value - to) < restDelta &&
            Math.abs(speed) < restDelta * 20
        ) {
            onUpdate(to);
            onDone();
            return;
        }
        onUpdate(value);
        frame = requestAnimationFrame(tick);
    });
    return () => cancelAnimationFrame(frame);
};

// A cropping window and the photo inside it, both moved with transforms.
const createFlyer = (root: HTMLElement, src: string, base: ViewerRect) => {
    const flyer = document.createElement("div");
    flyer.setAttribute("aria-hidden", "true");
    Object.assign(flyer.style, {
        height: `${base.h}px`,
        left: "0",
        overflow: "hidden",
        pointerEvents: "none",
        position: "absolute",
        top: "0",
        transformOrigin: "0 0",
        width: `${base.w}px`,
        willChange: "transform",
        zIndex: "1",
    });
    const image = document.createElement("img");
    image.alt = "";
    image.src = src;
    Object.assign(image.style, {
        display: "block",
        height: `${base.h}px`,
        left: "0",
        position: "absolute",
        top: "0",
        transformOrigin: "0 0",
        width: `${base.w}px`,
        willChange: "transform",
    });
    flyer.append(image);
    root.prepend(flyer);

    const draw = ({ image: i, visible: v, radii }: ViewerPhotoState) => {
        const sx = v.w / base.w;
        const sy = v.h / base.h;
        flyer.style.transform = `translate3d(${v.x}px, ${v.y}px, 0) scale(${sx}, ${sy})`;
        flyer.style.borderRadius = `${radii.map((radius) => `${radius / sx}px`).join(" ")} / ${radii.map((radius) => `${radius / sy}px`).join(" ")}`;
        image.style.transform = `translate3d(${(i.x - v.x) / sx}px, ${(i.y - v.y) / sy}px, 0) scale(${i.w / v.w}, ${i.h / v.h})`;
    };
    return { flyer, image, draw };
};

const createRider = (flyer: HTMLElement, tile: HTMLElement) => {
    const card = tile.closest("article");
    const overlays = card?.querySelectorAll<HTMLElement>(
        "[data-space-viewer-header-shade], [data-space-viewer-header], [data-space-viewer-overlay]",
    );
    if (overlays?.length) {
        const bounds = rectOf(tile);
        const rider = document.createElement("div");
        rider.setAttribute("aria-hidden", "true");
        rider.inert = true;
        rider.append(
            ...Array.from(overlays, (overlay) => overlay.cloneNode(true)),
        );
        for (const element of rider.querySelectorAll("*"))
            if (element instanceof HTMLElement)
                element.style.animation = "none";
        Object.assign(rider.style, {
            height: `${bounds.h}px`,
            left: "0",
            overflow: "hidden",
            pointerEvents: "none",
            position: "absolute",
            top: "0",
            transformOrigin: "0 0",
            width: `${bounds.w}px`,
            willChange: "transform",
            zIndex: "2",
        });
        flyer.after(rider);
        for (const overlay of overlays) overlay.style.opacity = "0";
        return {
            element: rider,
            draw: ({ visible: v, radii }: ViewerPhotoState, t: number) => {
                const sx = v.w / bounds.w;
                const sy = v.h / bounds.h;
                rider.style.transform = `translate3d(${v.x}px, ${v.y}px, 0) scale(${sx}, ${sy})`;
                rider.style.borderRadius = `${radii.map((radius) => `${radius / sx}px`).join(" ")} / ${radii.map((radius) => `${radius / sy}px`).join(" ")}`;
                rider.style.opacity = String(
                    1 - viewerBackgroundOpacity(t / 0.35),
                );
            },
            remove: () => rider.remove(),
            reveal: () => {
                for (const overlay of overlays) overlay.style.opacity = "";
            },
        };
    }
    const button = tile.parentElement?.querySelector<HTMLElement>(
        "[data-space-viewer-avatar]",
    );
    const avatar = button?.firstElementChild;
    const badge = tile.querySelector<HTMLElement>(
        "[data-space-viewer-photos-badge]",
    );
    const elements: HTMLElement[] = [];
    if (button && avatar instanceof HTMLElement) elements.push(avatar);
    if (badge) elements.push(badge);
    if (!elements.length) return undefined;

    const tileRect = rectOf(tile);
    const rider = document.createElement("div");
    rider.setAttribute("aria-hidden", "true");
    rider.inert = true;
    Object.assign(rider.style, {
        left: "0",
        pointerEvents: "none",
        position: "absolute",
        top: "0",
        zIndex: "1",
    });
    const drawElements = elements.map((element) => {
        const bounds = rectOf(element);
        const clone = element.cloneNode(true) as HTMLElement;
        for (const child of [clone, ...clone.querySelectorAll("*")])
            if (child instanceof HTMLElement) child.style.animation = "none";
        Object.assign(clone.style, {
            left: "0",
            position: "absolute",
            right: "auto",
            top: "0",
        });
        rider.append(clone);
        element.style.opacity = "0";
        return (v: ViewerRect) => {
            const x =
                element == avatar
                    ? v.x + bounds.x - tileRect.x
                    : v.x + v.w - (tileRect.x + tileRect.w - bounds.x);
            const y =
                element == avatar
                    ? v.y + v.h - (tileRect.y + tileRect.h - bounds.y)
                    : v.y + bounds.y - tileRect.y;
            clone.style.transform = `translate3d(${x}px, ${y}px, 0)`;
        };
    });
    flyer.after(rider);

    return {
        element: rider,
        draw: ({ visible: v }: ViewerPhotoState, t: number) => {
            for (const drawElement of drawElements) drawElement(v);
            rider.style.opacity = String(
                1 - Math.min(1, Math.max(0, t / 0.35)),
            );
        },
        remove: () => rider.remove(),
        reveal: () => {
            for (const element of elements) element.style.opacity = "";
        },
    };
};

// The tile stays empty until reveal, and the flying photo stays until release.
export const playViewerOpen = (
    root: HTMLElement,
    { origin, src, photo }: ViewerFlightTarget,
    to: ViewerRect,
    setProgress: (t: number) => void,
    onLanded: () => void,
) => {
    closingFlights.get(origin)?.();
    if (prefersReducedMotion() || !isOnScreen(origin)) return undefined;

    const from = tilePhotoState(
        rectOf(origin),
        photo,
        viewerCornerRadii(origin),
    );
    let end = fullPhotoState(to);
    let t = 0;
    const tileImage = origin.querySelector<HTMLImageElement>(
        "img:not([aria-hidden])",
    );
    const thumbnail =
        origin.querySelector<HTMLImageElement>("img[aria-hidden]");
    const preview =
        tileImage?.complete && tileImage.naturalWidth > 0
            ? tileImage
            : thumbnail;
    const flightSrc = preview?.currentSrc || src;
    const { flyer, image, draw } = createFlyer(root, flightSrc, to);
    let rider: ReturnType<typeof createRider>;
    let started = false;
    let disposed = false;
    let stopSpring: () => void = () => undefined;
    const drawAt = (value: number) => {
        const state = mixPhotoState(from, end, value);
        draw(state);
        rider?.draw(state, value);
    };
    flyer.style.visibility = "hidden";
    root.dataset.spaceViewerWaiting = "true";
    drawAt(0);
    setProgress(0);

    const release = () => {
        disposed = true;
        flyer.remove();
        rider?.remove();
    };
    const reveal = () => {
        origin.style.opacity = "";
        rider?.reveal();
    };
    void image.decode().then(
        () => {
            if (disposed) return;
            started = true;
            flyer.style.visibility = "";
            origin.style.opacity = "0";
            delete root.dataset.spaceViewerWaiting;
            rider = createRider(flyer, origin);
            drawAt(0);
            stopSpring = runSpring({
                from: 0,
                to: 1,
                velocity: 0,
                duration: openDuration,
                bounce: openBounce,
                restDelta: 1.5 / Math.max(1, photoStateTravel(from, end)),
                onUpdate: (value) => {
                    t = value;
                    drawAt(t);
                    setProgress(t);
                },
                onDone: onLanded,
            });
        },
        () => {
            if (!disposed) onLanded();
        },
    );
    return {
        src: flightSrc,
        current: () => (started ? mixPhotoState(from, end, t) : undefined),
        release,
        reveal,
        retarget: (rect: ViewerRect) => {
            end = fullPhotoState(rect);
            drawAt(t);
        },
        stop: () => {
            stopSpring();
            release();
            reveal();
        },
    };
};

// throwVelocity is in px per ms. A photo other than the tile's fades into it.
export const playViewerClose = (
    viewerRoot: HTMLElement,
    { origin, src, photo }: ViewerFlightTarget,
    from: ViewerPhotoState,
    throwVelocity: { x: number; y: number },
    startBackground: number,
) => {
    if (prefersReducedMotion() || !isOnScreen(origin)) return undefined;

    const root = document.createElement("div");
    root.setAttribute("aria-hidden", "true");
    root.inert = true;
    Object.assign(root.style, {
        inset: "0",
        pointerEvents: "none",
        position: "fixed",
        zIndex: "1299",
    });
    viewerRoot.after(root);
    const end = tilePhotoState(
        rectOf(origin),
        photo,
        viewerCornerRadii(origin),
    );
    const { flyer, draw } = createFlyer(root, src, from.image);
    const rider = createRider(flyer, origin);
    const drawAt = (t: number) => {
        const state = mixPhotoState(end, from, t);
        draw(state);
        rider?.draw(state, t);
        root.style.backgroundColor = `rgb(0 0 0 / ${startBackground * viewerBackgroundOpacity(t)})`;
    };
    origin.style.opacity = "0";
    drawAt(1);

    const dx =
        end.visible.x +
        end.visible.w / 2 -
        (from.visible.x + from.visible.w / 2);
    const dy =
        end.visible.y +
        end.visible.h / 2 -
        (from.visible.y + from.visible.h / 2);
    const distance = Math.max(1, Math.hypot(dx, dy));
    const toward =
        ((throwVelocity.x * dx + throwVelocity.y * dy) / distance) * 1000;
    const tileImage = origin.querySelector<HTMLImageElement>(
        "img:not([aria-hidden])",
    );
    const isTilePhoto = tileImage?.currentSrc == src || tileImage?.src == src;
    let fade: Animation | undefined;

    const cleanUp = () => {
        fade?.cancel();
        origin.style.opacity = "";
        rider?.remove();
        rider?.reveal();
        root.remove();
        closingFlights.delete(origin);
    };
    const stopSpring = runSpring({
        from: 1,
        to: 0,
        velocity: Math.min(1.2, Math.max(-8, -toward / distance)),
        duration: closeDuration,
        bounce: 0,
        restDelta: 0.5 / Math.max(1, photoStateTravel(from, end)),
        onUpdate: drawAt,
        onDone: () => {
            origin.style.opacity = "";
            rider?.reveal();
            if (isTilePhoto) {
                cleanUp();
            } else {
                fade = root.animate([{ opacity: 1 }, { opacity: 0 }], {
                    duration: swapFadeMs,
                    easing: "ease",
                    fill: "forwards",
                });
                fade.addEventListener("finish", cleanUp, { once: true });
            }
        },
    });
    closingFlights.set(origin, () => {
        stopSpring();
        cleanUp();
    });
};
