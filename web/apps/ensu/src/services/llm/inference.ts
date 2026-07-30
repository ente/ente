import { isTauriRuntime } from "@/services/tauri-runtime";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import type { AssetsPathConfig } from "@wllama/wllama/esm/index.js";
import {
    ModelManager,
    ModelValidationStatus,
    Wllama,
    WllamaAbortError,
} from "@wllama/wllama/esm/index.js";
import wllamaPackage from "@wllama/wllama/package.json";
import log from "ente-base/log";
import type {
    GenerateChatRequest,
    GenerateEvent,
    GenerateSummary,
    LlmMessage,
} from "./types";

const CDN_BASE = `https://cdn.jsdelivr.net/npm/@wllama/wllama@${wllamaPackage.version}/src`;
const MIN_GGUF_BYTES = 1024 * 1024;
const DEFAULT_GENERATION_MAX_TOKENS = 8_192;

export type WasmProgressCallback = (event: {
    loaded: number;
    total?: number;
    status?: string;
}) => void;

export const defaultWasmPaths: AssetsPathConfig = {
    "single-thread/wllama.wasm": `${CDN_BASE}/single-thread/wllama.wasm`,
    "multi-thread/wllama.wasm": `${CDN_BASE}/multi-thread/wllama.wasm`,
};

export type BackendType = "tauri" | "wasm";

export interface InferenceOptions {
    backend?: "auto" | BackendType;
    wasm?: {
        wasmPaths?: Partial<AssetsPathConfig>;
        wllamaConfig?: Record<string, unknown>;
        progressCallback?: WasmProgressCallback;
    };
}

export interface LoadModelParams {
    modelPath: string;
    nGpuLayers?: number | null;
    useMmap?: boolean | null;
    useMlock?: boolean | null;
}

export interface ContextParams {
    contextSize?: number | null;
    nThreads?: number | null;
    nBatch?: number | null;
}

export interface InferenceBackend {
    readonly kind: BackendType;
    initBackend(): Promise<void>;
    loadModel(params: LoadModelParams): Promise<void>;
    createContext(
        model: { modelPath: string },
        params?: ContextParams,
    ): Promise<void>;
    generateChatStream(
        request: GenerateChatRequest,
        onEvent?: (event: GenerateEvent) => void,
    ): Promise<GenerateSummary>;
    prewarmMultimodalContext?(
        mmprojPath: string,
        mediaMarker?: string,
    ): Promise<void>;
    cancel(jobId: number): void;
    freeContext(): Promise<void>;
    freeModel(): Promise<void>;
    isModelAvailable(modelPath: string): Promise<boolean>;
    applyChatTemplate?(
        messages: LlmMessage[],
        templateOverride?: string,
    ): Promise<string>;
}

export const createInferenceBackend = (
    options: InferenceOptions = {},
): InferenceBackend => {
    const backend = options.backend ?? "auto";
    if (backend === "tauri" || (backend === "auto" && isTauriRuntime())) {
        return new TauriInference();
    }
    return new WasmInference(options);
};

class WasmInference implements InferenceBackend {
    public readonly kind: BackendType = "wasm";

    private wllama: Wllama;
    private modelManager = new ModelManager();
    private loadedModelUrl: string | null = null;
    private loadedContextKey: string | null = null;
    private jobCounter = 0;
    private abortControllers = new Map<number, AbortController>();
    private progressCallback?: WasmProgressCallback;

    constructor(options: InferenceOptions = {}) {
        const wasmPaths: AssetsPathConfig = {
            ...defaultWasmPaths,
            ...(options.wasm?.wasmPaths ?? {}),
        };
        const wllamaConfig = options.wasm?.wllamaConfig ?? {};
        this.progressCallback = options.wasm?.progressCallback;
        this.wllama = new Wllama(wasmPaths, wllamaConfig);
    }

    async initBackend() {
        // No-op for WASM backend.
    }

    async loadModel(params: LoadModelParams) {
        const modelUrl = ensureUrl(params.modelPath);
        this.loadedModelUrl = modelUrl;
    }

    async createContext(
        model: { modelPath: string },
        params: ContextParams = {},
    ) {
        const modelUrl = ensureUrl(model.modelPath);
        await this.ensureModelLoaded(modelUrl, params);
    }

    async applyChatTemplate(
        messages: LlmMessage[],
        templateOverride?: string,
    ): Promise<string> {
        if (!this.loadedModelUrl) {
            throw new Error("WASM backend: model must be loaded first.");
        }
        return this.wllama.formatChat(
            messages,
            true,
            templateOverride ?? undefined,
        );
    }

