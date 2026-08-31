import { namedError } from "ente-base/error";
import log from "ente-base/log";
import { createInferenceBackend } from "./inference";
import type {
    DownloadProgress,
    GenerateChatRequest,
    GenerateEvent,
    GenerateSummary,
    ModelInfo,
    ModelSettings,
} from "./types";

const DEFAULT_WEB_CONTEXT_SIZE = 4096;
const DEFAULT_TAURI_CONTEXT_SIZE = 12000;
const DEFAULT_GENERATION_MAX_TOKENS = 8_192;
const OVERFLOW_SAFETY_TOKENS = 256;

// These fallback values must stay in sync with rust/crates/ensu/src/config.rs.
export const DEFAULT_MODEL: ModelInfo = {
    id: "lfm-vl-1.6b",
    name: "LFM 2.5 VL 1.6B (Q4_0)",
    url: "https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/main/LFM2.5-VL-1.6B-Q4_0.gguf?download=true",
    sha256: "8186364a4e7c3ad30f6dd3d3b7a4e0074c77dd91eed6cad5d8be9090ce285804",
    mmprojUrl:
        "https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/main/mmproj-LFM2.5-VL-1.6b-Q8_0.gguf",
    mmprojSha256:
        "2ce89e610c56f3198ece2b86cf61743a08b9307279c89125eb2412ebb908689d",
    sizeBytes: 695_752_160,
    mmprojSizeBytes: 583_109_888,
    sizeHuman: "~664 MB",
};

const DESKTOP_DEFAULT_MODEL: ModelInfo = {
    id: "gemma-4-e4b-q4km",
    name: "Gemma 4 E4B (Q4_K_M)",
    url: "https://huggingface.co/ente-ai/gemma-4-E4B-it-GGUF/resolve/f0089e04ac8494e513619d18b44c829c6b815440/gemma-4-E4B-it-Q4_K_M.gguf?download=true",
    sha256: "85a896a047553e842f25297ee5b031d64ff30147d9c4af17b1e4b394cd1fab87",
    mmprojUrl:
        "https://huggingface.co/ente-ai/gemma-4-E4B-it-GGUF/resolve/f0089e04ac8494e513619d18b44c829c6b815440/mmproj-F16.gguf",
    mmprojSha256:
        "ddf46c21d7078e95338cfc22306b19b276a29a5ad089023449dd54d4b6170a51",
    sizeBytes: 4_977_169_088,
    mmprojSizeBytes: 990_372_800,
    sizeHuman: "5.97 GB",
};

interface ConfigModelPreset {
    id: string;
    title: string;
    url: string;
    sha256: string;
    mmprojUrl?: string | null;
    mmprojSha256?: string | null;
}

interface ResolvedModelPolicy {
    defaultModel: ConfigModelPreset;
    visibleModels: ConfigModelPreset[];
    allowedPreferredModels: ConfigModelPreset[];
}

interface TauriLlmModelDownloadProgress {
    percent: number;
    status: string;
    bytesDownloaded: number;
    totalBytes?: number;
}

interface TauriModelStatus {
    modelPath: string;
    mmprojPath?: string | null;
    downloaded: boolean;
}

export interface ResolvedModelPreset {
    id: string;
    name: string;
}

const FALLBACK_SHARED_MODEL_PRESETS: ModelInfo[] = [
    {
        id: "qwen-0.8b",
        name: "Qwen 3.5 0.8B (Q4_K_M)",
        url: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf?download=true",
        sha256: "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517",
        mmprojUrl:
            "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/mmproj-F16.gguf",
        mmprojSha256:
            "56e4c6cfe73b0c82e3e82bc518d7591997e61d81f723fc41a586f4fa69ea2453",
    },
    {
        id: "qwen-2b-q8",
        name: "Qwen 3.5 2B (Q8_0)",
        url: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q8_0.gguf?download=true",
        sha256: "1b04acba824817554f4ce23639bc8495ff70453b8fcb047900c731521021f2c1",
        mmprojUrl:
            "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/mmproj-F16.gguf",
        mmprojSha256:
            "7035e9cb8d7c6a9681d07eef9a364783e86ea4cd73faab2eabb4f43a101830c7",
    },
    {
        id: "gemma-4-e2b-q4km",
        name: "Gemma 4 E2B (Q4_K_M)",
        url: "https://huggingface.co/ente-ai/gemma-4-E2B-it-GGUF/resolve/d9f70b02c9a2193b7263daee865dfa93276fd99a/gemma-4-E2B-it-Q4_K_M.gguf?download=true",
        sha256: "740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8",
        mmprojUrl:
            "https://huggingface.co/ente-ai/gemma-4-E2B-it-GGUF/resolve/d9f70b02c9a2193b7263daee865dfa93276fd99a/mmproj-F16.gguf",
        mmprojSha256:
            "140be8d7849741f88c50757d529b84373ee8e27052cc2236855b537f4a8215fa",
    },
];

