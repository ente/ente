import { tauriCommandError } from "@/services/tauri-error";
import { isTauriRuntime } from "@/services/tauri-runtime";

type KnowledgePackStatus = "download" | "ready" | "updateAvailable";

interface KnowledgeAttribution {
    credit: string;
    licenseLabel: string;
    licenseUrl: string;
    publicPackUrl: string;
    modificationNotice: string;
}

export interface KnowledgePack {
    stableId: string;
    label: string;
    downloadSizeBytes: number;
    status: KnowledgePackStatus;
    attribution: KnowledgeAttribution;
}

interface SourceCitation {
    datasetId: string;
    datasetLabel: string;
    credit: string;
    title: string;
    sourceUrl: string;
    licenseLabel: string;
    licenseUrl: string;
}

interface NoteSourceReference {
    collectionId: string;
    collectionLabel?: string;
    documentId: string;
    indexedRevision: string;
    title: string;
    section?: string | null;
}

export type GroundedSource =
    | { type: "ensuPack"; citation: SourceCitation }
    | { type: "localNote"; reference: NoteSourceReference };

export interface KnowledgePromptContext {
    text: string;
    sources: GroundedSource[];
    candidates?: unknown;
}

interface KnowledgeDownloadProgress {
    stableId: string;
    percent: number;
}

const invokeKnowledge = async <T>(
    command: string,
    args?: Record<string, unknown>,
) => {
    if (!isTauriRuntime()) {
        throw new Error("Ensu Packs are only available in the desktop app");
    }
    const { invoke } = await import("@tauri-apps/api/core");
    return invoke<T>(command, args);
};

export const loadKnowledgeCatalog = () =>
    invokeKnowledge<KnowledgePack[]>("knowledge_catalog");

export const downloadKnowledgePack = async (
    stableId: string,
    onProgress: (percent: number) => void,
) => {
    const { listen } = await import("@tauri-apps/api/event");
    const unlisten = await listen<KnowledgeDownloadProgress>(
        "knowledge-download-progress",
        (event) => {
            if (event.payload.stableId === stableId) {
                onProgress(event.payload.percent);
            }
        },
    );
    try {
        return await invokeKnowledge<KnowledgePack>("knowledge_download_pack", {
            stableId,
        });
    } finally {
        unlisten();
    }
};

export const cancelKnowledgePackDownload = (stableId: string) =>
    invokeKnowledge("knowledge_cancel_pack_download", { stableId });

export const retrieveKnowledge = (
    query: string,
    enabledStableIds: string[],
    enabledNoteCollectionIds: string[],
    maxContextUtf8Bytes: number,
    retrievalEpoch: number,
) =>
    invokeKnowledge<KnowledgePromptContext | null>("knowledge_retrieve", {
        input: {
            query,
            enabledStableIds,
            enabledNoteCollectionIds,
            maxContextUtf8Bytes,
            retrievalEpoch,
        },
    });

export const knowledgeErrorMessage = (error: unknown) => {
    const { name } = tauriCommandError(error);
    switch (name) {
        case "storage_full":
            return "Not enough storage space to download this knowledge pack.";
        case "network":
            return "Couldn't download the knowledge pack. Check your connection and try again.";
        case "http":
            return "The knowledge pack is currently unavailable. Please try again later.";
        case "validation":
        case "size_mismatch":
        case "protocol":
        case "invalid_pack":
        case "invalid_target":
            return "The knowledge pack couldn't be verified. Please try again.";
        case "io":
            return "Couldn't save the knowledge pack. Please try again.";
        default:
            return "Knowledge pack setup failed. Please try again.";
    }
};