    async isModelAvailable(modelPath: string): Promise<boolean> {
        const modelUrl = ensureUrl(modelPath);
        const urls = ModelManager.parseModelUrl(modelUrl);
        if (urls.length === 0) return false;
        const models = await this.modelManager.getModels({
            includeInvalid: true,
        });
        return urls.every((url) => {
            const existing = models.find((model) => model.url === url);
            return (
                existing && existing.validate() === ModelValidationStatus.VALID
            );
        });
    }

    async generateChatStream(
        request: GenerateChatRequest,
        onEvent?: (event: GenerateEvent) => void,
    ): Promise<GenerateSummary> {
        const addAssistant = request.addAssistant ?? true;
        const prompt = await this.wllama.formatChat(
            request.messages,
            addAssistant,
            request.templateOverride ?? undefined,
        );
        return this.generateCompletion(prompt, request, onEvent);
    }

    async prewarmMultimodalContext() {
        // Multimodal inference is only available through the native Tauri backend.
    }

    cancel(jobId: number) {
        if (jobId <= 0) {
            for (const controller of this.abortControllers.values()) {
                controller.abort();
            }
            this.abortControllers.clear();
            return;
        }
        const controller = this.abortControllers.get(jobId);
        if (controller) {
            controller.abort();
        }
    }

    async freeContext() {
        if (this.loadedModelUrl) {
            await this.wllama.exit();
            this.loadedModelUrl = null;
            this.loadedContextKey = null;
        }
    }

    async freeModel() {
        await this.freeContext();
    }

    private async ensureModelLoaded(modelUrl: string, params: ContextParams) {
        const contextKey = JSON.stringify({
            n_ctx: params.contextSize ?? null,
            n_threads: params.nThreads ?? null,
            n_batch: params.nBatch ?? null,
        });

        if (
            this.loadedModelUrl === modelUrl &&
            this.loadedContextKey === contextKey
        ) {
            return;
        }

        if (this.loadedModelUrl) {
            await this.wllama.exit();
        }

        const loadConfig = {
            n_ctx: params.contextSize ?? undefined,
            n_threads: params.nThreads ?? undefined,
            n_batch: params.nBatch ?? undefined,
        } as const;

        const downloadOptions: Record<string, unknown> = {};
        if (this.progressCallback) {
            downloadOptions.progressCallback = this.progressCallback;
        }

        await this.ensureModelCached(modelUrl);

        await this.wllama.loadModelFromUrl(modelUrl, {
            ...loadConfig,
            ...downloadOptions,
        });

        this.loadedModelUrl = modelUrl;
        this.loadedContextKey = contextKey;
    }

