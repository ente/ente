import { useCallback, useEffect, useEffectEvent, useRef } from "react";

type BrowserBackCleanupAction = "back" | "replace";

const waitForNextPopState = () =>
    new Promise<void>((resolve) => {
        const handlePopState = () => resolve();

        window.addEventListener("popstate", handlePopState, { once: true });
        window.setTimeout(() => {
            window.removeEventListener("popstate", handlePopState);
            resolve();
        }, 1000);
    });

const browserBackStateWithMarker = (
    state: unknown,
    stateKey: string,
    marker: string,
) =>
    state && typeof state == "object"
        ? { ...(state as Record<string, unknown>), [stateKey]: marker }
        : { [stateKey]: marker };

const browserBackStateHasMarker = (
    state: unknown,
    stateKey: string,
    marker: string,
) =>
    !!state &&
    typeof state == "object" &&
    (state as Record<string, unknown>)[stateKey] == marker;

const browserBackStateWithoutMarker = (state: unknown, stateKey: string) => {
    if (!state || typeof state != "object") return state;

    const next: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(
        state as Record<string, unknown>,
    )) {
        if (key != stateKey) next[key] = value;
    }
    return next;
};

export interface UseBrowserBackCloseOptions {
    open: boolean;
    onClose: () => void;
    stateKey: string;
    enabled?: boolean;
}

/**
 * Adds a transient history entry while an overlay is open, so mobile browser
 * back gestures close the overlay before navigating away or closing a parent
 * viewer.
 */
export const useBrowserBackClose = ({
    open,
    onClose,
    stateKey,
    enabled = true,
}: UseBrowserBackCloseOptions) => {
    const markerRef = useRef<string | undefined>(undefined);
    const onBrowserBack = useEffectEvent(onClose);

    const clearBrowserBackState = useCallback(
        (action: BrowserBackCleanupAction = "replace") => {
            if (typeof window == "undefined") return Promise.resolve();

            const marker = markerRef.current;
            if (!marker) return Promise.resolve();

            markerRef.current = undefined;

            const latestHistoryState: unknown = window.history.state;
            if (
                !browserBackStateHasMarker(latestHistoryState, stateKey, marker)
            ) {
                return Promise.resolve();
            }

            if (action == "back") {
                const popStatePromise = waitForNextPopState();
                window.history.back();
                return popStatePromise;
            } else {
                window.history.replaceState(
                    browserBackStateWithoutMarker(latestHistoryState, stateKey),
                    "",
                    window.location.href,
                );
                return Promise.resolve();
            }
        },
        [stateKey],
    );

    useEffect(() => {
        if (!open || !enabled || typeof window == "undefined") return;

        const marker = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        markerRef.current = marker;

        window.history.pushState(
            browserBackStateWithMarker(window.history.state, stateKey, marker),
            "",
            window.location.href,
        );

        const handlePopState = (event: PopStateEvent) => {
            if (markerRef.current != marker) return;
            if (browserBackStateHasMarker(event.state, stateKey, marker)) {
                return;
            }

            markerRef.current = undefined;
            onBrowserBack();
        };

        window.addEventListener("popstate", handlePopState);

        return () => {
            window.removeEventListener("popstate", handlePopState);
            if (markerRef.current != marker) return;
            void clearBrowserBackState("back");
        };
    }, [clearBrowserBackState, enabled, open, stateKey]);

    return { clearBrowserBackState };
};
