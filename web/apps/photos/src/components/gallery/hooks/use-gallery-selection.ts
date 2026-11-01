import type { SelectedState } from "@/utils/file";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { useCallback, useState } from "react";
import type { GalleryMediaSource } from "../section-types";

export const useGallerySelection = () => {
    const [mediaSource, setMediaSource] = useState<GalleryMediaSource>();
    const [selected, setSelected] = useState<SelectedState>({
        ownCount: 0,
        count: 0,
        collectionID: 0,
        context: { mode: "albums", collectionID: PseudoCollectionID.all },
    });
    const clearSelection = useCallback(() => {
        setSelected((previous) =>
            previous.count
                ? { ownCount: 0, count: 0, collectionID: 0, context: undefined }
                : previous,
        );
    }, []);
    return {
        selected,
        setSelected,
        clearSelection,
        mediaSource,
        setMediaSource,
    };
};
