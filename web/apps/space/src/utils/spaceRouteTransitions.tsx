import { useRouter, type NextRouter } from "next/router";
import React from "react";

type SpaceRouteMotionDirection = "forward" | "back";
type SpaceRouteURL = Parameters<NextRouter["push"]>[0];
type SpaceRouteAs = Parameters<NextRouter["push"]>[1];
type SpaceRouteOptions = Parameters<NextRouter["push"]>[2];

let routeMotionSequence = 0;
let routeStack: string[] = [];

const routePath = (route: SpaceRouteURL | SpaceRouteAs): string => {
    if (!route) return "";

    if (typeof route == "string") {
        const [routeWithoutHash = ""] = route.split("#", 1);
        const [routeWithoutQuery = ""] = routeWithoutHash.split("?", 1);
        const path = route.startsWith("http")
            ? new URL(route).pathname
            : routeWithoutQuery;
        return path.length > 1 ? path.replace(/\/+$/, "") : path || "/";
    }

    const pathname = route.pathname;
    if (!pathname || typeof pathname != "string") return "";
    return pathname.length > 1 ? pathname.replace(/\/+$/, "") : pathname;
};

const parentRoutePaths = (path: string) => {
    if (/^\/app\/friends\/[^/]+$/.test(path)) return ["/app/friends"];
    if (/^\/app\/messages\/[^/]+$/.test(path)) return ["/app/messages"];
    if (/^\/app\/posts\/[^/]+\/[^/]+$/.test(path)) {
        return ["/app"];
    }

    return (
        {
            "/app/friends": ["/app/profile"],
            "/app/messages": ["/app"],
            "/app/profile": ["/app"],
            "/app/profile/cover": ["/app/profile"],
            "/app/profile/cover-edit": ["/app/profile/cover"],
            "/app/profile/photo": ["/app/profile"],
            "/app/profile/photo-edit": ["/app/profile/photo"],
            "/app/settings": ["/app/profile"],
            "/app/settings/profile": ["/app/settings"],
            "/app/settings/profile/name": ["/app/settings/profile"],
            "/invite": ["/add-profile-photo"],
            "/login": ["/"],
            "/passkeys/finish": ["/passkeys/verify"],
            "/passkeys/verify": ["/login", "/verify"],
            "/create-profile": ["/login", "/verify"],
            "/add-profile-photo": ["/create-profile"],
            "/signup": ["/"],
            "/two-factor/verify": ["/login", "/verify"],
            "/verify": ["/login", "/signup"],
        } satisfies Record<string, string[]>
    )[path];
};

const previousStackRoute = () =>
    routeStack.length > 1 ? routeStack[routeStack.length - 2] : undefined;

const ensureRouteStack = (currentPath: string) => {
    if (routeStack.length == 0 && currentPath) routeStack = [currentPath];
};

const routeMotionDirection = (
    currentPath: string,
    targetPath: string,
): SpaceRouteMotionDirection => {
    ensureRouteStack(currentPath);

    if (previousStackRoute() == targetPath) return "back";
    if (parentRoutePaths(currentPath)?.includes(targetPath)) return "back";
    return "forward";
};

const recordRoutePush = (
    currentPath: string,
    targetPath: string,
    direction: SpaceRouteMotionDirection,
) => {
    ensureRouteStack(currentPath);

    if (direction == "back") {
        const targetIndex = routeStack.lastIndexOf(targetPath);
        routeStack =
            targetIndex >= 0
                ? routeStack.slice(0, targetIndex + 1)
                : [targetPath];
        return;
    }

    if (routeStack[routeStack.length - 1] != currentPath) {
        routeStack.push(currentPath);
    }
    if (routeStack[routeStack.length - 1] != targetPath) {
        routeStack.push(targetPath);
    }
};

const recordRouteReplace = (targetPath: string) => {
    if (!targetPath) return;
    if (routeStack.length == 0) {
        routeStack = [targetPath];
        return;
    }
    routeStack[routeStack.length - 1] = targetPath;
};

const prefersReducedMotion = () =>
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const startSpaceRouteTransition = async <T,>(
    direction: SpaceRouteMotionDirection,
    updateRoute: () => Promise<T>,
) => {
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

    root.dataset.spaceRouteMotion = direction;

    const transition = document.startViewTransition(async () => {
        result = await updateRoute();
    });

    void transition.ready.catch((error: unknown) => {
        if (error instanceof DOMException && error.name == "AbortError") return;
        console.error("Failed to start route transition", error);
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
    const currentPath = routePath(router.asPath);
    const targetPath = routePath(as ?? url);
    if (!targetPath || targetPath == currentPath) {
        return await router.push(url, as, options);
    }

    const direction = routeMotionDirection(currentPath, targetPath);
    const didNavigate = await startSpaceRouteTransition(direction, () =>
        router.push(url, as, options),
    );
    if (didNavigate) recordRoutePush(currentPath, targetPath, direction);
    return didNavigate;
};

const replaceSpaceRoute = async (
    router: NextRouter,
    url: SpaceRouteURL,
    as?: SpaceRouteAs,
    options?: SpaceRouteOptions,
) => {
    const didNavigate = await router.replace(url, as, options);
    if (didNavigate) recordRouteReplace(routePath(as ?? url));
    return didNavigate;
};

const backSpaceRoute = (router: NextRouter) => {
    const currentPath = routePath(router.asPath);
    const targetPath = previousStackRoute();

    void startSpaceRouteTransition("back", () => {
        const routeChangePromise = new Promise<boolean>((resolve, reject) => {
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
        });

        router.back();
        return routeChangePromise;
    })
        .then((didNavigate) => {
            if (didNavigate && targetPath) {
                recordRoutePush(currentPath, targetPath, "back");
            }
        })
        .catch((error: unknown) =>
            console.error("Failed to navigate back", error),
        );
};

export const useSpaceRouter = (): NextRouter => {
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
                        return () => backSpaceRoute(target);
                    }

                    const value = target[property as keyof NextRouter];
                    return typeof value == "function"
                        ? value.bind(target)
                        : value;
                },
            }),
        [router],
    );
};

export const useSpaceRouteTransitionPopState = () => {
    const router = useRouter();
    const asPathRef = React.useRef(router.asPath);
    asPathRef.current = router.asPath;

    React.useEffect(() => {
        recordRouteReplace(routePath(router.asPath));

        router.beforePopState((state) => {
            const currentPath = routePath(asPathRef.current);
            const targetPath = routePath(state.as);

            if (!targetPath || targetPath == currentPath) return true;

            void startSpaceRouteTransition("back", () =>
                router.replace(state.url, state.as, state.options),
            )
                .then((didNavigate) => {
                    if (didNavigate) {
                        recordRoutePush(currentPath, targetPath, "back");
                    }
                })
                .catch((error: unknown) =>
                    console.error("Failed to handle browser back", error),
                );

            return false;
        });

        return () => router.beforePopState(() => true);
    }, [router]);
};
