import type { CollectionPublicMagicMetadataData } from "./collection";
import type { EnteFile } from "./file";
import { fileCreationPhotoSortTime, fileFileName } from "./file-metadata";

export type CollectionSortBy = "date" | "name";

type SortMetadata = Pick<CollectionPublicMagicMetadataData, "sortBy" | "asc">;

const filenameCollator = new Intl.Collator(undefined, {
    numeric: true,
    sensitivity: "base",
});

export const sortCollectionFiles = (
    files: EnteFile[],
    metadata?: SortMetadata,
): EnteFile[] => {
    // ponytail: reuse the date sorter so legacy ordering has one implementation.
    if (metadata?.sortBy !== "name")
        return sortFiles([...files], metadata?.asc);
    const direction = metadata.asc ? 1 : -1;
    return [...files].sort(
        (a, b) =>
            direction *
                filenameCollator.compare(fileFileName(a), fileFileName(b)) ||
            a.id - b.id,
    );
};

export const sortFiles = (files: EnteFile[], sortAsc = false) => {
    // Break equal displayed creation dates by modification time.
    const factor = sortAsc ? -1 : 1;
    const sortTimeByFile = new Map<EnteFile, number>();
    const sortTimeForFile = (file: EnteFile) => {
        const cached = sortTimeByFile.get(file);
        if (cached != undefined) return cached;
        const t = fileCreationPhotoSortTime(file);
        sortTimeByFile.set(file, t);
        return t;
    };
    return files.sort((a, b) => {
        const at = sortTimeForFile(a);
        const bt = sortTimeForFile(b);
        return at == bt
            ? factor *
                  (b.metadata.modificationTime - a.metadata.modificationTime)
            : factor * (bt - at);
    });
};
