import type { FileContextAction } from "@/utils/file-actions";
import {
    AddSquareIcon,
    ArrowRight02Icon,
    Clock02Icon,
    Delete02Icon,
    Download01Icon,
    Download05Icon,
    Location01Icon,
    Navigation03Icon,
    RemoveCircleIcon,
    StarIcon,
    StarOffIcon,
    Time04Icon,
    Unarchive03Icon,
    UserAdd02Icon,
    ViewIcon,
    ViewOffSlashIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon, type IconSvgElement } from "@hugeicons/react";
import { ListItemIcon, ListItemText } from "@mui/material";
import { ContextMenu, ContextMenuItem } from "ente-base/components/ContextMenu";
import { t } from "i18next";
import React, { memo, useCallback, useMemo } from "react";

export interface ContextMenuPosition {
    top: number;
    left: number;
}

interface FileContextMenuProps {
    open: boolean;
    anchorPosition: ContextMenuPosition | undefined;
    onClose: () => void;
    actions: FileContextAction[];
    onAction: (action: FileContextAction) => void;
}

interface ActionConfig {
    label: string;
    Icon: React.ReactNode;
    isDestructive?: boolean;
}

const hugeIcon = (icon: IconSvgElement, size = 20) => (
    <HugeiconsIcon icon={icon} size={size} />
);

const actionConfigs: Record<FileContextAction, ActionConfig> = {
    sendLink: { label: "send_link", Icon: hugeIcon(Navigation03Icon) },
    download: { label: "download", Icon: hugeIcon(Download01Icon) },
    fixTime: { label: "fix_creation_time", Icon: hugeIcon(Time04Icon) },
    editLocation: { label: "edit_location", Icon: hugeIcon(Location01Icon) },
    favorite: { label: "favorite", Icon: hugeIcon(StarIcon) },
    unfavorite: { label: "un_favorite", Icon: hugeIcon(StarOffIcon) },
    archive: { label: "archive", Icon: hugeIcon(Download05Icon) },
    unarchive: { label: "unarchive", Icon: hugeIcon(Unarchive03Icon) },
    hide: { label: "hide", Icon: hugeIcon(ViewOffSlashIcon) },
    unhide: { label: "unhide", Icon: hugeIcon(ViewIcon) },
    trash: {
        label: "delete",
        Icon: hugeIcon(Delete02Icon),
        isDestructive: true,
    },
    deletePermanently: {
        label: "delete_permanently",
        Icon: hugeIcon(Delete02Icon),
        isDestructive: true,
    },
    restore: { label: "restore", Icon: hugeIcon(Clock02Icon) },
    addToAlbum: { label: "add", Icon: hugeIcon(AddSquareIcon) },
    moveToAlbum: { label: "move", Icon: hugeIcon(ArrowRight02Icon) },
    removeFromAlbum: { label: "remove", Icon: hugeIcon(RemoveCircleIcon) },
    addPerson: { label: "add_a_person", Icon: hugeIcon(UserAdd02Icon) },
};

export const FileContextMenu: React.FC<FileContextMenuProps> = memo(
    ({ open, anchorPosition, onClose, actions, onAction }) => {
        const handleActionClick = useCallback(
            (action: FileContextAction) => {
                onClose();
                onAction(action);
            },
            [onClose, onAction],
        );

        const [primaryActions, destructiveActions] = useMemo(() => {
            const primary: FileContextAction[] = [];
            const destructive: FileContextAction[] = [];
            for (const action of actions) {
                if (actionConfigs[action].isDestructive) {
                    destructive.push(action);
                } else {
                    primary.push(action);
                }
            }
            return [primary, destructive];
        }, [actions]);

        return (
            <ContextMenu
                open={open}
                onClose={onClose}
                disableAutoFocusItem
                anchorReference="anchorPosition"
                anchorPosition={anchorPosition}
                slotProps={{
                    root: {
                        onContextMenu: (e: React.MouseEvent) =>
                            e.preventDefault(),
                    },
                }}
            >
                {primaryActions.map((action) => {
                    const { label, Icon } = actionConfigs[action];
                    return (
                        <ContextMenuItem
                            key={action}
                            onClick={() => handleActionClick(action)}
                        >
                            <ListItemIcon>{Icon}</ListItemIcon>
                            <ListItemText>{t(label)}</ListItemText>
                        </ContextMenuItem>
                    );
                })}

                {destructiveActions.map((action) => {
                    const { label, Icon } = actionConfigs[action];
                    return (
                        <ContextMenuItem
                            key={action}
                            onClick={() => handleActionClick(action)}
                            destructive
                        >
                            <ListItemIcon sx={{ color: "inherit" }}>
                                {Icon}
                            </ListItemIcon>
                            <ListItemText>{t(label)}</ListItemText>
                        </ContextMenuItem>
                    );
                })}
            </ContextMenu>
        );
    },
);

FileContextMenu.displayName = "FileContextMenu";