    private async ensureModelCached(modelUrl: string) {
        if (
            typeof navigator === "undefined" ||
            !navigator.storage ||
            !("getDirectory" in navigator.storage)
        ) {
            return;
        }

        const urls = ModelManager.parseModelUrl(modelUrl);
        if (urls.length === 0) return;

        const totals = new Array<number>(urls.length).fill(0);
        const loaded = new Array<number>(urls.length).fill(0);
        const emitProgress = (status?: string) => {
            const totalBytes = totals.reduce((sum, value) => sum + value, 0);
            const bytesDownloaded = loaded.reduce(
                (sum, value) => sum + value,
                0,
            );
            this.progressCallback?.({
                loaded: bytesDownloaded,
                total: totalBytes || undefined,
                status,
            });
        };

        const cacheDir = await navigator.storage.getDirectory();
        const opfsCache = await cacheDir.getDirectoryHandle("cache", {
            create: true,
        });

        for (let index = 0; index < urls.length; index += 1) {
            const url = urls[index];
            if (!url) continue;

            const models = await this.modelManager.getModels({
                includeInvalid: true,
            });
            const existing = models.find((model) => model.url === url);
            if (
                existing &&
                existing.validate() === ModelValidationStatus.VALID
            ) {
                totals[index] = existing.size;
                loaded[index] = existing.size;
                emitProgress("Ready");
                continue;
            }

            const filename =
                await this.modelManager.cacheManager.getNameFromURL(url);
            const handle = await opfsCache.getFileHandle(filename, {
                create: true,
            });
            const file = await handle.getFile();
            let downloaded = file.size ?? 0;

            const metadata =
                await this.modelManager.cacheManager.getMetadata(url);
            if (metadata?.originalSize && downloaded >= metadata.originalSize) {
                totals[index] = metadata.originalSize;
                loaded[index] = metadata.originalSize;
                emitProgress("Ready");
                continue;
            }

            const headers: HeadersInit | undefined = downloaded
                ? { Range: `bytes=${downloaded}-` }
                : undefined;
            let res = await fetch(url, { headers });
            if (!res.ok || !res.body) {
                throw new Error(`Failed to download model (${res.status})`);
            }

            if (downloaded > 0 && res.status === 200) {
                downloaded = 0;
            }

            const contentRangeTotal = parseContentRangeTotal(
                res.headers.get("Content-Range"),
            );
            const contentLength = Number(
                res.headers.get("Content-Length") ?? 0,
            );
            const totalBytes =
                contentRangeTotal ??
                (contentLength ? contentLength + downloaded : 0);

            totals[index] = totalBytes;
            loaded[index] = downloaded;
            emitProgress(
                downloaded > 0 ? "Resuming download..." : "Downloading...",
            );

            const writable = await handle.createWritable({
                keepExistingData: true,
            });
            if (downloaded === 0) {
                await writable.truncate(0);
            } else {
                await writable.seek(downloaded);
            }

            const reader = res.body.getReader();
            while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                if (!value) continue;
                await writable.write(value);
                downloaded += value.length;
                loaded[index] = downloaded;
                emitProgress("Downloading...");
            }

            await writable.close();

            await this.writeModelMetadata(opfsCache, url, {
                etag: res.headers.get("ETag") ?? "",
                originalSize: totalBytes || downloaded,
                originalURL: url,
            });

            totals[index] = totalBytes || downloaded;
            loaded[index] = downloaded;
            emitProgress("Ready");
        }
    }

    private async writeModelMetadata(
        cacheDir: FileSystemDirectoryHandle,
        url: string,
        metadata: { etag: string; originalSize: number; originalURL: string },
    ) {
        try {
            const baseName =
                await this.modelManager.cacheManager.getNameFromURL(url);
            const metadataFileName = `__metadata__${baseName}`;
            const metadataHandle = await cacheDir.getFileHandle(
                metadataFileName,
                { create: true },
            );
            const writable = await metadataHandle.createWritable();
            await writable.write(
                new Blob([JSON.stringify(metadata)], { type: "text/plain" }),
            );
            await writable.close();
        } catch (error) {
            log.warn("LLM OPFS metadata write failed", error);
        }
    }

    private async generateCompletion(
        prompt: string,
        request: GenerateChatRequest,
        onEvent?: (event: GenerateEvent) => void,
    ): Promise<GenerateSummary> {
        const jobId = this.nextJobId();
        const start = Date.now();
        const controller = new AbortController();
        this.abortControllers.set(jobId, controller);

        let generatedTokens = 0;
        let promptTokens: number | null;

        try {
            try {
                const promptTokenList = await this.wllama.tokenize(
                    prompt,
                    true,
                );
                promptTokens = promptTokenList.length;
            } catch {
                promptTokens = null;
            }

            const { stopTokens } = await this.resolveStopTokens(
                request.stopSequences ?? [],
            );

            const sampling = buildSamplingConfig(request);
            const maxTokens =
                request.maxTokens ?? DEFAULT_GENERATION_MAX_TOKENS;

            const stream = await this.wllama.createCompletion(prompt, {
                stream: true,
                nPredict: maxTokens,
                sampling,
                stopTokens: stopTokens.length ? stopTokens : undefined,
                abortSignal: controller.signal,
            });

            let lastText = "";
            for await (const chunk of stream) {
                const currentText = chunk.currentText ?? "";
                const delta = currentText.slice(lastText.length);
                lastText = currentText;
                generatedTokens += 1;

                if (delta && onEvent) {
                    onEvent({
                        type: "text",
                        job_id: jobId,
                        text: delta,
                        token_id: chunk.token,
                    });
                }
            }
        } catch (error) {
            if (error instanceof WllamaAbortError) {
                throw new Error("Generation cancelled", { cause: error });
            }
            throw error instanceof Error ? error : new Error(String(error));
        } finally {
            this.abortControllers.delete(jobId);
        }

        const summary = {
            job_id: jobId,
            prompt_tokens: promptTokens,
            generated_tokens: generatedTokens,
            total_time_ms: Date.now() - start,
        };

        if (onEvent) {
            onEvent({ type: "done", summary });
        }

        return summary;
    }

    private async resolveStopTokens(stopSequences: string[]) {
        if (!stopSequences || stopSequences.length === 0) {
            return { stopTokens: [] as number[] };
        }

        const stopTokens: number[] = [];
        for (const sequence of stopSequences) {
            try {
                const tokens = await this.wllama.tokenize(sequence, true);
                const first = tokens[0];
                if (tokens.length === 1 && first !== undefined) {
                    stopTokens.push(first);
                }
            } catch {
                // Ignore invalid stop sequences.
            }
        }

        return { stopTokens };
    }

    private nextJobId() {
        this.jobCounter += 1;
        return this.jobCounter;
    }
}