export const FALLBACK_MOBILE_MODEL_PRESETS: ModelInfo[] = [
    ...FALLBACK_SHARED_MODEL_PRESETS,
];

export const FALLBACK_DESKTOP_MODEL_PRESETS: ModelInfo[] = [
    {
        id: "qwen-4b-q4km",
        name: "Qwen 3.5 4B (Q4_K_M)",
        url: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf?download=true",
        sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4",
        mmprojUrl:
            "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/mmproj-F16.gguf",
        mmprojSha256:
            "cd88edcf8d031894960bb0c9c5b9b7e1fea6ebee02b9f7ce925a00d12891f864",
    },
    DEFAULT_MODEL,
    ...FALLBACK_SHARED_MODEL_PRESETS,
];

const MODEL_INFO_FALLBACKS = [
    DESKTOP_DEFAULT_MODEL,
    ...FALLBACK_DESKTOP_MODEL_PRESETS,
];

const modelMissingError = () =>
    namedError("model_missing", "Required model assets are not downloaded");

export class LlmProvider {
    private backend = createInferenceBackend({
        backend: "auto",
        wasm: { progressCallback: (event) => this.handleWasmProgress(event) },
    });

    private initialized = false;
    private currentModel?: ModelInfo;
    private currentModelPath?: string;
    private currentMmprojPath?: string;
    private currentContextKey?: string;
    private defaultModel = DEFAULT_MODEL;
    private modelPolicy?: ResolvedModelPolicy;

    private downloadActive = false;
    private progressListeners = new Set<(progress: DownloadProgress) => void>();
    private modelReady = false;
    private ensureInFlight?: {
        key: string;
        promise: Promise<void>;
        emitsProgress: boolean;
    };

    public async initialize() {
        if (this.initialized) return;
        await this.backend.initBackend?.();
        await this.resolveDefaultModelForDevice();
        this.initialized = true;
    }

    public onDownloadProgress(listener: (progress: DownloadProgress) => void) {
        this.progressListeners.add(listener);
        return () => {
            this.progressListeners.delete(listener);
        };
    }

    public getCurrentModel() {
        return this.currentModel;
    }

    public getDefaultModel() {
        return this.defaultModel;
    }

    public getResolvedModelPresets(): ResolvedModelPreset[] | undefined {
        const policy = this.modelPolicy;
        if (!policy) {
            return undefined;
        }
        return policy.visibleModels
            .filter((preset) => preset.id !== policy.defaultModel.id)
            .map((preset) => ({ id: preset.id, name: preset.title }));
    }

    public getBackendKind() {
        return this.backend.kind;
    }

    public getCurrentMmprojPath() {
        return this.currentMmprojPath;
    }

