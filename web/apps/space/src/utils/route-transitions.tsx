import log from "ente-base/log";
import { useRouter, type NextRouter } from "next/router";
import React from "react";
import { spaceBackFallback } from "utils/routes";

type SpaceRouteURL = Parameters<NextRouter["push"]>[0];
type SpaceRouteAs = Parameters<NextRouter["push"]>[1];
type SpaceRouteOptions = Parameters<NextRouter["push"]>[2];
type SpaceRouter = Omit<NextRouter, "back"> & {
    back: (fallback?: string) => Promise<boolean>;
    backTo: (path: string) => Promise<boolean>;
};

let routeMotionSequence = 0;
let routeHistory: { key: string; as: string }[] = [];
let routeHistoryIndex = -1;
const routeHistoryStorageKey = "space-route-history";

const saveRouteHistory = () => {
    try {
        sessionStorage.setItem(
            routeHistoryStorageKey,
            JSON.stringify({ entries: routeHistory, index: routeHistoryIndex }),
        );
    } catch (error) {
        log.warn("Failed to save Space navigation history", error);
    }
};

const recordRoute = (action: "push" | "replace" | "pop") => {
    const { key, as } = window.history.state as { key: string; as: string };
    const index = routeHistory.findIndex((entry) => entry.key == key);
    if (index >= 0) {
        routeHistoryIndex = index;
        routeHistory[index] = { key, as };
    } else if (action == "push") {
        routeHistory = routeHistory.slice(0, routeHistoryIndex + 1);
        routeHistory.push({ key, as });
        routeHistoryIndex = routeHistory.length - 1;
    } else if (action == "replace" && routeHistoryIndex >= 0) {
        routeHistory[routeHistoryIndex] = { key, as };
    } else {
        routeHistory = [{ key, as }];
        routeHistoryIndex = 0;
    }
    saveRouteHistory();
};

const initializeRouteHistory = (router: NextRouter) => {
    if (routeHistoryIndex >= 0) return;
    const state = window.history.state as {
        key: string;
        url: string;
        as: string;
        options: object;
        __N: boolean;
    };
    const navigation = performance.getEntriesByType("navigation")[0] as
        PerformanceNavigationTiming | undefined;
    if (navigation?.type == "reload") {
        try {
            const saved = JSON.parse(
                sessionStorage.getItem(routeHistoryStorageKey) ?? "null",
            ) as { entries: typeof routeHistory; index: number } | null;
            if (saved?.entries[saved.index]?.as == router.asPath) {
                routeHistory = saved.entries;
                routeHistoryIndex = saved.index;
                routeHistory[routeHistoryIndex] = {
                    key: state.key,
                    as: state.as,
                };
                saveRouteHistory();
                return;
            }
        } catch (error) {
            log.warn("Failed to restore Space navigation history", error);
        }
    }

    const parents: string[] = [];
    let parent = spaceBackFallback(router.asPath, router.pathname);
    while (parent) {
        parents.unshift(parent);
        parent = spaceBackFallback(parent);
    }
    for (const [index, as] of parents.entries()) {
        const key = crypto.randomUUID();
        window.history[index == 0 ? "replaceState" : "pushState"](
            { ...state, key, url: as, as, options: {} },
            "",
            as,
        );
        routeHistory.push({ key, as });
    }
    if (parents.length > 0) window.history.pushState(state, "", state.as);
    routeHistory.push({ key: state.key, as: state.as });
    routeHistoryIndex = routeHistory.length - 1;
    saveRouteHistory();
};

const prefersReducedMotion = () =>
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const startSpaceRouteTransition = async <T,>(updateRoute: () => Promise<T>) => {
    if (
        typeof document == "undefined" ||
        typeof document.startViewTransition != "function" ||
        prefersReducedMotion()
    ) {
        return await updateRoute();
    }

    const sequence = ++routeMotionSequence;
    const root = document.documentElement;
    let result: T;

    root.dataset.spaceRouteMotion = "fade";

    const transition = document.startViewTransition(async () => {
        result = await updateRoute();
    });

    void transition.ready.catch((error: unknown) => {
        if (error instanceof DOMException && error.name == "AbortError") return;
        log.error("Failed to start route transition", error);
    });

    void transition.finished
        .catch(() => undefined)
        .then(() => {
            if (routeMotionSequence == sequence) {
                delete root.dataset.spaceRouteMotion;
            }
        });

    await transition.updateCallbackDone;
    return result!;
};

