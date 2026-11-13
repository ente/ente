import { ItemCard } from "@/components/items/ItemCard";
import { lockerContentMaxWidth } from "@/styles/tokens";
import type { LockerItem } from "@/types";
import { canShareLockerFileLink, isLockerItemOwner } from "@/types";
import { Box, Stack } from "@mui/material";
import { t } from "i18next";
import React from "react";

export const ItemsSection: React.FC<{
    items: LockerItem[];
    isTrashView: boolean;
    onEditItem?: (item: LockerItem) => void;
    onDeleteItem?: (item: LockerItem) => void;
    onPermanentlyDelete?: (items: LockerItem[]) => void;
    onRequestRestore: (item: LockerItem) => void;
    onSelectItem: (item: LockerItem) => void;
    currentUserID?: number;
    onShareLink?: (item: LockerItem) => void;
    selectionMode?: boolean;
    selectedItemIDSet?: Set<number>;
    onToggleItemSelection?: (item: LockerItem) => void;
    onStartSelection?: (item: LockerItem) => void;
    emptyState: React.ReactNode;
}> = ({
    items,
    isTrashView,
    onEditItem,
    onDeleteItem,
    onPermanentlyDelete,
    onRequestRestore,
    onSelectItem,
    currentUserID,
    onShareLink,
    selectionMode,
    selectedItemIDSet,
    onToggleItemSelection,
    onStartSelection,
    emptyState,
}) =>
    items.length > 0 ? (
        <Stack
            sx={{ maxWidth: lockerContentMaxWidth, mx: "auto", gap: 1, mt: 0 }}
        >
            {items.map((item) => {
                const isOwnedByCurrentUser = isLockerItemOwner(
                    item,
                    currentUserID,
                );
                return (
                    <ItemCard
                        key={item.id}
                        item={item}
                        isTrashView={isTrashView}
                        isIncomingShared={!isOwnedByCurrentUser}
                        onClick={() => onSelectItem(item)}
                        onEdit={
                            onEditItem && isOwnedByCurrentUser
                                ? onEditItem
                                : undefined
                        }
                        onDelete={
                            onDeleteItem && isOwnedByCurrentUser
                                ? onDeleteItem
                                : undefined
                        }
                        deleteDisabledHint={
                            onDeleteItem &&
                            !isTrashView &&
                            !isOwnedByCurrentUser
                                ? t("actionNotSupportedForSharedFiles", {
                                      count: 1,
                                  })
                                : undefined
                        }
                        onPermanentlyDelete={onPermanentlyDelete}
                        onRestore={
                            isTrashView
                                ? (trashItem) => onRequestRestore(trashItem)
                                : undefined
                        }
                        onShareLink={
                            onShareLink &&
                            canShareLockerFileLink(item, currentUserID)
                                ? onShareLink
                                : undefined
                        }
                        selectionMode={selectionMode}
                        selectable
                        selected={selectedItemIDSet?.has(item.id)}
                        onToggleSelection={onToggleItemSelection}
                        onLongPressSelect={onStartSelection}
                    />
                );
            })}
        </Stack>
    ) : (
        <Box sx={{ maxWidth: lockerContentMaxWidth, mx: "auto" }}>
            {emptyState}
        </Box>
    );
