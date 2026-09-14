import { collectionDialogIconButtonSx as v2TriggerButtonSx } from "@/components/CollectionDialog/styles";
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
    type Theme,
} from "@mui/material";
import Menu, { type MenuProps } from "@mui/material/Menu";
import type { CollectionsSortBy } from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import React, { useRef, useState } from "react";

interface CollectionsSortOptionsProps {
    activeSortBy: CollectionsSortBy;
    onChangeSortBy: (by: CollectionsSortBy) => void;
    nestedInDialog?: boolean;
    transparentTriggerButtonBackground?: boolean;
    variant?: "default" | "v2";
}

type SortCategory = "name" | "creation-time" | "updation-time";

const getSortCategory = (sortBy: CollectionsSortBy): SortCategory => {
    if (sortBy.startsWith("name")) return "name";
    if (sortBy.startsWith("creation-time")) return "creation-time";
    return "updation-time";
};

const isAscending = (sortBy: CollectionsSortBy): boolean =>
    sortBy.endsWith("-asc");

const getSortBy = (
    category: SortCategory,
    ascending: boolean,
): CollectionsSortBy => `${category}-${ascending ? "asc" : "desc"}`;

export const CollectionsSortOptions: React.FC<CollectionsSortOptionsProps> = ({
    activeSortBy,
    onChangeSortBy,
    nestedInDialog,
    transparentTriggerButtonBackground,
    variant = "default",
}) => {
    const [anchorEl, setAnchorEl] = useState<MenuProps["anchorEl"]>();
    // Apply sort changes after the menu closes to avoid flicker.
    const pendingSortByRef = useRef<CollectionsSortBy | undefined>(undefined);
    const ariaID = "collection-sort";

    const activeCategory = getSortCategory(activeSortBy);
    const activeAscending = isAscending(activeSortBy);

    const handleCategoryClick = (category: SortCategory) => {
        let nextSortBy: CollectionsSortBy;
        if (category === activeCategory) {
            nextSortBy = getSortBy(category, !activeAscending);
        } else {
            // Names default to ascending; dates default to newest first.
            const defaultAscending = category === "name";
            nextSortBy = getSortBy(category, defaultAscending);
        }
        pendingSortByRef.current = nextSortBy;
        setAnchorEl(undefined);
    };

    const isV2 = variant === "v2";

    const triggerButtonSxProps: IconButtonProps["sx"] = isV2
        ? v2TriggerButtonSx
        : [
              transparentTriggerButtonBackground
                  ? {}
                  : { backgroundColor: "fill.faint" },
          ];

    const menuPaperSxProps: PaperProps["sx"] | undefined =
        !isV2 && nestedInDialog
            ? { backgroundColor: "background.paper2" }
            : undefined;

    return (
        <>
            <IconButton
                onClick={(event) => setAnchorEl(event.currentTarget)}
                aria-controls={anchorEl ? ariaID : undefined}
                aria-haspopup="true"
                aria-expanded={anchorEl ? "true" : undefined}
                aria-label={isV2 ? t("sort_by") : undefined}
                sx={triggerButtonSxProps}
            >
                <SortIcon sx={isV2 ? { fontSize: 20 } : undefined} />
            </IconButton>
            <StyledMenu
                id={ariaID}
                sx={isV2 ? v2MenuSx : undefined}
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
                <SortCategoryOption
                    category="name"
                    activeCategory={activeCategory}
                    activeAscending={activeAscending}
                    onClick={handleCategoryClick}
                    label={t("name")}
                    ascLabel={t("sort_asc_indicator")}
                    descLabel={t("sort_desc_indicator")}
                />
                <SortCategoryOption
                    category="creation-time"
                    activeCategory={activeCategory}
                    activeAscending={activeAscending}
                    onClick={handleCategoryClick}
                    label={t("created")}
                    ascLabel={t("oldest")}
                    descLabel={t("newest")}
                />
                <SortCategoryOption
                    category="updation-time"
                    activeCategory={activeCategory}
                    activeAscending={activeAscending}
                    onClick={handleCategoryClick}
                    label={t("updated")}
                    ascLabel={t("oldest")}
                    descLabel={t("newest")}
                />
            </StyledMenu>
        </>
    );
};

interface SortCategoryOptionProps {
    category: SortCategory;
    activeCategory: SortCategory;
    activeAscending: boolean;
    onClick: (category: SortCategory) => void;
    label: string;
    ascLabel: string;
    descLabel: string;
}

const SortCategoryOption: React.FC<SortCategoryOptionProps> = ({
    category,
    activeCategory,
    activeAscending,
    onClick,
    label,
    ascLabel,
    descLabel,
}) => {
    const isSelected = category === activeCategory;
    const directionLabel = activeAscending ? ascLabel : descLabel;
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
                        <Typography>•</Typography>
                        <Typography sx={{ fontSize: "0.9rem" }}>
                            {directionLabel}
                        </Typography>
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

const v2MenuSx = (theme: Theme) => ({
    "& .MuiPaper-root": {
        width: 238,
        minWidth: 238,
        border: "1px solid #ececec",
        borderRadius: "16px",
        backgroundColor: "background.paper",
        boxShadow: "0 4px 4px rgba(0 0 0 / 0.16)",
        ...theme.applyStyles("dark", {
            borderColor: "rgba(255 255 255 / 0.12)",
            backgroundColor: "#282828",
            boxShadow: "0 4px 4px rgba(0 0 0 / 0.40)",
        }),
    },
    "& .MuiMenuItem-root": {
        minHeight: 44,
        height: 44,
        boxSizing: "border-box",
        py: "12px",
        px: "16px",
    },
    "& .MuiTypography-root": {
        fontSize: 14,
        lineHeight: "20px",
        fontWeight: 500,
    },
});
