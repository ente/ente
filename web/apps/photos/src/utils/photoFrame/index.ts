// TODO: Audit this file
import type { SelectedState, SetSelectedState } from "@/utils/file";
import type { SelectionContext } from "ente-new/photos/components/gallery";
import type { GalleryBarMode } from "ente-new/photos/components/gallery/reducer";

// TODO: All this is unnecessarily complex, and needs reworking.
export const handleSelectCreator =
    (
        setSelected: SetSelectedState,
        mode: GalleryBarMode | undefined,
        userID: number | undefined,
        activeCollectionID: number,
        activePersonID: string | undefined,
        setRangeStartIndex: (index: number | undefined) => void,
    ) =>
    ({ id, ownerID }: { id: number; ownerID: number }, index?: number) =>
    (checked: boolean) => {
        if (typeof index != "undefined") {
            if (checked) {
                setRangeStartIndex(index);
            } else {
                setRangeStartIndex(undefined);
            }
        }
        setSelected((_selected) => {
            const { selected, newContext } = createSelectedAndContext(
                mode,
                activeCollectionID,
                activePersonID,
                _selected,
            );

            const handleCounterChange = (count: number) => {
                if (selected[id] === checked) {
                    return count;
                }
                if (checked) {
                    return count + 1;
                } else {
                    return count - 1;
                }
            };

            const handleAllCounterChange = () => {
                if (ownerID === userID) {
                    return {
                        ownCount: handleCounterChange(selected.ownCount),
                        count: handleCounterChange(selected.count),
                    };
                } else {
                    return { count: handleCounterChange(selected.count) };
                }
            };
            return {
                ...selected,
                [id]: checked,
                collectionID: activeCollectionID,
                context: newContext,
                ...handleAllCounterChange(),
            };
        });
    };

export const handleSelectCreatorMulti =
    (
        setSelected: SetSelectedState,
        mode: GalleryBarMode | undefined,
        userID: number | undefined,
        activeCollectionID: number,
        activePersonID: string | undefined,
    ) =>
    (files: { id: number; ownerID: number }[]) =>
    (checked: boolean) => {
        setSelected((_selected) => {
            const { selected, newContext } = createSelectedAndContext(
                mode,
                activeCollectionID,
                activePersonID,
                _selected,
            );

            const newSelected = { ...selected };
            let newCount = selected.count;
            let newOwnCount = selected.ownCount;

            if (checked) {
                for (const file of files) {
                    if (!newSelected[file.id]) {
                        newSelected[file.id] = true;
                        newCount++;
                        if (file.ownerID === userID) newOwnCount++;
                    }
                }
            } else {
                for (const file of files) {
                    if (newSelected[file.id]) {
                        newSelected[file.id] = false;
                        newCount--;
                        if (file.ownerID === userID) newOwnCount--;
                    }
                }
            }

            return {
                ...newSelected,
                count: newCount,
                ownCount: newOwnCount,
                collectionID: activeCollectionID,
                context: newContext,
            };
        });
    };

const createSelectedAndContext = (
    mode: GalleryBarMode | undefined,

    activeCollectionID: number,
    activePersonID: string | undefined,
    selected: SelectedState,
) => {
    if (!mode) {
        // Retain older behavior for non-gallery call sites.
        if (selected.collectionID !== activeCollectionID) {
            selected = {
                ownCount: 0,
                count: 0,
                collectionID: 0,
                context: undefined,
            };
        }
    } else if (!selected.context) {
        // Gallery will specify a mode, but a fresh selection starts off
        // without a context, so fill it in with the current context.
        selected = {
            ...selected,
            context:
                mode == "people"
                    ? { mode, personID: activePersonID! }
                    : { mode, collectionID: activeCollectionID },
        };
    } else {
        // Both mode and context are defined.
        if (selected.context.mode != mode) {
            // Clear selection if mode has changed.
            selected = {
                ownCount: 0,
                count: 0,
                collectionID: 0,
                context:
                    mode == "people"
                        ? { mode, personID: activePersonID! }
                        : { mode, collectionID: activeCollectionID },
            };
        } else {
            if (selected.context.mode == "people") {
                if (selected.context.personID != activePersonID) {
                    // Clear selection if person has changed.
                    selected = {
                        ownCount: 0,
                        count: 0,
                        collectionID: 0,
                        context: {
                            mode: selected.context.mode,
                            personID: activePersonID!,
                        },
                    };
                }
            } else {
                if (selected.context.collectionID != activeCollectionID) {
                    // Clear selection if collection has changed.
                    selected = {
                        ownCount: 0,
                        count: 0,
                        collectionID: 0,
                        context: {
                            mode: selected.context.mode,
                            collectionID: activeCollectionID,
                        },
                    };
                }
            }
        }
    }

    const newContext: SelectionContext | undefined = !mode
        ? undefined
        : mode == "people"
          ? { mode, personID: activePersonID! }
          : { mode, collectionID: activeCollectionID };

    return { selected, newContext };
};
