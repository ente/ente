package io.ente.ensu
import io.ente.ensu.llm.ModelSettingsActions
import io.ente.ensu.chat.AttachmentStoreActions
import io.ente.ensu.chat.ChatStoreActions

import io.ente.ensu.chat.ChatRepository
import io.ente.ensu.device.ChatDeviceCapability
import io.ente.ensu.bindings.Transcriber
import io.ente.ensu.device.AndroidDeviceCapabilityProvider
import io.ente.ensu.llm.DownloadPhase
import io.ente.ensu.llm.LlmProvider
import io.ente.ensu.llm.ModelDownloader
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.chat.Attachment
import io.ente.ensu.chat.ChatMessage
import io.ente.ensu.bindings.ConfigDefaults
import io.ente.ensu.logging.LogLevel
import io.ente.ensu.settings.SessionPreferencesDataStore
import io.ente.ensu.AppState
import io.ente.ensu.settings.DeveloperSettingsState
import io.ente.ensu.llm.ModelSettingsState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AppStore(
    private val sessionPreferences: SessionPreferencesDataStore,
    private val chatRepository: ChatRepository,
    private val llmProvider: LlmProvider,
    val modelDownloader: ModelDownloader,
    val transcriber: Transcriber,
    private val deviceCapabilityProvider: AndroidDeviceCapabilityProvider,
    val configDefaults: ConfigDefaults,
    private val logRepository: FileLogRepository,
    private val clock: () -> Long = { System.currentTimeMillis() }
) {
    private val _state = MutableStateFlow(AppState())
    val state: StateFlow<AppState> = _state.asStateFlow()

    private val messageStore = mutableMapOf<String, MutableList<ChatMessage>>()
    private val attachmentActions = AttachmentStoreActions(_state, messageStore)
    private val modelSettingsActions =
        ModelSettingsActions(_state, sessionPreferences, llmProvider, modelDownloader, logRepository, configDefaults)
    private val chatActions = ChatStoreActions(
        state = _state,
        sessionPreferences = sessionPreferences,
        chatRepository = chatRepository,
        llmProvider = llmProvider,
        modelDownloader = modelDownloader,
        clock = clock,
        logRepository = logRepository,
        messageStore = messageStore,
        attachmentActions = attachmentActions,
        modelSettingsActions = modelSettingsActions,
        configDefaults = configDefaults
    )
    fun bootstrap(scope: CoroutineScope) {
        chatActions.setScope(scope)
        modelSettingsActions.setScope(scope)
        refreshDeviceCapability(scope)
        chatActions.bootstrap(scope)
        modelSettingsActions.refreshModelDownloadInfo()
        _state.value = _state.value.copy(
            chat = _state.value.chat.copy(isModelStateKnown = true)
        )
    }

    fun refreshDeviceCapability(scope: CoroutineScope? = null) {
        val capability = deviceCapabilityProvider.chatCapability()
        val unsupported = capability is ChatDeviceCapability.UnsupportedLowMemory
        _state.value = _state.value.copy(
            chat = _state.value.chat.copy(
                deviceCapability = capability,
                showUnsupportedDeviceDialog = unsupported || _state.value.chat.showUnsupportedDeviceDialog,
                isDownloading = if (unsupported) false else _state.value.chat.isDownloading,
                downloadPercent = if (unsupported) null else _state.value.chat.downloadPercent,
                downloadStatus = if (unsupported) null else _state.value.chat.downloadStatus,
                downloadPhase = if (unsupported) null else _state.value.chat.downloadPhase,
                hasRequestedModelDownload = if (unsupported) false else _state.value.chat.hasRequestedModelDownload,
                editingMessageId = if (unsupported) null else _state.value.chat.editingMessageId,
                messageText = if (unsupported) "" else _state.value.chat.messageText,
                attachments = if (unsupported) emptyList() else _state.value.chat.attachments
            )
        )
        if (unsupported) {
            scope?.let { coroutineScope ->
                coroutineScope.launch {
                    sessionPreferences.setModelDownloadRequested(false)
                }
            }
        }
        logRepository.log(
            LogLevel.Info,
            "Chat device capability evaluated",
            details = "capability=$capability",
            tag = "App"
        )
    }

    fun dismissUnsupportedDeviceDialog() {
        _state.value = _state.value.copy(
            chat = _state.value.chat.copy(showUnsupportedDeviceDialog = false)
        )
    }

    fun hydrateModelDownloadRequested(requested: Boolean) {
        if (!requested) return
        _state.value = _state.value.copy(
            chat = _state.value.chat.copy(
                hasRequestedModelDownload = true,
                isDownloading = true,
                downloadStatus = "Resuming download...",
                downloadPhase = DownloadPhase.Downloading
            )
        )
    }

    fun createNewSession(): String = chatActions.createNewSession()

    fun startNewSessionDraft() = chatActions.startNewSessionDraft()

    fun selectSession(sessionId: String) = chatActions.selectSession(sessionId)

    fun deleteSession(sessionId: String) = chatActions.deleteSession(sessionId)

    fun persistSelectedSession(scope: CoroutineScope, sessionId: String?) =
        chatActions.persistSelectedSession(scope, sessionId)

    fun updateMessageText(value: String) = chatActions.updateMessageText(value)

    fun updateBranchSelection(messageId: String, selectedIndex: Int) =
        chatActions.updateBranchSelection(messageId, selectedIndex)

    fun beginEditing(messageId: String) = chatActions.beginEditing(messageId)

    fun cancelEditing() = chatActions.cancelEditing()

    fun setAttachmentProcessing(isProcessing: Boolean) =
        attachmentActions.setAttachmentProcessing(isProcessing)

    fun addAttachment(attachment: Attachment) = attachmentActions.addAttachment(attachment)

    fun removeAttachment(attachment: Attachment) = attachmentActions.removeAttachment(attachment)

    fun stopGeneration() = chatActions.stopGeneration()

    fun startModelDownload(userInitiated: Boolean = true) =
        modelSettingsActions.startModelDownload(userInitiated)

    fun prewarmImageInferenceIfDownloaded() =
        modelSettingsActions.prewarmImageInferenceIfDownloaded()

    fun refreshModelDownloadInfo() = modelSettingsActions.refreshModelDownloadInfo()

    fun cancelDownload() {
        chatActions.cancelGenerationForDownload()
        modelSettingsActions.cancelModelDownload()
    }

    fun retryAssistantMessage(messageId: String) = chatActions.retryAssistantMessage(messageId)

    fun sendMessage() = chatActions.sendMessage()

    fun confirmOverflowTrim() = chatActions.confirmOverflowTrim()

    fun cancelOverflowDialog() = chatActions.cancelOverflowDialog()

    fun updateModelSettings(state: ModelSettingsState) =
        modelSettingsActions.updateModelSettings(state)

    fun resetModelSettings() = modelSettingsActions.resetModelSettings()

    fun updateDeveloperSettings(state: DeveloperSettingsState) {
        _state.value = _state.value.copy(developerSettings = state)
    }

    fun unlockAdvancedSettings() {
        updateDeveloperSettings(
            _state.value.developerSettings.copy(isAdvancedUnlocked = true)
        )
    }

    fun applyPersistedSettings(
        developerSettings: DeveloperSettingsState,
        modelSettings: ModelSettingsState
    ) {
        _state.value = _state.value.copy(developerSettings = developerSettings)
        modelSettingsActions.hydratePersistedModelSettings(modelSettings)
    }

}
