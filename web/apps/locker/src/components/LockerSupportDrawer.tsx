import {
    HelpCircleIcon,
    InformationCircleIcon,
    MessageQuestionIcon,
    NewsIcon,
} from "@hugeicons/core-free-icons";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import NorthEastIcon from "@mui/icons-material/NorthEast";
import { Box, Stack, Tooltip, Typography, useTheme } from "@mui/material";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { savedLogs } from "ente-base/log-web";
import { saveStringAsFile } from "ente-base/utils/web";
import { initiateEmail, openURL } from "ente-new/photos/utils/web";
import { t } from "i18next";
import React from "react";
import { Trans } from "react-i18next";
import { LockerSidebarCardButton } from "./LockerSidebarCardButton";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";

export const LockerSupportDrawer: React.FC<
    LockerNestedSidebarDrawerVisibilityProps
> = ({ open, onClose, onRootClose }) => {
    const { showMiniDialog } = useBaseContext();
    const theme = useTheme();

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const handleHelp = () => openURL("https://ente.com/help/photos/");
    const handleBlog = () => openURL("https://ente.com/blog/");
    const handleRequestFeature = () =>
        openURL("https://github.com/ente/ente/discussions");
    const handleSupport = () => initiateEmail("support@ente.com");

    const viewLogs = async () => {
        log.info("Viewing logs");
        const electron = globalThis.electron;
        if (electron) {
            await electron.openLogDirectory();
        } else {
            saveStringAsFile(savedLogs(), `ente-web-logs-${Date.now()}.txt`);
        }
    };

    const confirmViewLogs = () =>
        showMiniDialog({
            title: t("view_logs"),
            message: <Trans i18nKey="view_logs_message" />,
            continue: { text: t("view_logs"), action: viewLogs },
        });

    return (
        <LockerTitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("help_and_support")}
            hideRootCloseButton
        >
            <Stack
                sx={{
                    px: 2,
                    py: 1,
                    gap: 1,
                    backgroundColor: "background.default",
                    ...theme.applyStyles("dark", {
                        backgroundColor: "background.paper",
                    }),
                }}
            >
                <LockerSidebarCardButton
                    icon={InformationCircleIcon}
                    label={t("help")}
                    endIcon={<NorthEastIcon />}
                    onClick={handleHelp}
                />
                <LockerSidebarCardButton
                    icon={NewsIcon}
                    label={t("blog")}
                    endIcon={<NorthEastIcon />}
                    onClick={handleBlog}
                />
                <LockerSidebarCardButton
                    icon={MessageQuestionIcon}
                    label={t("request_feature")}
                    endIcon={<NorthEastIcon />}
                    onClick={handleRequestFeature}
                />
                <LockerSidebarCardButton
                    icon={HelpCircleIcon}
                    label={
                        <Tooltip title="support@ente.com">
                            <Typography
                                variant="small"
                                sx={{ fontWeight: 500 }}
                            >
                                {t("support")}
                            </Typography>
                        </Tooltip>
                    }
                    endIcon={<ChevronRightIcon />}
                    onClick={handleSupport}
                />
                <Box
                    sx={{ borderTop: 1, borderColor: "divider", mx: 1, my: 1 }}
                />
                <LockerSidebarCardButton
                    icon={InformationCircleIcon}
                    label={t("view_logs")}
                    endIcon={<ChevronRightIcon />}
                    onClick={confirmViewLogs}
                />
            </Stack>
        </LockerTitledNestedSidebarDrawer>
    );
};
