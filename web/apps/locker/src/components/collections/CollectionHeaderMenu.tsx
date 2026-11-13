import {
    LockerMenuOption,
    LockerOverflowMenu,
} from "@/components/ui/LockerMenu";
import DeleteOutlinedIcon from "@mui/icons-material/DeleteOutlined";
import EditOutlinedIcon from "@mui/icons-material/EditOutlined";
import LogoutOutlinedIcon from "@mui/icons-material/LogoutOutlined";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import { t } from "i18next";
import React from "react";

export const CollectionHeaderMenu: React.FC<{
    onShare?: () => void;
    onLeave?: () => void;
    onRename?: () => void;
    onDelete?: () => void;
}> = ({ onShare, onLeave, onRename, onDelete }) => (
    <LockerOverflowMenu
        ariaID="collection-header-menu"
        triggerButtonSxProps={{ color: "text.muted" }}
    >
        {onShare && (
            <LockerMenuOption
                startIcon={<ShareOutlinedIcon />}
                onClick={onShare}
            >
                {t(onLeave ? "sharedWith" : "share")}
            </LockerMenuOption>
        )}
        {onLeave && (
            <LockerMenuOption
                startIcon={<LogoutOutlinedIcon />}
                critical
                onClick={onLeave}
            >
                {t("leaveCollection")}
            </LockerMenuOption>
        )}
        {onRename && (
            <LockerMenuOption
                startIcon={<EditOutlinedIcon />}
                onClick={onRename}
            >
                {t("renameCollection")}
            </LockerMenuOption>
        )}
        {onDelete && (
            <LockerMenuOption
                startIcon={<DeleteOutlinedIcon />}
                critical
                onClick={onDelete}
            >
                {t("deleteCollection")}
            </LockerMenuOption>
        )}
    </LockerOverflowMenu>
);
