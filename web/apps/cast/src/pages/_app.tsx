import "@fontsource-variable/inter";
import { CssBaseline, GlobalStyles, ThemeProvider } from "@mui/material";
import { staticAppTitle } from "ente-base/app";
import { CustomHead } from "ente-base/components/Head";
import { useSetupLogs } from "ente-base/components/utils/hooks-app";
import { castTheme } from "ente-base/components/utils/theme";
import type { AppProps } from "next/app";
import React from "react";

const App: React.FC<AppProps> = ({ Component, pageProps }) => {
    useSetupLogs({ disableDiskLogs: true });

    return (
        <ThemeProvider theme={castTheme}>
            <CustomHead title={staticAppTitle} />
            <CssBaseline enableColorScheme />
            <GlobalStyles styles={{ "html, body": { overflow: "hidden" } }} />
            <Component {...pageProps} />
        </ThemeProvider>
    );
};

export default App;
