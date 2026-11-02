import type { SelectedState } from "@/utils/file";
import type { EnteFile } from "ente-media/file";

export const emptySelection: SelectedState = {
    ownCount: 0,
    count: 0,
    collectionID: undefined,
    context: undefined,
};

export const retainVisibleSelection = (
    selected: SelectedState,
    files: EnteFile[],
    userID: number | undefined,
): SelectedState => {
    if (!selected.count) return selected;
    const next: SelectedState = {
        ...emptySelection,
        collectionID: selected.collectionID,
        context: selected.context,
    };
    for (const file of files) {
        if (!selected[file.id] || next[file.id]) continue;
        next[file.id] = true;
        next.count++;
        if (file.ownerID === userID) next.ownCount++;
    }
    return next.count === selected.count && next.ownCount === selected.ownCount
        ? selected
        : next;
};
