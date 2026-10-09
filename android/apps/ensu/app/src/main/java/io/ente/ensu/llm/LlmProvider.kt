package io.ente.ensu.llm

import android.os.SystemClock
import android.util.Log
import io.ente.ensu.assets.AssetStore
import io.ente.ensu.bindings.Asset
import io.ente.ensu.bindings.KnowledgeEmbeddingConfig
import io.ente.ensu.bindings.LlmChatMessage as NativeChatMessage
import io.ente.ensu.bindings.LlmChatModelMemory
import io.ente.ensu.bindings.LlmChatRequest
import io.ente.ensu.bindings.LlmContext
import io.ente.ensu.bindings.LlmContextParams
import io.ente.ensu.bindings.LlmGenerationEvent
import io.ente.ensu.bindings.LlmGenerationEventCallback
import io.ente.ensu.bindings.LlmGenerationSummary as NativeSummary
import io.ente.ensu.bindings.LlmMemoryOperation
import io.ente.ensu.bindings.LlmModel
import io.ente.ensu.bindings.LlmModelLoadParams
import io.ente.ensu.bindings.ModelRuntimeSurface
import io.ente.ensu.bindings.Transcriber
import io.ente.ensu.bindings.knowledgeEmbeddingModelAsset
import io.ente.ensu.bindings.llmAsset
import io.ente.ensu.bindings.llmCancel
import io.ente.ensu.bindings.llmHasRequiredWorkReserve
import io.ente.ensu.bindings.llmInitBackendFromDirectory
import io.ente.ensu.bindings.llmMemoryBudget
import io.ente.ensu.device.AndroidDeviceCapabilityProvider
import io.ente.ensu.device.requireChatSupported
import io.ente.ensu.settings.IS_ENSU_PACKS_ENABLED
import io.ente.ensu.toDirectByteBuffer
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

internal class ModelMemoryDeferred : Exception()

internal class ModelMemoryUnavailable :
    Exception("Not enough free memory. Close other apps and try again.")

class RequiredModelValidationError(val modelId: String) :
    Exception("Downloaded model failed validation: $modelId")

