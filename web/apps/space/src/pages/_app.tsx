import "@fontsource-variable/inter";
import "@fontsource/nunito/800.css";
import { CssBaseline } from "@mui/material";
import { ThemeProvider } from "@mui/material/styles";
import { SpaceRouteTransitionBoundary } from "components/SpaceRouteTransitionBoundary";
import "configureZod";
import { CustomHead } from "ente-base/components/Head";
import { useSetupLogs } from "ente-base/components/utils/hooks-app";
import { shareTheme } from "ente-base/components/utils/theme";
import type { AppProps } from "next/app";
import "photoswipe/dist/photoswipe.css";
import React from "react";
import "react-easy-crop/react-easy-crop.css";
import { SpaceAppStateProvider } from "state/SpaceAppStateProvider";
import "styles/globals.css";

const App: React.FC<AppProps> = ({ Component, pageProps }) => {
    useSetupLogs({ disableDiskLogs: true });

    return (
        <ThemeProvider
            theme={shareTheme}
            defaultMode="light"
            storageManager={null}
        >
            <CustomHead
                title="Ente Space"
                viewportContent="width=device-width, initial-scale=1, maximum-scale=1"
            >
                <meta name="color-scheme" content="only light" />
                <meta name="application-name" content="Ente Space" />
                <meta name="mobile-web-app-capable" content="yes" />
                <meta name="apple-mobile-web-app-capable" content="yes" />
                <meta name="apple-mobile-web-app-title" content="Ente Space" />
                <meta
                    name="apple-mobile-web-app-status-bar-style"
                    content="default"
                />
                <link rel="manifest" href="/manifest.webmanifest" />
                <link
                    rel="apple-touch-icon"
                    href="/images/apple-touch-icon.png"
                />
            </CustomHead>
            <CssBaseline enableColorScheme />
            <SpaceRouteTransitionBoundary>
                <SpaceAppStateProvider>
                    <Component {...pageProps} />
                </SpaceAppStateProvider>
            </SpaceRouteTransitionBoundary>
        </ThemeProvider>
    );
};

export default App;
