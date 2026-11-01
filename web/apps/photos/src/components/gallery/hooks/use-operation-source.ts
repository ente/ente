import { useEffect, useMemo } from "react";
import type {
    GalleryMediaSource,
    GallerySectionOperations,
} from "../section-types";

export const useOperationSource = (
    source: GalleryMediaSource | undefined,
    setSource: GallerySectionOperations["setMediaSource"],
) => {
    const files = source?.files;
    const mode = source?.mode;
    const modePlus = source?.modePlus;
    const activeCollectionID = source?.activeCollectionID;
    const activeCollection = source?.activeCollection;
    const activeCollectionSummary = source?.activeCollectionSummary;
    const activePersonID = source?.activePersonID;
    const disableGrouping = source?.disableGrouping;
    const current = useMemo(
        () =>
            files
                ? {
                      files,
                      mode,
                      modePlus,
                      activeCollectionID,
                      activeCollection,
                      activeCollectionSummary,
                      activePersonID,
                      disableGrouping,
                  }
                : undefined,
        [
            files,
            mode,
            modePlus,
            activeCollectionID,
            activeCollection,
            activeCollectionSummary,
            activePersonID,
            disableGrouping,
        ],
    );
    useEffect(() => {
        if (!current) return;
        setSource(current);
        return () =>
            setSource((previous) =>
                previous === current ? undefined : previous,
            );
    }, [current, setSource]);
};
