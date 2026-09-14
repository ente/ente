import { collectionDialogIconButtonSx } from "@/components/CollectionDialog/styles";
import type { PeopleSortBy } from "@/utils/people-sort";
import { ArrowDown02Icon, ArrowUp02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import SortIcon from "@mui/icons-material/Sort";
import {
    IconButton,
    MenuItem,
    Stack,
    Typography,
    styled,
    type IconButtonProps,
    type PaperProps,
} from "@mui/material";
import Menu, { type MenuProps } from "@mui/material/Menu";
import { t } from "i18next";
import React, { useRef, useState } from "react";

interface PeopleSortOptionsProps {
    activeSortBy: PeopleSortBy;
    onChangeSortBy: (by: PeopleSortBy) => void;
    nestedInDialog?: boolean;
    variant?: "default" | "v2";
    transparentTriggerButtonBackground?: boolean;
}

type PeopleSortCategory = "name" | "count";

const getPeopleSortCategory = (sortBy: PeopleSortBy): PeopleSortCategory =>
    sortBy.startsWith("name") ? "name" : "count";

const isPeopleSortAscending = (sortBy: PeopleSortBy) => sortBy.endsWith("asc");

const getPeopleSortBy = (
    category: PeopleSortCategory,
    ascending: boolean,
): PeopleSortBy => `${category}-${ascending ? "asc" : "desc"}`;

export const PeopleSortOptions: React.FC<PeopleSortOptionsProps> = ({
    activeSortBy,
    onChangeSortBy,
    nestedInDialog,
    variant = "default",
    transparentTriggerButtonBackground,
}) => {
    const [anchorEl, setAnchorEl] = useState<MenuProps["anchorEl"]>();

    // Apply sort changes after the menu closes to avoid flicker.
    const pendingSortByRef = useRef<PeopleSortBy | undefined>(undefined);
    const ariaID = "people-sort";

    const activeCategory = getPeopleSortCategory(activeSortBy);
    const activeAscending = isPeopleSortAscending(activeSortBy);

    const handleCategoryClick = (category: PeopleSortCategory) => {
        let nextSortBy: PeopleSortBy;
        if (category === activeCategory) {
            nextSortBy = getPeopleSortBy(category, !activeAscending);
        } else {
            nextSortBy = getPeopleSortBy(category, category === "name");
        }
        pendingSortByRef.current = nextSortBy;
        setAnchorEl(undefined);
    };

    const triggerButtonSxProps: IconButtonProps["sx"] =
        variant === "v2"
            ? collectionDialogIconButtonSx
            : [
                  transparentTriggerButtonBackground
                      ? {}
                      : { backgroundColor: "fill.faint" },
              ];

    const menuPaperSxProps: PaperProps["sx"] | undefined = nestedInDialog
        ? { backgroundColor: "background.paper2" }
        : undefined;

    return (
        <>
            <IconButton
                onClick={(event) => setAnchorEl(event.currentTarget)}
                aria-controls={anchorEl ? ariaID : undefined}
                aria-haspopup="true"
                aria-expanded={anchorEl ? "true" : undefined}
                aria-label={t("sort_by")}
                sx={triggerButtonSxProps}
            >
                <SortIcon
                    sx={variant === "v2" ? { fontSize: 20 } : undefined}
                />
            </IconButton>
            <StyledMenu
                id={ariaID}
                {...(anchorEl && { anchorEl })}
                open={!!anchorEl}
                onClose={() => setAnchorEl(undefined)}
                slotProps={{
                    paper: menuPaperSxProps ? { sx: menuPaperSxProps } : {},
                    list: { disablePadding: true, "aria-labelledby": ariaID },
                    transition: {
                        onExited: () => {
                            const nextSortBy = pendingSortByRef.current;
                            if (nextSortBy) {
                                pendingSortByRef.current = undefined;
                                onChangeSortBy(nextSortBy);
                            }
                        },
                    },
                }}
                anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
                transformOrigin={{ vertical: "top", horizontal: "right" }}
            >
                <PeopleSortCategoryOption
                    category="name"
                    activeCategory={activeCategory}
                    activeAscending={activeAscending}
                    onClick={handleCategoryClick}
                    label={t("name")}
                    directionLabel={
                        activeAscending
                            ? t("sort_asc_indicator")
                            : t("sort_desc_indicator")
                    }
                />
                <PeopleSortCategoryOption
                    category="count"
                    activeCategory={activeCategory}
                    activeAscending={activeAscending}
                    onClick={handleCategoryClick}
                    label={t("photos")}
                />
            </StyledMenu>
        </>
    );
};

interface PeopleSortCategoryOptionProps {
    category: PeopleSortCategory;
    activeCategory: PeopleSortCategory;
    activeAscending: boolean;
    onClick: (category: PeopleSortCategory) => void;
    label: string;
    directionLabel?: string;
}

const PeopleSortCategoryOption: React.FC<PeopleSortCategoryOptionProps> = ({
    category,
    activeCategory,
    activeAscending,
    onClick,
    label,
    directionLabel,
}) => {
    const isSelected = category === activeCategory;
    const arrowIcon = activeAscending ? ArrowUp02Icon : ArrowDown02Icon;

    return (
        <StyledMenuItem onClick={() => onClick(category)}>
            <Stack direction="row" sx={{ alignItems: "center" }}>
                <Typography
                    sx={{
                        color: isSelected ? "text.primary" : "text.secondary",
                    }}
                >
                    {label}
                </Typography>
                {isSelected && (
                    <Stack
                        direction="row"
                        sx={{
                            alignItems: "center",
                            ml: 1,
                            gap: 0.75,
                            color: "text.muted",
                        }}
                    >
                        {directionLabel && <Typography>•</Typography>}
                        {directionLabel && (
                            <Typography sx={{ fontSize: "0.9rem" }}>
                                {directionLabel}
                            </Typography>
                        )}
                        <HugeiconsIcon
                            icon={arrowIcon}
                            size={19}
                            color="currentColor"
                        />
                    </Stack>
                )}
            </Stack>
        </StyledMenuItem>
    );
};

const StyledMenu = styled(Menu)(({ theme }) => ({
    "& .MuiPaper-root": {
        backgroundColor: theme.vars.palette.background.elevatedPaper,
        minWidth: 220,
        width: 220,
        borderRadius: 12,
        boxShadow: theme.vars.palette.boxShadow.menu,
        marginTop: 6,
    },
    "& .MuiList-root": { padding: theme.spacing(1) },
}));

const StyledMenuItem = styled(MenuItem)(({ theme }) => ({
    display: "flex",
    alignItems: "center",
    gap: 12,
    padding: theme.spacing(1.5, 2),
    borderRadius: 8,
    color: theme.vars.palette.text.base,
    fontSize: 15,
    "&:hover": { backgroundColor: theme.vars.palette.fill.faintHover },
    "& .MuiListItemIcon-root": { minWidth: 0, color: "inherit" },
    "& .MuiListItemText-root": { margin: 0 },
    "& .MuiListItemText-primary": { color: "inherit", fontSize: "inherit" },
}));
