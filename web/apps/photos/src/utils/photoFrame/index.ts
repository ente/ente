// TODO: Audit this file
import type { SelectionContext } from "@/components/gallery";
import type { GalleryBarMode } from "@/components/gallery/reducer";
import type { SelectedState, SetSelectedState } from "@/utils/file";
import { emptySelection } from "../../components/gallery/media/file-selection";

// TODO: All this is unnecessarily complex, and needs reworking.
export const handleSelectCreator =
    (
        setSelected: SetSelectedState,
        mode: GalleryBarMode | undefined,
        userID: number | undefined,
        activeCollectionID: number | undefined,
        activePersonIDs: string[] | undefined,
        setRangeStartIndex: (index: number | undefined) => void,
        peopleOnlyThem = false,
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
                activePersonIDs,
                _selected,
                peopleOnlyThem,
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
        activeCollectionID: number | undefined,
        activePersonIDs: string[] | undefined,
        peopleOnlyThem = false,
    ) =>
    (files: { id: number; ownerID: number }[]) =>
    (checked: boolean) => {
        setSelected((_selected) => {
            const { selected, newContext } = createSelectedAndContext(
                mode,
                activeCollectionID,
                activePersonIDs,
                _selected,
                peopleOnlyThem,
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

    activeCollectionID: number | undefined,
    activePersonIDs: string[] | undefined,
    selected: SelectedState,
    peopleOnlyThem: boolean,
) => {
    if (mode === "links")
        return { selected: emptySelection, newContext: undefined };

    const newContext: SelectionContext | undefined = !mode
        ? undefined
        : mode === "people"
          ? {
                mode,
                personIDs: activePersonIDs ?? [],
                onlyThem: peopleOnlyThem || undefined,
            }
          : { mode, collectionID: activeCollectionID };

    const previousContext = selected.context;
    let reset = false;
    if (!newContext) {
        reset = selected.collectionID !== activeCollectionID;
    } else if (previousContext) {
        if (previousContext.mode !== newContext.mode) {
            reset = true;
        } else if (
            previousContext.mode === "people" &&
            newContext.mode === "people"
        ) {
            reset =
                JSON.stringify(previousContext.personIDs) !==
                    JSON.stringify(newContext.personIDs) ||
                !!previousContext.onlyThem !== peopleOnlyThem;
        } else if (previousContext.mode !== "people") {
            reset = previousContext.collectionID !== activeCollectionID;
        }
    }
    return { selected: reset ? emptySelection : selected, newContext };
};
