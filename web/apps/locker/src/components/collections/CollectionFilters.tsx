import { LockerMenuFooter, LockerMenuOption } from "@/components/ui/LockerMenu";
import { lockerMenuPaperSx } from "@/styles/dialog";
import { lockerColorSx, lockerContentMaxWidth } from "@/styles/tokens";
import type { LockerCollection } from "@/types";
import FilterListRoundedIcon from "@mui/icons-material/FilterListRounded";
import { Box, ButtonBase, Menu, Stack, Tooltip } from "@mui/material";
import { t } from "i18next";
import React, { useCallback, useState } from "react";
import { CollectionChipFilters } from "./CollectionChipFilters";

interface CollectionFiltersProps {
    showFilters: boolean;
    orderedHomeCollections: LockerCollection[];
    dropdownHomeCollections: LockerCollection[];
    homeSelectedCollectionIDs: number[];
    toggleHomeCollection: (collectionID: number) => void;
    clearHomeCollectionSelection: () => void;
}
export function CollectionFilters({
    showFilters,
    orderedHomeCollections,
    dropdownHomeCollections,
    homeSelectedCollectionIDs,
    toggleHomeCollection,
    clearHomeCollectionSelection,
}: CollectionFiltersProps) {
    const [collectionFilterAnchorEl, setCollectionFilterAnchorEl] =
        useState<HTMLElement | null>(null);
    const openCollectionFilterMenu = useCallback(
        (event: React.MouseEvent<HTMLElement>) => {
            setCollectionFilterAnchorEl(event.currentTarget);
        },
        [],
    );
    const closeCollectionFilterMenu = useCallback(() => {
        setCollectionFilterAnchorEl(null);
    }, []);
    return (
        <>
            {showFilters && (
                <Stack
                    direction="row"
                    sx={{
                        width: "100%",
                        maxWidth: lockerContentMaxWidth,
                        mx: "auto",
                        alignItems: "center",
                        gap: 1,
                        mb: 2,
                        minWidth: 0,
                    }}
                >
                    <CollectionFilterChip
                        selected={homeSelectedCollectionIDs.length > 0}
                        onClick={openCollectionFilterMenu}
                    />
                    <Box
                        key={orderedHomeCollections
                            .map((collection) => collection.id)
                            .join("-")}
                        sx={{
                            flex: 1,
                            minWidth: 0,
                            "@keyframes chipBarRefresh": {
                                "0%": {
                                    opacity: 0.7,
                                    transform: "translateY(2px)",
                                },
                                "100%": {
                                    opacity: 1,
                                    transform: "translateY(0)",
                                },
                            },
                            animation: "chipBarRefresh 220ms ease-out",
                        }}
                    >
                        <CollectionChipFilters
                            collections={orderedHomeCollections}
                            selectedCollectionIDs={homeSelectedCollectionIDs}
                            onToggleCollection={toggleHomeCollection}
                        />
                    </Box>
                </Stack>
            )}
            <Menu
                anchorEl={collectionFilterAnchorEl}
                open={!!collectionFilterAnchorEl}
                onClose={closeCollectionFilterMenu}
                slotProps={{
                    paper: { sx: [lockerMenuPaperSx, { mt: 1 }] },
                    list: { disablePadding: true },
                }}
            >
                {dropdownHomeCollections.map((collection) => {
                    const isSelected = homeSelectedCollectionIDs.includes(
                        collection.id,
                    );
                    return (
                        <LockerMenuOption
                            key={collection.id}
                            onClick={() => toggleHomeCollection(collection.id)}
                            selected={isSelected}
                            secondary={new Intl.NumberFormat().format(
                                collection.items.length,
                            )}
                        >
                            {collection.name}
                        </LockerMenuOption>
                    );
                })}
                {homeSelectedCollectionIDs.length > 0 && (
                    <LockerMenuFooter
                        onClick={() => {
                            clearHomeCollectionSelection();
                            closeCollectionFilterMenu();
                        }}
                    >
                        {t("clearSelection")}
                    </LockerMenuFooter>
                )}
            </Menu>
        </>
    );
}
const CollectionFilterChip: React.FC<{
    selected: boolean;
    onClick: (event: React.MouseEvent<HTMLElement>) => void;
}> = ({ selected, onClick }) => (
    <Tooltip title={t("seeAllCollections")}>
        <ButtonBase
            onClick={onClick}
            sx={(theme) => ({
                width: 36,
                height: 36,
                borderRadius: "12px",
                flexShrink: 0,
                padding: 0,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                ...lockerColorSx(theme, {
                    backgroundColor: selected ? "primary" : "fillLight",
                    color: selected ? "specialWhite" : "iconColor",
                }),
                "&:hover": {
                    ...lockerColorSx(theme, {
                        backgroundColor: selected ? "primary" : "fillHover",
                    }),
                },
            })}
        >
            <FilterListRoundedIcon sx={{ fontSize: 18 }} />
        </ButtonBase>
    </Tooltip>
);
