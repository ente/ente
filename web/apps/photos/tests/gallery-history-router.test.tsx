import type { LocalUser } from "ente-accounts/services/user";
import type { EffectCallback } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";
import { useGalleryNavigation } from "../src/components/gallery/navigation/use-gallery-navigation";
import { initialGalleryState } from "../src/components/gallery/reducer";

const effects = vi.hoisted(() => [] as EffectCallback[]);
const platform = vi.hoisted(() => ({ desktop: false }));
vi.mock("ente-base/app", async (importOriginal) => ({
    ...(await importOriginal<typeof import("ente-base/app")>()),
    get isDesktop() {
        return platform.desktop;
    },
}));
vi.mock("react", async (importOriginal) => ({
    ...(await importOriginal<typeof import("react")>()),
    useEffect: (effect: EffectCallback) => effects.push(effect),
}));
const next = vi.hoisted(() => {
    let beforePop: (state: { as: string }) => boolean = () => true;
    const router = {
        pathname: "/gallery",
        asPath: "/gallery",
        isReady: true,
        push: vi.fn(),
        replace: vi.fn(),
        beforePopState: vi.fn((callback: typeof beforePop) => {
            beforePop = callback;
        }),
    };
    const transition = vi.fn((as: string) => {
        router.asPath = as;
        router.pathname = new URL(as, "https://photos.ente.io").pathname;
    });
    return {
        router,
        transition,
        pop: (as: string) => {
            if (beforePop({ as })) transition(as);
        },
    };
});
vi.mock("next/router", () => ({ useRouter: () => next.router }));
vi.mock("../src/components/gallery/hooks/use-gallery-preferences", () => ({
    useGalleryPreferences: () => ({}),
}));
vi.mock("../src/components/gallery/sections/people/use-people-entry", () => ({
    usePeopleEntry: () => ({}),
}));
vi.mock("../src/components/gallery/sections/places/use-map-entry", () => ({
    useMapEntry: () => vi.fn(),
}));
vi.mock("../src/components/gallery/sections/registry", () => ({
    sectionDefinition: () => ({ hasNavigation: true }),
}));

beforeEach(() => {
    vi.clearAllMocks();
    effects.length = 0;
    platform.desktop = false;
    next.router.pathname = "/gallery";
    next.router.asPath = "/gallery";
    next.router.beforePopState(() => true);
    next.router.beforePopState.mockClear();
});

const mount = () => {
    const Harness = () => {
        useGalleryNavigation(
            {
                state: { ...initialGalleryState, user: { id: 1 } as LocalUser },
            } as Parameters<typeof useGalleryNavigation>[0],
            vi.fn(() => Promise.resolve(true)),
        );
        return null;
    };
    renderToStaticMarkup(<Harness />);
    const cleanups = effects.map((effect) => effect());
    return () => cleanups.forEach((cleanup) => cleanup?.());
};

test("the web pop-state handler lets Next transition out of the gallery", () => {
    const unmount = mount();
    expect(next.router.beforePopState).toHaveBeenCalledOnce();
    next.pop("/credentials");
    expect(next.transition).toHaveBeenCalledExactlyOnceWith("/credentials");
    expect(next.router.pathname).toBe("/credentials");
    expect(next.router.asPath).toBe("/credentials");
    expect(next.router.push).not.toHaveBeenCalled();
    expect(next.router.replace).not.toHaveBeenCalled();
    unmount();
});

test("desktop keeps its existing history handler and URL synchronization", () => {
    platform.desktop = true;
    next.router.asPath = "/gallery?collection=1";
    const unmount = mount();
    expect(next.router.beforePopState).not.toHaveBeenCalled();
    expect(next.router.push).toHaveBeenCalledExactlyOnceWith(
        "/gallery",
        undefined,
        { shallow: true },
    );
    unmount();
    expect(next.router.beforePopState).not.toHaveBeenCalled();
});
