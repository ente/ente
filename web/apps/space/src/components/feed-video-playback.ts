import type { createSpaceVideoContent } from "components/PostVideoContent";

interface FeedVideo {
    element: HTMLElement;
    player: Pick<
        ReturnType<typeof createSpaceVideoContent>,
        "play" | "pause" | "deactivate"
    >;
    active: boolean;
    manuallyPaused: boolean;
}

const posts = new Map<HTMLElement, boolean>();
const videos = new Map<Element, FeedVideo>();
let selected: FeedVideo | undefined;
let manual: FeedVideo | undefined;
let interactedPost: HTMLElement | undefined;
let observer: IntersectionObserver | undefined;
let frame: number | undefined;
let pending: FeedVideo | undefined;
let selectionTimer: ReturnType<typeof setTimeout> | undefined;

const select = (next: FeedVideo | undefined, userInitiated = false) => {
    if (selected == next) return;
    selected?.player.deactivate();
    selected = next;
    if (next && !next.manuallyPaused) next.player.play(userInitiated);
};

const isVisible = (element: HTMLElement) => {
    const rect = element.getBoundingClientRect();
    return rect.bottom > 0 && rect.top < window.innerHeight;
};

const update = () => {
    for (const video of videos.values()) {
        if (!isVisible(video.element)) {
            video.manuallyPaused = false;
            if (manual == video) manual = undefined;
        }
    }
    if (manual && !manual.active) manual = undefined;
    if (interactedPost && !isVisible(interactedPost))
        interactedPost = undefined;
    if (document.hidden) {
        clearTimeout(selectionTimer);
        selectionTimer = undefined;
        pending = undefined;
        select(undefined);
        return;
    }
    let focusedPost: HTMLElement | undefined;
    let firstTop = Infinity;
    for (const [element, visible] of posts) {
        if (!visible) continue;
        const rect = element.getBoundingClientRect();
        const visibleHeight =
            Math.min(rect.bottom, window.innerHeight) - Math.max(rect.top, 0);
        if (
            visibleHeight > 0 &&
            visibleHeight >= Math.min(rect.height, window.innerHeight) / 2 &&
            rect.top < firstTop
        ) {
            focusedPost = element;
            firstTop = rect.top;
        }
    }
    const next =
        manual ??
        [...videos.values()].find(
            (video) =>
                video.active &&
                (interactedPost ?? focusedPost)?.contains(video.element),
        );
    if (next && next != selected && next != manual) {
        if (pending != next) {
            pending = next;
            clearTimeout(selectionTimer);
            selectionTimer = setTimeout(() => {
                selectionTimer = undefined;
                update();
            }, 120);
        }
        if (selectionTimer != undefined) {
            select(undefined);
            return;
        }
    }
    clearTimeout(selectionTimer);
    selectionTimer = undefined;
    pending = undefined;
    select(next);
};

const scheduleUpdate = () => {
    frame ??= requestAnimationFrame(() => {
        frame = undefined;
        update();
    });
};

export const focusFeedPost = (element: HTMLElement) => {
    interactedPost = element;
    manual = undefined;
    scheduleUpdate();
};

export const registerFeedPost = (element: HTMLElement) => {
    if (!observer) {
        observer = new IntersectionObserver(
            (entries) => {
                for (const entry of entries) {
                    const element = entry.target as HTMLElement;
                    if (posts.has(element))
                        posts.set(element, entry.isIntersecting);
                }
                scheduleUpdate();
            },
            { threshold: [0, 0.5, 1] },
        );
        window.addEventListener("scroll", scheduleUpdate, { passive: true });
        window.addEventListener("resize", scheduleUpdate);
        document.addEventListener("visibilitychange", update);
    }
    posts.set(element, false);
    observer.observe(element);
    return () => {
        posts.delete(element);
        if (interactedPost == element) interactedPost = undefined;
        observer!.unobserve(element);
        if (manual && element.contains(manual.element)) manual = undefined;
        if (selected && element.contains(selected.element)) select(undefined);
        if (posts.size) {
            scheduleUpdate();
        } else {
            observer!.disconnect();
            observer = undefined;
            if (frame != undefined) cancelAnimationFrame(frame);
            frame = undefined;
            clearTimeout(selectionTimer);
            selectionTimer = undefined;
            pending = undefined;
            window.removeEventListener("scroll", scheduleUpdate);
            window.removeEventListener("resize", scheduleUpdate);
            document.removeEventListener("visibilitychange", update);
        }
    };
};

export const registerFeedVideo = (
    element: HTMLElement,
    player: FeedVideo["player"],
) => {
    const video: FeedVideo = {
        element,
        player,
        active: false,
        manuallyPaused: false,
    };
    videos.set(element, video);
    return {
        setActive: (active: boolean) => {
            video.active = active;
            if (!active && selected == video) select(undefined);
            scheduleUpdate();
        },
        play: () => {
            if (!video.active || document.hidden || !isVisible(element)) return;
            video.manuallyPaused = false;
            manual = video;
            interactedPost = undefined;
            const wasSelected = selected == video;
            select(video, true);
            if (wasSelected) player.play(true);
        },
        pause: () => {
            video.manuallyPaused = true;
            player.pause();
        },
        unregister: () => {
            videos.delete(element);
            if (manual == video) manual = undefined;
            if (selected == video) select(undefined);
            if (posts.size) scheduleUpdate();
        },
    };
};
