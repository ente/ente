import "@fontsource-variable/inter";
import "@fontsource/gochi-hand";
import { CssBaseline } from "@mui/material";
import { ThemeProvider } from "@mui/material/styles";
import { CustomHead } from "ente-base/components/Head";
import { useSetupLogs } from "ente-base/components/utils/hooks-app";
import { shareTheme } from "ente-base/components/utils/theme";
import type { AppProps } from "next/app";
import React from "react";

const App: React.FC<AppProps> = ({ Component, pageProps }) => {
    useSetupLogs({ disableDiskLogs: true });

    return (
        <ThemeProvider theme={shareTheme} defaultMode="dark">
            <CustomHead title="Ente Paste" />
            <CssBaseline enableColorScheme />
            <Component {...pageProps} />
        </ThemeProvider>
    );
};

export default App;