    public resolveRuntimeSettings(settings: ModelSettings) {
        const model = this.resolveTargetModel(settings);
        const defaultContextSize =
            this.backend.kind === "tauri"
                ? DEFAULT_TAURI_CONTEXT_SIZE
                : DEFAULT_WEB_CONTEXT_SIZE;
        const requestedContextSize =
            settings.contextLength ?? model.contextLength ?? defaultContextSize;
        const contextSize =
            this.backend.kind === "tauri"
                ? requestedContextSize
                : Math.min(requestedContextSize, DEFAULT_WEB_CONTEXT_SIZE);
        const configuredMaxTokens = settings.maxTokens ?? model.maxTokens;
        const maxAllowedTokens = Math.max(
            1,
            contextSize - OVERFLOW_SAFETY_TOKENS,
        );
        const implicitMaxTokens = Math.min(
            DEFAULT_GENERATION_MAX_TOKENS,
            Math.max(1, Math.floor(contextSize / 2)),
        );
        const maxTokens = configuredMaxTokens ?? implicitMaxTokens;
        return {
            model,
            contextSize,
            maxTokens: Math.min(maxTokens, maxAllowedTokens),
        };
    }

    public async checkModelAvailability(settings: ModelSettings) {
        await this.initialize();
        const { model, contextSize } = this.resolveRuntimeSettings(settings);
        const contextKey = JSON.stringify({ contextSize });

        if (this.backend.kind !== "tauri") {
            const modelPath = model.url;
            return {
                model,
                modelPath,
                mmprojPath: undefined,
                contextKey,
                modelAvailable: await this.backend.isModelAvailable(modelPath),
                mmprojAvailable: undefined,
            };
        }

        const status = await this.modelStatus(model.id);
        return {
            model,
            modelPath: status.modelPath,
            mmprojPath: status.mmprojPath ?? undefined,
            contextKey,
            modelAvailable: status.downloaded,
            mmprojAvailable: status.mmprojPath ? status.downloaded : undefined,
        };
    }

    public async estimateMissingModelDownloadSize(settings: ModelSettings) {
        await this.initialize();
        if (this.backend.kind !== "tauri") return undefined;
        const { model } = this.resolveRuntimeSettings(settings);
        const { invoke } = await import("@tauri-apps/api/core");
        return (
            (await invoke<number | null>("llm_model_download_size", {
                modelId: model.id,
            })) ?? undefined
        );
    }

    public async ensureModelReady(
        settings: ModelSettings,
        options: { emitProgress?: boolean; downloadIfMissing?: boolean } = {},
    ) {
        await this.initialize();
        const emitProgress = options.emitProgress ?? true;
        const downloadIfMissing = options.downloadIfMissing ?? false;
        const { model, contextSize } = this.resolveRuntimeSettings(settings);
        const contextKey = JSON.stringify({ contextSize });

        const modelId = this.backend.kind === "tauri" ? model.id : undefined;
        const status = modelId ? await this.modelStatus(modelId) : undefined;
        const modelPath = status?.modelPath ?? model.url;
        const mmprojPath = status?.mmprojPath ?? undefined;

        const ensureKey = JSON.stringify({
            modelId: model.id,
            modelPath,
            mmprojPath,
            contextKey,
        });

        if (this.ensureInFlight) {
            if (this.ensureInFlight.key === ensureKey) {
                const inFlight = this.ensureInFlight;
                if (emitProgress && !inFlight.emitsProgress) {
                    inFlight.emitsProgress = true;
                    this.emitProgress({
                        percent: 100,
                        status: "Loading model...",
                    });
                    await inFlight.promise;
                    this.emitProgress({ percent: 100, status: "Ready" });
                    return;
                }
                return inFlight.promise;
            }
            try {
                await this.ensureInFlight.promise;
            } catch {
                // Wait only for settlement; the failure belongs to the
                // original caller.
            }
        }

        const ensurePromise = (async () => {
            log.info("LLM ensureModelReady", {
                backend: this.backend.kind,
                modelId: model.id,
                modelPath,
                mmprojPath,
                contextKey,
            });

            if (
                this.currentModel?.id === model.id &&
                this.currentModelPath === modelPath &&
                this.currentContextKey === contextKey &&
                this.currentMmprojPath === mmprojPath &&
                (!status || status.downloaded)
            ) {
                log.info("LLM model already ready", { modelId: model.id });
                this.modelReady = true;
                if (emitProgress) {
                    this.emitProgress({ percent: 100, status: "Ready" });
                }
                return;
            }

            this.modelReady = false;
            log.info("LLM resetting backend", {
                modelId: this.currentModel?.id,
            });
            await this.backend.freeContext();
            await this.backend.freeModel();
            this.currentModel = undefined;
            this.currentModelPath = undefined;
            this.currentMmprojPath = undefined;
            this.currentContextKey = undefined;

            if (modelId) {
                const isDownloaded = (await this.modelStatus(modelId))
                    .downloaded;
                if (!isDownloaded && !downloadIfMissing) {
                    throw modelMissingError();
                }
                if (downloadIfMissing && !isDownloaded) {
                    await this.downloadModelNative(modelId);
                }
            }

            if (emitProgress) {
                this.emitProgress({ percent: 100, status: "Loading model..." });
            }
            log.info("LLM load model", { modelPath });
            await this.backend.loadModel({ modelPath });
            log.info("LLM create context", { modelPath, contextSize });
            await this.backend.createContext({ modelPath }, { contextSize });

            this.currentModel = model;
            this.currentModelPath = modelPath;
            this.currentMmprojPath = mmprojPath;
            this.currentContextKey = contextKey;
            this.modelReady = true;
            log.info("LLM ready", { modelId: model.id, modelPath });
            if (emitProgress) {
                this.emitProgress({ percent: 100, status: "Ready" });
            }
        })();

        this.ensureInFlight = {
            key: ensureKey,
            promise: ensurePromise,
            emitsProgress: emitProgress,
        };

        try {
            await ensurePromise;
        } finally {
            if (this.ensureInFlight.promise === ensurePromise) {
                this.ensureInFlight = undefined;
            }
        }
    }

