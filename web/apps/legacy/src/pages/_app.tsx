import "@fontsource-variable/inter";
import { CssBaseline } from "@mui/material";
import { ThemeProvider } from "@mui/material/styles";
import { staticAppTitle } from "ente-base/app";
import { assertionFailed } from "ente-base/assert";
import { CustomHead } from "ente-base/components/Head";
import { LoadingIndicator } from "ente-base/components/loaders";
import { AttributedMiniDialog } from "ente-base/components/MiniDialog";
import { useAttributedMiniDialog } from "ente-base/components/utils/dialog";
import {
    useSetupI18n,
    useSetupLogs,
} from "ente-base/components/utils/hooks-app";
import { shareTheme } from "ente-base/components/utils/theme";
import { BaseContext, deriveBaseContext } from "ente-base/context";
import type { AppProps } from "next/app";
import React, { useMemo } from "react";

const App: React.FC<AppProps> = ({ Component, pageProps }) => {
    useSetupLogs({ disableDiskLogs: true });

    const isI18nReady = useSetupI18n();
    const { showMiniDialog, miniDialogProps } = useAttributedMiniDialog();

    const baseContext = useMemo(
        () => deriveBaseContext({ logout: assertionFailed, showMiniDialog }),
        [showMiniDialog],
    );

    return (
        <ThemeProvider theme={shareTheme}>
            <CustomHead title={staticAppTitle} />
            <CssBaseline enableColorScheme />
            <AttributedMiniDialog {...miniDialogProps} />

            <BaseContext value={baseContext}>
                {!isI18nReady ? (
                    <LoadingIndicator />
                ) : (
                    <Component {...pageProps} />
                )}
            </BaseContext>
        </ThemeProvider>
    );
};

export default App;
