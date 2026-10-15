import type { EffectCallback } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { useBrowserBackClose } from "../src/hooks/use-browser-back-close";

const mocks = vi.hoisted(() => ({
    effects: [] as EffectCallback[],
    back: vi.fn(),
}));

vi.mock("react", async (importOriginal) => ({
    ...(await importOriginal<typeof import("react")>()),
    useEffect: (effect: EffectCallback) => mocks.effects.push(effect),
}));

const route = {
    key: "post-route",
    as: "/app/posts/owner/42?likes=1",
    url: "/app/posts/[spaceId]/[postId]?spaceId=owner&postId=42&likes=1",
};

beforeEach(() => {
    mocks.effects = [];
    mocks.back.mockReset();
    const events = new EventTarget();
    const entries: Record<string, unknown>[] = [{ ...route }];
    const history = {
        get state() {
            return entries.at(-1);
        },
        pushState: (state: Record<string, unknown>) => entries.push(state),
        replaceState: (state: Record<string, unknown>) => {
            entries[entries.length - 1] = state;
        },
        back: mocks.back.mockImplementation(() => {
            entries.pop();
            events.dispatchEvent(
                Object.assign(new Event("popstate"), { state: history.state }),
            );
        }),
    };
    vi.stubGlobal("window", {
        history,
        location: { href: `https://space.test${route.as}` },
        addEventListener: events.addEventListener.bind(events),
        removeEventListener: events.removeEventListener.bind(events),
        setTimeout,
        clearTimeout,
    });
});

afterEach(() => vi.unstubAllGlobals());

const mountOverlay = (stateKey: string, onClose: () => void) => {
    const Overlay = () => {
        useBrowserBackClose({ open: true, onClose, stateKey });
        return null;
    };
    renderToStaticMarkup(<Overlay />);
    const cleanup = mocks.effects.pop()!();
    return () => {
        if (typeof cleanup == "function") cleanup();
    };
};

test("Android Back closes likes before the containing post viewer", () => {
    const closeViewer = vi.fn();
    const closeLikes = vi.fn();
    const unmountViewer = mountOverlay("space-feed-viewer", closeViewer);
    const unmountLikes = mountOverlay("space-post-likes", closeLikes);
    expect(window.history.state).toMatchObject(route);
    window.history.back();
    expect(closeLikes).toHaveBeenCalledOnce();
    expect(closeViewer).not.toHaveBeenCalled();
    unmountLikes();
    expect(mocks.back).toHaveBeenCalledTimes(1);
    window.history.back();
    expect(closeViewer).toHaveBeenCalledOnce();
    unmountViewer();
});

test("dismissing likes removes only its history entry and preserves the post route", () => {
    const closeViewer = vi.fn();
    const closeLikes = vi.fn();
    const unmountViewer = mountOverlay("space-profile-viewer", closeViewer);
    const viewerState: unknown = window.history.state;
    const unmountLikes = mountOverlay("space-post-likes", closeLikes);
    unmountLikes();
    expect(window.history.state).toEqual(viewerState);
    expect(closeViewer).not.toHaveBeenCalled();
    expect(closeLikes).not.toHaveBeenCalled();
    unmountViewer();
    expect(window.history.state).toEqual(route);
});

test("notification-opened likes return to the same post on Back", () => {
    const closeLikes = vi.fn();
    const unmountLikes = mountOverlay("space-post-likes", closeLikes);
    window.history.back();
    expect(closeLikes).toHaveBeenCalledOnce();
    expect(window.history.state).toEqual(route);
    unmountLikes();
    expect(mocks.back).toHaveBeenCalledOnce();
});