const pushSpaceRoute = async (
    router: NextRouter,
    url: SpaceRouteURL,
    as?: SpaceRouteAs,
    options?: SpaceRouteOptions,
) => {
    initializeRouteHistory(router);
    const didNavigate = await startSpaceRouteTransition(() =>
        router.push(url, as, options),
    );
    if (didNavigate) recordRoute("push");
    return didNavigate;
};

const replaceSpaceRoute = async (
    router: NextRouter,
    url: SpaceRouteURL,
    as?: SpaceRouteAs,
    options?: SpaceRouteOptions,
) => {
    initializeRouteHistory(router);
    const didNavigate = await router.replace(url, as, options);
    if (didNavigate) recordRoute("replace");
    return didNavigate;
};

const backSpaceRoute = (
    router: NextRouter,
    fallback: string,
    index = routeHistoryIndex - 1,
) => {
    if (index < 0) return replaceSpaceRoute(router, fallback);
    return new Promise<boolean>((resolve, reject) => {
        const cleanup = () => {
            router.events.off("routeChangeComplete", handleComplete);
            router.events.off("routeChangeError", handleError);
        };
        const handleComplete = () => {
            cleanup();
            resolve(true);
        };
        const handleError = (error: unknown) => {
            cleanup();
            reject(
                error instanceof Error
                    ? error
                    : new Error("Space route change failed"),
            );
        };

        router.events.on("routeChangeComplete", handleComplete);
        router.events.on("routeChangeError", handleError);
        window.history.go(index - routeHistoryIndex);
    });
};

export const useSpaceRouter = (): SpaceRouter => {
    const router = useRouter();

    return React.useMemo(
        () =>
            new Proxy<NextRouter>(router, {
                get(target, property) {
                    if (property == "push") {
                        return (
                            url: SpaceRouteURL,
                            as?: SpaceRouteAs,
                            options?: SpaceRouteOptions,
                        ) => pushSpaceRoute(target, url, as, options);
                    }
                    if (property == "replace") {
                        return (
                            url: SpaceRouteURL,
                            as?: SpaceRouteAs,
                            options?: SpaceRouteOptions,
                        ) => replaceSpaceRoute(target, url, as, options);
                    }
                    if (property == "back") {
                        return (fallback = "/app") =>
                            backSpaceRoute(target, fallback);
                    }
                    if (property == "backTo") {
                        return (path: string) =>
                            backSpaceRoute(
                                target,
                                path,
                                routeHistory
                                    .slice(0, routeHistoryIndex)
                                    .findLastIndex((entry) => entry.as == path),
                            );
                    }

                    const value = target[property as keyof NextRouter];
                    return typeof value == "function"
                        ? value.bind(target)
                        : value;
                },
            }) as SpaceRouter,
        [router],
    );
};

export const useSpaceRouteTransitionPopState = () => {
    const router = useRouter();
    const asPathRef = React.useRef(router.asPath);
    asPathRef.current = router.asPath;

    React.useEffect(() => {
        const scrollRestoration = window.history.scrollRestoration;
        window.history.scrollRestoration = "manual";
        initializeRouteHistory(router);

        router.beforePopState((state) => {
            if (
                state.as == asPathRef.current &&
                (window.history.state as { key: string }).key ==
                    routeHistory[routeHistoryIndex]?.key
            )
                return false;

            void startSpaceRouteTransition(() =>
                router.replace(state.url, state.as, state.options),
            )
                .then((didNavigate) => {
                    if (didNavigate) {
                        recordRoute("pop");
                    }
                })
                .catch((error: unknown) =>
                    log.error("Failed to handle browser back", error),
                );

            return false;
        });

        return () => {
            window.history.scrollRestoration = scrollRestoration;
            router.beforePopState(() => true);
        };
    }, [router]);
};