const parseContentRangeTotal = (header: string | null) => {
    if (!header) return undefined;
    const match = header.match(/\/(\d+)/);
    if (!match) return undefined;
    const total = Number(match[1]);
    return Number.isFinite(total) ? total : undefined;
};

const isGgufHeader = (bytes: Uint8Array) =>
    bytes.length >= 4 &&
    bytes[0] === 0x47 &&
    bytes[1] === 0x47 &&
    bytes[2] === 0x55 &&
    bytes[3] === 0x46;

class TauriInference implements InferenceBackend {
    public readonly kind: BackendType = "tauri";

    async initBackend() {
        log.info("LLM tauri init backend");
        try {
            await invoke("llm_init_backend");
        } catch (error) {
            const err = normalizeInvokeError(error, "Failed to init backend");
            log.error("LLM tauri init failed", err);
            throw err;
        }
    }

    async isModelAvailable(modelPath: string): Promise<boolean> {
        const { exists, open, stat } = await import("@tauri-apps/plugin-fs");
        try {
            if (!(await exists(modelPath))) return false;
            const { size } = await stat(modelPath);
            if (size < MIN_GGUF_BYTES) {
                return false;
            }
            const file = await open(modelPath, { read: true });
            try {
                const head = new Uint8Array(4);
                let offset = 0;
                while (offset < head.length) {
                    const bytesRead = await file.read(head.subarray(offset));
                    if (bytesRead === null) break;
                    offset += bytesRead;
                }
                if (!isGgufHeader(head.subarray(0, offset))) {
                    return false;
                }
            } finally {
                await file.close().catch(() => undefined);
            }
        } catch {
            return false;
        }
        return true;
    }

    async loadModel(params: LoadModelParams) {
        log.info("LLM tauri load model", { modelPath: params.modelPath });
        try {
            await invoke("llm_load_model", {
                params: {
                    model_path: params.modelPath,
                    n_gpu_layers: params.nGpuLayers ?? null,
                    use_mmap: params.useMmap ?? null,
                    use_mlock: params.useMlock ?? null,
                },
            });
        } catch (error) {
            const err = normalizeInvokeError(error, "Failed to load model");
            log.error("LLM tauri load failed", err);
            throw err;
        }
    }

    async createContext(
        model: { modelPath: string },
        params: ContextParams = {},
    ) {
        void model;
        log.info("LLM tauri create context", {
            contextSize: params.contextSize ?? null,
            nThreads: params.nThreads ?? null,
            nBatch: params.nBatch ?? null,
        });
        try {
            await invoke("llm_create_context", {
                params: {
                    context_size: params.contextSize ?? null,
                    n_threads: params.nThreads ?? null,
                    n_batch: params.nBatch ?? null,
                },
            });
        } catch (error) {
            const err = normalizeInvokeError(
                error,
                "Failed to create model context",
            );
            log.error("LLM tauri context failed", err);
            throw err;
        }
    }

    async prewarmMultimodalContext(
        mmprojPath: string,
        mediaMarker?: string,
    ): Promise<void> {
        log.info("LLM tauri prewarm multimodal context", { mmprojPath });
        try {
            await invoke("llm_prewarm_multimodal_context", {
                mmprojPath,
                mediaMarker: mediaMarker ?? null,
            });
        } catch (error) {
            const err = normalizeInvokeError(
                error,
                "Failed to prewarm multimodal context",
            );
            log.error("LLM tauri prewarm multimodal context failed", err);
            throw err;
        }
    }

