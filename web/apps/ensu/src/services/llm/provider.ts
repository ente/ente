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
const MIN_DESKTOP_DEFAULT_MEMORY_BYTES = 16 * 1024 * 1024 * 1024;

// These fallback values must stay in sync with rust/crates/ensu/src/config.rs.
// When running inside Tauri, resolveDefaultModelForDevice() overwrites them with
// values fetched from the Rust config_defaults command.
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
    url: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf?download=true",
    sha256: "519b9793ed6ce0ff530f1b7c96e848e08e49e7af4d57bb97f76215963a54146d",
    mmprojUrl:
        "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/mmproj-F16.gguf",
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

interface ConfigDefaults {
    mobileSystemPromptBody: string;
    desktopSystemPromptBody: string;
    systemPromptDatePlaceholder: string;
    sessionSummarySystemPrompt: string;
    mobileDefaultModel: ConfigModelPreset;
    mobileModelPresets: ConfigModelPreset[];
    desktopDefaultModel: ConfigModelPreset;
    desktopModelPresets: ConfigModelPreset[];
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
        url: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf?download=true",
        sha256: "9378bc471710229ef165709b62e34bfb62231420ddaf6d729e727305b5b8672d",
        mmprojUrl:
            "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/mmproj-F16.gguf",
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
    private configDefaults?: ConfigDefaults;
    private useDesktopRustDefaults = false;

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
        await this.backend.initBackend();
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

    public getConfigDefaults(): ConfigDefaults | undefined {
        return this.configDefaults;
    }

    public getResolvedModelPresets(): ResolvedModelPreset[] | undefined {
        if (!this.configDefaults) {
            return undefined;
        }

        const presets = this.useDesktopRustDefaults
            ? this.configDefaults.desktopModelPresets
            : this.configDefaults.mobileModelPresets;
        return presets.map((preset) => ({ id: preset.id, name: preset.title }));
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

    public async ensureModelReady(
        settings: ModelSettings,
        options: { emitProgress?: boolean } = {},
    ) {
        await this.initialize();
        const emitProgress = options.emitProgress ?? true;
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
                // ignore errors from previous load
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
                this.currentMmprojPath === mmprojPath
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

            if (modelId && !(await this.modelStatus(modelId)).downloaded) {
                await this.downloadModelNative(modelId);
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
            if (this.ensureInFlight?.promise === ensurePromise) {
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
        this.backend.cancel(jobId);
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
        const loaded = event.loaded ?? 0;
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
        this.useDesktopRustDefaults = false;

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

            this.useDesktopRustDefaults =
                totalMemoryBytes >= MIN_DESKTOP_DEFAULT_MEMORY_BYTES;

            if (this.useDesktopRustDefaults) {
                this.defaultModel = DESKTOP_DEFAULT_MODEL;
            }

            // Overlay Rust-authoritative fields (id, name, url, mmprojUrl)
            // while keeping the web-only display fields (sizeBytes etc.)
            // as fallbacks.
            try {
                const defaults =
                    await invoke<ConfigDefaults>("config_defaults");
                const rustPreset = this.useDesktopRustDefaults
                    ? defaults.desktopDefaultModel
                    : defaults.mobileDefaultModel;
                this.defaultModel = {
                    ...this.defaultModel,
                    id: rustPreset.id,
                    name: rustPreset.title,
                    url: rustPreset.url,
                    sha256: rustPreset.sha256,
                    mmprojUrl: rustPreset.mmprojUrl ?? undefined,
                    mmprojSha256: rustPreset.mmprojSha256 ?? undefined,
                };
                this.configDefaults = defaults;
            } catch (defaultsError) {
                log.warn(
                    "Failed to fetch ensu defaults from Rust",
                    defaultsError,
                );
            }

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
        const preset = this.resolveConfigPreset(settings.modelId);
        if (preset) {
            return {
                id: preset.id,
                name: preset.title,
                url: preset.url,
                sha256: preset.sha256,
                mmprojUrl: preset.mmprojUrl ?? undefined,
                mmprojSha256: preset.mmprojSha256 ?? undefined,
            };
        }
        if (settings.modelId && !this.configDefaults) {
            const fallback = [
                ...FALLBACK_DESKTOP_MODEL_PRESETS,
                ...FALLBACK_MOBILE_MODEL_PRESETS,
            ].find((preset) => preset.id === settings.modelId);
            if (fallback) {
                return fallback;
            }
        }
        return this.defaultModel;
    }

    private resolveConfigPreset(modelId: string | undefined) {
        const defaults = this.configDefaults;
        if (!defaults || !modelId) {
            return undefined;
        }
        return [
            defaults.mobileDefaultModel,
            defaults.desktopDefaultModel,
            ...defaults.mobileModelPresets,
            ...defaults.desktopModelPresets,
        ].find((preset) => preset.id == modelId);
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
