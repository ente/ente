import { useCallback, useRef } from "react";

export interface LoadingBarController {
    continuousStart: () => void;
    complete: () => void;
}

/**
 * A convenience hook for returning stable functions tied to a
 * {@link LoadingBar} ref.
 *
 * The {@link LoadingBar} component comes from the "react-top-loading-bar"
 * library. To control it, we keep a ref. We want to allow components in our
 * React tree to be able to also control the loading bar, but instead of
 * exposing the ref directly, we export wrapper functions to start and stop the
 * loading bar. This hook returns these functions (and the ref).
 */
export const useLoadingBar = () => {
    const loadingBarRef = useRef<LoadingBarController | null>(null);

    const showLoadingBar = useCallback(() => {
        loadingBarRef.current?.continuousStart();
    }, []);

    const hideLoadingBar = useCallback(() => {
        loadingBarRef.current?.complete();
    }, []);

    return { loadingBarRef, showLoadingBar, hideLoadingBar };
};
