import { AppLockReauthenticationDialog } from "@/components/app-lock/AppLockReauthenticationDialog";
import { AppLockSetupError } from "@/components/app-lock/LockScreenContents";
import {
    updateAvailableForDownloadDialogAttributes,
    updateReadyToInstallDialogAttributes,
} from "@/components/utils/download";
import {
    useAutoLockWhenBackgrounded,
    useSetupAppLock,
} from "@/components/utils/use-app-lock";
import { useDesktopAppLockRoute } from "@/components/utils/use-app-lock-route";
import { resumeExportsIfNeeded } from "@/services/export";
import { photosLogout } from "@/services/logout";
import { runMigrations } from "@/services/migration";
import "@fontsource-variable/inter";
import "@fontsource-variable/outfit";
import ArrowForwardIcon from "@mui/icons-material/ArrowForward";
import { CssBaseline, Typography } from "@mui/material";
import { styled, ThemeProvider } from "@mui/material/styles";
import {
    isLocalStorageAndIndexedDBMismatch,
    savedLocalUser,
} from "ente-accounts/services/accounts-db";
import { isDesktop, staticAppTitle } from "ente-base/app";
import { CenteredRow } from "ente-base/components/containers";
import { CustomHeadPhotos } from "ente-base/components/Head";
import {
    LoadingIndicator,
    TranslucentLoadingOverlay,
} from "ente-base/components/loaders";
import { AttributedMiniDialog } from "ente-base/components/MiniDialog";
import { Notification } from "ente-base/components/Notification";
import { ThemedLoadingBar } from "ente-base/components/ThemedLoadingBar";
import { useAttributedMiniDialog } from "ente-base/components/utils/dialog";
import {
    useIsRouteChangeInProgress,
    useNotification,
    useSetupI18n,
    useSetupLogs,
} from "ente-base/components/utils/hooks-app";
import { photosTheme } from "ente-base/components/utils/theme";
import { useLoadingBar } from "ente-base/components/utils/use-loading-bar";
import { BaseContext, deriveBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { logStartupBanner } from "ente-base/log-web";
import type { AppUpdate } from "ente-base/types/ipc";
import {
    initVideoProcessing,
    isHLSGenerationSupported,
} from "ente-gallery/services/video";
import { useAppLockSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import { initML, isMLSupported } from "ente-new/photos/services/ml";
import { PhotosAppContext } from "ente-new/photos/types/context";
import { t } from "i18next";
import type { AppProps } from "next/app";
import { useRouter } from "next/router";
import { useCallback, useEffect, useMemo, useState } from "react";

import "ente-gallery/styles/photoswipe.css";
import "../styles/global.css";

type PhotosAppProps = AppProps<Record<string, unknown>>;

type MainContentProps = Pick<PhotosAppProps, "Component" | "pageProps"> & {
    isChangingRoute: boolean;
};

const App: React.FC<PhotosAppProps> = ({ Component, pageProps }) => {
    useSetupLogs();

    const isI18nReady = useSetupI18n();
    const isChangingRoute = useIsRouteChangeInProgress();
    const router = useRouter();
    const { showMiniDialog, miniDialogProps } = useAttributedMiniDialog();
    const { showNotification, notificationProps } = useNotification();
    const { loadingBarRef, showLoadingBar, hideLoadingBar } = useLoadingBar();

    const [watchFolderView, setWatchFolderView] = useState(false);

    const logout = useCallback(() => void photosLogout(), []);

    useEffect(() => {
        logStartupBanner(savedLocalUser()?.id);
        void isLocalStorageAndIndexedDBMismatch().then((mismatch) => {
            if (mismatch) {
                log.error("Logging out (IndexedDB and local storage mismatch)");
                logout();
                return;
            } else {
                return runMigrations();
            }
        });
    }, [logout]);

    useEffect(() => {
        const electron = globalThis.electron;
        if (!electron) return undefined;

        const handleOpenEnteURL = (url: string) => {
            if (url.startsWith("ente://app")) {
                void router.push(url);
            } else {
                log.info(`Ignoring unhandled open request for URL ${url}`);
            }
        };

        const showUpdateDialog = (update: AppUpdate) => {
            if (update.autoUpdatable) {
                showMiniDialog(updateReadyToInstallDialogAttributes(update));
            } else {
                showNotification({
                    color: "secondary",
                    title: t("update_available"),
                    endIcon: <ArrowForwardIcon />,
                    onClick: () =>
                        showMiniDialog(
                            updateAvailableForDownloadDialogAttributes(update),
                        ),
                });
            }
        };

        if (isMLSupported) initML();
        if (isHLSGenerationSupported) void initVideoProcessing();

        electron.onOpenEnteURL(handleOpenEnteURL);
        electron.onAppUpdateAvailable(showUpdateDialog);

        return () => {
            electron.onOpenEnteURL(undefined);
            electron.onAppUpdateAvailable(undefined);
        };
    }, [router, showMiniDialog, showNotification]);

    useEffect(() => {
        if (isDesktop) void resumeExportsIfNeeded();
    }, []);

    const baseContext = useMemo(
        () => deriveBaseContext({ logout, showMiniDialog }),
        [logout, showMiniDialog],
    );
    const appContext = useMemo(
        () => ({
            showLoadingBar,
            hideLoadingBar,
            watchFolderView,
            setWatchFolderView,
            showNotification,
        }),
        [
            showLoadingBar,
            hideLoadingBar,
            watchFolderView,
            setWatchFolderView,
            showNotification,
        ],
    );

    const title = isI18nReady ? t("title_photos") : staticAppTitle;

    return (
        <ThemeProvider theme={photosTheme}>
            <CustomHeadPhotos {...{ title }} />
            <CssBaseline enableColorScheme />

            <ThemedLoadingBar ref={loadingBarRef} />
            <AttributedMiniDialog {...miniDialogProps} />
            <Notification {...notificationProps} />

            {isDesktop && <WindowTitlebar>{title}</WindowTitlebar>}
            <BaseContext value={baseContext}>
                <PhotosAppContext value={appContext}>
                    {!isI18nReady ? (
                        <LoadingIndicator />
                    ) : isDesktop ? (
                        <DesktopMainContent
                            Component={Component}
                            pageProps={pageProps}
                            isChangingRoute={isChangingRoute}
                        />
                    ) : (
                        <WebMainContent
                            Component={Component}
                            pageProps={pageProps}
                            isChangingRoute={isChangingRoute}
                        />
                    )}
                </PhotosAppContext>
            </BaseContext>
        </ThemeProvider>
    );
};

export default App;

const WebMainContent: React.FC<MainContentProps> = ({
    Component,
    pageProps,
    isChangingRoute,
}) => (
    <>
        {isChangingRoute && <TranslucentLoadingOverlay />}
        <Component {...pageProps} />
    </>
);

const DesktopMainContent: React.FC<MainContentProps> = ({
    Component,
    pageProps,
    isChangingRoute,
}) => {
    const { isAppLockReady, appLockSetupFailed, retryAppLockSetup } =
        useSetupAppLock();
    const appLock = useAppLockSnapshot();
    const { shouldBlockAppLockRouteTransition } = useDesktopAppLockRoute(
        isAppLockReady,
        appLock.isLocked,
        appLock.lockScreenMode,
    );

    useAutoLockWhenBackgrounded(
        appLock.enabled,
        appLock.isLocked,
        appLock.autoLockTimeMs,
    );

    if (appLockSetupFailed) {
        return <AppLockSetupError onRetry={retryAppLockSetup} />;
    }
    if (!isAppLockReady) return <LoadingIndicator />;
    if (shouldBlockAppLockRouteTransition) return <LoadingIndicator />;

    return (
        <>
            {isChangingRoute && <TranslucentLoadingOverlay />}
            <Component {...pageProps} />
            <AppLockReauthenticationDialog />
        </>
    );
};

const WindowTitlebar: React.FC<React.PropsWithChildren> = ({ children }) => (
    <WindowTitlebarArea>
        <Typography variant="small" sx={{ mt: "2px", fontWeight: "bold" }}>
            {children}
        </Typography>
    </WindowTitlebarArea>
);

// Electron uses this as a window drag region.
const WindowTitlebarArea = styled(CenteredRow)`
    width: 100%;
    height: env(titlebar-area-height, 30px);
    flex-shrink: 0;
    app-region: drag;
`;
