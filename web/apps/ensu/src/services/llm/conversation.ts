import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { finishPreparedReply, type FinishedReply } from "../chat/store";
import type { LlmProvider } from "./provider";
import type { LlmMessage } from "./types";

export interface PreparedReply {
    generateChatStream: LlmProvider["generateChatStream"];
    finish: (text: string) => Promise<FinishedReply>;
}

interface PreparedConversation {
    preparationToken: string;
    messages: LlmMessage[];
}

export const prepareDesktopConversation = async (
    input: {
        sessionUuid: string;
        path: string[];
        system: string;
        current: string;
        historyQuery?: string;
        groundingCandidates?: unknown;
        maxTokens: number;
        resolutionToken?: string;
    },
    provider: Pick<LlmProvider, "generateChatStream">,
    callbacks: { isCurrent: () => boolean; onProgress: () => void },
): Promise<PreparedReply | undefined> => {
    const preparationToken = crypto.randomUUID();
    const cancellationEpoch = await invoke<number>("llm_retrieval_epoch");
    if (!callbacks.isCurrent()) return;
    const unlisten = await listen<{ preparationToken: string }>(
        "conversation-progress",
        ({ payload }) => {
            if (
                payload.preparationToken === preparationToken &&
                callbacks.isCurrent()
            ) {
                callbacks.onProgress();
            }
        },
    );
    try {
        if (!callbacks.isCurrent()) return;
        const result = await invoke<PreparedConversation>(
            "conversation_prepare",
            {
                input: {
                    ...input,
                    expectedUserText: input.current,
                    preparationToken,
                    cancellationEpoch,
                },
            },
        );
        if (!callbacks.isCurrent()) return;
        let saved: Promise<FinishedReply> | undefined;
        return {
            generateChatStream: (request, onEvent) =>
                provider.generateChatStream(
                    {
                        ...request,
                        messages: result.messages,
                        preparationToken: result.preparationToken,
                    },
                    onEvent,
                ),
            finish: (text) =>
                (saved ??= finishPreparedReply(result.preparationToken, text)),
        };
    } finally {
        unlisten();
    }
};

export const resolveDesktopSourceFollowup = (input: {
    sessionUuid: string;
    path: string[];
    question: string;
    enabledStableIds: string[];
    enabledNoteCollectionIds: string[];
    cancellationEpoch: number;
    candidates?: unknown;
}): Promise<string> =>
    invoke<string>("conversation_resolve_followup", {
        input: { ...input, token: crypto.randomUUID() },
    });
