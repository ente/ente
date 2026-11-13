import { isDesktop } from "ente-base/app";
import type { AppLockState } from "ente-new/photos/services/app-lock";
import { useRouter } from "next/router";
import { useEffect } from "react";

const APP_LOCK_ROUTE = "/lock";
const APP_LOCK_RETURN_TO_KEY = "appLock.returnToPath";

interface DesktopAppLockRouteState {
    showLockPage: boolean;
    shouldBlockAppLockRouteTransition: boolean;
}

// Save the current route before locking; consume it once after unlock.
const rememberAppLockReturnTo = (path: string) => {
    if (path === APP_LOCK_ROUTE) return;
    sessionStorage.setItem(APP_LOCK_RETURN_TO_KEY, path);
};

const consumeAppLockReturnTo = (): string | null => {
    const returnTo = sessionStorage.getItem(APP_LOCK_RETURN_TO_KEY);
    sessionStorage.removeItem(APP_LOCK_RETURN_TO_KEY);
    return returnTo;
};

export const useDesktopAppLockRoute = (
    isAppLockReady: boolean,
    isLocked: AppLockState["isLocked"],
    lockScreenMode: AppLockState["lockScreenMode"],
): DesktopAppLockRouteState => {
    const router = useRouter();
    const showLockPage = isDesktop && isLocked && lockScreenMode === "lock";

    useEffect(() => {
        if (!isDesktop || !isAppLockReady || !showLockPage) return;

        if (router.asPath !== APP_LOCK_ROUTE) {
            rememberAppLockReturnTo(router.asPath);
        }

        if (router.pathname !== APP_LOCK_ROUTE) {
            void router.replace(APP_LOCK_ROUTE);
        }
    }, [isAppLockReady, showLockPage, router, router.asPath, router.pathname]);

    useEffect(() => {
        if (
            !isDesktop ||
            !isAppLockReady ||
            showLockPage ||
            router.pathname !== APP_LOCK_ROUTE
        ) {
            return;
        }

        const returnTo = consumeAppLockReturnTo();
        void router.replace(
            returnTo && returnTo !== APP_LOCK_ROUTE ? returnTo : "/gallery",
        );
    }, [isAppLockReady, showLockPage, router, router.pathname]);

    return {
        showLockPage,
        shouldBlockAppLockRouteTransition:
            isDesktop &&
            isAppLockReady &&
            ((showLockPage && router.pathname !== APP_LOCK_ROUTE) ||
                (!showLockPage && router.pathname === APP_LOCK_ROUTE)),
    };
};
