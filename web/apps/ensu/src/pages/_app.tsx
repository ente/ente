import { WhatsNewDialog } from "@/components/WhatsNewDialog";
import { setupAutoAppUpdates } from "@/services/app-update";
import { isTauriRuntime } from "@/services/tauri-runtime";
import {
    getPendingDesktopWhatsNew,
    markDesktopWhatsNewSeen,
    type PendingDesktopWhatsNew,
} from "@/services/whats-new";
import { CssBaseline } from "@mui/material";
import { ThemeProvider } from "@mui/material/styles";
import { staticAppTitle } from "ente-base/app";
import { assertionFailed } from "ente-base/assert";
import { CustomHead } from "ente-base/components/Head";
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
import { ensuTheme } from "ente-base/components/utils/theme";
import { BaseContext, deriveBaseContext } from "ente-base/context";
import { logStartupBanner } from "ente-base/log-web";
import "katex/dist/katex.min.css";
import type { AppProps } from "next/app";
import React, { useCallback, useEffect, useMemo, useState } from "react";

const App: React.FC<AppProps> = ({ Component, pageProps }) => {
    useSetupLogs();

    const isI18nReady = useSetupI18n();
    const isChangingRoute = useIsRouteChangeInProgress();
    const { showMiniDialog, miniDialogProps } = useAttributedMiniDialog();
    const [pendingWhatsNew, setPendingWhatsNew] = useState<
        PendingDesktopWhatsNew | undefined
    >();
    const [isWhatsNewOpen, setIsWhatsNewOpen] = useState(false);

    useEffect(() => {
        logStartupBanner();
    }, []);

    useEffect(() => setupAutoAppUpdates(showMiniDialog), [showMiniDialog]);

    useEffect(() => {
        setPendingWhatsNew(getPendingDesktopWhatsNew());
    }, []);

    useEffect(() => {
        if (!pendingWhatsNew || miniDialogProps.open || isWhatsNewOpen) return;

        const timeoutId = window.setTimeout(() => {
            if (!miniDialogProps.open) setIsWhatsNewOpen(true);
        }, 600);

        return () => window.clearTimeout(timeoutId);
    }, [isWhatsNewOpen, miniDialogProps.open, pendingWhatsNew]);

    useEffect(() => {
        if (!isTauriRuntime()) return;
        const isEditableTarget = (target: EventTarget | null) => {
            if (!(target instanceof HTMLElement)) return false;
            const tag = target.tagName.toLowerCase();
            if (tag === "input" || tag === "textarea") return true;
            if (target.isContentEditable) return true;
            return !!target.closest('[contenteditable="true"]');
        };

        let hasSelection = false;
        const updateSelection = () => {
            const selection = window.getSelection();
            hasSelection =
                !!selection && selection.toString().trim().length > 0;
        };
        updateSelection();

        const handleContextMenu = (event: MouseEvent) => {
            if (isEditableTarget(event.target) || hasSelection) {
                return;
            }
            event.preventDefault();
        };
        window.addEventListener("contextmenu", handleContextMenu);
        document.addEventListener("selectionchange", updateSelection);
        return () => {
            window.removeEventListener("contextmenu", handleContextMenu);
            document.removeEventListener("selectionchange", updateSelection);
        };
    }, []);

    const handleWhatsNewClose = useCallback(() => {
        markDesktopWhatsNewSeen();
        setIsWhatsNewOpen(false);
        setPendingWhatsNew(undefined);
    }, []);

    const baseContext = useMemo(
        () => deriveBaseContext({ logout: assertionFailed, showMiniDialog }),
        [showMiniDialog],
    );

    const title = staticAppTitle;

    return (
        <ThemeProvider theme={ensuTheme}>
            <CustomHead {...{ title }} />
            <CssBaseline enableColorScheme />
            <AttributedMiniDialog {...miniDialogProps} />
            <WhatsNewDialog
                open={isWhatsNewOpen}
                entries={pendingWhatsNew?.entries ?? []}
                onClose={handleWhatsNewClose}
            />

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
