import {
    Github01Icon,
    LicenseIcon,
    Shield01Icon,
} from "@hugeicons/core-free-icons";
import NorthEastIcon from "@mui/icons-material/NorthEast";
import { Stack, useTheme } from "@mui/material";
import { t } from "i18next";
import React from "react";
import { LockerSidebarCardButton } from "./LockerSidebarCardButton";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";

const openExternal = (url: string) => window.open(url, "_blank", "noopener");

export const LockerAboutDrawer: React.FC<
    LockerNestedSidebarDrawerVisibilityProps
> = ({ open, onClose, onRootClose }) => {
    const theme = useTheme();

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    return (
        <LockerTitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("about")}
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
                    icon={Github01Icon}
                    label={t("we_are_open_source")}
                    endIcon={<NorthEastIcon />}
                    onClick={() => openExternal("https://github.com/ente/ente")}
                />
                <LockerSidebarCardButton
                    icon={Shield01Icon}
                    label={t("privacy")}
                    endIcon={<NorthEastIcon />}
                    onClick={() => openExternal("https://ente.com/privacy")}
                />
                <LockerSidebarCardButton
                    icon={LicenseIcon}
                    label={t("terms")}
                    endIcon={<NorthEastIcon />}
                    onClick={() => openExternal("https://ente.com/terms")}
                />
            </Stack>
        </LockerTitledNestedSidebarDrawer>
    );
};
