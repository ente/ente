import {
    deleteLockerFileShareLink,
    downloadLockerFile,
    getOrCreateLockerFileShareLink,
} from "@/services/remote";
import type { LockerCollection, LockerItem } from "@/types";
import {
    canEditCollection,
    canLeaveCollection,
    canOpenCollectionSharing,
    canShareLockerFileLink,
    getItemTitle,
    hasDownloadableObject,
    isImportantCollection,
    isLockerItemOwner,
    restoreTargetLockerCollections,
    sortLockerCollections,
    visibleLockerCollections,
} from "@/types";
import AddOutlinedIcon from "@mui/icons-material/AddOutlined";
import ArrowBackRoundedIcon from "@mui/icons-material/ArrowBackRounded";
import CheckCircleRoundedIcon from "@mui/icons-material/CheckCircleRounded";
import ChevronRightRoundedIcon from "@mui/icons-material/ChevronRightRounded";
import ClearRoundedIcon from "@mui/icons-material/ClearRounded";
import DeleteOutlinedIcon from "@mui/icons-material/DeleteOutlined";
import DeleteSweepOutlinedIcon from "@mui/icons-material/DeleteSweepOutlined";
import EditOutlinedIcon from "@mui/icons-material/EditOutlined";
import FileDownloadOutlinedIcon from "@mui/icons-material/FileDownloadOutlined";
import FilterListRoundedIcon from "@mui/icons-material/FilterListRounded";
import FolderOutlinedIcon from "@mui/icons-material/FolderOutlined";
import LogoutOutlinedIcon from "@mui/icons-material/LogoutOutlined";
import ShareOutlinedIcon from "@mui/icons-material/ShareOutlined";
import StarIcon from "@mui/icons-material/Star";
import {
    Box,
    Button,
    ButtonBase,
    IconButton,
    Stack,
    Tooltip,
    Typography,
} from "@mui/material";
import { savedLocalUser } from "ente-accounts-rs/services/accounts-db";
import {
    OverflowMenu,
    OverflowMenuOption,
} from "ente-base/components/OverflowMenu";
import { isHTTPErrorWithStatus } from "ente-base/http";
import log from "ente-base/log";
import { t } from "i18next";
import React, {
    useCallback,
    useEffect,
    useMemo,
    useRef,
    useState,
} from "react";
import { ItemCard } from "./ItemCard";
import { ItemDetailView } from "./ItemDetailView";
import { ItemListDialogs } from "./itemList/ItemListDialogs";

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
    masterKey?: string;
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

const contentMaxWidth = 560;

