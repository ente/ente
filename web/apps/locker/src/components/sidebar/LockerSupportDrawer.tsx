import {
    Bug01Icon,
    FavouriteIcon,
    File01Icon,
    HelpCircleIcon,
    Idea01Icon,
    Rocket01Icon,
    SecurityCheckIcon,
    Wallet05Icon,
    Wrench01Icon,
} from "@hugeicons/core-free-icons";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import { Box } from "@mui/material";
import log from "ente-base/log";
import { savedLogs } from "ente-base/log-web";
import { saveStringAsFile } from "ente-base/utils/web";
import { initiateEmail, openURL } from "ente-new/photos/utils/web";
import { t } from "i18next";
import React, { useState } from "react";
import { Trans } from "react-i18next";
import { lockerColorSx } from "../../styles/tokens";
import { LockerConfirmDialog } from "../ui/LockerConfirmDialog";
import {
    LockerSidebarCardButton,
    LockerSidebarLink,
    LockerSidebarSectionTitle,
} from "./LockerSidebarCardButton";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";

const helpTopics = [
    { icon: Rocket01Icon, key: "getting_started", slug: "getting-started" },
    { icon: File01Icon, key: "information_types", slug: "information-types" },
    { icon: Wallet05Icon, key: "organization", slug: "organization" },
    { icon: FavouriteIcon, key: "legacy", slug: "legacy" },
    { icon: SecurityCheckIcon, key: "security", slug: "security" },
    { icon: Wrench01Icon, key: "troubleshooting", slug: "troubleshooting" },
] as const;

export const LockerSupportDrawer: React.FC<
    LockerNestedSidebarDrawerVisibilityProps
> = ({ open, onClose, onRootClose }) => {
    const [logsOpen, setLogsOpen] = useState(false);
    const [isViewingLogs, setIsViewingLogs] = useState(false);
    const [logsError, setLogsError] = useState<string>();
    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const handleRequestFeature = () =>
        openURL("https://github.com/ente/ente/discussions");
    const handleReportIssue = () =>
        openURL("https://github.com/ente/ente/issues");
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

    const handleViewLogs = async () => {
        if (isViewingLogs) return;
        setIsViewingLogs(true);
        setLogsError(undefined);
        try {
            await viewLogs();
            setLogsOpen(false);
        } catch (error) {
            log.error("Failed to view Locker logs", error);
            setLogsError(t("generic_error"));
        } finally {
            setIsViewingLogs(false);
        }
    };

    return (
        <LockerTitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("help_and_support")}
        >
            <LockerSidebarSectionTitle>
                {t("get_in_touch")}
            </LockerSidebarSectionTitle>
            <LockerSidebarCardButton
                icon={HelpCircleIcon}
                label={t("ask_a_question")}
                endIcon={<ChevronRightIcon />}
                onClick={handleSupport}
            />
            <LockerSidebarCardButton
                icon={Idea01Icon}
                label={t("request_a_feature")}
                endIcon={<ChevronRightIcon />}
                onClick={handleRequestFeature}
            />
            <LockerSidebarCardButton
                icon={Bug01Icon}
                label={t("report_an_issue")}
                endIcon={<ChevronRightIcon />}
                onClick={handleReportIssue}
            />
            <LockerSidebarLink
                onClick={() => {
                    setLogsError(undefined);
                    setLogsOpen(true);
                }}
            >
                {t("export_logs")}
            </LockerSidebarLink>
            <Box sx={{ mt: 2 }}>
                <LockerSidebarSectionTitle>
                    {t("browse_help_pages")}
                </LockerSidebarSectionTitle>
            </Box>
            {helpTopics.map(({ icon, key, slug }) => (
                <LockerSidebarCardButton
                    key={key}
                    icon={icon}
                    label={t(key)}
                    subtitle={t(`${key}_desc`)}
                    endIcon={<ChevronRightIcon />}
                    onClick={() =>
                        openURL(`https://ente.com/help/locker/faq/${slug}`)
                    }
                />
            ))}
            <LockerSidebarLink
                onClick={() => openURL("https://ente.com/help/locker")}
            >
                {t("view_all_help_topics")}
            </LockerSidebarLink>
            <LockerConfirmDialog
                open={logsOpen}
                illustration="/images/warning-grey.png"
                title={t("view_logs")}
                body={
                    <Box
                        component="span"
                        sx={(theme) => ({
                            display: "block",
                            textAlign: "center",
                            lineHeight: "22px",
                            ...lockerColorSx(theme, { color: "textBase" }),
                            "& > span": { display: "block" },
                            "& > span + span": {
                                mt: 2,
                                p: 1.5,
                                borderRadius: "12px",
                                ...lockerColorSx(theme, {
                                    backgroundColor: "fillDark",
                                    color: "textLight",
                                }),
                            },
                        })}
                    >
                        <Trans
                            i18nKey="view_logs_message"
                            components={{ p: <span /> }}
                        />
                    </Box>
                }
                confirmLabel={t("view_logs")}
                tone="primary"
                loading={isViewingLogs}
                error={logsError}
                onClose={() => setLogsOpen(false)}
                onConfirm={handleViewLogs}
            />
        </LockerTitledNestedSidebarDrawer>
    );
};
