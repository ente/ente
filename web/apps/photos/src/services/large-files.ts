import { ensureLocalUser } from "ente-accounts/services/user";
import { newID } from "ente-base/id";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import {
    moveToTrash,
    savedNormalCollections,
} from "ente-new/photos/services/collection";
import { savedCollectionFiles } from "ente-new/photos/services/photos-fdb";
import { pullFiles } from "./pull";

// Keep the 10 MB threshold aligned with mobile.
const MIN_LARGE_FILE_SIZE = 10 * 1024 * 1024;

export type LargeFileFilter = "all" | "photos" | "videos";

export interface LargeFileItem {
    id: string;
    file: EnteFile;
    size: number;
    isSelected: boolean;
}

export const findLargeFiles = async (
    filter: LargeFileFilter,
): Promise<LargeFileItem[]> => {
    const userID = ensureLocalUser().id;

    const normalCollections = await savedNormalCollections();
    const normalOwnedCollections = normalCollections.filter(
        ({ owner }) => owner.id === userID,
    );
    const allowedCollectionIDs = new Set(
        normalOwnedCollections.map(({ id }) => id),
    );

    const collectionFiles = await savedCollectionFiles();

    const seenFileIDs = new Set<number>();
    const largeFiles: LargeFileItem[] = [];

    for (const file of collectionFiles) {
        if (!allowedCollectionIDs.has(file.collectionID)) continue;

        if (file.ownerID !== userID) continue;

        if (seenFileIDs.has(file.id)) continue;

        const size = file.info?.fileSize;
        if (!size || size < MIN_LARGE_FILE_SIZE) continue;

        if (!matchesFilter(file, filter)) continue;

        seenFileIDs.add(file.id);

        largeFiles.push({ id: newID("lf_"), file, size, isSelected: false });
    }

    largeFiles.sort((a, b) => b.size - a.size);

    return largeFiles;
};

const matchesFilter = (file: EnteFile, filter: LargeFileFilter): boolean => {
    switch (filter) {
        case "all":
            return true;
        case "photos":
            return (
                file.metadata.fileType === FileType.image ||
                file.metadata.fileType === FileType.livePhoto
            );
        case "videos":
            return file.metadata.fileType === FileType.video;
    }
};

export const deleteSelectedLargeFiles = async (
    largeFiles: LargeFileItem[],
    onProgress: (progress: number) => void,
): Promise<Set<string>> => {
    const selectedItems = largeFiles.filter((item) => item.isSelected);
    const filesToTrash = selectedItems.map((item) => item.file);

    if (filesToTrash.length === 0) {
        return new Set();
    }

    let completedSteps = 0;
    const totalSteps = 2;
    const tickProgress = () =>
        onProgress((++completedSteps / totalSteps) * 100);

    await moveToTrash(filesToTrash);
    tickProgress();

    await pullFiles();
    tickProgress();

    return new Set(selectedItems.map((item) => item.id));
};

type SortOrder = "desc" | "asc";

interface LargeFilesState {
    analysisStatus: undefined | "started" | "failed" | "completed";
    largeFiles: LargeFileItem[];
    filter: LargeFileFilter;
    sortOrder: SortOrder;
    selectedCount: number;
    selectedSize: number;
    deleteProgress: number | undefined;
    // Persists selection across filters.
    selectedFileIDs: Set<number>;
}

type LargeFilesAction =
    | { type: "analyze" }
    | { type: "analysisFailed" }
    | { type: "analysisCompleted"; largeFiles: LargeFileItem[] }
    | { type: "changeFilter"; filter: LargeFileFilter }
    | { type: "changeSortOrder"; sortOrder: SortOrder }
    | { type: "toggleSelection"; index: number }
    | { type: "deselectAll" }
    | { type: "selectAll" }
    | { type: "delete" }
    | { type: "setDeleteProgress"; progress: number }
    | { type: "deleteFailed" }
    | { type: "deleteCompleted"; removedIDs: Set<string> };

export const largeFilesInitialState: LargeFilesState = {
    analysisStatus: undefined,
    largeFiles: [],
    filter: "all",
    sortOrder: "desc",
    selectedCount: 0,
    selectedSize: 0,
    deleteProgress: undefined,
    selectedFileIDs: new Set(),
};

