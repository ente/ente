import { Stack } from "@mui/material";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { RowCard } from "ente-base/components/v2/RowCard";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { savedLogs } from "ente-base/log-web";
import { saveStringAsFile } from "ente-base/utils/web";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import { initiateEmail, openURL } from "ente-new/photos/utils/web";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";
import { Trans } from "react-i18next";

export type HelpAction = Extract<
    SidebarActionID,
    | "help.helpCenter"
    | "help.blog"
    | "help.requestFeature"
    | "help.support"
    | "help.viewLogs"
>;

type HelpProps = NestedSidebarDrawerVisibilityProps & {
    pendingAction?: HelpAction;
    onActionHandled?: (Action?: HelpAction) => void;
};

export const Help: React.FC<HelpProps> = ({
    open,
    onClose,
    onRootClose,
    pendingAction,
    onActionHandled,
}) => {
    const { showMiniDialog } = useBaseContext();
    const [appVersion, setAppVersion] = useState("");

    useEffect(() => {
        void globalThis.electron?.appVersion().then(setAppVersion);
    }, []);

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const handleHelp = useCallback(
        () => openURL("https://ente.com/help/photos/"),
        [],
    );

    const handleBlog = useCallback(() => openURL("https://ente.com/blog/"), []);

    const handleRequestFeature = useCallback(
        () => openURL("https://github.com/ente/ente/discussions"),
        [],
    );

    const handleSupport = useCallback(
        () => initiateEmail("support@ente.com"),
        [],
    );

    const viewLogs = useCallback(async () => {
        log.info("Viewing logs");
        const electron = globalThis.electron;
        if (electron) {
            await electron.openLogDirectory();
        } else {
            saveStringAsFile(savedLogs(), `ente-web-logs-${Date.now()}.txt`);
        }
    }, []);

    const confirmViewLogs = useCallback(
        () =>
            showMiniDialog({
                title: t("view_logs"),
                message: <Trans i18nKey={"view_logs_message"} />,
                continue: { text: t("view_logs"), action: viewLogs },
            }),
        [showMiniDialog, viewLogs],
    );

    useEffect(() => {
        if (!open || !pendingAction) return;
        switch (pendingAction) {
            case "help.helpCenter":
                handleHelp();
                break;
            case "help.blog":
                handleBlog();
                break;
            case "help.requestFeature":
                handleRequestFeature();
                break;
            case "help.support":
                handleSupport();
                break;
            case "help.viewLogs":
                confirmViewLogs();
                break;
        }
        onActionHandled?.();
    }, [
        confirmViewLogs,
        handleBlog,
        handleHelp,
        handleRequestFeature,
        handleSupport,
        open,
        onActionHandled,
        pendingAction,
    ]);

    return (
        <TitledNestedSidebarDrawer
            maxWidth="440px"
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("help")}
        >
            <Stack sx={{ px: 2, py: 1, gap: 1 }}>
                <RowCard
                    title="Help centre"
                    subtitle="ente.com/help/photos"
                    onClick={handleHelp}
                />
                <RowCard
                    title={t("blog")}
                    subtitle="ente.com/blog"
                    onClick={handleBlog}
                />
                <RowCard
                    title="Request a feature"
                    subtitle="github.com/ente/ente"
                    onClick={handleRequestFeature}
                />
                <RowCard
                    title={t("support")}
                    subtitle="support@ente.com"
                    onClick={handleSupport}
                />
                <RowCard
                    title={t("view_logs")}
                    subtitle="Share with support when something goes wrong"
                    onClick={confirmViewLogs}
                />
                {appVersion && (
                    <RowCard
                        title="About"
                        subtitle={`Photos ${appVersion}`}
                        endIcon={null}
                    />
                )}
            </Stack>
        </TitledNestedSidebarDrawer>
    );
};
