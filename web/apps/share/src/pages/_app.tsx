import "@fontsource-variable/inter";
import { CssBaseline } from "@mui/material";
import { ThemeProvider } from "@mui/material/styles";
import { staticAppTitle } from "ente-base/app";
import { CustomHead } from "ente-base/components/Head";
import {
    useSetupI18n,
    useSetupLogs,
} from "ente-base/components/utils/hooks-app";
import { shareTheme } from "ente-base/components/utils/theme";
import type { AppProps } from "next/app";
import React from "react";

const App: React.FC<AppProps> = ({ Component, pageProps }) => {
    useSetupLogs({ disableDiskLogs: true });
    useSetupI18n();

    return (
        <ThemeProvider
            theme={shareTheme}
            defaultMode="system"
            // Avoid persisting a manual override; always follow the system theme.
            storageManager={null}
        >
            <CustomHead title={staticAppTitle} />
            <CssBaseline enableColorScheme />
            <Component {...pageProps} />
        </ThemeProvider>
    );
};

export default App;