class LlmProvider(
    private val assetStore: AssetStore,
    private val transcriber: Transcriber,
    private val deviceCapabilityProvider: AndroidDeviceCapabilityProvider,
    private val knowledgeEmbedding: KnowledgeEmbeddingConfig,
    private val nativeLibraryDir: String,
    private val ioDispatcher: kotlinx.coroutines.CoroutineDispatcher = Dispatchers.IO,
) {
    private data class LoadedModelKey(
        val id: String,
        val requestedContextLength: Int?,
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
    private var chatWarmupOwner: String? = null
    private var voiceOwner: String? = null
    @Volatile private var chatForeground = false
    @Volatile private var appForeground = false
    private val memoryPressure = ModelMemoryPressure(SystemClock::elapsedRealtime)

    private fun canAllocate(
        operation: LlmMemoryOperation,
        queryBytes: Int? = null,
    ): Boolean {
        val chat =
            currentModelKey
                ?.takeIf { operation == LlmMemoryOperation.EMBEDDING }
                ?.let {
                    LlmChatModelMemory(
                        modelId = it.id,
                        modelBytes =
                            assetStore.llmModelPath(llmAsset(it.id))?.length()?.toULong() ?: 0uL,
                        contextSize = (currentContextLength ?: 12000).toUInt(),
                    )
                }
        val budget =
            llmMemoryBudget(
                ModelRuntimeSurface.ANDROID,
                operation,
                chat,
                queryBytes?.coerceAtLeast(0)?.toULong(),
            )
        val headroom =
            deviceCapabilityProvider.modelMemoryHeadroom(
                optionalReserveCapBytes = budget.systemReserveCapBytes?.toLong()
            )
        return headroom != null && headroom >= budget.requiredBytes
    }

    private fun hasRequiredWorkReserve(): Boolean =
        llmHasRequiredWorkReserve(
            deviceCapabilityProvider.modelMemoryHeadroom(optionalWork = false)
        )

    private fun releaseProjector() {
        loadedContext?.releaseMultimodal()
    }

    internal fun setChatForeground(active: Boolean) {
        chatForeground = active
    }

    internal suspend fun setAppForeground(active: Boolean) {
        appForeground = active
        if (!active) releaseIdleResources()
    }

    internal suspend fun handleMemoryPressure() {
        memoryPressure.requestEviction()
        releaseIdleResources()
    }

    private suspend fun releaseIdleResources() =
        withContext(ioDispatcher) { modelLoadMutex.withLock { releaseIdleResourcesLocked() } }

    private fun releaseIdleResourcesLocked(force: Boolean = false) {
        val eviction = memoryPressure.pendingEviction()
        if (force || !appForeground || memoryPressure.suppressesOptionalWork()) {
            unloadTranscriptionModelIfLoaded()
            unloadModel()
            if (eviction != null) memoryPressure.didRelease(eviction)
        }
    }

    private suspend fun <T> withResources(
        retainAfterCooldown: Boolean = false,
        block: suspend () -> T,
    ): T {
        var releaseAfterUse = false
        return withModelResources(modelLoadMutex, { releaseIdleResourcesLocked(releaseAfterUse) }) {
            releaseAfterUse = !retainAfterCooldown && memoryPressure.suppressesOptionalWork()
            block()
        }
    }

    suspend fun prewarmVoice(owner: String) = withModelContext {
        withResources {
            currentCoroutineContext().ensureActive()
            if (!chatForeground || memoryPressure.suppressesOptionalWork()) return@withResources
            prepareVoiceResources()
            var completed = false
            try {
                transcriber.loadModel()
                currentCoroutineContext().ensureActive()
                voiceOwner = owner
                completed = true
            } finally {
                if (!completed) unloadTranscriptionModelIfLoaded()
            }
        }
    }

    suspend fun releaseVoice(owner: String) =
        withContext(ioDispatcher) {
            modelLoadMutex.withLock { if (voiceOwner == owner) unloadTranscriptionModelIfLoaded() }
        }

    suspend fun transcribe(inputSampleRate: UInt, pcm: ByteArray): String = withModelContext {
        withResources {
            currentCoroutineContext().ensureActive()
            prepareVoiceResources()
            try {
                val result = transcriber.transcribe(inputSampleRate, pcm.toDirectByteBuffer())
                currentCoroutineContext().ensureActive()
                result
            } finally {
                unloadTranscriptionModelIfLoaded()
            }
        }
    }

    private fun prepareVoiceResources() {
        releaseProjector()
        if (voiceOwner == null && !canAllocate(LlmMemoryOperation.VOICE)) {
            unloadModel()
            if (!hasRequiredWorkReserve()) throw ModelMemoryUnavailable()
        }
    }

    internal var modelMaintenance: ModelMaintenance? = null

    private suspend fun <T> withModelContext(block: suspend () -> T): T =
        modelMaintenance.withMaintenanceSuspended {
            withContext(ioDispatcher) { block() }
        }

    class EmbeddingAssetInvalid : Exception("Embedding model asset is invalid")

    fun isChatModelReady(selection: LlmModelSelection): Boolean =
        assetStore.isDownloaded(chatAsset(selection))

    fun isEmbeddingModelReady(): Boolean = assetStore.isDownloaded(embeddingAsset)

    suspend fun estimateEmbeddingDownloadSize(): Long? =
        assetStore.estimateDownloadSize(embeddingAsset)

    suspend fun estimateChatModelDownloadSize(selection: LlmModelSelection): Long? =
        assetStore.estimateDownloadSize(chatAsset(selection))

    val isDownloadActive: Boolean
        get() = activeDownloads.get() > 0

    suspend fun ensureChatModelAssetsReady(
        selection: LlmModelSelection,
        onProgress: (DownloadProgress) -> Unit,
    ) {
        deviceCapabilityProvider.chatCapability().requireChatSupported()
        val asset = chatAsset(selection)
        downloadAssets(listOf(asset), onProgress)
        if (!assetStore.isDownloaded(asset)) throw RequiredModelValidationError(selection.id)
    }

    internal suspend fun prewarmChatModelIfDownloaded(
        selection: LlmModelSelection,
        owner: String,
    ): ChatWarmupResult = withModelContext {
        val result =
            withResources(retainAfterCooldown = true) {
                currentCoroutineContext().ensureActive()
                if (
                    !chatForeground ||
                        !appForeground ||
                        voiceOwner != null ||
                        !isChatModelReady(selection)
                )
                    return@withResources ChatWarmupResult.Skipped
                val cooldown = memoryPressure.remainingCooldownMillis()
                if (cooldown > 0) return@withResources ChatWarmupResult.RetryAfter(cooldown)
                if (
                    memoryPressure.suppressesOptionalWork() ||
                        deviceCapabilityProvider.isLowMemory()
                )
                    return@withResources ChatWarmupResult.Skipped
                unloadTranscriptionModelIfLoaded()
                currentCoroutineContext().ensureActive()
                if (loadedContextLength(selection) != null) {
                    if (chatWarmupOwner != null) chatWarmupOwner = owner
                    return@withResources ChatWarmupResult.Ready
                }
                var completed = false
                try {
                    ensureModelReadyLocked(
                        selection,
                        {},
                        allowRecovery = false,
                        shouldDownload = false,
                    )
                    currentCoroutineContext().ensureActive()
                    chatWarmupOwner = owner
                    completed = true
                } finally {
                    if (!completed) unloadModel()
                }
                ChatWarmupResult.Ready
            }
        if (result != ChatWarmupResult.Ready) return@withModelContext result
        val cooldown = memoryPressure.remainingCooldownMillis()
        when {
            !appForeground -> ChatWarmupResult.Skipped
            cooldown > 0 -> ChatWarmupResult.RetryAfter(cooldown)
            !memoryPressure.suppressesOptionalWork() && loadedContextLength(selection) != null ->
                ChatWarmupResult.Ready
            else -> ChatWarmupResult.Skipped
        }
    }

    internal suspend fun releaseChatWarmup(owner: String) =
        withContext(ioDispatcher) {
            modelLoadMutex.withLock { if (chatWarmupOwner == owner) unloadModel() }
        }

    suspend fun ensureRequiredModelsReady(
        selection: LlmModelSelection,
        onProgress: (DownloadProgress) -> Unit,
    ) {
        withModelContext {
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
            withResources {
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
                    shouldDownload = false,
                )
            }
        }
    }

    internal fun generateImageChat(
        context: LlmContext,
        selection: LlmModelSelection,
        messages: List<LlmMessage>,
        imageFiles: List<File>,
        temperature: Float,
        maxTokens: Int?,
        onToken: (String) -> Unit,
    ): GenerationSummary {
        deviceCapabilityProvider.chatCapability().requireChatSupported()
        currentJobId = null
        val mmprojPath = assetStore.llmMmprojPath(chatAsset(selection))?.absolutePath
        if (mmprojPath != null && !hasRequiredWorkReserve()) {
            throw ModelMemoryUnavailable()
        }
        val request =
            chatRequest(
                messages.map { NativeChatMessage(it.roleString(), it.text) },
                imageFiles.map { it.absolutePath },
                mmprojPath,
                temperature,
                maxTokens,
            )

        try {
            val summary = generateStreamWithCallback(context, request, onToken)
            return GenerationSummary(
                summary.jobId,
                summary.generatedTokens ?: 0,
                summary.totalTimeMs,
            )
        } finally {
            releaseProjector()
        }
    }

    internal suspend fun generateTitle(
        selection: LlmModelSelection,
        messages: List<LlmMessage>,
        onToken: (String) -> Unit,
    ): Unit = withModelContext {
        withResources {
            val coroutine = currentCoroutineContext()
            coroutine.ensureActive()
            if (
                !chatForeground ||
                    memoryPressure.suppressesOptionalWork() ||
                    voiceOwner != null ||
                    loadedContextLength(selection) == null
            ) {
                throw ModelMemoryDeferred()
            }
            unloadTranscriptionModelIfLoaded()
            releaseProjector()
            if (!canAllocate(LlmMemoryOperation.TITLE)) throw ModelMemoryDeferred()
            coroutine.ensureActive()
            val model = checkNotNull(loadedModel) { "Model not loaded" }
            model
                .newTitleContext(
                    chatContextSize = checkNotNull(currentContextLength).toUInt(),
                    nThreads = generationThreads(),
                )
                .use { context ->
                    coroutine.ensureActive()
                    val titleMessages =
                        context.truncateTextChatMessages(
                            messages.map { NativeChatMessage(it.roleString(), it.text) },
                            (context.contextSize().toInt() - 48).coerceIn(0, 2000).toUInt(),
                        )
                    coroutine.ensureActive()
                    generateStreamWithCallback(
                        context,
                        chatRequest(
                            titleMessages,
                            emptyList(),
                            null,
                            0.2f,
                            48,
                        ),
                        onToken,
                        isCancelled = { !coroutine.isActive },
                    )
                }
        }
    }

    internal suspend fun <T> withConversationContext(
        selection: LlmModelSelection,
        onProgress: (DownloadProgress) -> Unit,
        block: suspend (LlmContext) -> T,
    ): T = withModelContext {
        withResources {
            currentCoroutineContext().ensureActive()
            ensureModelReadyLocked(selection, onProgress)
            currentCoroutineContext().ensureActive()
            unloadTranscriptionModelIfLoaded()
            block(requireNotNull(loadedContext))
        }
    }

    internal fun generatePreparedChat(
        context: LlmContext,
        messages: List<NativeChatMessage>,
        maxTokens: UInt,
        temperature: Float,
        onToken: (String) -> Unit,
    ): GenerationSummary {
        val summary =
            generateStreamWithCallback(
                context,
                chatRequest(messages, emptyList(), null, temperature, maxTokens.toInt()),
                onToken,
            )
        return GenerationSummary(summary.jobId, summary.generatedTokens ?: 0, summary.totalTimeMs)
    }

    private fun chatRequest(
        messages: List<NativeChatMessage>,
        imagePaths: List<String>,
        mmprojPath: String?,
        temperature: Float,
        maxTokens: Int?,
    ) =
        LlmChatRequest(
            messages = messages,
            templateOverride = null,
            addAssistant = true,
            imagePaths = imagePaths,
            mmprojPath = mmprojPath,
            mediaMarker = null,
            maxTokens = maxTokens,
            temperature = temperature.coerceIn(0.35f, 0.7f),
            topP = 0.9f,
            topK = 50,
            repeatPenalty = 1.18f,
            frequencyPenalty = 0f,
            presencePenalty = 0f,
            seed = null,
            stopSequences = null,
            grammar = null,
        )

    suspend fun <T> withRetrievalContext(
        queryBytes: Int,
        block: suspend (embed: (String) -> List<Float>) -> T,
    ): T = withModelContext {
        withEmbeddingContext(maintenance = false, queryBytes = queryBytes) { embedding ->
            block(embedding::embed)
        }
    }

    internal suspend fun <T> withEmbeddingContext(
        maintenance: Boolean = true,
        queryBytes: Int = 0,
        checkCancellation: () -> Unit = {},
        block: suspend (LlmContext) -> T,
    ): T =
        withContext(ioDispatcher) {
            withResources {
                checkCancellation()
                deviceCapabilityProvider.chatCapability().requireChatSupported()
                if (!isEmbeddingModelReady()) throw EmbeddingAssetInvalid()
                if (maintenance && (voiceOwner != null || memoryPressure.suppressesOptionalWork()))
                    throw ModelMemoryDeferred()
                unloadTranscriptionModelIfLoaded()
                releaseProjector()
                if (
                    !canAllocate(
                        LlmMemoryOperation.EMBEDDING,
                        queryBytes.takeUnless { maintenance },
                    )
                ) {
                    if (maintenance && chatForeground && loadedModel != null)
                        throw ModelMemoryDeferred()
                    unloadModel()
                    if (!hasRequiredWorkReserve()) {
                        if (maintenance) throw ModelMemoryDeferred()
                        throw ModelMemoryUnavailable()
                    }
                }
                if (!backendInitialized) {
                    llmInitBackendFromDirectory(nativeLibraryDir)
                    backendInitialized = true
                }

                val embeddingModel =
                    LlmModel.load(
                        LlmModelLoadParams(
                            modelPath =
                                requireNotNull(assetStore.llmModelPath(embeddingAsset))
                                    .absolutePath,
                            nGpuLayers = 0,
                            useMmap = true,
                            useMlock = false,
                        )
                    )
                var embeddingContext: LlmContext? = null
                try {
                    val threads = max(1, Runtime.getRuntime().availableProcessors() - 1)
                    embeddingContext = embeddingModel.newEmbeddingContext(threads)
                    block(embeddingContext)
                } finally {
                    embeddingContext?.destroy()
                    embeddingModel.destroy()
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
        withModelContext {
            withResources {
                val model = loadedModel ?: return@withResources
                val contextParams =
                    LlmContextParams(
                        contextSize = currentContextLength,
                        nThreads = generationThreads(),
                        nBatch = 512,
                    )
                loadedContext?.destroy()
                loadedContext = model.newContext(contextParams)
                currentContextLength = loadedContext?.contextSize()?.toInt()
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
        chatWarmupOwner = null
        loadedContext?.destroy()
        loadedContext = null
        loadedModel?.destroy()
        loadedModel = null
        currentModelKey = null
        currentContextLength = null
    }

    private fun unloadTranscriptionModelIfLoaded() {
        voiceOwner = null
        runCatching {
            transcriber.unloadModel()
        }
            .onFailure { error ->
                Log.d("LlmProvider", "Transcription model unload skipped", error)
            }
    }

    private suspend fun ensureModelReadyLocked(
        selection: LlmModelSelection,
        onProgress: (DownloadProgress) -> Unit,
        allowRecovery: Boolean = true,
        shouldDownload: Boolean = true,
    ) {
        chatWarmupOwner = null
        deviceCapabilityProvider.chatCapability().requireChatSupported()
        val modelKey = LoadedModelKey(selection.id, selection.contextLength)
        if (!backendInitialized) {
            llmInitBackendFromDirectory(nativeLibraryDir)
            backendInitialized = true
        }

        if (currentModelKey == modelKey && loadedContext != null && loadedModel != null) {
            return
        }

        unloadTranscriptionModelIfLoaded()
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
                requireNotNull(assetStore.llmModelPath(asset)),
            )
        } catch (error: Throwable) {
            if (allowRecovery && wasAlreadyDownloaded && assetStore.removeDownloaded(asset)) {
                onProgress(
                    DownloadProgress(0, "Starting download...", phase = DownloadPhase.Downloading)
                )
                ensureModelReadyLocked(selection, onProgress, allowRecovery = false)
                return
            }
            throw error
        }
        onProgress(DownloadProgress(100, "Ready", phase = DownloadPhase.Ready))
    }

    private suspend fun downloadAssets(
        assets: List<Asset>,
        onProgress: (DownloadProgress) -> Unit,
    ) {
        activeDownloads.incrementAndGet()
        try {
            assetStore.download(assets) { progress ->
                onProgress(
                    DownloadProgress(
                        progress.percentage.toInt().coerceIn(0, 99),
                        progress.status,
                    )
                )
            }
        } finally {
            activeDownloads.decrementAndGet()
        }
    }

    private fun chatAsset(selection: LlmModelSelection): Asset = llmAsset(selection.id)

    private fun generationThreads(): Int =
        (Runtime.getRuntime().availableProcessors() - 1).coerceIn(1, 3)

    private fun loadWithFallbacks(selection: LlmModelSelection, modelFile: File) {
        val desiredCtx = selection.contextLength ?: 12000
        val contexts =
            listOf(desiredCtx, 12000, 8192, 4096, 2048, 1024).distinct().filter { it > 0 }
        val threads = generationThreads()
        val batch = 512

        val modelParams =
            LlmModelLoadParams(
                modelPath = modelFile.absolutePath,
                nGpuLayers = 0,
                useMmap = true,
                useMlock = false,
            )

        val model = LlmModel.load(modelParams)
        loadedModel = model

        var lastError: Throwable? = null
        for (ctx in contexts) {
            try {
                val contextParams =
                    LlmContextParams(
                        contextSize = ctx,
                        nThreads = threads,
                        nBatch = batch,
                    )
                loadedContext = model.newContext(contextParams)
                currentModelKey = LoadedModelKey(selection.id, selection.contextLength)
                currentContextLength = loadedContext?.contextSize()?.toInt()
                return
            } catch (err: Throwable) {
                lastError = err
            }
        }
        unloadModel()
        throw (lastError ?: error("Failed to load model"))
    }

    private fun generateStreamWithCallback(
        context: LlmContext,
        request: LlmChatRequest,
        onToken: (String) -> Unit,
        isCancelled: () -> Boolean = { false },
    ): NativeSummary {
        val callback =
            object : LlmGenerationEventCallback {
                override fun onEvent(event: LlmGenerationEvent) {
                    when (event) {
                        is LlmGenerationEvent.Text -> {
                            currentJobId = event.jobId
                            if (isCancelled()) llmCancel(event.jobId)
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
