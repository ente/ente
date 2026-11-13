import { tauriCommandError } from "@/services/tauri-error";
import { isTauriRuntime } from "@/services/tauri-runtime";

export interface NotesCollection {
    id: string;
    label: string;
    status:
        "indexing" | "updating" | "ready" | "pending" | "unavailable" | "error";
    indexingProgress: number | null;
    indexedDocumentCount: number;
    lastUpdatedAtMs: number | null;
    updateDueAtMs: number | null;
    lastError: string | null;
    watcherError: string | null;
}

const invokeNotes = async <T>(
    command: string,
    args?: Record<string, unknown>,
) => {
    if (!isTauriRuntime()) {
        throw new Error("Your Notes is only available in the desktop app");
    }
    const { invoke } = await import("@tauri-apps/api/core");
    return invoke<T>(command, args);
};

export const selectNotesFolder = async () => {
    const { open } = await import("@tauri-apps/plugin-dialog");
    const selected = await open({
        directory: true,
        multiple: false,
        recursive: false,
    });
    return typeof selected === "string" ? selected : null;
};

export const listNotesCollections = () =>
    invokeNotes<NotesCollection[]>("notes_list_collections");

export const addNotesCollection = (sourceRoot: string) =>
    invokeNotes<NotesCollection>("notes_add_collection", { sourceRoot });

export const removeNotesCollection = (collectionId: string) =>
    invokeNotes<null>("notes_remove_collection", { collectionId });

export const indexNotesCollection = (
    collectionId: string,
    force: boolean,
    retrievalEpoch: number,
) =>
    invokeNotes<{ collection: NotesCollection; needsRerun: boolean }>(
        "notes_index_collection",
        { collectionId, force, retrievalEpoch },
    );

export const listenForNotesStateChanged = async (
    onStateChanged: (collection: NotesCollection) => void,
) => {
    const { listen } = await import("@tauri-apps/api/event");
    return listen<NotesCollection>("notes-state-changed", (event) =>
        onStateChanged(event.payload),
    );
};

export const openNoteDocument = (
    collectionId: string,
    documentId: string,
    indexedRevision: string,
) =>
    invokeNotes<null>("notes_open_document", {
        collectionId,
        documentId,
        indexedRevision,
    });

export const notesErrorMessage = (error: unknown) => {
    const { name, message } = tauriCommandError(error);
    switch (name) {
        case "duplicate":
            return "That folder is already in Your Notes.";
        case "nested":
            return "Choose a folder that does not contain another Notes folder.";
        case "invalid_folder":
        case "unavailable":
        case "source_unavailable":
            return "That folder is unavailable. Check its location and permissions.";
        case "embedding_missing":
            return "The knowledge embedding model must be downloaded first.";
        case "collection_too_large":
            return "This folder contains too many notes to index.";
        default:
            return typeof message === "string"
                ? message
                : "Your Notes could not be updated. Please try again.";
    }
};

export const noteSourceErrorMessage = (error: unknown) => {
    const { name } = tauriCommandError(error);
    switch (name) {
        case "open_failed":
            return "The note could not be opened.";
        case "source_changed":
            return "This note changed after the answer was generated.";
        default:
            return "Source no longer available.";
    }
};