    public async generateChatStream(
        request: GenerateChatRequest,
        onEvent?: (event: GenerateEvent) => void,
    ): Promise<GenerateSummary> {
        return this.backend.generateChatStream(request, onEvent);
    }

    public async prewarmImageInferenceIfAvailable(settings: ModelSettings) {
        await this.initialize();
        if (this.backend.kind !== "tauri") return;

        const availability = await this.checkModelAvailability(settings);
        if (
            !availability.modelAvailable ||
            !availability.mmprojPath ||
            availability.mmprojAvailable !== true
        ) {
            return;
        }

        await this.ensureModelReady(settings, { emitProgress: false });
        const mmprojPath = this.currentMmprojPath ?? availability.mmprojPath;
        if (!mmprojPath || !this.backend.prewarmMultimodalContext) return;
        await this.backend.prewarmMultimodalContext(mmprojPath);
    }

    public cancelGeneration(jobId: number) {
        return this.backend.cancel(jobId);
    }

    public async resetContext(contextSize?: number) {
        await this.backend.freeContext();
        this.currentContextKey = undefined;
        if (this.currentModel && this.currentModelPath) {
            const resolvedContext =
                contextSize ??
                (this.backend.kind === "tauri"
                    ? DEFAULT_TAURI_CONTEXT_SIZE
                    : DEFAULT_WEB_CONTEXT_SIZE);
            await this.backend.createContext(
                { modelPath: this.currentModelPath },
                { contextSize: resolvedContext },
            );
            this.currentContextKey = JSON.stringify({
                contextSize: resolvedContext,
            });
        }
    }

    private invalidateModelState() {
        this.currentModel = undefined;
        this.currentModelPath = undefined;
        this.currentMmprojPath = undefined;
        this.currentContextKey = undefined;
        this.modelReady = false;
    }

    public async withKnowledgeRetrieval<T>(
        operation: (retrievalEpoch: number) => Promise<T>,
        shouldContinue: () => boolean,
    ) {
        if (this.backend.kind !== "tauri") {
            throw new Error(
                "Knowledge retrieval is only available in the desktop app",
            );
        }
        const { invoke } = await import("@tauri-apps/api/core");
        const retrievalEpoch = await invoke<number>("llm_retrieval_epoch");
        await this.ensureInFlight?.promise.catch(() => undefined);
        if (!shouldContinue()) {
            throw namedError("cancelled", "Knowledge retrieval cancelled");
        }
        this.invalidateModelState();
        return operation(retrievalEpoch);
    }

