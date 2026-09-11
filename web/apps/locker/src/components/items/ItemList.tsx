import { CollectionFilters } from "@/components/collections/CollectionFilters";
import { CollectionGrid } from "@/components/collections/CollectionGrid";
import { CollectionHeaderMenu } from "@/components/collections/CollectionHeaderMenu";
import { CreateCollectionDialog } from "@/components/collections/CreateCollectionDialog";
import { RenameCollectionDialog } from "@/components/collections/RenameCollectionDialog";
import { ItemDetailView } from "@/components/items/ItemDetailView";
import { ItemsSection } from "@/components/items/ItemsSection";
import { LockerFileLinkDialog } from "@/components/items/LockerFileLinkDialog";
import { RestoreItemDialog } from "@/components/items/RestoreItemDialog";
import { SelectionActionBar } from "@/components/items/SelectionActionBar";
import { LockerConfirmDialog } from "@/components/ui/LockerConfirmDialog";
import { downloadLockerFile } from "@/services/download";
import {
    lockerColorSx,
    lockerContentMaxWidth,
    lockerTextDisplay2Sx,
    lockerTextLargeSx,
    lockerTextMiniSx,
} from "@/styles/tokens";
import type { LockerCollection, LockerItem } from "@/types";
import {
    canEditCollection,
    canLeaveCollection,
    canOpenCollectionSharing,
    canShareLockerFileLink,
    getItemTitle,
    isLockerItemOwner,
    restoreTargetLockerCollections,
    sortLockerCollections,
} from "@/types";
import { Delete02Icon, PlusSignIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArrowBackRoundedIcon from "@mui/icons-material/ArrowBackRounded";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import {
    Box,
    IconButton,
    Snackbar,
    Stack,
    Tooltip,
    Typography,
} from "@mui/material";
import { savedLocalUser } from "ente-accounts/services/accounts-db";
import log from "ente-base/log";
import { t } from "i18next";
import React, { useCallback, useEffect, useMemo, useState } from "react";
import { useFileLink } from "./use-file-link";
import { useItemSelection } from "./use-item-selection";

const uniqueCollectionsByID = (collections: LockerCollection[]) => {
    const seen = new Set<number>();
    return collections.filter((collection) => {
        if (seen.has(collection.id)) {
            return false;
        }
        seen.add(collection.id);
        return true;
    });
};

interface ItemListProps {
    collections: LockerCollection[];
    trashItems?: LockerItem[];
    isTrashView: boolean;
    isCollectionsView: boolean;
    selectedCollectionID: number | null;
    onSelectCollection: (id: number | null) => void;
    onEditItem?: (item: LockerItem) => void;
    onDeleteItem?: (item: LockerItem) => void;
    onDeleteItems?: (items: LockerItem[]) => void;
    onPermanentlyDelete?: (items: LockerItem[]) => void;
    onRestoreItem?: (
        item: LockerItem,
        collectionID: number,
    ) => void | Promise<void>;
    onEmptyTrash?: () => void;
    onRenameCollection?: (
        collectionID: number,
        newName: string,
    ) => void | Promise<void>;
    onDeleteCollection?: (collectionID: number) => void;
    onCreateCollection?: (name: string) => Promise<number>;
    onShareCollection?: (collection: LockerCollection) => void;
    onLeaveCollection?: (collection: LockerCollection) => void;
    searchTerm: string;
    onNavigateBack?: () => void;
}

export const ItemList: React.FC<ItemListProps> = ({
    collections,
    trashItems,
    isTrashView,
    isCollectionsView,
    selectedCollectionID,
    onSelectCollection,
    onEditItem,
    onDeleteItem,
    onDeleteItems,
    onPermanentlyDelete,
    onRestoreItem,
    onEmptyTrash,
    onRenameCollection,
    onDeleteCollection,
    onCreateCollection,
    onShareCollection,
    onLeaveCollection,
    searchTerm,
    onNavigateBack,
}) => {
    const currentUserID = savedLocalUser()?.id;
    const [selectedItemID, setSelectedItemID] = useState<number | null>(null);
    const [restoreItemID, setRestoreItemID] = useState<number | null>(null);
    const [renameCollection, setRenameCollection] =
        useState<LockerCollection | null>(null);
    const [createCollectionOpen, setCreateCollectionOpen] = useState(false);
    const [homeSelectedCollectionIDs, setHomeSelectedCollectionIDs] = useState<
        number[]
    >([]);
    const [bulkDownloading, setBulkDownloading] = useState(false);
    const [bulkDownloadProgress, setBulkDownloadProgress] = useState<{
        completed: number;
        total: number;
    } | null>(null);
    const [feedbackMessage, setFeedbackMessage] = useState<string | null>(null);

    const displayCollections = useMemo(
        () => uniqueCollectionsByID(sortLockerCollections(collections)),
        [collections],
    );
    const restoreCollections = useMemo(
        () =>
            uniqueCollectionsByID(
                restoreTargetLockerCollections(collections, currentUserID),
            ),
        [collections, currentUserID],
    );
    const allItems = useMemo(() => {
        const itemsByID = new Map<number, LockerItem>();
        for (const collection of collections) {
            for (const item of collection.items) {
                const existing = itemsByID.get(item.id);
                if (!existing) {
                    itemsByID.set(item.id, item);
                    continue;
                }

                itemsByID.set(item.id, {
                    ...existing,
                    ownerID: existing.ownerID ?? item.ownerID,
                    collectionIDs: Array.from(
                        new Set([
                            ...existing.collectionIDs,
                            ...item.collectionIDs,
                        ]),
                    ),
                });
            }
        }
        return [...itemsByID.values()];
    }, [collections]);
    const allItemsByID = useMemo(
        () => new Map(allItems.map((item) => [item.id, item])),
        [allItems],
    );
    const trashItemsByID = useMemo(
        () => new Map((trashItems ?? []).map((item) => [item.id, item])),
        [trashItems],
    );
    const selectedCollection = useMemo(
        () =>
            selectedCollectionID === null
                ? null
                : (collections.find(
                      (collection) => collection.id === selectedCollectionID,
                  ) ?? null),
        [collections, selectedCollectionID],
    );
    const selectedItem = useMemo(() => {
        if (selectedItemID === null) {
            return null;
        }

        return (
            allItemsByID.get(selectedItemID) ??
            trashItemsByID.get(selectedItemID) ??
            null
        );
    }, [allItemsByID, selectedItemID, trashItemsByID]);
    const selectedItemCollectionNames = useMemo(
        () =>
            (isTrashView ? [] : (selectedItem?.collectionIDs ?? [])).flatMap(
                (id) => {
                    const collection = collections.find(
                        (collection) => collection.id === id,
                    );
                    return collection ? [collection.name] : [];
                },
            ),
        [collections, isTrashView, selectedItem],
    );
    const restoreItem = useMemo(
        () =>
            restoreItemID === null
                ? null
                : (trashItemsByID.get(restoreItemID) ?? null),
        [restoreItemID, trashItemsByID],
    );
    const {
        activeFileLinkItem,
        activeFileLink,
        canNativeShare,
        isCreatingFileLink,
        isDeletingFileLink,
        isDeleteFileLinkConfirmOpen,
        setIsDeleteFileLinkConfirmOpen,
        closeFileLinkDialog,
        openFileLinkDialog,
        copyActiveFileLink,
        shareActiveFileLink,
        deleteActiveFileLink,
    } = useFileLink({ allItemsByID, currentUserID, setFeedbackMessage });
    const trimmedSearch = searchTerm.trim();
    const searchQuery = trimmedSearch.toLowerCase();
    const searchActive = searchQuery.length > 0;
    const isHomeView =
        !searchActive &&
        !isTrashView &&
        !isCollectionsView &&
        selectedCollectionID === null;

    const searchBaseItems = useMemo(() => {
        if (isTrashView) {
            return trashItems ?? [];
        }
        if (selectedCollection) {
            return selectedCollection.items;
        }
        return allItems;
    }, [allItems, isTrashView, selectedCollection, trashItems]);

    const filteredItems = useMemo(() => {
        if (!searchActive) {
            return searchBaseItems;
        }

        return searchBaseItems.filter((item) => {
            if (getItemTitle(item).toLowerCase().includes(searchQuery)) {
                return true;
            }

            return Object.values(
                item.data as unknown as Record<string, unknown>,
            ).some(
                (value) =>
                    typeof value === "string" &&
                    value.toLowerCase().includes(searchQuery),
            );
        });
    }, [searchActive, searchBaseItems, searchQuery]);

    const filteredCollections = useMemo(() => {
        if (!searchActive || isTrashView) {
            return [];
        }

        return displayCollections.filter((collection) =>
            collection.name.toLowerCase().includes(searchQuery),
        );
    }, [displayCollections, isTrashView, searchActive, searchQuery]);

    const sortedItems = useMemo(
        () =>
            [...filteredItems].sort(
                (a, b) =>
                    (b.updatedAt ?? b.createdAt ?? 0) -
                    (a.updatedAt ?? a.createdAt ?? 0),
            ),
        [filteredItems],
    );
    const homeFilteredItems = useMemo(() => {
        if (!isHomeView || homeSelectedCollectionIDs.length === 0) {
            return sortedItems;
        }

        return sortedItems.filter((item) =>
            homeSelectedCollectionIDs.every((collectionID) =>
                item.collectionIDs.includes(collectionID),
            ),
        );
    }, [homeSelectedCollectionIDs, isHomeView, sortedItems]);
    const orderedHomeCollections = useMemo(() => {
        if (!isHomeView || homeSelectedCollectionIDs.length === 0) {
            return displayCollections;
        }

        const selectedCollectionIDSet = new Set(homeSelectedCollectionIDs);
        const availableCollectionIDs = new Set<number>();
        for (const item of homeFilteredItems) {
            for (const collectionID of item.collectionIDs) {
                availableCollectionIDs.add(collectionID);
            }
        }
        for (const collectionID of homeSelectedCollectionIDs) {
            availableCollectionIDs.add(collectionID);
        }

        const selectedCollections = displayCollections.filter((collection) =>
            selectedCollectionIDSet.has(collection.id),
        );
        const remainingCollections = displayCollections.filter(
            (collection) =>
                availableCollectionIDs.has(collection.id) &&
                !selectedCollectionIDSet.has(collection.id),
        );

        return [...selectedCollections, ...remainingCollections];
    }, [
        displayCollections,
        homeFilteredItems,
        homeSelectedCollectionIDs,
        isHomeView,
    ]);
    const dropdownHomeCollections = useMemo(
        () => displayCollections,
        [displayCollections],
    );
    const visibleItems = useMemo(() => {
        if (isCollectionsView) {
            return [];
        }
        return isHomeView ? homeFilteredItems : sortedItems;
    }, [homeFilteredItems, isCollectionsView, isHomeView, sortedItems]);
    const closeItemDetail = useCallback(() => setSelectedItemID(null), []);
    const clearBulkDownloadProgress = useCallback(
        () => setBulkDownloadProgress(null),
        [],
    );
    const {
        selectionMode,
        selectedItemIDSet,
        selectedVisibleItems,
        selectedDownloadableItems,
        selectedOwnedItems,
        canBulkSelectVisibleItems,
        skippedSharedSelectionCount,
        skippedDownloadSelectionCount,
        allVisibleItemsSelected,
        startSelectionModeForItem,
        stopSelectionMode,
        toggleItemSelection,
        toggleSelectAllVisibleItems,
    } = useItemSelection({
        visibleItems,
        currentUserID,
        isTrashView,
        isCollectionsView,
        onStartSelection: closeItemDetail,
        onStopSelection: clearBulkDownloadProgress,
    });
    useEffect(() => {
        if (selectedItemID !== null && !selectedItem) {
            setSelectedItemID(null);
        }
    }, [selectedItem, selectedItemID]);

    useEffect(() => {
        if (restoreItemID !== null && !restoreItem) {
            setRestoreItemID(null);
        }
    }, [restoreItem, restoreItemID]);

    const canEditSelectedCollection =
        selectedCollection !== null &&
        currentUserID !== undefined &&
        canEditCollection(selectedCollection, currentUserID);
    const canLeaveSelectedCollection =
        selectedCollection !== null &&
        currentUserID !== undefined &&
        canLeaveCollection(selectedCollection, currentUserID);
    const canShareSelectedCollection =
        selectedCollection !== null &&
        canOpenCollectionSharing(selectedCollection);
    const handleShareSelectedCollection = useCallback(() => {
        if (selectedCollection && onShareCollection) {
            onShareCollection(selectedCollection);
        }
    }, [onShareCollection, selectedCollection]);
    const toggleHomeCollection = useCallback((collectionID: number) => {
        setHomeSelectedCollectionIDs((current) =>
            current.includes(collectionID)
                ? current.filter((id) => id !== collectionID)
                : [...current, collectionID],
        );
    }, []);
    const clearHomeCollectionSelection = useCallback(() => {
        setHomeSelectedCollectionIDs([]);
    }, []);
    const downloadSelectedFiles = useCallback(async () => {
        if (bulkDownloading || selectedDownloadableItems.length === 0) {
            return;
        }

        setBulkDownloading(true);
        setBulkDownloadProgress({
            completed: 0,
            total: selectedDownloadableItems.length,
        });
        try {
            for (const [index, item] of selectedDownloadableItems.entries()) {
                await downloadLockerFile(item.id, getItemTitle(item));
                setBulkDownloadProgress({
                    completed: index + 1,
                    total: selectedDownloadableItems.length,
                });
            }
            if (skippedDownloadSelectionCount > 0) {
                setFeedbackMessage(
                    t("downloadSkippedUnavailableFiles", {
                        count: skippedDownloadSelectionCount,
                    }),
                );
            }
            stopSelectionMode();
        } catch (error) {
            log.error("Failed to download selected Locker files", error);
            setFeedbackMessage(t("downloadFailed"));
        } finally {
            setBulkDownloading(false);
            setBulkDownloadProgress(null);
        }
    }, [
        bulkDownloading,
        selectedDownloadableItems,
        skippedDownloadSelectionCount,
        stopSelectionMode,
    ]);
    const deleteSelectedFiles = useCallback(() => {
        if (selectedOwnedItems.length === 0) {
            if (skippedSharedSelectionCount > 0) {
                setFeedbackMessage(
                    t("actionNotSupportedForSharedFiles", {
                        count: skippedSharedSelectionCount,
                    }),
                );
            }
            return;
        }

        if (skippedSharedSelectionCount > 0) {
            setFeedbackMessage(
                t("actionNotSupportedForSharedFiles", {
                    count: skippedSharedSelectionCount,
                }),
            );
        }

        onDeleteItems?.(selectedOwnedItems);
        stopSelectionMode();
    }, [
        onDeleteItems,
        selectedOwnedItems,
        skippedSharedSelectionCount,
        stopSelectionMode,
    ]);

    React.useEffect(() => {
        if (!isHomeView && homeSelectedCollectionIDs.length > 0) {
            setHomeSelectedCollectionIDs([]);
        }
    }, [homeSelectedCollectionIDs.length, isHomeView]);
    return (
        <Stack
            sx={{ flex: 1, minHeight: 0, overflow: "hidden", height: "100%" }}
        >
            <Box
                sx={(theme) => ({
                    flex: 1,
                    minHeight: 0,
                    overflowY: "auto",
                    overscrollBehavior: "contain",
                    WebkitOverflowScrolling: "touch",
                    scrollbarWidth: "thin",
                    scrollbarColor: `${theme.vars.palette.fill.muted} transparent`,
                    "&::-webkit-scrollbar": { width: 6 },
                    "&::-webkit-scrollbar-track": { background: "transparent" },
                    "&::-webkit-scrollbar-thumb": {
                        borderRadius: "999px",
                        backgroundColor: theme.vars.palette.fill.muted,
                    },
                    "&::-webkit-scrollbar-thumb:hover": {
                        backgroundColor: theme.vars.palette.stroke.muted,
                    },
                    ...lockerColorSx(theme, {
                        backgroundColor: "backgroundBase",
                    }),
                })}
            >
                <Box
                    sx={(theme) => ({
                        px: 2,
                        pt: 2,
                        pb: isTrashView
                            ? 3
                            : "calc(env(safe-area-inset-bottom) + 120px)",
                        ...lockerColorSx(theme, {
                            backgroundColor: "backgroundBase",
                        }),
                    })}
                >
                    <CollectionFilters
                        showFilters={
                            isHomeView && displayCollections.length > 0
                        }
                        orderedHomeCollections={orderedHomeCollections}
                        dropdownHomeCollections={dropdownHomeCollections}
                        homeSelectedCollectionIDs={homeSelectedCollectionIDs}
                        toggleHomeCollection={toggleHomeCollection}
                        clearHomeCollectionSelection={
                            clearHomeCollectionSelection
                        }
                    />
                    {isHomeView && (
                        <>
                            <ItemsSection
                                items={homeFilteredItems}
                                isTrashView={false}
                                onEditItem={onEditItem}
                                onDeleteItem={onDeleteItem}
                                onPermanentlyDelete={onPermanentlyDelete}
                                onRequestRestore={(item) => {
                                    setRestoreItemID(item.id);
                                }}
                                onSelectItem={(item) =>
                                    setSelectedItemID(item.id)
                                }
                                currentUserID={currentUserID}
                                onShareLink={openFileLinkDialog}
                                selectionMode={selectionMode}
                                selectedItemIDSet={selectedItemIDSet}
                                onToggleItemSelection={toggleItemSelection}
                                onStartSelection={
                                    canBulkSelectVisibleItems
                                        ? startSelectionModeForItem
                                        : undefined
                                }
                                emptyState={
                                    <EmptyState
                                        title={
                                            homeSelectedCollectionIDs.length > 0
                                                ? t("noResults")
                                                : t("homeLockerEmptyTitle")
                                        }
                                        subtitle={
                                            homeSelectedCollectionIDs.length > 0
                                                ? t(
                                                      "noItemsMatchSelectedFilters",
                                                  )
                                                : t("homeLockerEmptySubtitle")
                                        }
                                    />
                                }
                            />
                        </>
                    )}

                    {!isHomeView && isCollectionsView && !searchActive && (
                        <>
                            <SectionHeader
                                title={t("collections")}
                                countLabel={t("lockerCollectionsCount", {
                                    count: displayCollections.length,
                                })}
                                onBack={onNavigateBack}
                                action={
                                    onCreateCollection ? (
                                        <Tooltip
                                            title={t("createCollectionButton")}
                                        >
                                            <IconButton
                                                aria-label={t(
                                                    "createCollectionButton",
                                                )}
                                                onClick={() => {
                                                    setCreateCollectionOpen(
                                                        true,
                                                    );
                                                }}
                                                sx={(theme) => ({
                                                    width: 36,
                                                    height: 36,
                                                    borderRadius: "12px",
                                                    padding: 0,
                                                    ...lockerColorSx(theme, {
                                                        backgroundColor:
                                                            "fillLight",
                                                        color: "iconColor",
                                                    }),
                                                    "&:hover": {
                                                        ...lockerColorSx(
                                                            theme,
                                                            {
                                                                backgroundColor:
                                                                    "fillDark",
                                                            },
                                                        ),
                                                    },
                                                })}
                                            >
                                                <HugeiconsIcon
                                                    icon={PlusSignIcon}
                                                    size={18}
                                                    strokeWidth={1.5}
                                                />
                                            </IconButton>
                                        </Tooltip>
                                    ) : undefined
                                }
                            />

                            {displayCollections.length > 0 ? (
                                <Box sx={{ mt: 1.25 }}>
                                    <CollectionGrid
                                        collections={displayCollections}
                                        onSelectCollection={onSelectCollection}
                                        onShareCollection={onShareCollection}
                                        onLeaveCollection={onLeaveCollection}
                                        onRequestRenameCollection={(
                                            collection,
                                        ) => {
                                            setRenameCollection(collection);
                                        }}
                                        onDeleteCollection={onDeleteCollection}
                                    />
                                </Box>
                            ) : (
                                <EmptyState
                                    image={{ src: "/images/empty_state.png" }}
                                    title={t("noCollections")}
                                />
                            )}
                        </>
                    )}

                    {!isHomeView && searchActive && (
                        <>
                            {filteredCollections.length > 0 && (
                                <>
                                    <SectionHeader
                                        title={t("collections")}
                                        countLabel={t(
                                            "lockerCollectionsCount",
                                            {
                                                count: filteredCollections.length,
                                            },
                                        )}
                                    />
                                    <CollectionGrid
                                        collections={filteredCollections}
                                        onSelectCollection={onSelectCollection}
                                        onShareCollection={onShareCollection}
                                        onLeaveCollection={onLeaveCollection}
                                        onRequestRenameCollection={(
                                            collection,
                                        ) => {
                                            setRenameCollection(collection);
                                        }}
                                        onDeleteCollection={onDeleteCollection}
                                    />
                                </>
                            )}

                            <SectionHeader
                                title={t("results")}
                                countLabel={t("lockerItemsCount", {
                                    count: sortedItems.length,
                                })}
                            />

                            <ItemsSection
                                items={sortedItems}
                                isTrashView={isTrashView}
                                onEditItem={onEditItem}
                                onDeleteItem={onDeleteItem}
                                onPermanentlyDelete={onPermanentlyDelete}
                                onRequestRestore={(item) => {
                                    setRestoreItemID(item.id);
                                }}
                                onSelectItem={(item) =>
                                    setSelectedItemID(item.id)
                                }
                                currentUserID={currentUserID}
                                onShareLink={openFileLinkDialog}
                                selectionMode={selectionMode}
                                selectedItemIDSet={selectedItemIDSet}
                                onToggleItemSelection={toggleItemSelection}
                                onStartSelection={
                                    canBulkSelectVisibleItems
                                        ? startSelectionModeForItem
                                        : undefined
                                }
                                emptyState={
                                    <EmptyState
                                        title={t("searchEmptyTitle")}
                                        subtitle={t("searchEverywhereEmpty")}
                                    />
                                }
                            />
                        </>
                    )}

                    {!isHomeView && !isCollectionsView && !searchActive && (
                        <>
                            <SectionHeader
                                title={
                                    isTrashView
                                        ? t("trash")
                                        : (selectedCollection?.name ??
                                          t("allItems"))
                                }
                                countLabel={
                                    isTrashView && sortedItems.length === 0
                                        ? undefined
                                        : t("lockerItemsCount", {
                                              count: sortedItems.length,
                                          })
                                }
                                onBack={onNavigateBack}
                                action={
                                    <Stack
                                        direction="row"
                                        sx={{ alignItems: "center", gap: 1 }}
                                    >
                                        {isTrashView &&
                                            sortedItems.length > 0 &&
                                            onEmptyTrash && (
                                                <Tooltip
                                                    title={t("empty_trash")}
                                                >
                                                    <IconButton
                                                        aria-label={t(
                                                            "empty_trash",
                                                        )}
                                                        onClick={onEmptyTrash}
                                                        sx={(theme) => ({
                                                            width: 36,
                                                            height: 36,
                                                            borderRadius:
                                                                "12px",
                                                            padding: 0,
                                                            ...lockerColorSx(
                                                                theme,
                                                                {
                                                                    backgroundColor:
                                                                        "fillLight",
                                                                    color: "warning",
                                                                },
                                                            ),
                                                            "&:hover": {
                                                                ...lockerColorSx(
                                                                    theme,
                                                                    {
                                                                        backgroundColor:
                                                                            "fillDark",
                                                                    },
                                                                ),
                                                            },
                                                        })}
                                                    >
                                                        <HugeiconsIcon
                                                            icon={Delete02Icon}
                                                            size={18}
                                                            strokeWidth={1.5}
                                                        />
                                                    </IconButton>
                                                </Tooltip>
                                            )}
                                        {selectedCollection &&
                                            canShareSelectedCollection &&
                                            onShareCollection && (
                                                <Tooltip
                                                    title={t("sharedWith")}
                                                >
                                                    <IconButton
                                                        color="secondary"
                                                        onClick={() =>
                                                            onShareCollection(
                                                                selectedCollection,
                                                            )
                                                        }
                                                        sx={{
                                                            color: "text.muted",
                                                        }}
                                                    >
                                                        <ShareOutlinedIcon />
                                                    </IconButton>
                                                </Tooltip>
                                            )}
                                        {(canEditSelectedCollection ||
                                            canLeaveSelectedCollection) && (
                                            <CollectionHeaderMenu
                                                onShare={
                                                    canShareSelectedCollection &&
                                                    onShareCollection
                                                        ? handleShareSelectedCollection
                                                        : undefined
                                                }
                                                onRename={
                                                    canEditSelectedCollection &&
                                                    onRenameCollection
                                                        ? () => {
                                                              setRenameCollection(
                                                                  selectedCollection,
                                                              );
                                                          }
                                                        : undefined
                                                }
                                                onDelete={
                                                    canEditSelectedCollection &&
                                                    onDeleteCollection
                                                        ? () =>
                                                              onDeleteCollection(
                                                                  selectedCollection.id,
                                                              )
                                                        : undefined
                                                }
                                                onLeave={
                                                    onLeaveCollection &&
                                                    canLeaveSelectedCollection
                                                        ? () =>
                                                              onLeaveCollection(
                                                                  selectedCollection,
                                                              )
                                                        : undefined
                                                }
                                            />
                                        )}
                                    </Stack>
                                }
                            />

                            <ItemsSection
                                items={sortedItems}
                                isTrashView={isTrashView}
                                onEditItem={onEditItem}
                                onDeleteItem={onDeleteItem}
                                onPermanentlyDelete={onPermanentlyDelete}
                                onRequestRestore={(item) => {
                                    setRestoreItemID(item.id);
                                }}
                                onSelectItem={(item) =>
                                    setSelectedItemID(item.id)
                                }
                                currentUserID={currentUserID}
                                onShareLink={
                                    isTrashView ? undefined : openFileLinkDialog
                                }
                                selectionMode={selectionMode}
                                selectedItemIDSet={selectedItemIDSet}
                                onToggleItemSelection={toggleItemSelection}
                                onStartSelection={
                                    canBulkSelectVisibleItems
                                        ? startSelectionModeForItem
                                        : undefined
                                }
                                emptyState={
                                    isTrashView ? (
                                        <EmptyState
                                            image={{
                                                src: "/images/empty_state.png",
                                            }}
                                            title={t("yourTrashIsEmpty")}
                                        />
                                    ) : (
                                        <EmptyState
                                            title={t(
                                                "collectionEmptyStateTitle",
                                            )}
                                            subtitle={t(
                                                "collectionEmptyStateSubtitle",
                                            )}
                                        />
                                    )
                                }
                            />
                        </>
                    )}
                </Box>
            </Box>

            {selectionMode && canBulkSelectVisibleItems && (
                <SelectionActionBar
                    selectedCount={selectedVisibleItems.length}
                    allSelected={allVisibleItemsSelected}
                    bulkDownloading={bulkDownloading}
                    bulkDownloadProgress={bulkDownloadProgress}
                    canDownload={selectedDownloadableItems.length > 0}
                    canDelete={
                        !!onDeleteItems && selectedVisibleItems.length > 0
                    }
                    onToggleSelectAll={toggleSelectAllVisibleItems}
                    onDownload={downloadSelectedFiles}
                    onDelete={deleteSelectedFiles}
                    onDone={stopSelectionMode}
                />
            )}

            <ItemDetailView
                item={selectedItem}
                collectionNames={selectedItemCollectionNames}
                onClose={() => setSelectedItemID(null)}
                onEdit={
                    onEditItem &&
                    !isTrashView &&
                    selectedItem &&
                    isLockerItemOwner(selectedItem, currentUserID)
                        ? (item) => {
                              setSelectedItemID(null);
                              onEditItem(item);
                          }
                        : undefined
                }
                onDelete={
                    onDeleteItem &&
                    !isTrashView &&
                    selectedItem &&
                    isLockerItemOwner(selectedItem, currentUserID)
                        ? (item) => {
                              setSelectedItemID(null);
                              onDeleteItem(item);
                          }
                        : undefined
                }
                onDeleteDisabledHint={
                    !isTrashView &&
                    selectedItem &&
                    !isLockerItemOwner(selectedItem, currentUserID)
                        ? t("actionNotSupportedForSharedFiles", { count: 1 })
                        : undefined
                }
                isTrashView={isTrashView}
                onShareLink={
                    !isTrashView &&
                    selectedItem &&
                    canShareLockerFileLink(selectedItem, currentUserID)
                        ? openFileLinkDialog
                        : undefined
                }
            />

            <LockerFileLinkDialog
                open={activeFileLinkItem !== null}
                itemTitle={
                    activeFileLinkItem ? getItemTitle(activeFileLinkItem) : ""
                }
                url={activeFileLink?.url}
                loading={isCreatingFileLink}
                deleting={isDeletingFileLink}
                showShareAction={canNativeShare}
                onClose={closeFileLinkDialog}
                onCopy={() => void copyActiveFileLink()}
                onShare={() => void shareActiveFileLink()}
                onDelete={() => setIsDeleteFileLinkConfirmOpen(true)}
            />

            <LockerConfirmDialog
                open={isDeleteFileLinkConfirmOpen}
                illustration="/images/file_delete_icon.png"
                title={t("deleteShareLinkDialogTitle")}
                body={t("deleteShareLinkConfirmation")}
                confirmLabel={t("delete")}
                loading={isDeletingFileLink}
                onClose={() => {
                    if (!isDeletingFileLink) {
                        setIsDeleteFileLinkConfirmOpen(false);
                    }
                }}
                onConfirm={() => void deleteActiveFileLink()}
            />

            <RestoreItemDialog
                restoreItem={restoreItem}
                restoreCollections={restoreCollections}
                onClose={() => setRestoreItemID(null)}
                onRestoreItem={onRestoreItem}
            />
            <RenameCollectionDialog
                collection={renameCollection}
                onClose={() => setRenameCollection(null)}
                onRenameCollection={onRenameCollection}
            />
            <CreateCollectionDialog
                open={createCollectionOpen}
                onClose={() => setCreateCollectionOpen(false)}
                onCreateCollection={onCreateCollection}
                onSelectCollection={onSelectCollection}
            />
            <Snackbar
                open={feedbackMessage !== null}
                message={feedbackMessage}
                autoHideDuration={2500}
                onClose={() => setFeedbackMessage(null)}
            />
        </Stack>
    );
};

const SectionHeader: React.FC<{
    title: string;
    countLabel?: string;
    action?: React.ReactNode;
    onBack?: () => void;
}> = ({ title, countLabel, action, onBack }) =>
    onBack ? (
        <Stack
            sx={{
                gap: 2,
                maxWidth: lockerContentMaxWidth,
                mx: "auto",
                mt: 1,
                mb: 2.25,
            }}
        >
            <IconButton
                aria-label="Back"
                onClick={onBack}
                sx={(theme) => ({
                    alignSelf: "flex-start",
                    width: 36,
                    height: 36,
                    flexShrink: 0,
                    borderRadius: "12px",
                    padding: 0,
                    ...lockerColorSx(theme, {
                        color: "iconColor",
                        backgroundColor: "fillLight",
                    }),
                    "&:hover": {
                        ...lockerColorSx(theme, {
                            backgroundColor: "fillHover",
                        }),
                    },
                })}
            >
                <ArrowBackRoundedIcon sx={{ fontSize: 18 }} />
            </IconButton>
            <Stack
                direction="row"
                sx={{
                    alignItems: "center",
                    justifyContent: "space-between",
                    gap: 2,
                }}
            >
                <Box sx={{ minWidth: 0 }}>
                    <Typography sx={{ ...lockerTextDisplay2Sx, minWidth: 0 }}>
                        {title}
                    </Typography>
                    {countLabel && (
                        <Typography
                            sx={(theme) => ({
                                ...lockerTextMiniSx,
                                mt: 1,
                                ...lockerColorSx(theme, { color: "textLight" }),
                            })}
                        >
                            {countLabel}
                        </Typography>
                    )}
                </Box>
                {action}
            </Stack>
        </Stack>
    ) : (
        <Stack
            direction="row"
            sx={{
                alignItems: "center",
                justifyContent: "space-between",
                gap: 2,
                maxWidth: lockerContentMaxWidth,
                mx: "auto",
                mt: 1,
                mb: 2.25,
            }}
        >
            <Box sx={{ minWidth: 0 }}>
                <Typography
                    variant="h3"
                    sx={{ fontWeight: "bold", minWidth: 0 }}
                >
                    {title}
                </Typography>
                {countLabel && (
                    <Typography
                        variant="small"
                        sx={{ color: "text.muted", mt: 1 }}
                    >
                        {countLabel}
                    </Typography>
                )}
            </Box>
            {action}
        </Stack>
    );

const EmptyState: React.FC<{
    title: string;
    subtitle?: string;
    image?: { src: string; alt?: string };
}> = ({ title, subtitle, image }) => (
    <Box sx={{ textAlign: "center", py: 8 }}>
        {image && (
            <img
                src={image.src}
                alt={image.alt ?? ""}
                style={{
                    height: 112,
                    width: "auto",
                    display: "block",
                    margin: "0 auto",
                }}
            />
        )}
        {image ? (
            <Typography sx={{ ...lockerTextLargeSx, mt: 2.5, mb: 0.5 }}>
                {title}
            </Typography>
        ) : (
            <Typography variant="h4" sx={{ mb: 0.5 }}>
                {title}
            </Typography>
        )}
        {subtitle && (
            <Typography variant="body" sx={{ color: "text.muted" }}>
                {subtitle}
            </Typography>
        )}
    </Box>
);
