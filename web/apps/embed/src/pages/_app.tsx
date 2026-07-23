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
import { PhotosAppContext } from "ente-new/photos/types/context";
import type { AppProps } from "next/app";
import "photoswipe/dist/photoswipe.css";
import { useCallback, useEffect, useMemo } from "react";
import "../styles/photoswipe.css";

export default function App({ Component, pageProps }: AppProps) {
    useSetupLogs();
    useSetupI18n();

    useEffect(() => {
        logStartupBanner();
    }, []);

    // Simplified - no complex dialogs needed for embed
    const isRouteChangeInProgress = useIsRouteChangeInProgress();

    const { showLoadingBar, hideLoadingBar } = useLoadingBar();

    // Show loading bar on route changes
    useEffect(() => {
        if (isRouteChangeInProgress) {
            showLoadingBar();
        } else {
            hideLoadingBar();
        }
    }, [isRouteChangeInProgress, showLoadingBar, hideLoadingBar]);

    const showMiniDialog = useCallback(() => {
        // Simplified for embed - no complex dialogs needed
    }, []);

    const logout = useCallback(() => {
        // No logout functionality needed for embed
    }, []);

    const baseContext = useMemo(
        () => deriveBaseContext({ logout, showMiniDialog }),
        [logout, showMiniDialog],
    );

    const photosAppContextValue = useMemo(
        () => ({
            showLoadingBar,
            hideLoadingBar,
            showNotification: () => {
                // No notifications in embed
            },
            watchFolderView: false,
            setWatchFolderView: () => {
                // No watch folder in embed
            },
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
                        <ThemedLoadingBar ref={{ current: null }} />
                    </PhotosAppContext.Provider>
                </BaseContext.Provider>
            </ThemeProvider>
        </>
    );
}