    async generateChatStream(
        request: GenerateChatRequest,
        onEvent?: (event: GenerateEvent) => void,
    ): Promise<GenerateSummary> {
        let resolvedJobId: number | null = null;

        let resolveDone!: () => void;
        const done = new Promise<void>((resolve) => {
            resolveDone = resolve;
        });

        const unlisten = await listen<GenerateEvent>("llm-event", (event) => {
            const payload = event.payload;

            const payloadJobId =
                payload.type === "done"
                    ? payload.summary.job_id
                    : payload.job_id;

            if (resolvedJobId && payloadJobId !== resolvedJobId) return;
            if (!resolvedJobId) resolvedJobId = payloadJobId;

            if (onEvent) {
                onEvent(payload);
            }

            if (payload.type === "done") resolveDone();
        });

        try {
            log.info("LLM tauri generate", {
                messageCount: request.messages.length,
                maxTokens: request.maxTokens ?? null,
            });
            const summary = await invoke<GenerateSummary>(
                "llm_generate_chat_stream",
                { request: buildGenerateChatRequest(request) },
            );
            await done;
            return summary;
        } catch (error) {
            const err = normalizeInvokeError(error, "Generation failed");
            log.error("LLM tauri generate failed", err);
            throw err;
        } finally {
            void unlisten();
        }
    }

    cancel(jobId: number) {
        log.info("LLM tauri cancel", { jobId });
        void invoke("llm_cancel", { jobId });
    }

    async freeContext() {
        log.info("LLM tauri free context");
        try {
            await invoke("llm_free_context");
        } catch (error) {
            log.error("LLM tauri free context failed", error);
        }
    }

    async freeModel() {
        log.info("LLM tauri free model");
        try {
            await invoke("llm_free_model");
        } catch (error) {
            log.error("LLM tauri free model failed", error);
        }
    }
}

const normalizeInvokeError = (error: unknown, fallback: string) => {
    if (error instanceof Error) return error;
    if (typeof error === "string") return new Error(error);
    if (error && typeof error === "object") {
        const code =
            "code" in error
                ? String((error as { code?: unknown }).code)
                : undefined;
        const message =
            "message" in error
                ? String((error as { message?: unknown }).message)
                : "";
        const payload = message || safeJson(error);
        const text = payload
            ? code
                ? `${payload} (${code})`
                : payload
            : fallback;
        const err = new Error(text);
        if (code) {
            (err as Error & { code?: string }).code = code;
        }
        return err;
    }
    return new Error(fallback);
};

const safeJson = (value: unknown) => {
    try {
        return JSON.stringify(value);
    } catch {
        return "";
    }
};

const buildGenerateChatRequest = (request: GenerateChatRequest) => ({
    messages: request.messages,
    template_override: request.templateOverride ?? null,
    add_assistant: request.addAssistant ?? null,
    image_paths: request.imagePaths ?? null,
    mmproj_path: request.mmprojPath ?? null,
    media_marker: request.mediaMarker ?? null,
    max_tokens: request.maxTokens ?? null,
    temperature: request.temperature ?? null,
    top_p: request.topP ?? null,
    top_k: request.topK ?? null,
    repeat_penalty: request.repeatPenalty ?? null,
    frequency_penalty: request.frequencyPenalty ?? null,
    presence_penalty: request.presencePenalty ?? null,
    seed: request.seed ?? null,
    stop_sequences: request.stopSequences ?? null,
    grammar: request.grammar ?? null,
});

const buildSamplingConfig = (request: GenerateChatRequest) => {
    const sampling: Record<string, unknown> = {};

    if (request.temperature !== undefined && request.temperature !== null) {
        sampling.temp = request.temperature;
    }
    if (request.topP !== undefined && request.topP !== null) {
        sampling.top_p = request.topP;
    }
    if (request.topK !== undefined && request.topK !== null) {
        sampling.top_k = request.topK;
    }
    if (request.repeatPenalty !== undefined && request.repeatPenalty !== null) {
        sampling.penalty_repeat = request.repeatPenalty;
    }
    if (
        request.frequencyPenalty !== undefined &&
        request.frequencyPenalty !== null
    ) {
        sampling.penalty_freq = request.frequencyPenalty;
    }
    if (
        request.presencePenalty !== undefined &&
        request.presencePenalty !== null
    ) {
        sampling.penalty_present = request.presencePenalty;
    }
    if (request.grammar !== undefined && request.grammar !== null) {
        sampling.grammar = request.grammar;
    }

    return sampling;
};

const ensureUrl = (value?: string) => {
    if (!value) {
        throw new Error("Model URL is required for WASM backend.");
    }

    try {
        const parsed = new URL(value);
        if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
            throw new Error("Model URL must use http(s) protocol.");
        }
        return parsed.toString();
    } catch {
        throw new Error(`Invalid model URL for WASM backend: ${value}`);
    }
};
