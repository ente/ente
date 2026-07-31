export type LlmRole = "system" | "user" | "assistant";

export interface LlmMessage {
    role: LlmRole;
    content: string;
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
    maxTokens?: number;
}

export interface ModelSettings {
    modelId?: string;
    contextLength?: number;
    maxTokens?: number;
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
}
