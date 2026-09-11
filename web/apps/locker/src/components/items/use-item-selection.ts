import type { LockerItem } from "@/types";
import { hasDownloadableObject, isLockerItemOwner } from "@/types";
import React, { useCallback, useMemo, useState } from "react";

interface ItemSelectionOptions {
    visibleItems: LockerItem[];
    currentUserID: number | undefined;
    isTrashView: boolean;
    isCollectionsView: boolean;
    onStartSelection: () => void;
    onStopSelection: () => void;
}
export function useItemSelection({
    visibleItems,
    currentUserID,
    isTrashView,
    isCollectionsView,
    onStartSelection,
    onStopSelection,
}: ItemSelectionOptions) {
    const [selectionMode, setSelectionMode] = useState(false);
    const [selectedItemIDs, setSelectedItemIDs] = useState<number[]>([]);
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
    const startSelectionModeForItem = useCallback(
        (item: LockerItem) => {
            setSelectionMode(true);
            setSelectedItemIDs([item.id]);
            onStartSelection();
        },
        [onStartSelection],
    );
    const stopSelectionMode = useCallback(() => {
        setSelectionMode(false);
        setSelectedItemIDs([]);
        onStopSelection();
    }, [onStopSelection]);
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

    return {
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
    };
}
