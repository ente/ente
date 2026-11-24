import { MoreHorizontalIcon, Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { IconButton, Tooltip } from "@mui/material";
import { ContextMenu, ContextMenuItem } from "ente-base/components/ContextMenu";
import { useId, useState, type ReactNode } from "react";
import { headerIconButtonSx, headerIconSize } from "./header-styles";

interface GalleryActionMenuItem {
    label: string;
    icon?: ReactNode;
    selected?: boolean;
    destructive?: boolean;
    onClick: () => void;
}

interface GalleryActionMenuProps {
    label: string;
    icon?: ReactNode;
    items: GalleryActionMenuItem[];
}

export const GalleryActionMenu = ({
    label,
    icon,
    items,
}: GalleryActionMenuProps) => {
    const triggerId = useId();
    const menuId = useId();
    const [anchorEl, setAnchorEl] = useState<HTMLButtonElement | null>(null);
    const open = Boolean(anchorEl);

    return (
        <>
            <Tooltip title={label}>
                <IconButton
                    id={triggerId}
                    aria-label={label}
                    aria-haspopup="menu"
                    aria-expanded={open}
                    aria-controls={open ? menuId : undefined}
                    onClick={(event) => setAnchorEl(event.currentTarget)}
                    sx={headerIconButtonSx}
                >
                    {icon ?? <HugeiconsIcon icon={MoreHorizontalIcon} />}
                </IconButton>
            </Tooltip>
            <ContextMenu
                anchorEl={anchorEl}
                open={open}
                onClose={() => setAnchorEl(null)}
                slotProps={{
                    list: { id: menuId, "aria-labelledby": triggerId },
                }}
                anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
                transformOrigin={{ vertical: "top", horizontal: "right" }}
            >
                {items.map(
                    ({ label, icon, selected, destructive, onClick }) => (
                        <ContextMenuItem
                            key={label}
                            destructive={destructive}
                            selected={selected}
                            role={
                                selected === undefined
                                    ? "menuitem"
                                    : "menuitemradio"
                            }
                            aria-checked={selected}
                            sx={{
                                whiteSpace: "normal",
                                overflowWrap: "anywhere",
                                "& > svg": { flexShrink: 0 },
                            }}
                            onClick={() => {
                                setAnchorEl(null);
                                onClick();
                            }}
                        >
                            {icon}
                            {label}
                            {selected && (
                                <HugeiconsIcon
                                    icon={Tick02Icon}
                                    size={headerIconSize}
                                    style={{ marginInlineStart: "auto" }}
                                />
                            )}
                        </ContextMenuItem>
                    ),
                )}
            </ContextMenu>
        </>
    );
};
