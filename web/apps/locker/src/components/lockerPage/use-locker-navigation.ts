import type { NextRouter } from "next/router";
import { useCallback, useEffect, useRef } from "react";

const isLockerAppPath = (path: string) => {
    const pathname = path.split("?")[0] ?? path;
    return (
        pathname === "/" ||
        pathname === "/collections" ||
        pathname === "/trash" ||
        pathname === "/collection"
    );
};

const getCollectionIDFromPath = (path: string) => {
    const searchParams = new URLSearchParams(path.split("?")[1] ?? "");
    const id = searchParams.get("id");
    if (id === null) {
        return null;
    }

    const parsedID = Number.parseInt(id, 10);
    return Number.isFinite(parsedID) ? parsedID : null;
};

interface UseLockerNavigationProps {
    router: NextRouter;
    onAfterNavigate?: () => void;
}

export const useLockerNavigation = ({
    router,
    onAfterNavigate,
}: UseLockerNavigationProps) => {
    const lockerRouteStackRef = useRef<string[]>([]);
    const lockerRouteIndexRef = useRef(-1);
    const isNavigatingBackRef = useRef(false);
    const isProgrammaticLockerNavigationRef = useRef(false);

    const routeCollectionID =
        router.pathname === "/collection"
            ? getCollectionIDFromPath(router.asPath)
            : null;
    const selectedCollectionID =
        routeCollectionID !== null && Number.isFinite(routeCollectionID)
            ? routeCollectionID
            : null;
    const isTrashView = router.pathname === "/trash";
    const isCollectionsView = router.pathname === "/collections";
    const isHomeView =
        !isTrashView && !isCollectionsView && selectedCollectionID === null;
    const isCollectionRoutePending =
        router.pathname === "/collection" &&
        (router.asPath.split("?")[0] ?? router.asPath) === "/collection" &&
        !router.isReady;

    useEffect(() => {
        if (router.pathname !== "/locker") {
            return;
        }

        void router.replace("/", undefined, { shallow: true });
    }, [router]);

    useEffect(() => {
        if (!router.isReady || !isLockerAppPath(router.asPath)) {
            return;
        }

        const routeStack = lockerRouteStackRef.current;
        const currentIndex = lockerRouteIndexRef.current;
        const currentPath = router.asPath;

        if (isNavigatingBackRef.current) {
            isNavigatingBackRef.current = false;
            const previousIndex = routeStack.lastIndexOf(currentPath);
            if (previousIndex >= 0) {
                lockerRouteIndexRef.current = previousIndex;
            } else {
                routeStack.push(currentPath);
                lockerRouteIndexRef.current = routeStack.length - 1;
            }
            return;
        }

        if (routeStack.length === 0) {
            routeStack.push(currentPath);
            lockerRouteIndexRef.current = 0;
            isProgrammaticLockerNavigationRef.current = false;
            return;
        }

        if (currentIndex >= 0 && routeStack[currentIndex] === currentPath) {
            isProgrammaticLockerNavigationRef.current = false;
            return;
        }

        if (isProgrammaticLockerNavigationRef.current) {
            isProgrammaticLockerNavigationRef.current = false;
            routeStack.splice(currentIndex + 1);
            routeStack.push(currentPath);
            lockerRouteIndexRef.current = routeStack.length - 1;
            return;
        }

        const existingIndex = routeStack.lastIndexOf(currentPath);
        if (existingIndex >= 0) {
            lockerRouteIndexRef.current = existingIndex;
            return;
        }

        routeStack.splice(currentIndex + 1);
        routeStack.push(currentPath);
        lockerRouteIndexRef.current = routeStack.length - 1;
    }, [router.asPath, router.isReady]);

    useEffect(() => {
        if (
            router.pathname === "/collection" &&
            router.isReady &&
            routeCollectionID === null
        ) {
            void router.replace("/", undefined, { shallow: true });
        }
    }, [routeCollectionID, router]);

    const navigateHome = useCallback(() => {
        onAfterNavigate?.();
        if (router.asPath === "/") {
            return;
        }
        isProgrammaticLockerNavigationRef.current = true;
        void router.push("/", undefined, { shallow: true });
    }, [onAfterNavigate, router]);

    const handleNavigateBack = useCallback(() => {
        onAfterNavigate?.();

        const currentIndex = lockerRouteIndexRef.current;
        if (currentIndex > 0) {
            lockerRouteIndexRef.current = currentIndex - 1;
            isNavigatingBackRef.current = true;
            router.back();
            return;
        }

        if (router.asPath !== "/") {
            lockerRouteStackRef.current = [router.asPath, "/"];
            lockerRouteIndexRef.current = 1;
            isNavigatingBackRef.current = true;
            isProgrammaticLockerNavigationRef.current = true;
            void router.push("/", undefined, { shallow: true });
        }
    }, [onAfterNavigate, router]);

    const handleSelectCollection = useCallback(
        (id: number | null) => {
            if (id === null) {
                navigateHome();
                return;
            }

            onAfterNavigate?.();

            if (
                router.pathname === "/collection" &&
                selectedCollectionID === id
            ) {
                return;
            }

            isProgrammaticLockerNavigationRef.current = true;
            void router.push(
                { pathname: "/collection", query: { id: String(id) } },
                undefined,
                { shallow: true },
            );
        },
        [navigateHome, onAfterNavigate, router, selectedCollectionID],
    );

    const handleSelectCollections = useCallback(() => {
        onAfterNavigate?.();
        if (router.pathname === "/collections") {
            return;
        }
        isProgrammaticLockerNavigationRef.current = true;
        void router.push("/collections", undefined, { shallow: true });
    }, [onAfterNavigate, router]);

    const handleSelectTrash = useCallback(() => {
        onAfterNavigate?.();
        if (router.pathname === "/trash") {
            return;
        }
        isProgrammaticLockerNavigationRef.current = true;
        void router.push("/trash", undefined, { shallow: true });
    }, [onAfterNavigate, router]);

    return {
        handleNavigateBack,
        handleSelectCollection,
        handleSelectCollections,
        handleSelectTrash,
        isCollectionRoutePending,
        isCollectionsView,
        isHomeView,
        isTrashView,
        navigateHome,
        selectedCollectionID,
    };
};
