import { MAX_PAGE_PHOTOS } from "@/lib/photoPlacement";
import { pageMenuColors, uiColors } from "@/theme/colors";
import { pageMenuItemSx, pageMenuPaperSx } from "@/theme/menus";
import { IconButton, Menu, MenuItem } from "@mui/material";
import { useState } from "react";
import {
    AddPageIcon,
    AddPhotosIcon,
    DeleteIcon,
    EditPhotoIcon,
    MoreIcon,
} from "./icons";
import RequiredPageDialog from "./RequiredPageDialog";

export type PageInsertPosition = "before" | "after";

interface PageMenuProps {
    pageId: string;
    pageIndex: number;
    totalPages: number;
    side: "left" | "right";
    photoCount: number;
    requiredBlank: boolean;
    onAddPhotos: () => void;
    onInsert: (position: PageInsertPosition) => void;
    onDelete: () => void;
}

export default function PageMenu({
    pageId,
    pageIndex,
    totalPages,
    side,
    photoCount,
    requiredBlank,
    onAddPhotos,
    onInsert,
    onDelete,
}: PageMenuProps) {
    const [anchorEl, setAnchorEl] = useState<HTMLButtonElement | null>(null);
    const [restoreFocus, setRestoreFocus] = useState(true);
    const [requiredPageDialogOpen, setRequiredPageDialogOpen] = useState(false);
    const isFrontCover = pageIndex === 0;
    const isBackCover = pageIndex === totalPages - 1;
    const isInterior = !isFrontCover && !isBackCover;
    const label = isFrontCover
        ? "Front cover"
        : isBackCover
          ? "Back cover"
          : `Page ${pageIndex}`;
    const buttonId = `page-menu-button-${pageId}`;
    const menuId = `page-menu-${pageId}`;
    const open = Boolean(anchorEl);

    const runAction = (action: () => void) => {
        setRestoreFocus(false);
        setAnchorEl(null);
        action();
    };

    return (
        <>
            <IconButton
                id={buttonId}
                data-page-control
                data-open={open ? "true" : undefined}
                aria-label={`${label} options`}
                aria-haspopup="menu"
                aria-controls={open ? menuId : undefined}
                aria-expanded={open ? true : undefined}
                onClick={(event) => {
                    event.stopPropagation();
                    setRestoreFocus(true);
                    setAnchorEl(event.currentTarget);
                }}
                sx={{
                    bgcolor: open
                        ? pageMenuColors.active
                        : pageMenuColors.hover,
                    borderRadius: "14px",
                    color: open ? pageMenuColors.text : uiColors.muted,
                    width: 44,
                    height: 44,
                    flexShrink: 0,
                    mt: "auto",
                    p: 0,
                    "&:hover": {
                        bgcolor: pageMenuColors.active,
                        color: pageMenuColors.text,
                    },
                    "&.Mui-focusVisible": { opacity: 1, pointerEvents: "auto" },
                }}
            >
                <MoreIcon sx={{ fontSize: 20 }} />
            </IconButton>
            <Menu
                id={menuId}
                anchorEl={anchorEl}
                open={open}
                onClose={() => setAnchorEl(null)}
                onClick={(event) => event.stopPropagation()}
                disableRestoreFocus={!restoreFocus}
                anchorOrigin={{ vertical: "bottom", horizontal: side }}
                transformOrigin={{ vertical: "top", horizontal: side }}
                slotProps={{
                    paper: { sx: pageMenuPaperSx },
                    list: { "aria-labelledby": buttonId, sx: { p: 0 } },
                }}
            >
                {isFrontCover && (
                    <MenuItem
                        dense
                        disableRipple
                        onClick={() => runAction(onAddPhotos)}
                        sx={pageMenuItemSx}
                    >
                        <EditPhotoIcon sx={{ fontSize: 18, flexShrink: 0 }} />
                        Change cover image
                    </MenuItem>
                )}
                {isInterior && photoCount < MAX_PAGE_PHOTOS && (
                    <MenuItem
                        dense
                        disableRipple
                        onClick={() => runAction(onAddPhotos)}
                        sx={pageMenuItemSx}
                    >
                        <AddPhotosIcon sx={{ fontSize: 18, flexShrink: 0 }} />
                        Add photos
                    </MenuItem>
                )}
                {!isFrontCover && (
                    <MenuItem
                        dense
                        disableRipple
                        onClick={() => runAction(() => onInsert("before"))}
                        sx={pageMenuItemSx}
                    >
                        <AddPageIcon sx={{ fontSize: 18, flexShrink: 0 }} />
                        Insert page before
                    </MenuItem>
                )}
                {!isBackCover && (
                    <MenuItem
                        dense
                        disableRipple
                        onClick={() => runAction(() => onInsert("after"))}
                        sx={pageMenuItemSx}
                    >
                        <AddPageIcon sx={{ fontSize: 18, flexShrink: 0 }} />
                        Insert page after
                    </MenuItem>
                )}
                {isInterior && (
                    <MenuItem
                        dense
                        disableRipple
                        onClick={() =>
                            runAction(() => {
                                if (requiredBlank)
                                    setRequiredPageDialogOpen(true);
                                else onDelete();
                            })
                        }
                        sx={{
                            ...pageMenuItemSx,
                            color: pageMenuColors.danger,
                            "& .MuiSvgIcon-root": {
                                color: pageMenuColors.danger,
                            },
                            "&:hover, &.Mui-focusVisible": {
                                bgcolor: pageMenuColors.dangerHover,
                                "& .MuiSvgIcon-root": {
                                    color: pageMenuColors.danger,
                                },
                            },
                            "&:active": {
                                bgcolor: pageMenuColors.dangerActive,
                            },
                        }}
                    >
                        <DeleteIcon sx={{ fontSize: 18, flexShrink: 0 }} />
                        Delete page
                    </MenuItem>
                )}
            </Menu>
            {requiredPageDialogOpen && (
                <RequiredPageDialog
                    onClose={() => setRequiredPageDialogOpen(false)}
                />
            )}
        </>
    );
}