export const largeFilesReducer = (
    state: LargeFilesState,
    action: LargeFilesAction,
): LargeFilesState => {
    switch (action.type) {
        case "analyze":
            return { ...state, analysisStatus: "started" };
        case "analysisFailed":
            return { ...state, analysisStatus: "failed" };
        case "analysisCompleted": {
            const selectedFileIDs = state.selectedFileIDs;
            const filesWithSelection = action.largeFiles.map((item) => ({
                ...item,
                isSelected: selectedFileIDs.has(item.file.id),
            }));
            const largeFiles = sortedCopyOfLargeFiles(
                filesWithSelection,
                state.sortOrder,
            );
            const { selectedCount, selectedSize } =
                computeSelectedCountAndSize(largeFiles);
            return {
                ...state,
                analysisStatus: "completed",
                largeFiles,
                selectedCount,
                selectedSize,
            };
        }

        case "changeFilter": {
            if (action.filter === state.filter) {
                return state;
            }
            // Do not change the visible set during deletion.
            if (state.deleteProgress !== undefined) {
                return state;
            }
            return {
                ...largeFilesInitialState,
                filter: action.filter,
                sortOrder: state.sortOrder,
                selectedFileIDs: state.selectedFileIDs,
            };
        }

        case "changeSortOrder": {
            // Do not change the visible set during deletion.
            if (state.deleteProgress !== undefined) {
                return state;
            }
            const sortOrder = action.sortOrder;
            const largeFiles = sortedCopyOfLargeFiles(
                state.largeFiles,
                sortOrder,
            );
            return { ...state, sortOrder, largeFiles };
        }

        case "toggleSelection": {
            const index = action.index;
            if (index < 0 || index >= state.largeFiles.length) {
                return state;
            }
            const item = state.largeFiles[index]!;
            const newIsSelected = !item.isSelected;
            const largeFiles = state.largeFiles.map((file, i) =>
                i === index ? { ...file, isSelected: newIsSelected } : file,
            );
            const selectedFileIDs = new Set(state.selectedFileIDs);
            if (newIsSelected) {
                selectedFileIDs.add(item.file.id);
            } else {
                selectedFileIDs.delete(item.file.id);
            }
            const { selectedCount, selectedSize } =
                computeSelectedCountAndSize(largeFiles);
            return {
                ...state,
                largeFiles,
                selectedCount,
                selectedSize,
                selectedFileIDs,
            };
        }

        case "deselectAll": {
            const visibleFileIDs = new Set(
                state.largeFiles.map((item) => item.file.id),
            );
            const selectedFileIDs = new Set<number>();
            for (const id of state.selectedFileIDs) {
                if (!visibleFileIDs.has(id)) {
                    selectedFileIDs.add(id);
                }
            }
            const largeFiles = state.largeFiles.map((item) => ({
                ...item,
                isSelected: false,
            }));
            return {
                ...state,
                largeFiles,
                selectedCount: 0,
                selectedSize: 0,
                selectedFileIDs,
            };
        }

        case "selectAll": {
            const largeFiles = state.largeFiles.map((item) => ({
                ...item,
                isSelected: true,
            }));
            const selectedFileIDs = new Set(state.selectedFileIDs);
            for (const item of largeFiles) {
                selectedFileIDs.add(item.file.id);
            }
            const { selectedCount, selectedSize } =
                computeSelectedCountAndSize(largeFiles);
            return {
                ...state,
                largeFiles,
                selectedCount,
                selectedSize,
                selectedFileIDs,
            };
        }

        case "delete":
            return { ...state, deleteProgress: 0 };

        case "setDeleteProgress":
            return { ...state, deleteProgress: action.progress };

        case "deleteFailed":
            return { ...state, deleteProgress: undefined };

        case "deleteCompleted": {
            const largeFiles: LargeFileItem[] = [];
            const removedFileIDs = new Set<number>();
            for (const item of state.largeFiles) {
                if (action.removedIDs.has(item.id)) {
                    removedFileIDs.add(item.file.id);
                } else {
                    largeFiles.push(item);
                }
            }
            const selectedFileIDs = new Set<number>();
            for (const id of state.selectedFileIDs) {
                if (!removedFileIDs.has(id)) {
                    selectedFileIDs.add(id);
                }
            }
            const { selectedCount, selectedSize } =
                computeSelectedCountAndSize(largeFiles);
            return {
                ...state,
                largeFiles,
                selectedCount,
                selectedSize,
                deleteProgress: undefined,
                selectedFileIDs,
            };
        }
    }
};

const computeSelectedCountAndSize = (largeFiles: LargeFileItem[]) => {
    const selectedCount = largeFiles.reduce(
        (sum, { isSelected }) => sum + (isSelected ? 1 : 0),
        0,
    );
    const selectedSize = largeFiles.reduce(
        (sum, { size, isSelected }) => sum + (isSelected ? size : 0),
        0,
    );
    return { selectedCount, selectedSize };
};

const sortedCopyOfLargeFiles = (
    largeFiles: LargeFileItem[],
    sortOrder: SortOrder,
) =>
    [...largeFiles].sort((a, b) =>
        sortOrder === "desc" ? b.size - a.size : a.size - b.size,
    );
