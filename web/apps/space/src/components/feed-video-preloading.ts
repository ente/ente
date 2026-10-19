interface VideoLoad {
    element: HTMLElement;
    load: () => Promise<string>;
    start: () => void;
    resolve: (url: string) => void;
    reject: (error: unknown) => void;
}

const queued = new Set<VideoLoad>();
let inFlight = 0;
let frame: number | undefined;
let foreground: VideoLoad | undefined;

const distance = ({ element }: VideoLoad) => {
    const rect = element.getBoundingClientRect();
    const post = element.closest("article")!.getBoundingClientRect();
    return (
        Math.max(0, rect.top - window.innerHeight, -rect.bottom) +
        Math.abs(rect.left - post.left)
    );
};

const schedule = () => {
    if (!queued.size || inFlight >= 3) return;
    frame ??= requestAnimationFrame(() => {
        frame = undefined;
        for (const request of queued) {
            if (!request.element.isConnected) {
                queued.delete(request);
                if (foreground == request) foreground = undefined;
                request.reject(
                    new DOMException("Video preload canceled", "AbortError"),
                );
            }
        }
        const next = [...queued].sort(
            (a, b) =>
                Number(b == foreground) - Number(a == foreground) ||
                distance(a) - distance(b),
        );
        for (const request of next) {
            if (inFlight >= (request == foreground ? 3 : 2)) continue;
            queued.delete(request);
            inFlight++;
            request.start();
            void (async () => {
                try {
                    request.resolve(await request.load());
                } catch (error) {
                    request.reject(error);
                } finally {
                    inFlight--;
                    if (foreground == request) foreground = undefined;
                    schedule();
                }
            })();
        }
    });
};

export const queueFeedVideoLoad = (
    element: HTMLElement,
    load: VideoLoad["load"],
) => {
    let start: () => void;
    const started = new Promise<void>((resolve) => {
        start = resolve;
    });
    let request: VideoLoad;
    const promise = new Promise<string>((resolve, reject) => {
        request = { element, load, start, resolve, reject };
        queued.add(request);
        schedule();
    });
    return {
        promise,
        prioritize: () => {
            if (queued.has(request)) {
                foreground = request;
                schedule();
            }
            return Promise.race([started, promise.then(() => undefined)]);
        },
        deprioritize: () => {
            if (foreground == request) foreground = undefined;
        },
        cancel: () => {
            if (foreground == request) foreground = undefined;
            if (!queued.delete(request)) return;
            request.reject(
                new DOMException("Video preload canceled", "AbortError"),
            );
            if (!queued.size && frame != undefined) {
                cancelAnimationFrame(frame);
                frame = undefined;
            }
        },
    };
};
