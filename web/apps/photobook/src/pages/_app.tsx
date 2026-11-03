import { BookProvider } from "@/context/BookContext";
import { PhotoImportProvider } from "@/hooks/usePhotoImport";
import theme from "@/theme/theme";
import "@fontsource-variable/inter";
import "@fontsource-variable/outfit";
import "@fontsource/gochi-hand";
import { CssBaseline } from "@mui/material";
import { ThemeProvider } from "@mui/material/styles";
import { staticAppTitle } from "ente-base/app";
import { CustomHead } from "ente-base/components/Head";
import { useSetupLogs } from "ente-base/components/utils/hooks-app";
import type { AppProps } from "next/app";
import "../globals.css";

export default function App({ Component, pageProps }: AppProps) {
    useSetupLogs({ disableDiskLogs: true });
    return (
        <ThemeProvider theme={theme} defaultMode="dark" storageManager={null}>
            <CustomHead
                title={staticAppTitle}
                description="Create photobooks privately in your browser"
            >
                <link rel="apple-touch-icon" href="/icon-192x192.png" />
            </CustomHead>
            <CssBaseline enableColorScheme />
            <BookProvider>
                <PhotoImportProvider>
                    <Component {...pageProps} />
                </PhotoImportProvider>
            </BookProvider>
        </ThemeProvider>
    );
}
