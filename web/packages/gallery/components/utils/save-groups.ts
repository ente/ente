import { useSyncExternalStore } from "react";

// "Save" here means a user-initiated download, not a cache or viewer fetch.
export interface SaveGroup {
    id: number;
    retry?: () => void;
    title: string;
    collectionSummaryID?: number;
    isHiddenCollectionSummary?: boolean;
    downloadDirPath?: string;
    total: number;
    success: number;
    failed: number;
    canceller: AbortController;
    failureReason?: "network_offline" | "file_error";
    includeZipNumber?: boolean;
    isDownloadingZip?: boolean;
    currentPart?: number;
}

export const isSaveComplete = ({ total, success, failed }: SaveGroup) =>
    total == success + failed;

export const isSaveCompleteWithErrors = (group: SaveGroup) =>
    group.failed > 0 && isSaveComplete(group);

export const isSaveCancelled = (group: SaveGroup) =>
    group.canceller.signal.aborted;

export type AddSaveGroup = (
    group: Pick<
        SaveGroup,
        | "title"
        | "collectionSummaryID"
        | "isHiddenCollectionSummary"
        | "downloadDirPath"
        | "total"
        | "includeZipNumber"
        | "canceller"
        | "retry"
    >,
) => UpdateSaveGroup;

export type UpdateSaveGroup = (
    tranform: (prev: SaveGroup) => SaveGroup,
) => void;

type RemoveSaveGroup = (saveGroup: SaveGroup) => void;

// Module state lets route remounts rehydrate in-progress downloads.
type SaveGroupsListener = () => void;

let saveGroupsSnapshot: SaveGroup[] = [];
const listeners = new Set<SaveGroupsListener>();

const emitChange = () => {
    for (const listener of listeners) listener();
};

const getSnapshot = () => saveGroupsSnapshot;

const subscribe = (listener: SaveGroupsListener) => {
    listeners.add(listener);
    return () => {
        listeners.delete(listener);
    };
};

const setSaveGroupsSnapshot = (
    next: SaveGroup[] | ((currentSaveGroups: SaveGroup[]) => SaveGroup[]),
) => {
    saveGroupsSnapshot =
        typeof next == "function" ? next(saveGroupsSnapshot) : next;
    emitChange();
};

const addSaveGroup: AddSaveGroup = (saveGroup) => {
    const id = Math.random();
    setSaveGroupsSnapshot((groups) => [
        ...groups,
        { ...saveGroup, id, success: 0, failed: 0 },
    ]);

    return (tx: (group: SaveGroup) => SaveGroup) => {
        setSaveGroupsSnapshot((groups) =>
            groups.map((g) => (g.id == id ? tx(g) : g)),
        );
    };
};

const removeSaveGroup: RemoveSaveGroup = ({ id }) =>
    setSaveGroupsSnapshot((groups) => groups.filter((g) => g.id != id));

export const resetSaveGroups = () => {
    if (!saveGroupsSnapshot.length) return;

    saveGroupsSnapshot = [];
    emitChange();
};

export const useSaveGroups = () => {
    const saveGroups = useSyncExternalStore(
        subscribe,
        getSnapshot,
        getSnapshot,
    );

    return {
        saveGroups,
        onAddSaveGroup: addSaveGroup,
        onRemoveSaveGroup: removeSaveGroup,
    };
};

// Avoid subscribing action-only callers to frequent progress updates.
export const useSaveGroupsActions = () => ({
    onAddSaveGroup: addSaveGroup,
    onRemoveSaveGroup: removeSaveGroup,
});