    public cancelDownload() {
        if (this.downloadActive && this.backend.kind === "tauri") {
            void import("@tauri-apps/api/core").then(({ invoke }) =>
                invoke("llm_cancel_model_download").catch((error: unknown) => {
                    log.warn("LLM cancel model download failed", { error });
                }),
            );
        }
        this.emitProgress({ percent: -1, status: "Cancelled" });
    }

    private emitProgress(progress: DownloadProgress) {
        for (const listener of this.progressListeners) {
            listener(progress);
        }
    }

    private handleWasmProgress(event: {
        loaded: number;
        total?: number;
        status?: string;
    }) {
        if (this.modelReady) {
            return;
        }
        const total = event.total ?? 0;
        const loaded = event.loaded;
        const percent = total
            ? Math.min(99, Math.round((loaded / total) * 100))
            : 0;
        this.emitProgress({
            percent,
            status: event.status ?? "Downloading...",
            bytesDownloaded: loaded,
            totalBytes: total,
        });
    }

    private async resolveDefaultModelForDevice() {
        this.defaultModel = DEFAULT_MODEL;
        this.modelPolicy = undefined;

        if (this.backend.kind !== "tauri") {
            return;
        }

        try {
            const { invoke } = await import("@tauri-apps/api/core");
            const info = await invoke<{
                platform?: string;
                totalMemoryBytes?: number | null;
            }>("system_info");

            const platform = info.platform?.toLowerCase();
            const totalMemoryBytes = info.totalMemoryBytes ?? 0;

            this.modelPolicy = await invoke<ResolvedModelPolicy>(
                "desktop_model_policy",
                { totalMemoryBytes: info.totalMemoryBytes },
            );
            this.defaultModel = this.modelInfo(this.modelPolicy.defaultModel);

            log.info("LLM default model resolved", {
                platform,
                totalMemoryBytes,
                modelId: this.defaultModel.id,
            });
        } catch (error) {
            log.warn("Failed to resolve device-specific default model", error);
        }
    }

    private resolveTargetModel(settings: ModelSettings): ModelInfo {
        if (this.modelPolicy) {
            const preset = settings.modelId
                ? this.modelPolicy.allowedPreferredModels.find(
                      (candidate) => candidate.id === settings.modelId,
                  )
                : undefined;
            return preset ? this.modelInfo(preset) : this.defaultModel;
        }
        return (
            FALLBACK_DESKTOP_MODEL_PRESETS.find(
                (preset) => preset.id === settings.modelId,
            ) ?? this.defaultModel
        );
    }

    private modelInfo(preset: ConfigModelPreset): ModelInfo {
        const fallback = MODEL_INFO_FALLBACKS.find(
            (candidate) => candidate.id === preset.id,
        );
        return {
            ...fallback,
            id: preset.id,
            name: preset.title,
            url: preset.url,
            sha256: preset.sha256,
            mmprojUrl: preset.mmprojUrl ?? undefined,
            mmprojSha256: preset.mmprojSha256 ?? undefined,
        };
    }

    private async modelStatus(modelId: string): Promise<TauriModelStatus> {
        const { invoke } = await import("@tauri-apps/api/core");
        return invoke<TauriModelStatus>("llm_model_status", { modelId });
    }

    private async downloadModelNative(modelId: string) {
        const [{ invoke }, { listen }] = await Promise.all([
            import("@tauri-apps/api/core"),
            import("@tauri-apps/api/event"),
        ]);

        log.info("LLM native download start", { modelId });
        this.emitProgress({
            percent: 0,
            status: "Starting download...",
            bytesDownloaded: 0,
            totalBytes: 0,
        });
        this.downloadActive = true;
        const unlisten = await listen<TauriLlmModelDownloadProgress>(
            "llm-download-progress",
            (event) => {
                const progress = event.payload;
                this.emitProgress({
                    percent: Math.min(99, progress.percent),
                    status: progress.status,
                    bytesDownloaded: progress.bytesDownloaded,
                    totalBytes: progress.totalBytes,
                });
            },
        );

        try {
            await invoke("llm_download_model", { modelId });
            log.info("LLM native download complete", { modelId });
        } finally {
            this.downloadActive = false;
            unlisten();
        }
    }
}
