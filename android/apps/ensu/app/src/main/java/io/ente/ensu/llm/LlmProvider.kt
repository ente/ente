package io.ente.ensu.llm

import android.util.Log
import io.ente.ensu.assets.AssetStore
import io.ente.ensu.bindings.Asset
import io.ente.ensu.bindings.LlmChatMessage as NativeChatMessage
import io.ente.ensu.bindings.LlmChatRequest
import io.ente.ensu.bindings.LlmContext
import io.ente.ensu.bindings.LlmContextParams
import io.ente.ensu.bindings.LlmGenerationEvent
import io.ente.ensu.bindings.LlmGenerationEventCallback
import io.ente.ensu.bindings.LlmGenerationSummary as NativeSummary
import io.ente.ensu.bindings.LlmModel
import io.ente.ensu.bindings.LlmModelLoadParams
import io.ente.ensu.bindings.KnowledgeEmbeddingConfig
import io.ente.ensu.bindings.Transcriber
import io.ente.ensu.bindings.knowledgeEmbeddingModelAsset
import io.ente.ensu.bindings.llmAsset
import io.ente.ensu.bindings.llmCancel
import io.ente.ensu.bindings.llmInitBackend
import io.ente.ensu.device.AndroidDeviceCapabilityProvider
import io.ente.ensu.device.requireChatSupported
import io.ente.ensu.settings.IS_ENSU_PACKS_ENABLED
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class RequiredModelValidationError(
    val modelId: String
) : Exception("Downloaded model failed validation: $modelId")

