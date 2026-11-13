// TODO: Audit this file
import type {
    SelectedState,
    SetSelectedState,
} from "@/public-album/utils/file";

export const handleSelectCreator =
    (
        setSelected: SetSelectedState,
        setRangeStartIndex: (index: number | undefined) => void,
    ) =>
    ({ id }: { id: number }, index?: number) =>
    (checked: boolean) => {
        if (typeof index != "undefined") {
            if (checked) {
                setRangeStartIndex(index);
            } else {
                setRangeStartIndex(undefined);
            }
        }
        setSelected((selected) => {
            return {
                ...selected,
                [id]: checked,
                count: nextSelectedCount(selected, id, checked),
            };
        });
    };

export const handleSelectCreatorMulti =
    (setSelected: SetSelectedState) =>
    (files: { id: number }[]) =>
    (checked: boolean) => {
        setSelected((selected) => {
            const newSelected = { ...selected };
            let newCount = selected.count;

            if (checked) {
                for (const file of files) {
                    if (!newSelected[file.id]) {
                        newSelected[file.id] = true;
                        newCount++;
                    }
                }
            } else {
                for (const file of files) {
                    if (newSelected[file.id]) {
                        newSelected[file.id] = false;
                        newCount--;
                    }
                }
            }

            return { ...newSelected, count: newCount };
        });
    };

const nextSelectedCount = (
    selected: SelectedState,
    id: number,
    checked: boolean,
) => {
    if (selected[id] === checked) {
        return selected.count;
    }
    if (checked) {
        return selected.count + 1;
    }
    return selected.count - 1;
};
