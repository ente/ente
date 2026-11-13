import {
    File01Icon,
    GithubIcon,
    Shield01Icon,
} from "@hugeicons/core-free-icons";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
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
    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    return (
        <LockerTitledNestedSidebarDrawer
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("about")}
        >
            <LockerSidebarCardButton
                icon={GithubIcon}
                label={t("we_are_open_source")}
                endIcon={<ChevronRightIcon />}
                onClick={() => openExternal("https://github.com/ente/ente")}
            />
            <LockerSidebarCardButton
                icon={Shield01Icon}
                label={t("privacy")}
                endIcon={<ChevronRightIcon />}
                onClick={() => openExternal("https://ente.com/privacy")}
            />
            <LockerSidebarCardButton
                icon={File01Icon}
                label={t("terms")}
                endIcon={<ChevronRightIcon />}
                onClick={() => openExternal("https://ente.com/terms")}
            />
        </LockerTitledNestedSidebarDrawer>
    );
};
