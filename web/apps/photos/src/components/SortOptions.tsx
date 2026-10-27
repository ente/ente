import { ArrowDown02Icon, ArrowUp02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import SortIcon from "@mui/icons-material/Sort";
import {
    IconButton,
    Stack,
    type IconButtonProps,
    type Theme,
} from "@mui/material";
import type { MenuProps } from "@mui/material/Menu";
import { ContextMenu, ContextMenuItem } from "ente-base/components/ContextMenu";
import { t } from "i18next";
import React, { useRef, useState } from "react";

export interface SortOptionsAppearanceProps {
    variant?: "default" | "v2";
    transparentTriggerButtonBackground?: boolean;
}

interface SortOption<Category extends string> {
    category: Category;
    label: string;
    defaultAscending: boolean;
    ascendingLabel?: string;
    descendingLabel?: string;
}

interface SortOptionsProps<
    Category extends string,
> extends SortOptionsAppearanceProps {
    id: string;
    activeCategory: Category;
    activeAscending: boolean;
    options: SortOption<Category>[];
    onChange: (category: Category, ascending: boolean) => void;
}

export function SortOptions<Category extends string>({
    id: ariaID,
    activeCategory,
    activeAscending,
    options,
    onChange,
    variant = "default",
    transparentTriggerButtonBackground,
}: SortOptionsProps<Category>) {
    const [anchorEl, setAnchorEl] = useState<MenuProps["anchorEl"]>();
    // Apply sort changes after the menu closes to avoid flicker.
    const pendingSortRef = useRef<
        { category: Category; ascending: boolean } | undefined
    >(undefined);

    const handleOptionClick = (option: SortOption<Category>) => {
        pendingSortRef.current = {
            category: option.category,
            ascending:
                option.category === activeCategory
                    ? !activeAscending
                    : option.defaultAscending,
        };
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
            <ContextMenu
                id={ariaID}
                {...(anchorEl && { anchorEl })}
                open={!!anchorEl}
                onClose={() => setAnchorEl(undefined)}
                slotProps={{
                    list: { "aria-labelledby": ariaID },
                    transition: {
                        onExited: () => {
                            const nextSort = pendingSortRef.current;
                            if (nextSort) {
                                pendingSortRef.current = undefined;
                                onChange(nextSort.category, nextSort.ascending);
                            }
                        },
                    },
                }}
                anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
                transformOrigin={{ vertical: "top", horizontal: "right" }}
            >
                {options.map((option) => (
                    <SortCategoryOption
                        key={option.category}
                        isSelected={option.category === activeCategory}
                        activeAscending={activeAscending}
                        onClick={() => handleOptionClick(option)}
                        label={option.label}
                        directionLabel={
                            activeAscending
                                ? option.ascendingLabel
                                : option.descendingLabel
                        }
                    />
                ))}
            </ContextMenu>
        </>
    );
}

interface SortCategoryOptionProps {
    isSelected: boolean;
    activeAscending: boolean;
    onClick: () => void;
    label: string;
    directionLabel?: string;
}

const SortCategoryOption: React.FC<SortCategoryOptionProps> = ({
    isSelected,
    activeAscending,
    onClick,
    label,
    directionLabel,
}) => {
    const arrowIcon = activeAscending ? ArrowUp02Icon : ArrowDown02Icon;

    return (
        <ContextMenuItem onClick={onClick}>
            {label}
            {isSelected && (
                <Stack
                    component="span"
                    direction="row"
                    sx={{
                        alignItems: "center",
                        gap: 0.75,
                        color: "text.muted",
                    }}
                >
                    {directionLabel && <span>•</span>}
                    {directionLabel && <span>{directionLabel}</span>}
                    <HugeiconsIcon
                        icon={arrowIcon}
                        size={19}
                        color="currentColor"
                    />
                </Stack>
            )}
        </ContextMenuItem>
    );
};

const v2TriggerButtonSx = (theme: Theme) => ({
    width: 38,
    height: 38,
    p: 0,
    color: "text.base",
    backgroundColor: "background.paper",
    "&:hover": { backgroundColor: "fill.faintHover" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
    }),
});
