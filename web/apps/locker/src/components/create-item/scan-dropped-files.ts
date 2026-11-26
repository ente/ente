import type { LockerUploadCandidate } from "@/types";
import {
    LOCKER_MAX_FILE_SIZE_BYTES,
    type LockerUploadPreflightFailure,
} from "../../services/locker-limits";

export type DragDataTransferItem = DataTransferItem & {
    webkitGetAsEntry?: () => FileSystemEntry | null;
};

type FileSystemFileEntry = FileSystemEntry & {
    file: (
        successCallback: (file: File) => void,
        errorCallback?: (error: DOMException) => void,
    ) => void;
};

interface FileSystemDirectoryReader {
    readEntries: (
        successCallback: (entries: FileSystemEntry[]) => void,
        errorCallback?: (error: DOMException) => void,
    ) => void;
}

type FileSystemDirectoryEntry = FileSystemEntry & {
    createReader: () => FileSystemDirectoryReader;
};

const fileFromEntry = (entry: FileSystemFileEntry) =>
    new Promise<File>((resolve, reject) => {
        entry.file(resolve, reject);
    });

const readDirectoryEntries = (entry: FileSystemDirectoryEntry) =>
    new Promise<FileSystemEntry[]>((resolve, reject) => {
        const reader = entry.createReader();
        const entries: FileSystemEntry[] = [];
        const readBatch = () => {
            reader.readEntries((batch) => {
                if (batch.length === 0) {
                    resolve(entries);
                    return;
                }
                entries.push(...batch);
                readBatch();
            }, reject);
        };
        readBatch();
    });

const collectionNamesFromRelativePath = (relativePath?: string) => [
    ...new Set((relativePath?.split("/").slice(0, -1) ?? []).filter(Boolean)),
];

const uploadCandidateFromFile = (
    file: File,
    relativePath?: string,
): LockerUploadCandidate => ({
    file,
    relativePath,
    suggestedCollectionNames: collectionNamesFromRelativePath(relativePath),
});

const droppedUploadCandidateKey = (file: File, relativePath?: string) =>
    `${relativePath ?? file.name}:${file.size}:${file.lastModified}`;

interface DropUploadScanOptions {
    remainingFileCount: number;
    freeStorage: number;
}

interface DropUploadScanResult {
    items: LockerUploadCandidate[];
    preflightFailure?: LockerUploadPreflightFailure;
    scannedNonEmptyFileCount: number;
    scannedTotalSize: number;
}

type PendingDroppedNode =
    | { type: "entry"; entry: FileSystemEntry; parentPath: string }
    | { type: "file"; file: File; relativePath: string };

export const collectUploadCandidatesFromDrop = async (
    droppedItems: DragDataTransferItem[],
    fallbackFiles: File[],
    options: DropUploadScanOptions,
): Promise<DropUploadScanResult> => {
    const items: LockerUploadCandidate[] = [];
    const pendingNodes: PendingDroppedNode[] = [];
    const seenUploadCandidateKeys = new Set<string>();
    let scannedNonEmptyFileCount = 0;
    let scannedTotalSize = 0;

    const addFile = (
        file: File,
        relativePath: string,
    ): LockerUploadPreflightFailure | undefined => {
        if (file.size === 0) {
            return undefined;
        }

        const dedupeKey = droppedUploadCandidateKey(file, relativePath);
        if (seenUploadCandidateKeys.has(dedupeKey)) {
            return undefined;
        }
        seenUploadCandidateKeys.add(dedupeKey);

        if (file.size > LOCKER_MAX_FILE_SIZE_BYTES) {
            return { reason: "fileTooLarge", fileName: file.name };
        }

        scannedNonEmptyFileCount += 1;
        if (scannedNonEmptyFileCount > options.remainingFileCount) {
            return { reason: "fileCountLimit" };
        }

        scannedTotalSize += file.size;
        if (scannedTotalSize > options.freeStorage) {
            return { reason: "storageLimit" };
        }

        items.push(uploadCandidateFromFile(file, relativePath));
        return undefined;
    };

    for (let index = droppedItems.length - 1; index >= 0; index -= 1) {
        const item = droppedItems[index]!;
        if (item.kind !== "file") {
            continue;
        }

        const getAsEntry = item.webkitGetAsEntry;
        const entry =
            typeof getAsEntry === "function" ? getAsEntry.call(item) : null;
        if (entry) {
            pendingNodes.push({ type: "entry", entry, parentPath: "" });
            continue;
        }

        const file = item.getAsFile();
        if (file) {
            pendingNodes.push({
                type: "file",
                file,
                relativePath: file.webkitRelativePath || file.name,
            });
        }
    }

    if (pendingNodes.length === 0) {
        for (const file of fallbackFiles) {
            const preflightFailure = addFile(
                file,
                file.webkitRelativePath || file.name,
            );
            if (preflightFailure) {
                return {
                    items,
                    preflightFailure,
                    scannedNonEmptyFileCount,
                    scannedTotalSize,
                };
            }
        }
        return { items, scannedNonEmptyFileCount, scannedTotalSize };
    }

    while (pendingNodes.length > 0) {
        const node = pendingNodes.pop()!;

        if (node.type === "file") {
            const preflightFailure = addFile(node.file, node.relativePath);
            if (preflightFailure) {
                return {
                    items,
                    preflightFailure,
                    scannedNonEmptyFileCount,
                    scannedTotalSize,
                };
            }
            continue;
        }

        if (node.entry.isFile) {
            const file = await fileFromEntry(node.entry as FileSystemFileEntry);
            const relativePath = node.parentPath
                ? `${node.parentPath}/${file.name}`
                : file.name;
            const preflightFailure = addFile(file, relativePath);
            if (preflightFailure) {
                return {
                    items,
                    preflightFailure,
                    scannedNonEmptyFileCount,
                    scannedTotalSize,
                };
            }
            continue;
        }

        if (node.entry.isDirectory) {
            const directoryPath = node.parentPath
                ? `${node.parentPath}/${node.entry.name}`
                : node.entry.name;
            const directoryEntries = await readDirectoryEntries(
                node.entry as FileSystemDirectoryEntry,
            );
            for (
                let index = directoryEntries.length - 1;
                index >= 0;
                index -= 1
            ) {
                pendingNodes.push({
                    type: "entry",
                    entry: directoryEntries[index]!,
                    parentPath: directoryPath,
                });
            }
        }
    }

    return { items, scannedNonEmptyFileCount, scannedTotalSize };
};
