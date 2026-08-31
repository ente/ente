import { isTauriRuntime } from "@/services/tauri-runtime";
import log from "ente-base/log";

const ENABLED_PACKS_STORAGE_KEY = "ensu.desktop.enabledKnowledgePacks";

export type KnowledgePackStatus = "download" | "ready" | "updateAvailable";

export interface KnowledgeAttribution {
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
    status: KnowledgePackStatus | null;
    attribution: KnowledgeAttribution;
}

export interface SourceCitation {
    datasetId: string;
    datasetLabel: string;
    credit: string;
    title: string;
    sourceUrl: string;
    licenseLabel: string;
    licenseUrl: string;
}

export interface KnowledgePromptContext {
    text: string;
    citations: SourceCitation[];
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

export const loadKnowledgeCatalog = (reconcileStableIds?: string[]) =>
    invokeKnowledge<KnowledgePack[]>("knowledge_catalog", {
        reconcileStableIds,
    });

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
    maxContextUtf8Bytes: number,
    retrievalEpoch: number,
) =>
    invokeKnowledge<KnowledgePromptContext | null>("knowledge_retrieve", {
        query,
        enabledStableIds,
        maxContextUtf8Bytes,
        retrievalEpoch,
    });

export const loadEnabledKnowledgePacks = () => {
    if (typeof window === "undefined" || !isTauriRuntime()) {
        return new Set<string>();
    }
    try {
        const raw = window.localStorage.getItem(ENABLED_PACKS_STORAGE_KEY);
        const parsed = raw ? (JSON.parse(raw) as unknown) : [];
        return new Set(
            Array.isArray(parsed)
                ? parsed.filter((value): value is string =>
                      Boolean(typeof value === "string" && value),
                  )
                : [],
        );
    } catch (error) {
        log.warn("Failed to load enabled Ensu Packs", error);
        return new Set<string>();
    }
};

export const saveEnabledKnowledgePacks = (stableIds: Set<string>) => {
    if (typeof window === "undefined") return;
    try {
        window.localStorage.setItem(
            ENABLED_PACKS_STORAGE_KEY,
            JSON.stringify([...stableIds].sort()),
        );
    } catch (error) {
        log.warn("Failed to save enabled Ensu Packs", error);
    }
};

export const knowledgeErrorMessage = (error: unknown) => {
    const record =
        error && typeof error === "object"
            ? (error as { name?: unknown })
            : undefined;
    const name = typeof record?.name === "string" ? record.name : undefined;
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