export const ItemList: React.FC<ItemListProps> = ({
    collections,
    masterKey,
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
    const [restoreCollectionID, setRestoreCollectionID] = useState<
        number | null
    >(null);
    const [restoreError, setRestoreError] = useState<string | null>(null);
    const [restoringItem, setRestoringItem] = useState(false);
    const [renameCollectionID, setRenameCollectionID] = useState<number | null>(
        null,
    );
    const [renameValue, setRenameValue] = useState("");
    const [renameError, setRenameError] = useState<string | null>(null);
    const [renamingCollection, setRenamingCollection] = useState(false);
    const [createCollectionOpen, setCreateCollectionOpen] = useState(false);
    const [createCollectionName, setCreateCollectionName] = useState("");
    const [creatingCollection, setCreatingCollection] = useState(false);
    const [createCollectionError, setCreateCollectionError] = useState<
        string | null
    >(null);
    const [homeSelectedCollectionIDs, setHomeSelectedCollectionIDs] = useState<
        number[]
    >([]);
    const [collectionFilterAnchorEl, setCollectionFilterAnchorEl] =
        useState<HTMLElement | null>(null);
    const [selectionMode, setSelectionMode] = useState(false);
    const [selectedItemIDs, setSelectedItemIDs] = useState<number[]>([]);
    const [bulkDownloading, setBulkDownloading] = useState(false);
    const [bulkDownloadProgress, setBulkDownloadProgress] = useState<{
        completed: number;
        total: number;
    } | null>(null);
    const [activeFileLinkItemID, setActiveFileLinkItemID] = useState<
        number | null
    >(null);
    const [activeFileLink, setActiveFileLink] = useState<{
        linkID: string;
        url: string;
    } | null>(null);
    const [isCreatingFileLink, setIsCreatingFileLink] = useState(false);
    const [isDeletingFileLink, setIsDeletingFileLink] = useState(false);
    const [isDeleteFileLinkConfirmOpen, setIsDeleteFileLinkConfirmOpen] =
        useState(false);
    const [feedbackMessage, setFeedbackMessage] = useState<string | null>(null);

    const displayCollections = useMemo(
        () =>
            uniqueCollectionsByID(
                isCollectionsView
                    ? sortLockerCollections(collections)
                    : visibleLockerCollections(collections),
            ),
        [collections, isCollectionsView],
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
    const restoreItem = useMemo(
        () =>
            restoreItemID === null
                ? null
                : (trashItemsByID.get(restoreItemID) ?? null),
        [restoreItemID, trashItemsByID],
    );
    const activeFileLinkItem = useMemo(
        () =>
            activeFileLinkItemID === null
                ? null
                : (allItemsByID.get(activeFileLinkItemID) ?? null),
        [activeFileLinkItemID, allItemsByID],
    );
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
    const visibleSelectableItems = useMemo(() => visibleItems, [visibleItems]);
    const visibleSelectableItemIDs = useMemo(
        () => visibleSelectableItems.map((item) => item.id),
        [visibleSelectableItems],
    );
    const selectedVisibleItems = useMemo(() => {
        const selectedIDSet = new Set(selectedItemIDs);
        return visibleSelectableItems.filter((item) =>
            selectedIDSet.has(item.id),
        );
    }, [selectedItemIDs, visibleSelectableItems]);
    const selectedDownloadableItems = useMemo(
        () =>
            selectedVisibleItems.filter(
                (item) => item.type === "file" && hasDownloadableObject(item),
            ),
        [selectedVisibleItems],
    );
    const selectedOwnedItems = useMemo(
        () =>
            selectedVisibleItems.filter((item) =>
                isLockerItemOwner(item, currentUserID),
            ),
        [currentUserID, selectedVisibleItems],
    );
    const selectedItemIDSet = useMemo(
        () => new Set(selectedItemIDs),
        [selectedItemIDs],
    );
    const canBulkSelectVisibleItems =
        !isTrashView && !isCollectionsView && visibleSelectableItems.length > 0;
    const skippedSharedSelectionCount =
        selectedVisibleItems.length - selectedOwnedItems.length;
    const skippedDownloadSelectionCount =
        selectedVisibleItems.length - selectedDownloadableItems.length;
    const allVisibleItemsSelected =
        visibleSelectableItemIDs.length > 0 &&
        selectedVisibleItems.length === visibleSelectableItemIDs.length;
    const canNativeShare =
        typeof navigator !== "undefined" &&
        typeof navigator.share === "function";

    useEffect(() => {
        if (selectedItemID !== null && !selectedItem) {
            setSelectedItemID(null);
        }
    }, [selectedItem, selectedItemID]);

    useEffect(() => {
        if (restoreItemID !== null && !restoreItem) {
            setRestoreItemID(null);
            setRestoreCollectionID(null);
        }
    }, [restoreItem, restoreItemID]);

    useEffect(() => {
        if (
            restoreCollectionID !== null &&
            !restoreCollections.some(
                (collection) => collection.id === restoreCollectionID,
            )
        ) {
            setRestoreCollectionID(null);
        }
    }, [restoreCollectionID, restoreCollections]);

    useEffect(() => {
        if (restoreItemID === null) {
            setRestoreError(null);
            setRestoringItem(false);
        }
    }, [restoreItemID]);

    useEffect(() => {
        if (renameCollectionID === null) {
            setRenameError(null);
            setRenamingCollection(false);
        }
    }, [renameCollectionID]);

    useEffect(() => {
        if (activeFileLinkItemID !== null && !activeFileLinkItem) {
            setActiveFileLinkItemID(null);
            setActiveFileLink(null);
            setIsCreatingFileLink(false);
            setIsDeletingFileLink(false);
            setIsDeleteFileLinkConfirmOpen(false);
        }
    }, [activeFileLinkItem, activeFileLinkItemID]);

    const handleRestoreConfirm = useCallback(async () => {
        if (
            !restoreItem ||
            restoreCollectionID === null ||
            !onRestoreItem ||
            restoringItem
        ) {
            return;
        }

        setRestoringItem(true);
        setRestoreError(null);
        try {
            await Promise.resolve(
                onRestoreItem(restoreItem, restoreCollectionID),
            );
            setRestoreItemID(null);
            setRestoreCollectionID(null);
        } catch (error) {
            log.error("Failed to restore Locker item", error);
            setRestoreError(
                error instanceof Error ? error.message : t("generic_error"),
            );
        } finally {
            setRestoringItem(false);
        }
    }, [onRestoreItem, restoreCollectionID, restoreItem, restoringItem]);

    const handleRenameConfirm = useCallback(async () => {
        if (
            renameCollectionID === null ||
            !renameValue.trim() ||
            !onRenameCollection ||
            renamingCollection
        ) {
            return;
        }

        setRenamingCollection(true);
        setRenameError(null);
        try {
            await Promise.resolve(
                onRenameCollection(renameCollectionID, renameValue.trim()),
            );
            setRenameCollectionID(null);
            setRenameValue("");
        } catch (error) {
            log.error("Failed to rename Locker collection", error);
            setRenameError(
                error instanceof Error ? error.message : t("generic_error"),
            );
        } finally {
            setRenamingCollection(false);
        }
    }, [
        onRenameCollection,
        renameCollectionID,
        renameValue,
        renamingCollection,
    ]);

    const handleCreateCollectionConfirm = useCallback(async () => {
        if (!onCreateCollection || !createCollectionName.trim()) {
            return;
        }

        setCreatingCollection(true);
        setCreateCollectionError(null);
        try {
            const newCollectionID = await onCreateCollection(
                createCollectionName.trim(),
            );
            setCreateCollectionOpen(false);
            setCreateCollectionName("");
            onSelectCollection(newCollectionID);
        } catch (error) {
            setCreateCollectionError(
                error instanceof Error
                    ? error.message
                    : t("failedToCreateCollection"),
            );
        } finally {
            setCreatingCollection(false);
        }
    }, [createCollectionName, onCreateCollection, onSelectCollection]);

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
    const openCollectionFilterMenu = useCallback(
        (event: React.MouseEvent<HTMLElement>) => {
            setCollectionFilterAnchorEl(event.currentTarget);
        },
        [],
    );
    const closeCollectionFilterMenu = useCallback(() => {
        setCollectionFilterAnchorEl(null);
    }, []);
    const startSelectionModeForItem = useCallback((item: LockerItem) => {
        setSelectionMode(true);
        setSelectedItemIDs([item.id]);
        setSelectedItemID(null);
    }, []);
    const stopSelectionMode = useCallback(() => {
        setSelectionMode(false);
        setSelectedItemIDs([]);
        setBulkDownloadProgress(null);
    }, []);
    const toggleItemSelection = useCallback((item: LockerItem) => {
        setSelectedItemIDs((current) =>
            current.includes(item.id)
                ? current.filter((id) => id !== item.id)
                : [...current, item.id],
        );
    }, []);
    const toggleSelectAllVisibleItems = useCallback(() => {
        setSelectedItemIDs((current) =>
            current.length === visibleSelectableItemIDs.length
                ? []
                : visibleSelectableItemIDs,
        );
    }, [visibleSelectableItemIDs]);
    const closeFileLinkDialog = useCallback(() => {
        if (
            isCreatingFileLink ||
            isDeletingFileLink ||
            isDeleteFileLinkConfirmOpen
        ) {
            return;
        }
        setActiveFileLinkItemID(null);
        setActiveFileLink(null);
    }, [isCreatingFileLink, isDeleteFileLinkConfirmOpen, isDeletingFileLink]);
    const openFileLinkDialog = useCallback(
        async (item: LockerItem) => {
            if (!masterKey) {
                return;
            }
            if (!canShareLockerFileLink(item, currentUserID)) {
                setFeedbackMessage(t("shareNotSupportedForSharedFiles"));
                return;
            }

            setActiveFileLinkItemID(item.id);
            setActiveFileLink(null);
            setIsCreatingFileLink(true);
            try {
                const link = await getOrCreateLockerFileShareLink(
                    item.id,
                    masterKey,
                );
                setActiveFileLink(link);
            } catch (error) {
                log.error(
                    `Failed to create share link for file ${item.id}`,
                    error,
                );
                setFeedbackMessage(
                    isHTTPErrorWithStatus(error, 402)
                        ? t("sharingRequiresPaidPlan")
                        : t("failedToCreateShareLink"),
                );
                setActiveFileLinkItemID(null);
            } finally {
                setIsCreatingFileLink(false);
            }
        },
        [currentUserID, masterKey],
    );
    const copyActiveFileLink = useCallback(async () => {
        if (!activeFileLink?.url) {
            return;
        }
        await navigator.clipboard.writeText(activeFileLink.url);
        setFeedbackMessage(t("linkCopiedToClipboard"));
    }, [activeFileLink?.url]);
    const shareActiveFileLink = useCallback(async () => {
        if (!activeFileLink?.url) {
            return;
        }

        if (canNativeShare) {
            try {
                await navigator.share({
                    title: activeFileLinkItem
                        ? getItemTitle(activeFileLinkItem)
                        : undefined,
                    url: activeFileLink.url,
                });
                return;
            } catch (error) {
                if (
                    error instanceof DOMException &&
                    error.name === "AbortError"
                ) {
                    return;
                }
            }
        }

        await navigator.clipboard.writeText(activeFileLink.url);
        setFeedbackMessage(t("linkCopiedToClipboard"));
    }, [activeFileLink?.url, activeFileLinkItem, canNativeShare]);
    const deleteActiveFileLink = useCallback(async () => {
        if (!activeFileLinkItem) {
            return;
        }

        setIsDeletingFileLink(true);
        try {
            await deleteLockerFileShareLink(
                activeFileLinkItem.id,
                activeFileLink?.linkID,
            );
            setFeedbackMessage(t("shareLinkDeletedSuccessfully"));
            setActiveFileLinkItemID(null);
            setActiveFileLink(null);
        } catch (error) {
            log.error(
                `Failed to delete share link for file ${activeFileLinkItem.id}`,
                error,
            );
            setFeedbackMessage(t("failedToDeleteShareLink"));
        } finally {
            setIsDeletingFileLink(false);
            setIsDeleteFileLinkConfirmOpen(false);
        }
    }, [activeFileLink?.linkID, activeFileLinkItem]);
    const downloadSelectedFiles = useCallback(async () => {
        if (
            !masterKey ||
            bulkDownloading ||
            selectedDownloadableItems.length === 0
        ) {
            return;
        }

        setBulkDownloading(true);
        setBulkDownloadProgress({
            completed: 0,
            total: selectedDownloadableItems.length,
        });
        try {
            for (const [index, item] of selectedDownloadableItems.entries()) {
                await downloadLockerFile(
                    item.id,
                    getItemTitle(item),
                    masterKey,
                );
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
        masterKey,
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
    React.useEffect(() => {
        if (selectionMode && selectedItemIDs.length === 0) {
            setSelectionMode(false);
        }
    }, [selectedItemIDs.length, selectionMode]);
    React.useEffect(() => {
        if (
            isTrashView ||
            isCollectionsView ||
            visibleSelectableItemIDs.length === 0
        ) {
            setSelectionMode(false);
            setSelectedItemIDs([]);
            return;
        }

        const visibleItemIDSet = new Set(visibleSelectableItemIDs);
        setSelectedItemIDs((current) =>
            current.filter((id) => visibleItemIDSet.has(id)),
        );
    }, [isCollectionsView, isTrashView, visibleSelectableItemIDs]);

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
                    backgroundColor: "#08090A",
                    ...theme.applyStyles("light", {
                        backgroundColor: "#F3F4F6",
                    }),
                })}
            >
                <Box
                    sx={(theme) => ({
                        px: { xs: 2, sm: 3 },
                        pb: isTrashView
                            ? 3
                            : "calc(env(safe-area-inset-bottom) + 120px)",
                        backgroundColor: "#08090A",
                        ...theme.applyStyles("light", {
                            backgroundColor: "#F3F4F6",
                        }),
                    })}
                >
                    {isHomeView && (
                        <>
                            <SectionHeader
                                title={t("recents")}
                                countLabel={t("lockerItemsCount", {
                                    count: homeFilteredItems.length,
                                })}
                            />

                            {displayCollections.length > 0 && (
                                <Stack
                                    direction="row"
                                    sx={{
                                        width: "100%",
                                        maxWidth: contentMaxWidth,
                                        mx: "auto",
                                        alignItems: "center",
                                        gap: 0.75,
                                        mt: -0.25,
                                        mb: 1.75,
                                        minWidth: 0,
                                    }}
                                >
                                    <CollectionFilterChip
                                        selected={
                                            homeSelectedCollectionIDs.length > 0
                                        }
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
                                                    transform:
                                                        "translateY(2px)",
                                                },
                                                "100%": {
                                                    opacity: 1,
                                                    transform: "translateY(0)",
                                                },
                                            },
                                            animation:
                                                "chipBarRefresh 220ms ease-out",
                                        }}
                                    >
                                        <CollectionChipFilters
                                            collections={orderedHomeCollections}
                                            selectedCollectionIDs={
                                                homeSelectedCollectionIDs
                                            }
                                            onToggleCollection={
                                                toggleHomeCollection
                                            }
                                        />
                                    </Box>
                                </Stack>
                            )}

                            <ItemsSection
                                items={homeFilteredItems}
                                masterKey={masterKey}
                                isTrashView={false}
                                onEditItem={onEditItem}
                                onDeleteItem={onDeleteItem}
                                onPermanentlyDelete={onPermanentlyDelete}
                                onRequestRestore={(item) => {
                                    setRestoreItemID(item.id);
                                    setRestoreCollectionID(null);
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
                                                    setCreateCollectionError(
                                                        null,
                                                    );
                                                    setCreateCollectionName("");
                                                    setCreateCollectionOpen(
                                                        true,
                                                    );
                                                }}
                                                sx={{
                                                    width: 40,
                                                    height: 40,
                                                    color: "#FFFFFF",
                                                    background: "#0E6BFF",
                                                    border: "1px solid rgba(160, 199, 255, 0.18)",
                                                    boxShadow:
                                                        "0 10px 24px rgba(0, 66, 173, 0.20)",
                                                    "&:hover": {
                                                        background: "#1A7AFF",
                                                        boxShadow:
                                                            "0 12px 28px rgba(0, 66, 173, 0.24)",
                                                    },
                                                }}
                                            >
                                                <AddOutlinedIcon
                                                    sx={{ fontSize: 24 }}
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
                                            setRenameCollectionID(
                                                collection.id,
                                            );
                                            setRenameValue(collection.name);
                                        }}
                                        onDeleteCollection={onDeleteCollection}
                                    />
                                </Box>
                            ) : (
                                <EmptyState
                                    title={t("noCollections")}
                                    subtitle={t("createCollection")}
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
                                            setRenameCollectionID(
                                                collection.id,
                                            );
                                            setRenameValue(collection.name);
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
                                masterKey={masterKey}
                                isTrashView={isTrashView}
                                onEditItem={onEditItem}
                                onDeleteItem={onDeleteItem}
                                onPermanentlyDelete={onPermanentlyDelete}
                                onRequestRestore={(item) => {
                                    setRestoreItemID(item.id);
                                    setRestoreCollectionID(null);
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
                                countLabel={t("lockerItemsCount", {
                                    count: sortedItems.length,
                                })}
                                onBack={onNavigateBack}
                                action={
                                    <Stack
                                        direction="row"
                                        sx={{ alignItems: "center", gap: 1 }}
                                    >
                                        {isTrashView &&
                                            sortedItems.length > 0 &&
                                            onEmptyTrash && (
                                                <Button
                                                    color="critical"
                                                    startIcon={
                                                        <DeleteSweepOutlinedIcon />
                                                    }
                                                    onClick={onEmptyTrash}
                                                >
                                                    {t("empty_trash")}
                                                </Button>
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
                                                    onRenameCollection
                                                        ? () => {
                                                              setRenameCollectionID(
                                                                  selectedCollection.id,
                                                              );
                                                              setRenameValue(
                                                                  selectedCollection.name,
                                                              );
                                                          }
                                                        : undefined
                                                }
                                                onDelete={
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
                                masterKey={masterKey}
                                isTrashView={isTrashView}
                                onEditItem={onEditItem}
                                onDeleteItem={onDeleteItem}
                                onPermanentlyDelete={onPermanentlyDelete}
                                onRequestRestore={(item) => {
                                    setRestoreItemID(item.id);
                                    setRestoreCollectionID(null);
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
                                            title={t("trashIsEmpty")}
                                            subtitle={t("yourTrashIsEmpty")}
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
                    canDownload={
                        !!masterKey && selectedDownloadableItems.length > 0
                    }
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
                masterKey={masterKey}
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

            <ItemListDialogs
                activeFileLinkItemTitle={
                    activeFileLinkItem ? getItemTitle(activeFileLinkItem) : ""
                }
                activeFileLinkURL={activeFileLink?.url ?? null}
                canNativeShare={canNativeShare}
                closeCollectionFilterMenu={closeCollectionFilterMenu}
                closeFileLinkDialog={closeFileLinkDialog}
                clearHomeCollectionSelection={clearHomeCollectionSelection}
                collectionFilterAnchorEl={collectionFilterAnchorEl}
                createCollectionError={createCollectionError}
                createCollectionName={createCollectionName}
                createCollectionOpen={createCollectionOpen}
                creatingCollection={creatingCollection}
                deleteFileLink={() => void deleteActiveFileLink()}
                dropdownHomeCollections={dropdownHomeCollections}
                feedbackMessage={feedbackMessage}
                fileLinkDialogOpen={activeFileLinkItem !== null}
                homeSelectedCollectionIDs={homeSelectedCollectionIDs}
                isCreatingFileLink={isCreatingFileLink}
                isDeleteFileLinkConfirmOpen={isDeleteFileLinkConfirmOpen}
                isDeletingFileLink={isDeletingFileLink}
                onCloseCreateCollectionDialog={() =>
                    setCreateCollectionOpen(false)
                }
                onCloseFeedback={() => setFeedbackMessage(null)}
                onCloseRenameDialog={() => {
                    if (renamingCollection) {
                        return;
                    }
                    setRenameCollectionID(null);
                    setRenameError(null);
                }}
                onCloseRestoreDialog={() => {
                    if (restoringItem) {
                        return;
                    }
                    setRestoreItemID(null);
                    setRestoreCollectionID(null);
                    setRestoreError(null);
                }}
                onConfirmCreateCollection={() =>
                    void handleCreateCollectionConfirm()
                }
                onConfirmRename={handleRenameConfirm}
                onConfirmRestore={handleRestoreConfirm}
                onCopyFileLink={() => void copyActiveFileLink()}
                onRequestDeleteFileLink={() =>
                    setIsDeleteFileLinkConfirmOpen(true)
                }
                onShareFileLink={() => void shareActiveFileLink()}
                onToggleHomeCollection={toggleHomeCollection}
                renameError={renameError}
                renameCollectionOpen={renameCollectionID !== null}
                renamingCollection={renamingCollection}
                renameValue={renameValue}
                restoreCollections={restoreCollections}
                restoreError={restoreError}
                restoreCollectionID={restoreCollectionID}
                restoreDialogOpen={restoreItem !== null}
                restoringItem={restoringItem}
                setCreateCollectionName={(value) => {
                    setCreateCollectionName(value);
                    setCreateCollectionError(null);
                }}
                setDeleteFileLinkConfirmOpen={setIsDeleteFileLinkConfirmOpen}
                setRenameValue={(value) => {
                    setRenameValue(value);
                    setRenameError(null);
                }}
                setRestoreCollectionID={(collectionID) => {
                    setRestoreCollectionID(collectionID);
                    setRestoreError(null);
                }}
            />
        </Stack>
    );
};

const SectionHeader: React.FC<{
    title: string;
    countLabel: string;
    action?: React.ReactNode;
    onBack?: () => void;
}> = ({ title, countLabel, action, onBack }) => (
    <Stack
        direction="row"
        sx={{
            alignItems: "center",
            justifyContent: "space-between",
            gap: 2,
            maxWidth: contentMaxWidth,
            mx: "auto",
            mt: 3,
            mb: 2.25,
        }}
    >
        <Stack
            direction="row"
            sx={{ minWidth: 0, gap: 1.5, alignItems: "center" }}
        >
            {onBack && (
                <IconButton
                    aria-label="Back"
                    onClick={onBack}
                    sx={{
                        alignSelf: "center",
                        width: 44,
                        height: 44,
                        flexShrink: 0,
                        color: "text.secondary",
                        border: "1px solid rgba(255, 255, 255, 0.10)",
                        backgroundColor: "rgba(255, 255, 255, 0.03)",
                        "&:hover": {
                            backgroundColor: "rgba(255, 255, 255, 0.08)",
                        },
                    }}
                >
                    <ArrowBackRoundedIcon sx={{ fontSize: 20 }} />
                </IconButton>
            )}
            <Box sx={{ minWidth: 0 }}>
                <Typography
                    variant="h3"
                    sx={{ fontWeight: "bold", minWidth: 0 }}
                >
                    {title}
                </Typography>
                <Typography variant="small" sx={{ color: "text.muted", mt: 1 }}>
                    {countLabel}
                </Typography>
            </Box>
        </Stack>
        {action}
    </Stack>
);

const ItemsSection: React.FC<{
    items: LockerItem[];
    masterKey?: string;
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
    masterKey,
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
            sx={{ maxWidth: contentMaxWidth, mx: "auto", gap: 1.1, mt: 1.25 }}
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
                        masterKey={masterKey}
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
        <Box sx={{ maxWidth: contentMaxWidth, mx: "auto" }}>{emptyState}</Box>
    );

const SelectionActionBar: React.FC<{
    selectedCount: number;
    allSelected: boolean;
    bulkDownloading: boolean;
    bulkDownloadProgress: { completed: number; total: number } | null;
    canDownload: boolean;
    canDelete: boolean;
    onToggleSelectAll: () => void;
    onDownload: () => void;
    onDelete: () => void;
    onDone: () => void;
}> = ({
    selectedCount,
    allSelected,
    bulkDownloading,
    bulkDownloadProgress,
    canDownload,
    canDelete,
    onToggleSelectAll,
    onDownload,
    onDelete,
    onDone,
}) => (
    <Box sx={{ px: { xs: 2, sm: 3 }, py: { xs: 1.25, sm: 1.5 } }}>
        <Box
            sx={(theme) => ({
                maxWidth: 760,
                mx: "auto",
                borderRadius: "20px",
                border: `1px solid ${theme.vars.palette.stroke.faint}`,
                backgroundColor: theme.vars.palette.background.paper,
                boxShadow: "0 12px 30px rgba(15, 23, 42, 0.12)",
                backdropFilter: "blur(18px)",
                px: { xs: 1.25, sm: 1.5 },
                py: 1.25,
            })}
        >
            <Stack
                direction={{ xs: "column", sm: "row" }}
                sx={{
                    alignItems: { xs: "stretch", sm: "center" },
                    justifyContent: "space-between",
                    gap: 1,
                }}
            >
                <Stack
                    direction="row"
                    sx={{
                        alignItems: "center",
                        justifyContent: "space-between",
                        gap: 1,
                    }}
                >
                    <Box
                        sx={{
                            display: "flex",
                            alignItems: "center",
                            gap: 1,
                            minWidth: 0,
                            px: 1.25,
                            py: 0.875,
                            borderRadius: "14px",
                            backgroundColor: "rgba(16, 113, 255, 0.10)",
                            border: "1px solid rgba(16, 113, 255, 0.16)",
                        }}
                    >
                        <CheckCircleRoundedIcon
                            sx={{
                                fontSize: 18,
                                color: "#1071FF",
                                flexShrink: 0,
                            }}
                        />
                        <Typography
                            variant="body"
                            sx={{ fontWeight: 600, minWidth: 0 }}
                            noWrap
                        >
                            {t("filesSelected", { count: selectedCount })}
                        </Typography>
                    </Box>
                    <IconButton
                        onClick={onDone}
                        disabled={bulkDownloading}
                        sx={(theme) => ({
                            color: "text.muted",
                            width: 38,
                            height: 38,
                            flexShrink: 0,
                            border: `1px solid ${theme.vars.palette.stroke.faint}`,
                            backgroundColor: theme.vars.palette.fill.faint,
                            "&:hover": {
                                backgroundColor:
                                    theme.vars.palette.fill.faintHover,
                            },
                        })}
                    >
                        <ClearRoundedIcon sx={{ fontSize: 18 }} />
                    </IconButton>
                </Stack>
                <Stack
                    direction={{ xs: "column", sm: "row" }}
                    sx={{ alignItems: { xs: "stretch", sm: "center" }, gap: 1 }}
                >
                    <Button
                        color="secondary"
                        onClick={onToggleSelectAll}
                        disabled={bulkDownloading}
                        sx={(theme) => ({
                            minHeight: 42,
                            px: 1.5,
                            borderRadius: "14px",
                            border: `1px solid ${theme.vars.palette.stroke.faint}`,
                            backgroundColor: theme.vars.palette.fill.faint,
                            "&:hover": {
                                backgroundColor:
                                    theme.vars.palette.fill.faintHover,
                            },
                        })}
                    >
                        {allSelected ? t("deselectAll") : t("selectAll")}
                    </Button>
                    <Button
                        variant="contained"
                        startIcon={<FileDownloadOutlinedIcon />}
                        onClick={onDownload}
                        disabled={bulkDownloading || !canDownload}
                        sx={{
                            minHeight: 42,
                            px: 1.75,
                            borderRadius: "14px",
                            boxShadow: "none",
                            color: "#FFFFFF",
                            background:
                                "linear-gradient(180deg, #1674FF 0%, #0B5FE0 100%)",
                            "& .MuiButton-startIcon": { color: "#FFFFFF" },
                            "&:hover": {
                                boxShadow: "none",
                                background:
                                    "linear-gradient(180deg, #2A82FF 0%, #1269F0 100%)",
                            },
                        }}
                    >
                        {bulkDownloading && bulkDownloadProgress
                            ? `${t("downloading")} ${bulkDownloadProgress.completed}/${bulkDownloadProgress.total}`
                            : t("download")}
                    </Button>
                    <Button
                        color="critical"
                        startIcon={<DeleteOutlinedIcon />}
                        onClick={onDelete}
                        disabled={bulkDownloading || !canDelete}
                        sx={{
                            minHeight: 42,
                            px: 1.75,
                            borderRadius: "14px",
                            color: "#FFFFFF",
                            border: "1px solid rgba(185, 28, 28, 0.26)",
                            backgroundColor: "#D14343",
                            "& .MuiButton-startIcon": { color: "#FFFFFF" },
                            "&:hover": { backgroundColor: "#B93838" },
                        }}
                    >
                        {t("delete")}
                    </Button>
                </Stack>
            </Stack>
        </Box>
    </Box>
);

const CollectionGrid: React.FC<{
    collections: LockerCollection[];
    onSelectCollection: (collectionID: number) => void;
    onShareCollection?: (collection: LockerCollection) => void;
    onLeaveCollection?: (collection: LockerCollection) => void;
    onRequestRenameCollection?: (collection: LockerCollection) => void;
    onDeleteCollection?: (collectionID: number) => void;
}> = ({
    collections,
    onSelectCollection,
    onShareCollection,
    onLeaveCollection,
    onRequestRenameCollection,
    onDeleteCollection,
}) => {
    const currentUserID = savedLocalUser()?.id;

    return (
        <Box
            sx={{
                width: "100%",
                maxWidth: contentMaxWidth,
                mx: "auto",
                display: "grid",
                gap: 2,
            }}
        >
            {collections.map((collection) => (
                <CollectionCard
                    key={collection.id}
                    collection={collection}
                    onClick={() => onSelectCollection(collection.id)}
                    onShare={
                        onShareCollection &&
                        canOpenCollectionSharing(collection)
                            ? () => onShareCollection(collection)
                            : undefined
                    }
                    onLeave={
                        onLeaveCollection &&
                        canLeaveCollection(collection, currentUserID)
                            ? () => onLeaveCollection(collection)
                            : undefined
                    }
                    onRename={
                        onRequestRenameCollection &&
                        canEditCollection(collection, currentUserID)
                            ? () => onRequestRenameCollection(collection)
                            : undefined
                    }
                    onDelete={
                        onDeleteCollection &&
                        canEditCollection(collection, currentUserID)
                            ? () => onDeleteCollection(collection.id)
                            : undefined
                    }
                />
            ))}
        </Box>
    );
};

const CollectionChipFilters: React.FC<{
    collections: LockerCollection[];
    selectedCollectionIDs: number[];
    onToggleCollection: (collectionID: number) => void;
}> = ({ collections, selectedCollectionIDs, onToggleCollection }) => {
    const scrollContainerRef = useRef<HTMLDivElement | null>(null);
    const [showLeftScrollHint, setShowLeftScrollHint] = useState(false);
    const [showRightScrollHint, setShowRightScrollHint] = useState(false);

    const scrollRight = () => {
        const container = scrollContainerRef.current;
        if (!container) {
            return;
        }

        container.scrollBy({
            left: Math.max(container.clientWidth * 0.6, 160),
            behavior: "smooth",
        });
    };

    useEffect(() => {
        const container = scrollContainerRef.current;
        if (!container) {
            return;
        }

        const updateScrollHint = () => {
            setShowLeftScrollHint(container.scrollLeft > 8);
            const remainingScroll =
                container.scrollWidth -
                container.clientWidth -
                container.scrollLeft;
            setShowRightScrollHint(remainingScroll > 8);
        };

        updateScrollHint();
        container.addEventListener("scroll", updateScrollHint, {
            passive: true,
        });
        window.addEventListener("resize", updateScrollHint);

        return () => {
            container.removeEventListener("scroll", updateScrollHint);
            window.removeEventListener("resize", updateScrollHint);
        };
    }, [collections, selectedCollectionIDs]);

    return (
        <Box
            sx={{
                width: "100%",
                maxWidth: contentMaxWidth,
                mx: "auto",
                mt: 0.5,
            }}
        >
            <Stack direction="row" sx={{ alignItems: "stretch", gap: 0 }}>
                <Box sx={{ position: "relative", flex: 1, minWidth: 0 }}>
                    <Stack
                        ref={scrollContainerRef}
                        direction="row"
                        sx={{
                            gap: 1,
                            flexWrap: "nowrap",
                            overflowX: "auto",
                            overflowY: "hidden",
                            justifyContent: "flex-start",
                            pr: 2,
                            pb: 0.5,
                            scrollbarWidth: "none",
                            "&::-webkit-scrollbar": { display: "none" },
                        }}
                    >
                        {collections.map((collection) => {
                            const isSelected = selectedCollectionIDs.includes(
                                collection.id,
                            );

                            return (
                                <ButtonBase
                                    key={collection.id}
                                    onClick={() =>
                                        onToggleCollection(collection.id)
                                    }
                                    sx={(theme) => ({
                                        borderRadius: "999px",
                                        px: 1.5,
                                        py: 0.875,
                                        whiteSpace: "nowrap",
                                        flexShrink: 0,
                                        backgroundColor: isSelected
                                            ? "#1071FF"
                                            : theme.vars.palette.fill.faint,
                                        color: isSelected
                                            ? "#FFFFFF"
                                            : theme.vars.palette.text.base,
                                        ...theme.applyStyles("light", {
                                            backgroundColor: isSelected
                                                ? "#1071FF"
                                                : "#FFFFFF",
                                            border: isSelected
                                                ? "none"
                                                : "1px solid rgba(17, 24, 39, 0.06)",
                                        }),
                                    })}
                                >
                                    <Typography variant="small">
                                        {collection.name}
                                    </Typography>
                                </ButtonBase>
                            );
                        })}
                    </Stack>
                    {showLeftScrollHint && (
                        <Box
                            sx={(theme) => ({
                                position: "absolute",
                                top: 0,
                                left: 0,
                                bottom: 0,
                                width: 40,
                                pointerEvents: "none",
                                background:
                                    "linear-gradient(90deg, #08090A 0%, rgba(8, 9, 10, 0) 100%)",
                                ...theme.applyStyles("light", {
                                    background:
                                        "linear-gradient(90deg, #F3F4F6 0%, rgba(243, 244, 246, 0) 100%)",
                                }),
                            })}
                        />
                    )}
                    {showRightScrollHint && (
                        <Box
                            sx={(theme) => ({
                                position: "absolute",
                                top: 0,
                                right: 0,
                                bottom: 0,
                                width: 72,
                                pointerEvents: "none",
                                background:
                                    "linear-gradient(90deg, rgba(8, 9, 10, 0) 0%, #08090A 100%)",
                                ...theme.applyStyles("light", {
                                    background:
                                        "linear-gradient(90deg, rgba(243, 244, 246, 0) 0%, #F3F4F6 100%)",
                                }),
                            })}
                        />
                    )}
                </Box>
                <Box
                    sx={{
                        width: 28,
                        flexShrink: 0,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                    }}
                >
                    {showRightScrollHint && (
                        <ButtonBase
                            onClick={scrollRight}
                            sx={(theme) => ({
                                width: 28,
                                height: "100%",
                                color: "#4A4A4A",
                                borderRadius: "999px",
                                ...theme.applyStyles("dark", {
                                    color: "#FFFFFF",
                                }),
                            })}
                        >
                            <ChevronRightRoundedIcon sx={{ fontSize: 28 }} />
                        </ButtonBase>
                    )}
                </Box>
            </Stack>
        </Box>
    );
};

const CollectionFilterChip: React.FC<{
    selected: boolean;
    onClick: (event: React.MouseEvent<HTMLElement>) => void;
}> = ({ selected, onClick }) => (
    <Tooltip title={t("seeAllCollections")}>
        <ButtonBase
            onClick={onClick}
            sx={(theme) => ({
                borderRadius: "999px",
                px: 1.25,
                py: 0.875,
                flexShrink: 0,
                minWidth: 44,
                color: selected ? "#FFFFFF" : theme.vars.palette.text.base,
                backgroundColor: selected
                    ? "#1071FF"
                    : theme.vars.palette.fill.faint,
                "&:hover": {
                    backgroundColor: selected
                        ? "#1071FF"
                        : theme.vars.palette.fill.faintHover,
                },
                ...theme.applyStyles("light", {
                    backgroundColor: selected ? "#1071FF" : "#FFFFFF",
                    border: selected
                        ? "none"
                        : "1px solid rgba(17, 24, 39, 0.06)",
                    "&:hover": {
                        backgroundColor: selected ? "#1071FF" : "#F8FAFC",
                    },
                }),
            })}
        >
            <FilterListRoundedIcon sx={{ fontSize: 18 }} />
        </ButtonBase>
    </Tooltip>
);

const EmptyState: React.FC<{ title: string; subtitle: string }> = ({
    title,
    subtitle,
}) => (
    <Box sx={{ textAlign: "center", py: 8 }}>
        <Typography variant="h4" sx={{ mb: 0.5 }}>
            {title}
        </Typography>
        <Typography variant="body" sx={{ color: "text.muted" }}>
            {subtitle}
        </Typography>
    </Box>
);

const CollectionCard: React.FC<{
    collection: LockerCollection;
    onClick: () => void;
    onShare?: () => void;
    onLeave?: () => void;
    onRename?: () => void;
    onDelete?: () => void;
}> = ({ collection, onClick, onShare, onLeave, onRename, onDelete }) => {
    return (
        <ButtonBase
            component="div"
            onClick={onClick}
            sx={(theme) => ({
                width: "100%",
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                gap: 1.25,
                px: 1.5,
                py: 1.25,
                minHeight: 84,
                borderRadius: "18px",
                backgroundColor:
                    collection.items.length > 0
                        ? theme.vars.palette.fill.faint
                        : "rgba(255, 255, 255, 0.03)",
                border: 1,
                borderStyle: "solid",
                borderColor:
                    collection.items.length > 0
                        ? "rgba(255, 255, 255, 0.08)"
                        : "rgba(255, 255, 255, 0.08)",
                transition: "background-color 0.15s, border-color 0.15s",
                "&:hover": {
                    backgroundColor:
                        collection.items.length > 0
                            ? theme.vars.palette.fill.faintHover
                            : "rgba(255, 255, 255, 0.05)",
                    borderColor: "rgba(255, 255, 255, 0.13)",
                },
                ...theme.applyStyles("light", {
                    backgroundColor:
                        collection.items.length > 0 ? "#FFFFFF" : "#F8FAFC",
                    borderColor:
                        collection.items.length > 0
                            ? "rgba(17, 24, 39, 0.08)"
                            : "rgba(17, 24, 39, 0.06)",
                    "&:hover": {
                        backgroundColor:
                            collection.items.length > 0 ? "#FFFFFF" : "#F1F5F9",
                        borderColor: "rgba(17, 24, 39, 0.12)",
                    },
                }),
            })}
        >
            <Stack
                direction="row"
                sx={{ flex: 1, minWidth: 0, alignItems: "center", gap: 1.25 }}
            >
                <Box
                    sx={{
                        position: "relative",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        width: 52,
                        height: 52,
                        flexShrink: 0,
                    }}
                >
                    <Box
                        sx={{
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            width: 40,
                            height: 40,
                            m: "6px",
                            borderRadius: "12px",
                            backgroundColor: isImportantCollection(collection)
                                ? "rgba(16, 113, 255, 0.16)"
                                : "rgba(18, 36, 63, 0.96)",
                            border: isImportantCollection(collection)
                                ? "none"
                                : "1px solid rgba(159, 193, 255, 0.12)",
                        }}
                    >
                        {isImportantCollection(collection) ? (
                            <StarIcon sx={{ fontSize: 20, color: "#1071FF" }} />
                        ) : (
                            <FolderOutlinedIcon
                                sx={{ fontSize: 20, color: "#D6E5FF" }}
                            />
                        )}
                    </Box>
                    {collection.isShared && <SharedCollectionBadge />}
                </Box>
                <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography
                        variant="body"
                        sx={{
                            minWidth: 0,
                            fontWeight: "regular",
                            lineHeight: 1.45,
                        }}
                        noWrap
                    >
                        {collection.name}
                    </Typography>
                    <Typography
                        variant="small"
                        sx={{ color: "text.muted", mt: 0.25 }}
                    >
                        {t("lockerItemsCount", {
                            count: collection.items.length,
                        })}
                    </Typography>
                </Box>
            </Stack>
            {(onShare || onLeave || onRename || onDelete) && (
                <Box
                    sx={{ flexShrink: 0, ml: 0.25 }}
                    onClick={(event) => event.stopPropagation()}
                >
                    <CollectionContextMenu
                        ariaID={`collection-context-menu-${collection.id}`}
                        onShare={onShare}
                        onLeave={onLeave}
                        onRename={onRename}
                        onDelete={onDelete}
                    />
                </Box>
            )}
        </ButtonBase>
    );
};

const SharedCollectionBadge: React.FC = () => {
    return (
        <Box
            sx={(theme) => ({
                position: "absolute",
                right: -2,
                bottom: -2,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                width: 16,
                height: 16,
                borderRadius: "999px",
                backgroundColor: "#1071FF",
                border: `1.5px solid ${theme.vars.palette.background.paper}`,
                boxShadow: "0 2px 6px rgba(0, 66, 173, 0.24)",
            })}
        >
            <ShareOutlinedIcon sx={{ fontSize: 10, color: "#FFFFFF" }} />
        </Box>
    );
};

const CollectionContextMenu: React.FC<{
    ariaID: string;
    onShare?: () => void;
    onLeave?: () => void;
    onRename?: () => void;
    onDelete?: () => void;
}> = ({ ariaID, onShare, onLeave, onRename, onDelete }) => (
    <OverflowMenu
        ariaID={ariaID}
        triggerButtonSxProps={{
            p: 0.25,
            color: "text.faint",
            opacity: 0,
            ".MuiButtonBase-root:hover &": { opacity: 1 },
        }}
    >
        {onShare && (
            <OverflowMenuOption
                startIcon={<ShareOutlinedIcon />}
                onClick={onShare}
            >
                {t("share")}
            </OverflowMenuOption>
        )}
        {onLeave && (
            <OverflowMenuOption
                startIcon={<LogoutOutlinedIcon />}
                color="critical"
                onClick={onLeave}
            >
                {t("leaveCollection")}
            </OverflowMenuOption>
        )}
        {onRename && (
            <OverflowMenuOption
                startIcon={<EditOutlinedIcon />}
                onClick={onRename}
            >
                {t("renameCollection")}
            </OverflowMenuOption>
        )}
        {onDelete && (
            <OverflowMenuOption
                startIcon={<DeleteOutlinedIcon />}
                color="critical"
                onClick={onDelete}
            >
                {t("deleteCollection")}
            </OverflowMenuOption>
        )}
    </OverflowMenu>
);

const CollectionHeaderMenu: React.FC<{
    onShare?: () => void;
    onLeave?: () => void;
    onRename?: () => void;
    onDelete?: () => void;
}> = ({ onShare, onLeave, onRename, onDelete }) => (
    <OverflowMenu
        ariaID="collection-header-menu"
        triggerButtonSxProps={{ color: "text.muted" }}
    >
        {onShare && (
            <OverflowMenuOption
                startIcon={<ShareOutlinedIcon />}
                onClick={onShare}
            >
                {t("share")}
            </OverflowMenuOption>
        )}
        {onLeave && (
            <OverflowMenuOption
                startIcon={<LogoutOutlinedIcon />}
                color="critical"
                onClick={onLeave}
            >
                {t("leaveCollection")}
            </OverflowMenuOption>
        )}
        {onRename && (
            <OverflowMenuOption
                startIcon={<EditOutlinedIcon />}
                onClick={onRename}
            >
                {t("renameCollection")}
            </OverflowMenuOption>
        )}
        {onDelete && (
            <OverflowMenuOption
                startIcon={<DeleteOutlinedIcon />}
                color="critical"
                onClick={onDelete}
            >
                {t("deleteCollection")}
            </OverflowMenuOption>
        )}
    </OverflowMenu>
);
