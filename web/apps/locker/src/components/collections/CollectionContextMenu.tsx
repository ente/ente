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

export const CollectionContextMenu: React.FC<{
    ariaID: string;
    onShare?: () => void;
    onLeave?: () => void;
    onRename?: () => void;
    onDelete?: () => void;
}> = ({ ariaID, onShare, onLeave, onRename, onDelete }) => (
    <LockerOverflowMenu
        ariaID={ariaID}
        triggerButtonSxProps={{ p: 0.25, color: "text.muted" }}
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
