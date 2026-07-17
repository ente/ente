package io.ente.ensu.llm

import android.util.Log
import io.ente.ensu.bindings.LlmChatMessage as NativeChatMessage
import io.ente.ensu.bindings.LlmChatRequest
import io.ente.ensu.bindings.LlmContext
import io.ente.ensu.bindings.LlmContextParams
import io.ente.ensu.bindings.LlmGenerationEvent
import io.ente.ensu.bindings.LlmGenerationEventCallback
import io.ente.ensu.bindings.LlmGenerationSummary as NativeSummary
import io.ente.ensu.bindings.LlmModel
import io.ente.ensu.bindings.LlmModelLoadParams
import io.ente.ensu.bindings.Transcriber
import io.ente.ensu.bindings.llmCancel
import io.ente.ensu.bindings.llmInitBackend
import io.ente.ensu.device.AndroidDeviceCapabilityProvider
import io.ente.ensu.device.requireChatSupported
import java.io.File
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class LlmProvider(
    private val downloader: ModelDownloader,
    private val transcriber: Transcriber,
    private val deviceCapabilityProvider: AndroidDeviceCapabilityProvider,
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

    suspend fun ensureModelReady(
        target: LlmModelTarget,
        onProgress: (DownloadProgress) -> Unit
    ) {
        withContext(ioDispatcher) {
            modelLoadMutex.withLock {
                ensureModelReadyLocked(target, onProgress)
            }
        }
    }

    suspend fun generateChat(
        target: LlmModelTarget,
        messages: List<LlmMessage>,
        imageFiles: List<File>,
        temperature: Float,
        maxTokens: Int?,
        onToken: (String) -> Unit
    ): GenerationSummary = withContext(ioDispatcher) {
        deviceCapabilityProvider.chatCapability().requireChatSupported()
        val context = loadedContext ?: throw IllegalStateException("Model context not loaded")
        currentJobId = null
        val mmprojPath = if (imageFiles.isEmpty()) {
            null
        } else {
            downloader.mmprojPath(target.downloadTarget)
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

    suspend fun prewarmImageInference(target: LlmModelTarget) {
        withContext(ioDispatcher) {
            runCatching {
                modelLoadMutex.withLock {
                    if (!downloader.isDownloaded(target.downloadTarget)) return@withLock
                    val mmprojPath = downloader.mmprojPath(target.downloadTarget)
                        ?.takeIf { File(it).exists() }
                        ?: return@withLock
                    ensureModelReadyLocked(target, onProgress = {})
                    val context = loadedContext ?: return@withLock
                    unloadTranscriptionModelIfLoaded()
                    context.prewarmMultimodal(mmprojPath, null)
                }
            }.onFailure { error ->
                Log.d("LlmProvider", "Image inference prewarm skipped", error)
            }
        }
    }

    fun loadedContextLength(target: LlmModelTarget): Int? {
        val modelKey = LoadedModelKey(target.id, target.contextLength)
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

    fun resetContext() {
        val model = loadedModel ?: return
        val contextParams = LlmContextParams(
            contextSize = currentContextLength,
            nThreads = null,
            nBatch = null
        )
        loadedContext?.destroy()
        loadedContext = model.newContext(contextParams)
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
        target: LlmModelTarget,
        onProgress: (DownloadProgress) -> Unit,
        allowRecovery: Boolean = true
    ) {
        deviceCapabilityProvider.chatCapability().requireChatSupported()
        val modelKey = LoadedModelKey(target.id, target.contextLength)
        if (!backendInitialized) {
            llmInitBackend()
            backendInitialized = true
        }

        if (currentModelKey == modelKey && loadedContext != null && loadedModel != null) {
            return
        }

        unloadModel()

        val downloaded = downloader.download(listOf(target.downloadTarget), onProgress)

        onProgress(DownloadProgress(100, "Loading model...", phase = DownloadPhase.Loading))
        try {
            loadWithFallbacks(target, downloader.modelPath(target.downloadTarget))
        } catch (error: Throwable) {
            if (allowRecovery && !downloaded && downloader.removeDownloaded(target.downloadTarget)) {
                onProgress(DownloadProgress(0, "Starting download...", phase = DownloadPhase.Downloading))
                ensureModelReadyLocked(target, onProgress, allowRecovery = false)
                return
            }
            throw error
        }
        onProgress(DownloadProgress(100, "Ready", phase = DownloadPhase.Ready))
    }

    private fun loadWithFallbacks(target: LlmModelTarget, modelFile: File) {
        val desiredCtx = target.contextLength ?: 12000
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
                currentModelKey = LoadedModelKey(target.id, target.contextLength)
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
