import type { DuplicateGroup } from "./dedup";
import type { LargeFileItem } from "./large-files";

/** Estimate cleanup space without counting large duplicate files twice. */
export const summarizeFreeUpSpace = (
    largeFiles: LargeFileItem[],
    duplicateGroups: DuplicateGroup[],
) => {
    const largeSizeByID = new Map(
        largeFiles.map(({ file, size }) => [file.id, size]),
    );
    const largeFileSize = largeFiles.reduce((sum, { size }) => sum + size, 0);
    const duplicateSize = duplicateGroups.reduce(
        (sum, { prunableSize }) => sum + prunableSize,
        0,
    );
    const additionalDuplicateSize = duplicateGroups.reduce(
        (sum, { items, prunableSize }) => {
            const overlappingSize = items.reduce(
                (size, { file }) => size + (largeSizeByID.get(file.id) ?? 0),
                0,
            );
            return sum + Math.max(0, prunableSize - overlappingSize);
        },
        0,
    );
    return {
        largeFileCount: largeFiles.length,
        largeFileSize,
        duplicateGroupCount: duplicateGroups.length,
        duplicateSize,
        reclaimableSize: largeFileSize + additionalDuplicateSize,
    };
};
