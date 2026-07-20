package io.ente.ensu.llm

import android.system.ErrnoException
import android.system.OsConstants
import io.ente.ensu.AppState
import io.ente.ensu.bindings.ConfigDefaults
import io.ente.ensu.bindings.DownloadError
import io.ente.ensu.bindings.LlmException
import io.ente.ensu.device.isChatSupported
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.logging.LogLevel
import io.ente.ensu.settings.SessionPreferencesDataStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

internal class ModelSettingsActions(
    private val state: MutableStateFlow<AppState>,
    private val sessionPreferences: SessionPreferencesDataStore,
    private val llmProvider: LlmProvider,
    private val modelDownloader: ModelDownloader,
    private val logRepository: FileLogRepository,
    private val configDefaults: ConfigDefaults
) {
    private var scope: CoroutineScope? = null
    private var modelDownloadJob: Job? = null

    fun setScope(scope: CoroutineScope) {
        this.scope = scope
    }

    fun updateModelSettings(settings: ModelSettingsState) {
        val oldTarget = resolveTarget(state.value.modelSettings)
        val newTarget = resolveTarget(settings)
        state.update { appState ->
            appState.copy(modelSettings = settings)
        }
        if (downloadIdentityChanged(oldTarget, newTarget)) {
            modelDownloadJob?.cancel()
            modelDownloadJob = null
            modelDownloader.cancel()
        }
        refreshModelDownloadInfo()
    }

    fun hydratePersistedModelSettings(settings: ModelSettingsState) {
        state.update { appState ->
            appState.copy(modelSettings = settings)
        }
        refreshModelDownloadInfo()
    }

    fun resetModelSettings() {
        state.update { appState ->
            appState.copy(modelSettings = ModelSettingsState())
        }
        refreshModelDownloadInfo()
    }

    fun refreshModelDownloadInfo() {
        if (!state.value.chat.deviceCapability.isChatSupported()) {
            modelDownloadJob?.cancel()
            modelDownloader.cancel()
            persistModelDownloadRequested(false)
            state.update { appState ->
                appState.copy(
                    chat = appState.chat.copy(
                        isDownloading = false,
                        downloadPercent = null,
                        downloadStatus = null,
                        downloadPhase = null,
                        modelDownloadSizeBytes = null,
                        hasRequestedModelDownload = false
                    )
                )
            }
            return
        }
        val target = resolveTarget(state.value.modelSettings)
        val isDownloaded = modelDownloader.isDownloaded(target.downloadTarget)
        if (isDownloaded) {
            persistModelDownloadRequested(false)
        }
        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    isModelDownloaded = isDownloaded,
                    isDownloading = if (isDownloaded) false else appState.chat.isDownloading,
                    downloadPercent = if (isDownloaded) null else appState.chat.downloadPercent,
                    downloadStatus = if (isDownloaded) null else appState.chat.downloadStatus,
                    downloadPhase = if (isDownloaded) null else appState.chat.downloadPhase,
                    modelDownloadSizeBytes = if (isDownloaded) null else appState.chat.modelDownloadSizeBytes,
                    hasRequestedModelDownload = appState.chat.hasRequestedModelDownload || isDownloaded
                )
            )
        }

        if (isDownloaded) return

        val scope = scope ?: return
        scope.launch {
            if (!modelDownloader.isDownloadActive && modelDownloadJob?.isActive != true) {
                persistModelDownloadRequested(false)
                state.update { appState ->
                    appState.copy(
                        chat = appState.chat.copy(
                            isDownloading = false,
                            downloadPercent = null,
                            downloadStatus = null,
                            downloadPhase = null,
                            hasRequestedModelDownload = false
                        )
                    )
                }
            }

            val size = modelDownloader.estimateDownloadSize(target.downloadTarget)
            state.update { appState ->
                appState.copy(
                    chat = appState.chat.copy(
                        modelDownloadSizeBytes = size ?: appState.chat.modelDownloadSizeBytes
                    )
                )
            }
        }
    }

    fun startModelDownload(userInitiated: Boolean = true) {
        val scope = scope ?: return
        val currentState = state.value
        if (!currentState.chat.deviceCapability.isChatSupported()) return
        if (modelDownloadJob?.isActive == true) return
        if (currentState.chat.isDownloading || currentState.chat.isGenerating) return
        if (!userInitiated && !currentState.chat.hasRequestedModelDownload) return

        val target = resolveTarget(currentState.modelSettings)
        val isDownloaded = modelDownloader.isDownloaded(target.downloadTarget)
        if (isDownloaded) {
            state.update { appState ->
                appState.copy(
                    chat = appState.chat.copy(
                        isModelDownloaded = true,
                        modelDownloadSizeBytes = null,
                        hasRequestedModelDownload = if (userInitiated) true else appState.chat.hasRequestedModelDownload
                    )
                )
            }
        }

        modelDownloadJob?.cancel()
        if (!isDownloaded) {
            persistModelDownloadRequested(true)
            logRepository.log(
                LogLevel.Info,
                "Model download started",
                details = "model=${target.id}",
                tag = "Model"
            )
            state.update { appState ->
                appState.copy(
                    chat = appState.chat.copy(
                        isDownloading = true,
                        downloadPercent = 0,
                        downloadStatus = "Starting download...",
                        downloadPhase = DownloadPhase.Downloading,
                        hasRequestedModelDownload = if (userInitiated) true else appState.chat.hasRequestedModelDownload
                    )
                )
            }
        }

        modelDownloadJob = scope.launch {
            var loggedComplete = false
            val progressTracker = DownloadProgressTracker(
                initialPercent = if (isDownloaded) null else 0,
                initialStatus = if (isDownloaded) null else "Starting download..."
            )
            try {
                var retryCount = 0
                while (true) {
                    try {
                        llmProvider.ensureModelReady(target) { progress ->
                            val resolvedProgress = progressTracker.resolve(progress)
                            if (!isDownloaded && resolvedProgress.isFinished && !loggedComplete) {
                                loggedComplete = true
                                logRepository.log(
                                    LogLevel.Info,
                                    "Model download complete",
                                    details = "model=${target.id}",
                                    tag = "Model"
                                )
                            }
                            state.update { appState ->
                                appState.copy(
                                    chat = appState.chat.copy(
                                        isDownloading = resolvedProgress.isDownloading,
                                        downloadPercent = resolvedProgress.percent,
                                        downloadStatus = resolvedProgress.status,
                                        downloadPhase = resolvedProgress.phase,
                                        isModelDownloaded = if (resolvedProgress.isFinished) true else appState.chat.isModelDownloaded,
                                        modelDownloadSizeBytes = if (resolvedProgress.isFinished) null else appState.chat.modelDownloadSizeBytes
                                    )
                                )
                            }
                        }
                        break
                    } catch (err: Throwable) {
                        if (!shouldRetryDownload(err, retryCount)) {
                            throw err
                        }

                        retryCount += 1
                        delay(retryDelayMs(retryCount))
                    }
                }
            } catch (err: Throwable) {
                val cancelled = err is kotlinx.coroutines.CancellationException ||
                    err is LlmException.Cancelled
                val failureMessage = if (cancelled) {
                    "Download cancelled"
                } else {
                    userFacingDownloadError(err, isDownloaded)
                }
                state.update { appState ->
                    appState.copy(
                        chat = appState.chat.copy(
                            isDownloading = false,
                            downloadPercent = null,
                            downloadStatus = failureMessage,
                            downloadPhase = if (cancelled) null else DownloadPhase.Failed,
                            hasRequestedModelDownload = false
                        )
                    )
                }
                persistModelDownloadRequested(false)
                if (cancelled) {
                    if (!isDownloaded) {
                        logRepository.log(LogLevel.Info, "Model download cancelled", tag = "Model")
                    }
                } else {
                    logRepository.log(
                        LogLevel.Error,
                        if (isDownloaded) "Model load failed" else "Model download failed",
                        details = err.message,
                        tag = "Model",
                        throwable = err
                    )
                }
            } finally {
                modelDownloadJob = null
                refreshModelDownloadInfo()
            }
        }
    }

    fun prewarmImageInferenceIfDownloaded() {
        val scope = scope ?: return
        val currentState = state.value
        if (currentState.chat.isGenerating || currentState.chat.isDownloading) return
        if (!currentState.chat.deviceCapability.isChatSupported()) return

        val target = resolveTarget(currentState.modelSettings)
        if (!modelDownloader.isDownloaded(target.downloadTarget)) return

        scope.launch {
            try {
                llmProvider.prewarmImageInference(target)
            } catch (err: Throwable) {
                logRepository.log(
                    LogLevel.Warning,
                    "Image inference prewarm skipped",
                    details = err.message,
                    tag = "Model"
                )
            }
        }
    }

    fun cancelModelDownload() {
        modelDownloadJob?.cancel()
        modelDownloadJob = null
        modelDownloader.cancel()
        persistModelDownloadRequested(false)
        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    isDownloading = false,
                    downloadPercent = null,
                    downloadStatus = "Download cancelled",
                    downloadPhase = null,
                    hasRequestedModelDownload = false
                )
            )
        }
        refreshModelDownloadInfo()
    }

    private fun persistModelDownloadRequested(requested: Boolean) {
        scope?.launch {
            runCatching {
                sessionPreferences.setModelDownloadRequested(requested)
            }.onFailure { error ->
                logRepository.log(
                    LogLevel.Error,
                    "Failed to persist model download state",
                    details = error.message,
                    tag = "Model",
                    throwable = error
                )
            }
        }
    }

    fun resolveTarget(settings: ModelSettingsState): LlmModelTarget {
        val useCustom = settings.useCustomModel && settings.modelUrl.isNotBlank()
        val url = if (useCustom) settings.modelUrl else configDefaults.mobileDefaultModel.url
        val mmproj = if (useCustom) {
            settings.mmprojUrl.takeIf { it.isNotBlank() }
        } else {
            configDefaults.mobileDefaultModel.mmprojUrl
        }
        val contextLength = settings.contextLength.toIntOrNull()
        val maxTokens = settings.maxTokens.toIntOrNull()?.takeIf { it > 0 }
        val id = if (useCustom) {
            (listOf(configDefaults.mobileDefaultModel) + configDefaults.mobileModelPresets)
                .firstOrNull { it.url == url && it.mmprojUrl == mmproj }
                ?.id
                ?: "custom:$url"
        } else {
            configDefaults.mobileDefaultModel.id
        }

        return LlmModelTarget(
            id = id,
            url = url,
            mmprojUrl = mmproj,
            contextLength = contextLength,
            maxTokens = maxTokens
        )
    }

    fun resolveTemperature(settings: ModelSettingsState): Float {
        val temperature = settings.temperature.trim().toFloatOrNull()
        val resolved = temperature?.takeIf { it >= 0f } ?: DEFAULT_TEMPERATURE
        return resolved.coerceIn(0.35f, 0.7f)
    }

    private fun downloadIdentityChanged(
        oldTarget: LlmModelTarget,
        newTarget: LlmModelTarget
    ): Boolean {
        return oldTarget.id != newTarget.id ||
            oldTarget.url != newTarget.url ||
            oldTarget.mmprojUrl != newTarget.mmprojUrl
    }

    companion object {
        private const val MAX_DOWNLOAD_RETRIES = 5
        private val NON_RETRYABLE_HTTP = setOf(401, 403, 404)
        private const val RETRY_DELAY_BASE_MS = 1500L
        private const val RETRY_DELAY_MAX_MS = 12000L
        private const val DEFAULT_TEMPERATURE = 0.5f
    }

    private fun shouldRetryDownload(err: Throwable, retryCount: Int): Boolean {
        if (retryCount >= MAX_DOWNLOAD_RETRIES) return false
        if (err is kotlinx.coroutines.CancellationException) return false
        if (err is LlmException.Cancelled) return false
        if (isOutOfStorageError(err)) return false
        if (err is LlmException.Download) {
            when (val error = err.error) {
                is DownloadError.Validation -> return false
                is DownloadError.Http -> if (error.status.toInt() in NON_RETRYABLE_HTTP) return false
                else -> {}
            }
        }
        return true
    }

    private fun retryDelayMs(retryCount: Int): Long {
        val multiplier = 1L shl (retryCount - 1).coerceAtLeast(0)
        return (RETRY_DELAY_BASE_MS * multiplier).coerceAtMost(RETRY_DELAY_MAX_MS)
    }

    private fun userFacingDownloadError(err: Throwable, wasAlreadyDownloaded: Boolean): String {
        if (isOutOfStorageError(err)) {
            return "Not enough storage space to download the model. Please free up space and try again."
        }
        return if (wasAlreadyDownloaded) "Model load failed" else "Download failed. Please try again."
    }

    private fun isOutOfStorageError(err: Throwable): Boolean {
        var current: Throwable? = err
        while (current != null) {
            if (current is LlmException.Download && current.error is DownloadError.StorageFull) {
                return true
            }
            if (current is ErrnoException && current.errno == OsConstants.ENOSPC) return true
            current = current.cause
        }
        return false
    }
}
