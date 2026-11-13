import type { SetSelectedState } from "@/utils/file";
import type { EnteFile } from "ente-media/file";
import { useCallback, useMemo, useState } from "react";
import { emptySelection, retainVisibleSelection } from "./file-selection";

export const useGallerySelection = (
    files: EnteFile[],
    userID: number | undefined,
) => {
    const [stored, setStored] = useState({
        value: emptySelection,
        revision: 0,
    });
    const selected = useMemo(
        () => retainVisibleSelection(stored.value, files, userID),
        [stored.value, files, userID],
    );
    if (selected !== stored.value) setStored({ ...stored, value: selected });
    const setSelected = useCallback<SetSelectedState>((update) => {
        setStored((previous) => ({
            value:
                typeof update === "function" ? update(previous.value) : update,
            revision: previous.revision + 1,
        }));
    }, []);
    const revision = stored.revision;
    const clearSelection = useCallback(() => {
        // Data refreshes retain the revision; newer user selections do not.
        setStored((previous) =>
            previous.revision === revision
                ? { value: emptySelection, revision: revision + 1 }
                : previous,
        );
    }, [revision]);
    return { selected, setSelected, clearSelection };
};