class LlmProvider(
    private val assetStore: AssetStore,
    private val transcriber: Transcriber,
    private val deviceCapabilityProvider: AndroidDeviceCapabilityProvider,
    private val knowledgeEmbedding: KnowledgeEmbeddingConfig,
    private val ioDispatcher: kotlinx.coroutines.CoroutineDispatcher = Dispatchers.IO
) {
    private data class LoadedModelKey(
        val id: String,
        val requestedContextLength: Int?
    )

    @Volatile private var loadedModel: LlmModel? = null
    @Volatile private var loadedContext: LlmContext? = null
    @Volatile private var currentModelKey: LoadedModelKey? = null
    @Volatile private var currentContextLength: Int? = null
    @Volatile private var currentJobId: Long? = null
    private var backendInitialized = false
    private val modelLoadMutex = Mutex()
    private val activeDownloads = AtomicInteger()
    private val embeddingAsset = knowledgeEmbeddingModelAsset()

    class EmbeddingAssetInvalid : Exception("Embedding model asset is invalid")

    fun isChatModelReady(selection: LlmModelSelection): Boolean =
        assetStore.isDownloaded(chatAsset(selection))

    fun isEmbeddingModelReady(): Boolean =
        assetStore.isDownloaded(embeddingAsset)

    suspend fun estimateEmbeddingDownloadSize(): Long? =
        assetStore.estimateDownloadSize(embeddingAsset)

    suspend fun estimateChatModelDownloadSize(selection: LlmModelSelection): Long? =
        assetStore.estimateDownloadSize(chatAsset(selection))

    val isDownloadActive: Boolean
        get() = activeDownloads.get() > 0

    suspend fun ensureModelReady(
        selection: LlmModelSelection,
        onProgress: (DownloadProgress) -> Unit
    ) {
        withContext(ioDispatcher) {
            modelLoadMutex.withLock {
                ensureModelReadyLocked(selection, onProgress)
            }
        }
    }

    suspend fun ensureRequiredModelsReady(
        selection: LlmModelSelection,
        onProgress: (DownloadProgress) -> Unit
    ) {
        withContext(ioDispatcher) {
            deviceCapabilityProvider.chatCapability().requireChatSupported()
            val asset = chatAsset(selection)
            val missingAssets = modelLoadMutex.withLock {
                val embeddingReady = isEmbeddingModelReady()
                if (IS_ENSU_PACKS_ENABLED && !embeddingReady) {
                    val embeddingFile = assetStore.llmModelPath(embeddingAsset)
                    if (embeddingFile?.exists() == true) {
                        assetStore.removeDownloaded(embeddingAsset)
                    }
                }

                buildList {
                    if (!assetStore.isDownloaded(asset)) add(asset)
                    if (IS_ENSU_PACKS_ENABLED && !isEmbeddingModelReady()) add(embeddingAsset)
                }
            }
            if (missingAssets.isNotEmpty()) {
                downloadAssets(missingAssets, onProgress)
            }
            modelLoadMutex.withLock {
                if (IS_ENSU_PACKS_ENABLED && !isEmbeddingModelReady()) {
                    assetStore.removeDownloaded(embeddingAsset)
                    throw RequiredModelValidationError(knowledgeEmbedding.targetId)
                }
                if (!assetStore.isDownloaded(asset)) {
                    throw RequiredModelValidationError(selection.id)
                }
                ensureModelReadyLocked(
                    selection,
                    onProgress,
                    allowRecovery = false,
                    shouldDownload = false
                )
            }
        }
    }

    suspend fun generateChat(
        selection: LlmModelSelection,
        messages: List<LlmMessage>,
        imageFiles: List<File>,
        temperature: Float,
        maxTokens: Int?,
        onToken: (String) -> Unit
    ): GenerationSummary = withContext(ioDispatcher) {
        modelLoadMutex.withLock {
            deviceCapabilityProvider.chatCapability().requireChatSupported()
            val context = loadedContext ?: throw IllegalStateException("Model context not loaded")
            currentJobId = null
            val mmprojPath = if (imageFiles.isEmpty()) {
                null
            } else {
                assetStore.llmMmprojPath(chatAsset(selection))?.absolutePath
            }
            val clampedTemperature = temperature.coerceIn(0.35f, 0.7f)

            val request = LlmChatRequest(
                messages = messages.map { msg ->
                    NativeChatMessage(msg.roleString(), msg.text)
                },
                templateOverride = null,
                addAssistant = true,
                imagePaths = imageFiles.map { it.absolutePath },
                mmprojPath = mmprojPath,
                mediaMarker = null,
                maxTokens = maxTokens,
                temperature = clampedTemperature,
                topP = 0.9f,
                topK = 50,
                repeatPenalty = 1.18f,
                frequencyPenalty = 0f,
                presencePenalty = 0f,
                seed = null,
                stopSequences = null,
                grammar = null
            )

            unloadTranscriptionModelIfLoaded()
            val summary = generateStreamWithCallback(context, request, onToken)
            GenerationSummary(summary.jobId, summary.generatedTokens ?: 0, summary.totalTimeMs)
        }
    }

    suspend fun <T> withChatModelReleasedForRetrieval(
        block: suspend (embed: (String) -> List<Float>) -> T
    ): T = withContext(ioDispatcher) {
        modelLoadMutex.withLock {
            deviceCapabilityProvider.chatCapability().requireChatSupported()
            if (!isEmbeddingModelReady()) throw EmbeddingAssetInvalid()
            unloadTranscriptionModelIfLoaded()
            unloadModel()
            if (!backendInitialized) {
                llmInitBackend()
                backendInitialized = true
            }

            val embeddingModel = LlmModel.load(
                LlmModelLoadParams(
                    modelPath = requireNotNull(assetStore.llmModelPath(embeddingAsset)).absolutePath,
                    nGpuLayers = 0,
                    useMmap = true,
                    useMlock = false
                )
            )
            var embeddingContext: LlmContext? = null
            try {
                val threads = max(1, Runtime.getRuntime().availableProcessors() - 1)
                embeddingContext = embeddingModel.newEmbeddingContext(threads)
                block { text -> embeddingContext.embed(text) }
            } finally {
                embeddingContext?.destroy()
                embeddingModel.destroy()
            }
        }
    }

    suspend fun prewarmImageInference(selection: LlmModelSelection) {
        withContext(ioDispatcher) {
            runCatching {
                modelLoadMutex.withLock {
                    val asset = chatAsset(selection)
                    if (!assetStore.isDownloaded(asset)) return@withLock
                    val mmprojPath =
                        assetStore.llmMmprojPath(asset)?.absolutePath
                        ?.takeIf { File(it).exists() }
                        ?: return@withLock
                    ensureModelReadyLocked(selection, onProgress = {})
                    val context = loadedContext ?: return@withLock
                    unloadTranscriptionModelIfLoaded()
                    context.prewarmMultimodal(mmprojPath, null)
                }
            }.onFailure { error ->
                Log.d("LlmProvider", "Image inference prewarm skipped", error)
            }
        }
    }

    fun loadedContextLength(selection: LlmModelSelection): Int? {
        val modelKey = LoadedModelKey(selection.id, selection.contextLength)
        return if (currentModelKey == modelKey && loadedContext != null && loadedModel != null) {
            currentContextLength
        } else {
            null
        }
    }

    fun stopGeneration() {
        val jobId = currentJobId
        if (jobId != null) {
            llmCancel(jobId)
        } else {
            llmCancel(0)
        }
    }

    suspend fun resetContext() {
        withContext(ioDispatcher) {
            modelLoadMutex.withLock {
                val model = loadedModel ?: return@withLock
                val contextParams = LlmContextParams(
                    contextSize = currentContextLength,
                    nThreads = null,
                    nBatch = null
                )
                loadedContext?.destroy()
                loadedContext = model.newContext(contextParams)
            }
        }
    }

    private fun LlmMessage.roleString(): String {
        return when (role) {
            LlmMessageRole.User -> "user"
            LlmMessageRole.Assistant -> "assistant"
            LlmMessageRole.System -> "system"
        }
    }

    private fun unloadModel() {
        loadedContext?.destroy()
        loadedContext = null
        loadedModel?.destroy()
        loadedModel = null
        currentModelKey = null
        currentContextLength = null
    }

    private fun unloadTranscriptionModelIfLoaded() {
        runCatching {
            transcriber.unloadModel()
        }.onFailure { error ->
            Log.d("LlmProvider", "Transcription model unload skipped", error)
        }
    }

    private suspend fun ensureModelReadyLocked(
        selection: LlmModelSelection,
        onProgress: (DownloadProgress) -> Unit,
        allowRecovery: Boolean = true,
        shouldDownload: Boolean = true
    ) {
        deviceCapabilityProvider.chatCapability().requireChatSupported()
        val modelKey = LoadedModelKey(selection.id, selection.contextLength)
        if (!backendInitialized) {
            llmInitBackend()
            backendInitialized = true
        }

        if (currentModelKey == modelKey && loadedContext != null && loadedModel != null) {
            return
        }

        unloadModel()

        val asset = chatAsset(selection)
        val wasAlreadyDownloaded = assetStore.isDownloaded(asset)
        if (shouldDownload) {
            downloadAssets(listOf(asset), onProgress)
        }

        onProgress(DownloadProgress(100, "Loading model...", phase = DownloadPhase.Loading))
        try {
            loadWithFallbacks(
                selection,
                requireNotNull(assetStore.llmModelPath(asset))
            )
        } catch (error: Throwable) {
            if (allowRecovery && wasAlreadyDownloaded && assetStore.removeDownloaded(asset)) {
                onProgress(DownloadProgress(0, "Starting download...", phase = DownloadPhase.Downloading))
                ensureModelReadyLocked(selection, onProgress, allowRecovery = false)
                return
            }
            throw error
        }
        onProgress(DownloadProgress(100, "Ready", phase = DownloadPhase.Ready))
    }

    private suspend fun downloadAssets(
        assets: List<Asset>,
        onProgress: (DownloadProgress) -> Unit
    ) {
        activeDownloads.incrementAndGet()
        try {
            assetStore.download(assets) { progress ->
                onProgress(
                    DownloadProgress(
                        progress.percentage.toInt().coerceIn(0, 99),
                        progress.status
                    )
                )
            }
        } finally {
            activeDownloads.decrementAndGet()
        }
    }

    private fun chatAsset(selection: LlmModelSelection): Asset = llmAsset(selection.id)

    private fun loadWithFallbacks(selection: LlmModelSelection, modelFile: File) {
        val desiredCtx = selection.contextLength ?: 12000
        val contexts = listOf(desiredCtx, 12000, 8192, 4096, 2048, 1024).distinct().filter { it > 0 }
        val threads = max(1, Runtime.getRuntime().availableProcessors() - 1)
        val batch = 512

        val modelParams = LlmModelLoadParams(
            modelPath = modelFile.absolutePath,
            nGpuLayers = 0,
            useMmap = true,
            useMlock = false
        )

        val model = LlmModel.load(modelParams)
        loadedModel = model

        var lastError: Throwable? = null
        for (ctx in contexts) {
            try {
                val contextParams = LlmContextParams(
                    contextSize = ctx,
                    nThreads = threads,
                    nBatch = batch
                )
                loadedContext = model.newContext(contextParams)
                currentModelKey = LoadedModelKey(selection.id, selection.contextLength)
                currentContextLength = ctx
                return
            } catch (err: Throwable) {
                lastError = err
            }
        }
        unloadModel()
        throw lastError ?: IllegalStateException("Failed to load model")
    }

    private fun generateStreamWithCallback(
        context: LlmContext,
        request: LlmChatRequest,
        onToken: (String) -> Unit
    ): NativeSummary {
        val callback = object : LlmGenerationEventCallback {
            override fun onEvent(event: LlmGenerationEvent) {
                when (event) {
                    is LlmGenerationEvent.Text -> {
                        currentJobId = event.jobId
                        if (event.text.isNotEmpty()) {
                            onToken(event.text)
                        }
                    }
                    is LlmGenerationEvent.Done -> {
                        currentJobId = null
                    }
                }
            }
        }

        try {
            return context.generateChatStream(request, callback)
        } finally {
            currentJobId = null
        }
    }
}
