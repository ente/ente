import { useCallback, useRef } from "react";

export interface LoadingBarController {
    continuousStart: () => void;
    complete: () => void;
}

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
