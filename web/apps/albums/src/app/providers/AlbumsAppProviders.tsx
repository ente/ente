import { AlbumsAppContext } from "@/app/context/albums-app-context";
import {
    LazyAttributedMiniDialog,
    LazyNotification,
} from "@/app/lazy/global-ui";
import { CssBaseline } from "@mui/material";
import { ThemeProvider } from "@mui/material/styles";
import { staticAppTitle } from "ente-base/app";
import { CustomHeadAlbums } from "ente-base/components/Head";
import { LoadingIndicator } from "ente-base/components/loaders";
import { ThemedLoadingBar } from "ente-base/components/ThemedLoadingBar";
import { useAttributedMiniDialog } from "ente-base/components/utils/dialog";
import {
    useNotification,
    useSetupI18n,
} from "ente-base/components/utils/hooks-app";
import { photosTheme } from "ente-base/components/utils/theme";
import { useLoadingBar } from "ente-base/components/utils/use-loading-bar";
import { BaseContext, deriveBaseContext } from "ente-base/context";
import { t } from "i18next";
import { useCallback, useMemo, type PropsWithChildren } from "react";

export const AlbumsAppProviders: React.FC<PropsWithChildren> = ({
    children,
}) => {
    const isI18nReady = useSetupI18n();
    const { showMiniDialog, miniDialogProps } = useAttributedMiniDialog();
    const { showNotification, notificationProps } = useNotification();
    const { loadingBarRef, showLoadingBar, hideLoadingBar } = useLoadingBar();
    const logout = useCallback(() => {
        // Public albums does not maintain a logged-in app session.
    }, []);

    const baseContext = useMemo(
        () => deriveBaseContext({ logout, showMiniDialog }),
        [logout, showMiniDialog],
    );
    const appContext = useMemo(
        () => ({ showLoadingBar, hideLoadingBar, showNotification }),
        [showLoadingBar, hideLoadingBar, showNotification],
    );
    const title = isI18nReady ? t("title_photos") : staticAppTitle;

    return (
        <ThemeProvider theme={photosTheme}>
            <CustomHeadAlbums {...{ title }} />
            <CssBaseline enableColorScheme />

            <ThemedLoadingBar ref={loadingBarRef} />
            {miniDialogProps.open && (
                <LazyAttributedMiniDialog {...miniDialogProps} />
            )}
            {notificationProps.open && (
                <LazyNotification {...notificationProps} />
            )}

            <BaseContext value={baseContext}>
                <AlbumsAppContext value={appContext}>
                    {!isI18nReady ? <LoadingIndicator /> : children}
                </AlbumsAppContext>
            </BaseContext>
        </ThemeProvider>
    );
};
