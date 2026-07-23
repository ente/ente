import { LockerHead } from "@/components/LockerHead";
import { lockerLogout } from "@/services/logout";
import "@fontsource-variable/inter";
import { CssBaseline } from "@mui/material";
import { ThemeProvider } from "@mui/material/styles";
import {
    isSavedUserTokenMismatch,
    savedLocalUser,
} from "ente-accounts-rs/services/accounts-db";
import {
    LoadingIndicator,
    TranslucentLoadingOverlay,
} from "ente-base/components/loaders";
import { AttributedMiniDialog } from "ente-base/components/MiniDialog";
import { useAttributedMiniDialog } from "ente-base/components/utils/dialog";
import {
    useIsRouteChangeInProgress,
    useSetupI18n,
    useSetupLogs,
} from "ente-base/components/utils/hooks-app";
import { lockerTheme } from "ente-base/components/utils/theme";
import { BaseContext, deriveBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { logStartupBanner } from "ente-base/log-web";
import type { AppProps } from "next/app";
import React, { useCallback, useEffect, useMemo } from "react";

const App: React.FC<AppProps> = ({ Component, pageProps }) => {
    useSetupLogs();

    const isI18nReady = useSetupI18n();
    const isChangingRoute = useIsRouteChangeInProgress();
    const { showMiniDialog, miniDialogProps } = useAttributedMiniDialog();

    useEffect(() => {
        logStartupBanner(savedLocalUser()?.id);
    }, []);

    const logout = useCallback(() => {
        void lockerLogout().then(() => window.location.replace("/login"));
    }, []);

    useEffect(() => {
        void isSavedUserTokenMismatch()
            .then((mismatch) => {
                if (!mismatch) {
                    return;
                }

                log.error("Logging out (saved user token mismatch)");
                logout();
            })
            .catch((error: unknown) => {
                log.error(
                    "Failed to validate saved user token mismatch",
                    error,
                );
            });
    }, [logout]);

    const baseContext = useMemo(
        () => deriveBaseContext({ logout, showMiniDialog }),
        [logout, showMiniDialog],
    );

    return (
        <ThemeProvider theme={lockerTheme}>
            <LockerHead />
            <CssBaseline enableColorScheme />
            <AttributedMiniDialog {...miniDialogProps} />

            <BaseContext value={baseContext}>
                {!isI18nReady ? (
                    <LoadingIndicator />
                ) : (
                    <>
                        {isChangingRoute && <TranslucentLoadingOverlay />}
                        <Component {...pageProps} />
                    </>
                )}
            </BaseContext>
        </ThemeProvider>
    );
};

export default App;
