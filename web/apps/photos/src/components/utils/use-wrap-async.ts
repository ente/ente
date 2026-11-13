import { useBaseContext } from "ente-base/context";
import { usePhotosAppContext } from "ente-new/photos/types/context";
import { useCallback } from "react";

export const useWrapAsyncOperation = <T extends unknown[]>(
    f: (...args: T) => Promise<void>,
) => {
    const { onGenericError } = useBaseContext();
    const { showLoadingBar, hideLoadingBar } = usePhotosAppContext();
    return useCallback(
        async (...args: T) => {
            showLoadingBar();
            try {
                await f(...args);
            } catch (e) {
                onGenericError(e);
            } finally {
                hideLoadingBar();
            }
        },
        [f, showLoadingBar, hideLoadingBar, onGenericError],
    );
};
