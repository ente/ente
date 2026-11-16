type LlmRole = "system" | "user" | "assistant" | "tool";

/** A tool call the model made, as returned by the native layer. */
export interface LlmToolCall {
    name: string;
    arguments: Record<string, string | number>;
}

/**
 * Tool declarations built by the native layer. The web layer only passes
 * them back with the generation request, so the shape stays opaque here.
 */
export type LlmToolRequest = Record<string, unknown>;

export interface LlmToolOutcome {
    calls: LlmToolCall[];
    call_probability: number | null;
    supported: boolean;
}

export interface LlmMessage {
    role: LlmRole;
    content: string;
    tool_calls?: LlmToolCall[];
}

export interface ModelInfo {
    id: string;
    name: string;
    url: string;
    sha256: string;
    mmprojUrl?: string;
    mmprojSha256?: string;
    sizeHuman?: string;
    sizeBytes?: number;
    mmprojSizeBytes?: number;
    contextLength?: number;
}

export interface ModelSettings {
    modelId?: string;
    contextLength?: number;
}

export interface DownloadProgress {
    percent: number;
    status?: string;
    bytesDownloaded?: number;
    totalBytes?: number;
}

export interface GenerateSummary {
    job_id: number;
    prompt_tokens: number | null;
    generated_tokens: number | null;
    total_time_ms: number | null;
    tools?: LlmToolOutcome | null;
}

export type GenerateEvent =
    | { type: "text"; job_id: number; text: string; token_id?: number | null }
    | { type: "done"; summary: GenerateSummary };

export interface GenerateChatRequest {
    messages: LlmMessage[];
    templateOverride?: string;
    addAssistant?: boolean;
    imagePaths?: string[];
    mmprojPath?: string;
    mediaMarker?: string;
    maxTokens?: number;
    temperature?: number;
    topP?: number;
    topK?: number;
    repeatPenalty?: number;
    frequencyPenalty?: number;
    presencePenalty?: number;
    seed?: number;
    stopSequences?: string[];
    grammar?: string;
    tools?: LlmToolRequest;
    preparationToken?: string;
}
