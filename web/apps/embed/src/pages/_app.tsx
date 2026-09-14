import "@fontsource-variable/inter";
import { CssBaseline } from "@mui/material";
import { ThemeProvider } from "@mui/material/styles";
import { CustomHead } from "ente-base/components/Head";
import { ThemedLoadingBar } from "ente-base/components/ThemedLoadingBar";
import {
    useIsRouteChangeInProgress,
    useSetupI18n,
    useSetupLogs,
} from "ente-base/components/utils/hooks-app";
import { photosTheme } from "ente-base/components/utils/theme";
import { useLoadingBar } from "ente-base/components/utils/use-loading-bar";
import { BaseContext, deriveBaseContext } from "ente-base/context";
import { logStartupBanner } from "ente-base/log-web";
import "ente-gallery/styles/photoswipe.css";
import { PhotosAppContext } from "ente-new/photos/types/context";
import type { AppProps } from "next/app";
import { useCallback, useEffect, useMemo } from "react";

export default function App({ Component, pageProps }: AppProps) {
    useSetupLogs();
    useSetupI18n();

    useEffect(() => {
        logStartupBanner();
    }, []);

    const isRouteChangeInProgress = useIsRouteChangeInProgress();

    const { loadingBarRef, showLoadingBar, hideLoadingBar } = useLoadingBar();

    useEffect(() => {
        if (isRouteChangeInProgress) {
            showLoadingBar();
        } else {
            hideLoadingBar();
        }
    }, [isRouteChangeInProgress, showLoadingBar, hideLoadingBar]);

    const showMiniDialog = useCallback(() => undefined, []);

    const logout = useCallback(() => undefined, []);

    const baseContext = useMemo(
        () => deriveBaseContext({ logout, showMiniDialog }),
        [logout, showMiniDialog],
    );

    const photosAppContextValue = useMemo(
        () => ({
            showLoadingBar,
            hideLoadingBar,
            showNotification: () => undefined,
            watchFolderView: false,
            setWatchFolderView: () => undefined,
        }),
        [showLoadingBar, hideLoadingBar],
    );

    return (
        <>
            <CustomHead title="Ente Photos" />
            <ThemeProvider theme={photosTheme}>
                <CssBaseline enableColorScheme />
                <BaseContext.Provider value={baseContext}>
                    <PhotosAppContext.Provider value={photosAppContextValue}>
                        <Component {...pageProps} />
                        <ThemedLoadingBar ref={loadingBarRef} />
                    </PhotosAppContext.Provider>
                </BaseContext.Provider>
            </ThemeProvider>
        </>
    );
}
