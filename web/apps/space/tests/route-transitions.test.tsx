import type { NextRouter } from "next/router";
import type { EffectCallback } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
    router: undefined as unknown as NextRouter,
    effects: [] as EffectCallback[],
}));

vi.mock("next/router", () => ({ useRouter: () => mocks.router }));
vi.mock("ente-base/log", () => ({
    default: { error: vi.fn(), warn: vi.fn() },
}));
vi.mock("react", async (importOriginal) => {
    const actual = await importOriginal<typeof import("react")>();
    return {
        ...actual,
        default: {
            ...actual,
            useEffect: (effect: EffectCallback) => {
                mocks.effects.push(effect);
            },
        },
    };
});

beforeEach(() => {
    vi.resetModules();
    mocks.effects = [];
});

afterEach(() => vi.unstubAllGlobals());

const setup = async (initialPath: string) => {
    const { useSpaceRouter, useSpaceRouteTransitionPopState } =
        await import("../src/utils/route-transitions");
    interface Entry {
        key: string;
        url: string;
        as: string;
        options: object;
    }
    let entries: Entry[] = [
        { key: "0", url: initialPath, as: initialPath, options: {} },
    ];
    let position = 0;
    let nextKey = 0;
    let popState: (state: Entry) => boolean = () => true;
    const events = new Map<string, Set<(...args: unknown[]) => void>>();
    const emit = (name: string, ...args: unknown[]) =>
        events.get(name)?.forEach((handler) => handler(...args));
    let router: ReturnType<typeof useSpaceRouter>;
    const Harness = () => {
        router = useSpaceRouter();
        useSpaceRouteTransitionPopState();
        return null;
    };
    const render = () => {
        renderToStaticMarkup(<Harness />);
        mocks.effects.splice(0).forEach((effect) => effect());
    };
    const navigate = (url: string, as = url, replace = false) => {
        const entry = {
            key: replace ? entries[position]!.key : String(++nextKey),
            url,
            as,
            options: {},
        };
        if (replace) entries[position] = entry;
        else {
            entries = entries.slice(0, position + 1);
            entries.push(entry);
            position++;
        }
        mocks.router.asPath = as;
        render();
        emit("routeChangeComplete", as);
        return Promise.resolve(true);
    };
    const go = vi.fn((delta: number) => {
        position += delta;
        popState(entries[position]!);
    });
    vi.stubGlobal("window", {
        history: {
            get state() {
                return entries[position];
            },
            go,
            replaceState: (state: Entry) => {
                entries[position] = state;
            },
            pushState: (state: Entry) => {
                entries = entries.slice(0, position + 1);
                entries.push(state);
                position++;
            },
            scrollRestoration: "auto",
        },
    });
    mocks.router = {
        asPath: initialPath,
        pathname: initialPath.split("?")[0],
        push: vi.fn((url: string, as?: string) => navigate(url, as)),
        replace: vi.fn((url: string, as?: string) => navigate(url, as, true)),
        beforePopState: (callback: typeof popState) => {
            popState = callback;
        },
        events: {
            on: (name: string, handler: (...args: unknown[]) => void) => {
                if (!events.has(name)) events.set(name, new Set());
                events.get(name)!.add(handler);
            },
            off: (name: string, handler: (...args: unknown[]) => void) =>
                events.get(name)?.delete(handler),
        },
    } as unknown as NextRouter;
    render();
    return {
        get router() {
            return router;
        },
        get path() {
            return entries[position]!.as;
        },
        get length() {
            return entries.length;
        },
        go,
    };
};

describe("Space back navigation", () => {
    it.each(["/app/friends", "/app/messages", "/anand"])(
        "returns from a DM to its origin %s",
        async (origin) => {
            const app = await setup(origin);
            await app.router.push("/app/messages/anand");
            await app.router.back("/app/messages");
            expect(app.path).toBe(origin);
        },
    );

    it("retraces a notification, friend profile, and DM without losing history", async () => {
        const app = await setup("/app/notifications");
        await app.router.push("/profile-link", "/anand");
        await app.router.push("/app/messages/anand");
        await app.router.back("/app/messages");
        expect(app.path).toBe("/anand");
        await app.router.back("/app");
        expect(app.path).toBe("/app/notifications");
    });

    it("keeps repeated tab visits in their actual browser order", async () => {
        const app = await setup("/app");
        await app.router.push("/app/friends");
        await app.router.push("/app");
        await app.router.push("/app/profile");
        await app.router.back("/app");
        await app.router.back("/app");
        expect(app.path).toBe("/app/friends");
    });

    it("keeps query parameters when returning from profile editing", async () => {
        const app = await setup("/app/settings");
        await app.router.push("/app/profile/photo?from=settings");
        await app.router.push("/app/profile/photo-edit?from=settings");
        await app.router.back("/app/profile/photo");
        expect(app.path).toBe("/app/profile/photo?from=settings");
        await app.router.back("/app/profile");
        expect(app.path).toBe("/app/settings");
    });

    it("returns past a completed edit flow without adding a settings visit", async () => {
        const app = await setup("/app");
        await app.router.push("/app/settings");
        await app.router.push("/app/profile/photo?from=settings");
        await app.router.push("/app/profile/photo-edit?from=settings");
        await app.router.backTo("/app/settings");
        expect(app.go).toHaveBeenLastCalledWith(-2);
        expect(app.path).toBe("/app/settings");
        await app.router.back("/app");
        expect(app.path).toBe("/app");
    });

    it("uses replace for a direct link fallback, avoiding a back loop", async () => {
        const app = await setup("/login");
        await app.router.back("/app/messages");
        expect(app.path).toBe("/app/messages");
        expect(app.go).not.toHaveBeenCalled();
        expect(app.length).toBe(1);
        await app.router.back("/app");
        expect(app.path).toBe("/app");
        expect(app.length).toBe(1);
    });

    it("gives browser Back a parent chain on a freshly opened DM link", async () => {
        const app = await setup("/app/messages/anand");
        app.go(-1);
        await vi.waitFor(() => expect(app.path).toBe("/app/messages"));
        await app.router.back("/app");
        expect(app.path).toBe("/app");
    });

    it("follows browser Back and Forward before navigating back again", async () => {
        const app = await setup("/app/friends");
        await app.router.push("/app/messages/anand");
        await app.router.back("/app/messages");
        app.go(1);
        await vi.waitFor(() => expect(app.path).toBe("/app/messages/anand"));
        await app.router.back("/app/messages");
        expect(app.path).toBe("/app/friends");
    });
});
