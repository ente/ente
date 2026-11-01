import type { SelectedState } from "@/utils/file";
import { useCallback, useEffect, useEffectEvent } from "react";
import type { GalleryMediaSource } from "../sections/types";

export const useSelectionShortcuts = ({
    source,
    userID,
    setSelected,
    clearSelection,
    disabled,
}: {
    source: GalleryMediaSource;
    userID: number | undefined;
    setSelected: React.Dispatch<React.SetStateAction<SelectedState>>;
    clearSelection: () => void;
    disabled: boolean;
}) => {
    const { files, mode, activeCollectionID, activePersonID } = source;
    const selectAll = useCallback(() => {
        if (userID === undefined || !files.length) return;
        const selected: SelectedState = {
            count: 0,
            ownCount: 0,
            collectionID: activeCollectionID,
            context:
                mode === "people" && activePersonID
                    ? { mode: "people", personID: activePersonID }
                    : {
                          mode: mode as
                              "albums" | "hidden-albums" | "archive-albums",
                          collectionID: activeCollectionID!,
                      },
        };
        for (const file of files) {
            if (selected[file.id]) continue;
            selected[file.id] = true;
            selected.count++;
            if (file.ownerID === userID) selected.ownCount++;
        }
        setSelected(selected);
    }, [files, mode, activeCollectionID, activePersonID, userID, setSelected]);
    const handleKey = useEffectEvent((event: KeyboardEvent) => {
        if (
            disabled ||
            event.defaultPrevented ||
            (event.target instanceof Element &&
                event.target.closest(
                    'input, textarea, [contenteditable="true"]',
                )) ||
            Array.from(
                document.querySelectorAll<HTMLElement>(
                    '[role="dialog"], [role="alertdialog"], [role="menu"]',
                ),
            ).some(
                (element) =>
                    element.getClientRects().length > 0 &&
                    !element.closest('[aria-hidden="true"]') &&
                    getComputedStyle(element).visibility !== "hidden",
            )
        )
            return;
        if (event.key === "Escape") clearSelection();
        else if (
            event.key.toLowerCase() === "a" &&
            (event.ctrlKey || event.metaKey)
        ) {
            event.preventDefault();
            selectAll();
        }
    });
    useEffect(() => {
        const handler = (event: KeyboardEvent) => handleKey(event);
        document.addEventListener("keydown", handler);
        return () => document.removeEventListener("keydown", handler);
    }, []);
    return selectAll;
};
