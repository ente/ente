package io.ente.ensu

import android.content.Context
import android.icu.text.BreakIterator
import io.ente.ensu.assets.AssetStore
import io.ente.ensu.bindings.ConfigDefaults
import io.ente.ensu.bindings.DictationInsertion
import io.ente.ensu.chat.Attachment
import io.ente.ensu.chat.AttachmentStoreActions
import io.ente.ensu.chat.ChatMessage
import io.ente.ensu.chat.ChatRepository
import io.ente.ensu.chat.ChatStoreActions
import io.ente.ensu.chat.VoiceInputFailure
import io.ente.ensu.chat.VoiceTranscriptionController
import io.ente.ensu.device.AndroidDeviceCapabilityProvider
import io.ente.ensu.device.ChatDeviceCapability
import io.ente.ensu.knowledge.KnowledgeProvider
import io.ente.ensu.knowledge.KnowledgeStore
import io.ente.ensu.llm.DownloadPhase
import io.ente.ensu.llm.LlmProvider
import io.ente.ensu.llm.ModelSettingsActions
import io.ente.ensu.llm.ModelSettingsState
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.logging.LogLevel
import io.ente.ensu.notes.NotesStore
import io.ente.ensu.settings.DeveloperSettingsState
import io.ente.ensu.settings.SessionPreferencesDataStore
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AppStore(
    context: Context,
    private val sessionPreferences: SessionPreferencesDataStore,
    chatRepository: ChatRepository,
    val llmProvider: LlmProvider,
    knowledgeProvider: KnowledgeProvider,
    val assetStore: AssetStore,
    private val deviceCapabilityProvider: AndroidDeviceCapabilityProvider,
    val configDefaults: ConfigDefaults,
    private val logRepository: FileLogRepository,
    clock: () -> Long = { System.currentTimeMillis() },
) {
    private val sourcePreferences =
        context.applicationContext.getSharedPreferences("ensu_chat_sources", Context.MODE_PRIVATE)
    private val _state = MutableStateFlow(AppState())
    val state: StateFlow<AppState> = _state.asStateFlow()

    val notesStore =
        NotesStore(context, llmProvider, logRepository).also { llmProvider.modelMaintenance = it }

    private val messageStore = mutableMapOf<String, MutableList<ChatMessage>>()
    private val attachmentActions = AttachmentStoreActions(_state, messageStore)
    private val knowledgeStore =
        KnowledgeStore(
            context = context,
            state = _state,
            provider = knowledgeProvider,
            datasets = configDefaults.knowledgeDatasets,
            logRepository = logRepository,
        )
    private val modelSettingsActions =
        ModelSettingsActions(
            state = _state,
            sessionPreferences = sessionPreferences,
            llmProvider = llmProvider,
            logRepository = logRepository,
            notesStore = notesStore,
            awaitKnowledgeReady = knowledgeStore::awaitReady,
        )
    private val chatActions =
        ChatStoreActions(
            state = _state,
            sessionPreferences = sessionPreferences,
            chatRepository = chatRepository,
            llmProvider = llmProvider,
            knowledgeProvider = knowledgeProvider,
            clock = clock,
            logRepository = logRepository,
            messageStore = messageStore,
            attachmentActions = attachmentActions,
            modelSettingsActions = modelSettingsActions,
            configDefaults = configDefaults,
            notesStore = notesStore,
            awaitKnowledgeReady = knowledgeStore::awaitReady,
        )

    private var composerRevision = 0uL
    private var emptyComposerId = UUID.randomUUID().toString()
    private var composerSelectionStart = 0
    private var composerSelectionEnd = 0
    private var composerIsComposing = false

    internal fun updateComposerSelection(start: Int, end: Int, isComposing: Boolean) {
        composerSelectionStart = start
        composerSelectionEnd = end
        composerIsComposing = isComposing
    }

    private fun invalidateComposer() {
        composerRevision++
        voiceController.composerCaret = null
    }

    internal val voiceController: VoiceTranscriptionController =
        VoiceTranscriptionController(
            context.applicationContext,
            assetStore,
            llmProvider,
            logRepository,
            ::trackVoiceInput,
        ) { insertion, transcript ->
            val chat = _state.value.chat
            runCatching {
                    val result =
                        insertion.apply(
                            chat.currentSessionId ?: emptyComposerId,
                            composerRevision,
                            chat.messageText,
                            transcript,
                            true,
                            false,
                        )
                    chatActions.updateMessageText(result.text)
                    composerRevision = result.revision
                    voiceController.composerCaret = result.caretUtf16.toInt()
                    true
                }
                .getOrDefault(false)
        }

    internal fun openVoiceInput(
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
        isComposing: Boolean,
    ) {
        val chat = _state.value.chat
        if (isComposing || chat.isGenerating || chat.isDownloading || chat.editingMessageId != null)
            return
        if (chat.messageText != text || !voiceController.canOpen) return
        if (selectionStart !in 0..selectionEnd || selectionEnd > text.length) return
        val characters = BreakIterator.getCharacterInstance(Locale.ROOT).apply { setText(text) }
        if (!characters.isBoundary(selectionStart) || !characters.isBoundary(selectionEnd)) return
        updateComposerSelection(selectionStart, selectionEnd, isComposing)
        val destination = chat.currentSessionId ?: emptyComposerId
        voiceController.open {
            val current = _state.value.chat
            val start = composerSelectionStart
            val end = composerSelectionEnd
            val boundaries =
                BreakIterator.getCharacterInstance(Locale.ROOT).apply {
                    setText(current.messageText)
                }
            if (
                destination != (current.currentSessionId ?: emptyComposerId) ||
                    current.isGenerating ||
                    current.isDownloading ||
                    current.editingMessageId != null ||
                    composerIsComposing ||
                    start !in 0..end ||
                    end > current.messageText.length ||
                    !boundaries.isBoundary(start) ||
                    !boundaries.isBoundary(end)
            )
                null
            else DictationInsertion(destination, composerRevision, start.toUInt(), end.toUInt())
        }
    }

    fun dispose() = voiceController.dispose()

    fun bootstrap(scope: CoroutineScope) {
        notesStore.bootstrap(scope)
        chatActions.setScope(scope)
        modelSettingsActions.bootstrap(scope)
        refreshDeviceCapability(scope)
        chatActions.bootstrap(scope)
        modelSettingsActions.refreshModelDownloadInfo()
        knowledgeStore.bootstrap(scope)
        _state.value = _state.value.copy(chat = _state.value.chat.copy(isModelStateKnown = true))
    }

    fun setChatActive(active: Boolean) {
        if (!active) chatActions.cancelSessionSummary()
        modelSettingsActions.setChatActive(active)
    }

    fun setAppForeground(active: Boolean) {
        voiceController.setForeground(active)
        modelSettingsActions.setAppForeground(active)
    }

    fun setPickerPending(pending: Boolean) {
        if (pending) voiceController.discard(keepDownload = true)
        modelSettingsActions.setPickerPending(pending)
    }

    fun handleMemoryPressure() {
        voiceController.interrupt(VoiceInputFailure.MemoryUnavailable)
        chatActions.cancelSessionSummary()
        modelSettingsActions.handleMemoryPressure()
    }

    fun trackVoiceInput(job: Job) {
        chatActions.cancelSessionSummary()
        modelSettingsActions.trackVoiceInput(job)
    }

    fun refreshDeviceCapability(scope: CoroutineScope? = null) {
        val capability = deviceCapabilityProvider.chatCapability()
        val unsupported = capability is ChatDeviceCapability.UnsupportedLowMemory
        if (unsupported) {
            voiceController.discard()
            invalidateComposer()
        }
        _state.value =
            _state.value.copy(
                chat =
                    _state.value.chat.copy(
                        deviceCapability = capability,
                        showUnsupportedDeviceDialog =
                            unsupported || _state.value.chat.showUnsupportedDeviceDialog,
                        isDownloading = if (unsupported) false else _state.value.chat.isDownloading,
                        downloadPercent =
                            if (unsupported) null else _state.value.chat.downloadPercent,
                        downloadStatus =
                            if (unsupported) null else _state.value.chat.downloadStatus,
                        downloadPhase = if (unsupported) null else _state.value.chat.downloadPhase,
                        hasRequestedModelDownload =
                            if (unsupported) false else _state.value.chat.hasRequestedModelDownload,
                        editingMessageId =
                            if (unsupported) null else _state.value.chat.editingMessageId,
                        messageText = if (unsupported) "" else _state.value.chat.messageText,
                        attachments =
                            if (unsupported) emptyList() else _state.value.chat.attachments,
                    )
            )
        if (unsupported) {
            scope?.let { coroutineScope ->
                coroutineScope.launch { sessionPreferences.setModelDownloadRequested(false) }
            }
        }
        logRepository.log(
            LogLevel.Info,
            "Chat device capability evaluated",
            details = "capability=$capability",
            tag = "App",
        )
    }

    fun dismissUnsupportedDeviceDialog() {
        _state.value =
            _state.value.copy(chat = _state.value.chat.copy(showUnsupportedDeviceDialog = false))
    }

    fun hydrateModelDownloadRequested(requested: Boolean) {
        if (!requested) return
        _state.value =
            _state.value.copy(
                chat =
                    _state.value.chat.copy(
                        hasRequestedModelDownload = true,
                        isDownloading = true,
                        downloadStatus = "Resuming download...",
                        downloadPhase = DownloadPhase.Downloading,
                    )
            )
    }

    fun createNewSession(): String {
        voiceController.discard(keepDownload = true)
        invalidateComposer()
        return chatActions.createNewSession()
    }

    fun startNewSessionDraft() {
        voiceController.discard(keepDownload = true)
        emptyComposerId = UUID.randomUUID().toString()
        invalidateComposer()
        chatActions.startNewSessionDraft()
    }

    fun selectSession(sessionId: String) {
        voiceController.discard(keepDownload = true)
        invalidateComposer()
        chatActions.selectSession(sessionId)
    }

    fun deleteSession(sessionId: String) {
        if (sessionId == _state.value.chat.currentSessionId) {
            voiceController.discard(keepDownload = true)
            invalidateComposer()
        }
        chatActions.deleteSession(sessionId)
    }

    fun persistSelectedSession(scope: CoroutineScope, sessionId: String?) =
        chatActions.persistSelectedSession(scope, sessionId)

    fun updateMessageText(value: String) {
        if (value != _state.value.chat.messageText) {
            invalidateComposer()
        }
        chatActions.updateMessageText(value)
    }

    fun updateBranchSelection(messageId: String, selectedIndex: Int) =
        chatActions.updateBranchSelection(messageId, selectedIndex)

    fun beginEditing(messageId: String) {
        voiceController.discard(keepDownload = true)
        invalidateComposer()
        chatActions.beginEditing(messageId)
    }

    fun cancelEditing() {
        invalidateComposer()
        chatActions.cancelEditing()
    }

    fun setAttachmentProcessing(isProcessing: Boolean) =
        attachmentActions.setAttachmentProcessing(isProcessing)

    fun addAttachment(attachment: Attachment) = attachmentActions.addAttachment(attachment)

    fun removeAttachment(attachment: Attachment) = attachmentActions.removeAttachment(attachment)

    fun stopGeneration() = chatActions.stopGeneration()

    fun startModelDownload(userInitiated: Boolean = true) =
        modelSettingsActions.startModelDownload(userInitiated)

    fun refreshModelDownloadInfo() = modelSettingsActions.refreshModelDownloadInfo()

    fun retrySourceInventory() {
        knowledgeStore.retry()
        notesStore.retryLoad()
        chatActions.refreshSourceInventory()
    }

    fun downloadOrUpdateKnowledgePack(stableId: String) = knowledgeStore.downloadOrUpdate(stableId)

    fun setKnowledgePackEnabled(stableId: String, enabled: Boolean) =
        knowledgeStore.setEnabled(stableId, enabled)

    fun hasSeenSourceIntroduction() =
        sourcePreferences.getBoolean("sources_introduction_seen", false)

    fun completeSourceIntroduction() {
        sourcePreferences.edit().putBoolean("sources_introduction_seen", true).apply()
    }

    fun cancelKnowledgePackDownload(stableId: String) = knowledgeStore.cancel(stableId)

    fun cancelDownload() {
        chatActions.cancelGenerationForDownload()
        modelSettingsActions.cancelModelDownload()
    }

    fun retryAssistantMessage(messageId: String) {
        voiceController.interrupt()
        chatActions.retryAssistantMessage(messageId)
    }

    fun sendMessage() {
        if (voiceController.blocksComposer) return
        voiceController.discard(keepDownload = true)
        invalidateComposer()
        chatActions.sendMessage()
    }

    fun confirmOverflowTrim() = chatActions.confirmOverflowTrim()

    fun cancelOverflowDialog() = chatActions.cancelOverflowDialog()

    fun updateModelSettings(state: ModelSettingsState) {
        chatActions.cancelGenerationForDownload()
        modelSettingsActions.updateModelSettings(state)
    }

    fun resetModelSettings() {
        chatActions.cancelGenerationForDownload()
        modelSettingsActions.resetModelSettings()
    }

    fun updateDeveloperSettings(state: DeveloperSettingsState) {
        if (state.systemPrompt != _state.value.developerSettings.systemPrompt) {
            chatActions.cancelGenerationForDownload()
        }
        _state.value = _state.value.copy(developerSettings = state)
    }

    fun unlockAdvancedSettings() {
        updateDeveloperSettings(_state.value.developerSettings.copy(isAdvancedUnlocked = true))
    }

    fun applyPersistedSettings(
        developerSettings: DeveloperSettingsState,
        modelSettings: ModelSettingsState,
    ) {
        _state.value = _state.value.copy(developerSettings = developerSettings)
        modelSettingsActions.hydratePersistedModelSettings(modelSettings)
    }
}
