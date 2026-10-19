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
import {
    ListItemIcon,
    ListItemText,
    Menu,
    MenuItem,
    styled,
} from "@mui/material";
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
            <StyledMenu
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
                        <StyledMenuItem
                            key={action}
                            onClick={() => handleActionClick(action)}
                        >
                            <ListItemIcon>{Icon}</ListItemIcon>
                            <ListItemText>{t(label)}</ListItemText>
                        </StyledMenuItem>
                    );
                })}

                {destructiveActions.map((action) => {
                    const { label, Icon } = actionConfigs[action];
                    return (
                        <StyledMenuItem
                            key={action}
                            onClick={() => handleActionClick(action)}
                            sx={{
                                color: "critical.main",
                                "&:hover": {
                                    backgroundColor: "critical.main",
                                    color: "#fff",
                                },
                            }}
                        >
                            <ListItemIcon sx={{ color: "inherit" }}>
                                {Icon}
                            </ListItemIcon>
                            <ListItemText>{t(label)}</ListItemText>
                        </StyledMenuItem>
                    );
                })}
            </StyledMenu>
        );
    },
);

FileContextMenu.displayName = "FileContextMenu";

const StyledMenu = styled(Menu)(({ theme }) => ({
    "& .MuiPaper-root": {
        backgroundColor: "#1f1f1f",
        minWidth: 220,
        borderRadius: 12,
        boxShadow: "0 8px 24px rgba(0, 0, 0, 0.35)",
        marginTop: 6,
    },
    "& .MuiList-root": { padding: theme.spacing(1) },
    ...theme.applyStyles("dark", {
        "& .MuiPaper-root": {
            backgroundColor: "#161616",
            boxShadow: "0 8px 24px rgba(0, 0, 0, 0.6)",
        },
    }),
}));

const StyledMenuItem = styled(MenuItem)(({ theme }) => ({
    display: "flex",
    alignItems: "center",
    gap: 12,
    padding: theme.spacing(1.5, 2),
    borderRadius: 10,
    color: "#f5f5f5",
    fontSize: 15,
    "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.08)" },
    "& .MuiListItemIcon-root": { minWidth: 0, color: "inherit" },
    "& .MuiListItemText-root": { margin: 0 },
    "& .MuiListItemText-primary": { color: "inherit", fontSize: "inherit" },
}));
