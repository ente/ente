import { expect, test, vi } from "vitest";
import {
    collectUploadCandidatesFromDrop,
    type DragDataTransferItem,
} from "../src/components/create-item/scan-dropped-files";
import { LOCKER_MAX_FILE_SIZE_BYTES } from "../src/services/locker-limits";

const allowance = { remainingFileCount: 10, freeStorage: 100 };
const file = (name: string, size = 1) =>
    new File(["x".repeat(size)], name, { lastModified: 1 });
const fileEntry = (value: File) =>
    ({
        isFile: true,
        isDirectory: false,
        name: value.name,
        file: (resolve: (file: File) => void) => resolve(value),
    }) as unknown as FileSystemEntry;
const directory = (name: string, batches: FileSystemEntry[][]) =>
    ({
        isFile: false,
        isDirectory: true,
        name,
        createReader: () => {
            let index = 0;
            return {
                readEntries: (resolve: (entries: FileSystemEntry[]) => void) =>
                    resolve(batches[index++] ?? []),
            };
        },
    }) as unknown as FileSystemEntry;
const droppedEntry = (entry: FileSystemEntry) =>
    ({ kind: "file", webkitGetAsEntry: () => entry }) as DragDataTransferItem;

test("reads every directory batch in order and preserves nested paths", async () => {
    const root = directory("root", [
        [
            fileEntry(file("first")),
            directory("child", [[fileEntry(file("second"))]]),
        ],
        [fileEntry(file("third"))],
    ]);
    const result = await collectUploadCandidatesFromDrop(
        [droppedEntry(root)],
        [],
        allowance,
    );
    expect(
        result.items.map(({ relativePath, suggestedCollectionNames }) => ({
            relativePath,
            suggestedCollectionNames,
        })),
    ).toEqual([
        { relativePath: "root/first", suggestedCollectionNames: ["root"] },
        {
            relativePath: "root/child/second",
            suggestedCollectionNames: ["root", "child"],
        },
        { relativePath: "root/third", suggestedCollectionNames: ["root"] },
    ]);
    expect(result.scannedNonEmptyFileCount).toBe(3);
    expect(result.scannedTotalSize).toBe(3);
});

test("fallback skips empty files and duplicate path/size/timestamp entries", async () => {
    const result = await collectUploadCandidatesFromDrop(
        [],
        [file("empty", 0), file("same"), file("same"), file("last")],
        allowance,
    );
    expect(result.items.map(({ file }) => file.name)).toEqual(["same", "last"]);
    expect(result.scannedNonEmptyFileCount).toBe(2);
    expect(result.scannedTotalSize).toBe(2);
});

test("uses getAsFile without also ingesting fallback files", async () => {
    const value = file("selected");
    const item = {
        kind: "file",
        getAsFile: () => value,
    } as DragDataTransferItem;
    const result = await collectUploadCandidatesFromDrop(
        [item],
        [file("fallback")],
        allowance,
    );
    expect(result.items.map(({ file }) => file.name)).toEqual(["selected"]);
});

test.each([
    {
        options: { remainingFileCount: 1, freeStorage: 100 },
        reason: "fileCountLimit",
        count: 2,
        size: 1,
    },
    {
        options: { remainingFileCount: 10, freeStorage: 1 },
        reason: "storageLimit",
        count: 2,
        size: 2,
    },
])("stops scanning at $reason", async ({ options, reason, count, size }) => {
    const unread = vi.fn();
    const later = { isFile: true, file: unread } as unknown as FileSystemEntry;
    const result = await collectUploadCandidatesFromDrop(
        [
            droppedEntry(fileEntry(file("first"))),
            droppedEntry(fileEntry(file("second"))),
            droppedEntry(later),
        ],
        [],
        options,
    );
    expect(result.preflightFailure).toEqual({ reason });
    expect(result.items).toHaveLength(1);
    expect(result.scannedNonEmptyFileCount).toBe(count);
    expect(result.scannedTotalSize).toBe(size);
    expect(unread).not.toHaveBeenCalled();
});

test("rejects oversized files before counting them", async () => {
    const oversized = file("large");
    Object.defineProperty(oversized, "size", {
        value: LOCKER_MAX_FILE_SIZE_BYTES + 1,
    });
    const result = await collectUploadCandidatesFromDrop(
        [],
        [oversized],
        allowance,
    );
    expect(result).toEqual({
        items: [],
        preflightFailure: { reason: "fileTooLarge", fileName: "large" },
        scannedNonEmptyFileCount: 0,
        scannedTotalSize: 0,
    });
});

test("accepts exact count and storage boundaries", async () => {
    const result = await collectUploadCandidatesFromDrop([], [file("one")], {
        remainingFileCount: 1,
        freeStorage: 1,
    });
    expect(result.preflightFailure).toBeUndefined();
    expect(result.items).toHaveLength(1);
});

test("propagates directory read failures", async () => {
    const failure = new DOMException("Cannot read directory");
    const entry = {
        isDirectory: true,
        name: "blocked",
        createReader: () => ({
            readEntries: (
                _resolve: unknown,
                reject: (error: DOMException) => void,
            ) => reject(failure),
        }),
    } as unknown as FileSystemEntry;
    await expect(
        collectUploadCandidatesFromDrop([droppedEntry(entry)], [], allowance),
    ).rejects.toBe(failure);
});
