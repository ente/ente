import "@fontsource-variable/inter";
import "@fontsource/nunito/800.css";
import { CssBaseline } from "@mui/material";
import { createTheme, ThemeProvider } from "@mui/material/styles";
import { SpaceRouteTransitionBoundary } from "components/SpaceRouteTransitionBoundary";
import { SpaceShareLinkDialogHost } from "components/SpaceShareLinkDialog";
import "configureZod";
import { CustomHead } from "ente-base/components/Head";
import { useSetupLogs } from "ente-base/components/utils/hooks-app";
import { shareTheme } from "ente-base/components/utils/theme";
import { captureSpacePWAInstallPrompt } from "hooks/useSpacePWAInstallPrompt";
import type { AppProps } from "next/app";
import { useRouter } from "next/router";
import "photoswipe/dist/photoswipe.css";
import React from "react";
import "react-easy-crop/react-easy-crop.css";
import { registerSpaceServiceWorker } from "services/spaceWebPush";
import { SpaceAppStateProvider } from "state/SpaceAppStateProvider";
import "styles/globals.css";

const spaceTheme = createTheme(shareTheme, {
    components: {
        MuiDialog: {
            styleOverrides: {
                root: {
                    ".MuiBackdrop-root": {
                        backgroundColor:
                            "var(--space-dialog-backdrop, rgba(0 0 0 / 0.48))",
                    },
                },
            },
        },
    },
});

const App: React.FC<AppProps> = ({ Component, pageProps }) => {
    useSetupLogs({ disableDiskLogs: true });
    const router = useRouter();
    const publicProfileManifest = router.pathname == "/profile-link";

    React.useEffect(captureSpacePWAInstallPrompt, []);
    React.useEffect(() => {
        void registerSpaceServiceWorker().catch((error: unknown) =>
            console.warn("Failed to register the Space service worker", error),
        );
    }, []);

    return (
        <ThemeProvider
            theme={spaceTheme}
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
                <link
                    rel="manifest"
                    href={
                        publicProfileManifest
                            ? "/manifest-public.webmanifest"
                            : "/manifest.webmanifest"
                    }
                />
                <link
                    rel="apple-touch-icon"
                    href="/images/apple-touch-icon.png"
                />
            </CustomHead>
            <CssBaseline enableColorScheme />
            <SpaceRouteTransitionBoundary>
                <SpaceAppStateProvider>
                    <Component {...pageProps} />
                    <SpaceShareLinkDialogHost />
                </SpaceAppStateProvider>
            </SpaceRouteTransitionBoundary>
        </ThemeProvider>
    );
};

export default App;
