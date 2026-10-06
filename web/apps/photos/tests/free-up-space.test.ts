import { expect, test } from "vitest";
import type { DuplicateGroup } from "../src/services/dedup";
import { summarizeFreeUpSpace } from "../src/services/free-up-space";
import type { LargeFileItem } from "../src/services/large-files";

test("cleanup summary counts overlapping large duplicates only once", () => {
    const largeFiles = [
        { file: { id: 1 }, size: 100 },
        { file: { id: 2 }, size: 100 },
        { file: { id: 3 }, size: 200 },
    ] as LargeFileItem[];
    const groups = [
        {
            items: [{ file: { id: 1 } }, { file: { id: 2 } }],
            prunableSize: 100,
        },
        { items: [{ file: { id: 4 } }, { file: { id: 5 } }], prunableSize: 5 },
    ] as DuplicateGroup[];
    expect(summarizeFreeUpSpace(largeFiles, groups)).toEqual({
        largeFileCount: 3,
        largeFileSize: 400,
        duplicateGroupCount: 2,
        duplicateSize: 105,
        reclaimableSize: 405,
    });
    expect(summarizeFreeUpSpace([], []).reclaimableSize).toBe(0);
    expect(summarizeFreeUpSpace([], groups).reclaimableSize).toBe(105);
});
