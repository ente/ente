import "@fontsource-variable/inter";
import "@fontsource/nunito/800.css";
import { CssBaseline } from "@mui/material";
import { createTheme, ThemeProvider } from "@mui/material/styles";
import { SpacePostComposerHost } from "components/PostComposer";
import { SpaceRouteTransitionBoundary } from "components/RouteTransitionBoundary";
import "configure-zod";
import { CustomHead } from "ente-base/components/Head";
import { useSetupLogs } from "ente-base/components/utils/hooks-app";
import { shareTheme } from "ente-base/components/utils/theme";
import { captureSpacePWAInstallPrompt } from "hooks/use-pwa-install-prompt";
import type { AppProps } from "next/app";
import { useRouter } from "next/router";
import "photoswipe/dist/photoswipe.css";
import React from "react";
import "react-easy-crop/react-easy-crop.css";
import { registerSpaceServiceWorker } from "services/web-push";
import { SpaceAppStateProvider } from "state/AppStateProvider";
import {
    spaceAppBackground,
    spaceAppBackgroundColor,
    spaceDialogBackground,
    spaceSurface,
    spaceSurfaceHover,
    spaceText,
    spaceTextMuted,
} from "styles/colors";
import "styles/globals.css";

const interFontURL = new URL(
    "@fontsource-variable/inter/files/inter-latin-wght-normal.woff2",
    import.meta.url,
).href;

const darkPalette = shareTheme.colorSchemes.dark!.palette;

const spaceTheme = createTheme(
    {
        cssVariables: { colorSchemeSelector: "class" },
        colorSchemes: {
            light: false,
            dark: {
                palette: {
                    ...darkPalette,
                    background: {
                        ...darkPalette.background,
                        default: spaceAppBackgroundColor,
                        paper: spaceDialogBackground,
                        paper2: spaceSurface,
                        elevatedPaper: spaceDialogBackground,
                        searchInput: spaceSurface,
                    },
                    primary: {
                        main: spaceSurfaceHover,
                        contrastText: spaceText,
                    },
                    text: {
                        ...darkPalette.text,
                        primary: spaceText,
                        secondary: spaceTextMuted,
                        base: spaceText,
                        muted: spaceTextMuted,
                    },
                },
            },
        },
        defaultColorScheme: "dark",
        typography: shareTheme.typography,
        shape: shareTheme.shape,
        transitions: shareTheme.transitions,
        components: shareTheme.components,
    },
    {
        components: {
            MuiCssBaseline: {
                styleOverrides: {
                    html: { backgroundColor: spaceAppBackgroundColor },
                    body: { background: spaceAppBackground },
                    "#__next": { minHeight: "100svh" },
                },
            },
            MuiDialog: {
                styleOverrides: {
                    paper: {
                        backgroundColor: spaceDialogBackground,
                        backgroundImage: "none",
                    },
                    root: {
                        ".MuiBackdrop-root": {
                            backgroundColor:
                                "var(--space-dialog-backdrop, rgba(0 0 0 / 0.48))",
                        },
                    },
                },
            },
        },
    },
);

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
            defaultMode="dark"
            storageManager={null}
        >
            <CustomHead
                title="Ente Space"
                viewportContent="width=device-width, initial-scale=1, maximum-scale=1"
            >
                <link
                    rel="preload"
                    href={interFontURL}
                    as="font"
                    type="font/woff2"
                    crossOrigin="anonymous"
                />
                <meta name="color-scheme" content="dark" />
                <meta name="theme-color" content={spaceAppBackgroundColor} />
                <meta name="application-name" content="Ente Space" />
                <meta name="mobile-web-app-capable" content="yes" />
                <meta name="apple-mobile-web-app-capable" content="yes" />
                <meta name="apple-mobile-web-app-title" content="Ente Space" />
                <meta
                    name="apple-mobile-web-app-status-bar-style"
                    content="black"
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
                    <SpacePostComposerHost />
                </SpaceAppStateProvider>
            </SpaceRouteTransitionBoundary>
        </ThemeProvider>
    );
};

export default App;
