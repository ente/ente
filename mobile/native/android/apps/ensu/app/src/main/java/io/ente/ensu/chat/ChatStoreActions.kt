package io.ente.ensu.chat
import io.ente.ensu.llm.DownloadProgressTracker
import io.ente.ensu.llm.ModelSettingsActions

import io.ente.ensu.chat.ChatRepository
import io.ente.ensu.device.isChatSupported
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.llm.DownloadPhase
import io.ente.ensu.llm.LlmMessage
import io.ente.ensu.llm.LlmMessageRole
import io.ente.ensu.llm.LlmModelTarget
import io.ente.ensu.llm.ModelDownloader
import io.ente.ensu.llm.LlmProvider
import io.ente.ensu.chat.Attachment
import io.ente.ensu.chat.ChatMessage
import io.ente.ensu.chat.ChatSession
import io.ente.ensu.bindings.DbException
import io.ente.ensu.bindings.LlmException
import io.ente.ensu.bindings.ConfigDefaults
import io.ente.ensu.logging.LogLevel
import io.ente.ensu.chat.MessageAuthor
import io.ente.ensu.chat.sessionTitleFromText
import io.ente.ensu.settings.SessionPreferencesDataStore
import io.ente.ensu.AppState
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

internal class ChatStoreActions(
    private val state: MutableStateFlow<AppState>,
    private val sessionPreferences: SessionPreferencesDataStore,
    private val chatRepository: ChatRepository,
    private val llmProvider: LlmProvider,
    private val modelDownloader: ModelDownloader,
    private val clock: () -> Long,
    private val logRepository: FileLogRepository,
    private val messageStore: MutableMap<String, MutableList<ChatMessage>>,
    private val attachmentActions: AttachmentStoreActions,
    private val modelSettingsActions: ModelSettingsActions,
    private val configDefaults: ConfigDefaults
) {
    private val branchSelections = mutableMapOf<String, MutableMap<String, String>>()
    private val sessionSummaries = mutableMapOf<String, String>()
    private val sessionAccessTimes = mutableMapOf<String, Long>()
    private var scope: CoroutineScope? = null
    private var generationJob: Job? = null
    private var sessionSummaryJob: Job? = null
    private var stopRequested = false
    private var streamingParentId: String? = null
    private var activeGenerationToken = 0L
    private var pendingOverflow: PendingOverflow? = null
    private var overflowBypassMessageId: String? = null

    private val sessionSummarySystemPrompt = configDefaults.sessionSummarySystemPrompt
    private val sessionSummaryMaxWords = 7

    fun setScope(scope: CoroutineScope) {
        this.scope = scope
    }

    fun bootstrap(scope: CoroutineScope) {
        this.scope = scope

        sessionSummaries.clear()
        scope.launch {
            val summaries = sessionPreferences.sessionSummaries.first()
            sessionSummaries.clear()
            sessionSummaries.putAll(summaries.mapKeys { sessionKey(it.key) })
            applySessionSummariesToState()
        }

        if (state.value.chat.sessions.isEmpty()) {
            loadSessionsFromDb()
        }

        scope.launch {
            sessionPreferences.sessionSummaries.collectLatest { summaries ->
                sessionSummaries.clear()
                sessionSummaries.putAll(summaries.mapKeys { sessionKey(it.key) })
                applySessionSummariesToState()
            }
        }
    }

    fun createNewSession(): String {
        resetGenerationState()

        val session = chatRepository.createSession("New Chat")
        messageStore[session.id] = mutableListOf()
        branchSelections[session.id] = mutableMapOf()

        state.update { appState ->
            val updatedSessions = listOf(session) + appState.chat.sessions
            appState.copy(
                chat = appState.chat.copy(
                    sessions = updatedSessions,
                    currentSessionId = session.id,
                    messageText = "",
                    attachments = emptyList(),
                    editingMessageId = null
                )
            )
        }
        markSessionAccess(session.id)
        trimSessionCaches()
        rebuildChatState(session.id)
        logRepository.log(LogLevel.Info, "Session created", tag = "Chat")
        return session.id
    }

    fun startNewSessionDraft() {
        if (state.value.chat.isDownloading) return

        resetGenerationState()
        attachmentActions.discardAttachments(state.value.chat.attachments)
        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    currentSessionId = null,
                    messages = emptyList(),
                    branchSelections = emptyMap(),
                    messageText = "",
                    attachments = emptyList(),
                    editingMessageId = null
                )
            )
        }
    }

    fun selectSession(sessionId: String) {
        resetGenerationState()
        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    currentSessionId = sessionId
                )
            )
        }
        val scope = scope ?: return
        scope.launch(Dispatchers.IO) {
            loadMessagesFromDb(sessionId)
            rebuildChatState(sessionId)
        }
    }

    fun deleteSession(sessionId: String) {
        val currentState = state.value
        val isCurrent = currentState.chat.currentSessionId == sessionId

        if (isCurrent) {
            cancelGeneration()
        }

        chatRepository.deleteSession(sessionId)
        if (isCurrent) attachmentActions.discardAttachments(currentState.chat.attachments)
        removeSessionCaches(sessionId)
        sessionSummaries.remove(sessionKey(sessionId))
        scope?.launch { sessionPreferences.setSessionSummary(sessionId, null) }

        val sessions = currentState.chat.sessions.filterNot { it.id == sessionId }

        val newCurrent = if (isCurrent) {
            sessions.firstOrNull()?.id
        } else {
            currentState.chat.currentSessionId?.takeIf { id -> sessions.any { it.id == id } }
                ?: sessions.firstOrNull()?.id
        }

        state.update { appState ->
            val resetCurrent = isCurrent
            appState.copy(
                chat = appState.chat.copy(
                    sessions = sessions,
                    currentSessionId = newCurrent,
                    isGenerating = if (resetCurrent) false else appState.chat.isGenerating,
                    isDownloading = if (resetCurrent) false else appState.chat.isDownloading,
                    streamingResponse = if (resetCurrent) "" else appState.chat.streamingResponse,
                    streamingParentId = if (resetCurrent) null else appState.chat.streamingParentId,
                    downloadPercent = if (resetCurrent) null else appState.chat.downloadPercent,
                    downloadStatus = if (resetCurrent) null else appState.chat.downloadStatus,
                    downloadPhase = if (resetCurrent) null else appState.chat.downloadPhase,
                    messageText = if (resetCurrent) "" else appState.chat.messageText,
                    attachments = if (resetCurrent) emptyList() else appState.chat.attachments,
                    editingMessageId = if (resetCurrent) null else appState.chat.editingMessageId
                )
            )
        }

        if (newCurrent != null) {
            val scope = scope
            if (scope != null) {
                scope.launch(Dispatchers.IO) {
                    loadMessagesFromDb(newCurrent)
                    rebuildChatState(newCurrent)
                }
            } else {
                state.update { appState ->
                    appState.copy(chat = appState.chat.copy(messages = emptyList(), branchSelections = emptyMap()))
                }
            }
        } else {
            state.update { appState ->
                appState.copy(chat = appState.chat.copy(messages = emptyList(), branchSelections = emptyMap()))
            }
        }
        trimSessionCaches(sessions.map { it.id }.toSet())

        scope?.launch { sessionPreferences.setSelectedSessionId(newCurrent) }
        logRepository.log(LogLevel.Info, "Session deleted", tag = "Chat")
    }

    fun persistSelectedSession(scope: CoroutineScope, sessionId: String?) {
        scope.launch {
            sessionPreferences.setSelectedSessionId(sessionId)
        }
    }

    fun updateMessageText(value: String) {
        state.update { appState ->
            appState.copy(chat = appState.chat.copy(messageText = value))
        }
    }

    fun updateBranchSelection(messageId: String, selectedIndex: Int) {
        if (state.value.chat.isGenerating) {
            stopGeneration()
        }
        val sessionId = state.value.chat.currentSessionId ?: return
        val messages = messageStore[sessionId].orEmpty()
        val byId = messages.associateBy { it.id }
        val message = byId[messageId] ?: return
        val parentKey = message.parentId?.takeIf { byId.containsKey(it) } ?: "__root__"
        val siblings = dedupeSiblings(buildChildrenMap(messages)[parentKey].orEmpty())
        if (siblings.isEmpty()) return
        val index = (selectedIndex - 1).coerceIn(0, siblings.lastIndex)
        val selectionMap = branchSelections.getOrPut(sessionId) { mutableMapOf() }
        selectionMap[parentKey] = siblings[index].id
        rebuildChatState(sessionId)
    }

    fun beginEditing(messageId: String) {
        val currentState = state.value
        if (!currentState.chat.deviceCapability.isChatSupported()) return
        val sessionId = currentState.chat.currentSessionId ?: return
        val message = messageStore[sessionId]?.firstOrNull { it.id == messageId } ?: return
        if (message.author != MessageAuthor.User) return

        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    editingMessageId = message.id,
                    messageText = message.text,
                    attachments = message.attachments
                )
            )
        }
    }

    fun cancelEditing() {
        attachmentActions.discardAttachments(state.value.chat.attachments)
        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    editingMessageId = null,
                    messageText = "",
                    attachments = emptyList()
                )
            )
        }
    }

    fun stopGeneration() {
        stopRequested = true
        llmProvider.stopGeneration()
        generationJob?.cancel()
    }

    fun retryAssistantMessage(messageId: String) {
        if (state.value.chat.isGenerating) {
            stopGeneration()
        }
        if (!state.value.chat.deviceCapability.isChatSupported()) return
        val sessionId = state.value.chat.currentSessionId ?: return

        // For synthetic interrupted placeholders, find the parent user message directly
        val parent = if (messageId.startsWith("interrupted-placeholder-")) {
            val parentUserId = messageId.removePrefix("interrupted-placeholder-")
            messageStore[sessionId]?.firstOrNull { it.id == parentUserId }
        } else {
            val message = messageStore[sessionId]?.firstOrNull { it.id == messageId } ?: return
            if (message.author != MessageAuthor.Assistant) return
            val parentId = message.parentId ?: return
            messageStore[sessionId]?.firstOrNull { it.id == parentId }
        } ?: return

        llmProvider.resetContext()
        startGeneration(sessionId, parent)
    }

    fun sendMessage() {
        val currentState = state.value
        if (currentState.chat.isGenerating || currentState.chat.isDownloading) return
        if (!currentState.chat.deviceCapability.isChatSupported()) return
        val text = currentState.chat.messageText.trim()
        val attachments = currentState.chat.attachments
        if (text.isEmpty() && attachments.isEmpty()) return

        val sessionId = currentState.chat.currentSessionId ?: createNewSession()
        val timestamp = clock()

        val editingMessageId = currentState.chat.editingMessageId
        val parentId = if (editingMessageId != null) {
            val existing = messageStore[sessionId]?.firstOrNull { it.id == editingMessageId }
            existing?.parentId
        } else {
            buildSelectedPath(sessionId).lastOrNull()?.id
        }

        val userMessage = chatRepository.insertMessage(
            sessionId = sessionId,
            parentId = parentId,
            author = MessageAuthor.User,
            text = text,
            attachments = attachments
        )

        messageStore.getOrPut(sessionId) { mutableListOf() }.add(userMessage)
        updateSelectionForParent(sessionId, parentId, userMessage.id)

        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    messageText = "",
                    attachments = emptyList(),
                    editingMessageId = null
                )
            )
        }

        updateCurrentSessionPreview(sessionId, text, timestamp)
        rebuildChatState(sessionId)
        startGeneration(sessionId, userMessage)
        logRepository.log(
            LogLevel.Info,
            "Message sent",
            details = "len=${text.length} attachments=${attachments.size} edited=${editingMessageId != null}",
            tag = "Chat"
        )
    }

    fun confirmOverflowTrim() {
        val pending = pendingOverflow ?: return
        val message = messageStore[pending.sessionId]?.firstOrNull { it.id == pending.messageId }
        if (message == null) {
            pendingOverflow = null
            overflowBypassMessageId = null
            clearOverflowDialog()
            return
        }
        overflowBypassMessageId = pending.messageId
        pendingOverflow = null
        clearOverflowDialog()
        startGeneration(pending.sessionId, message)
    }

    fun cancelOverflowDialog() {
        pendingOverflow = null
        overflowBypassMessageId = null
        clearOverflowDialog()
    }

    fun cancelGenerationForDownload() {
        resetGenerationState()
    }

    fun loadSessionsFromDb() {
        val scope = scope ?: return
        scope.launch(Dispatchers.IO) {
            val loaded = try {
                chatRepository.listSessions()
            } catch (error: DbException) {
                logRepository.log(
                    LogLevel.Error,
                    "Failed to load sessions",
                    details = error.message,
                    tag = "Chat",
                    throwable = error
                )
                return@launch
            }
            val sessions = loaded.map { session ->
                val summary = sessionSummaries[sessionKey(session.id)]
                if (!summary.isNullOrBlank()) {
                    session.copy(title = summary)
                } else {
                    session
                }
            }

            val currentSessionId = state.value.chat.currentSessionId
            val sessionStillExists = currentSessionId != null && sessions.any { it.id == currentSessionId }

            state.update { appState ->
                appState.copy(
                    chat = appState.chat.copy(
                        sessions = sessions,
                        currentSessionId = if (sessionStillExists) currentSessionId else null
                    )
                )
            }

            if (sessionStillExists && currentSessionId != null) {
                loadMessagesFromDb(currentSessionId)
                rebuildChatState(currentSessionId)
            }
            trimSessionCaches(sessions.map { it.id }.toSet())
        }
    }

    private fun startGeneration(sessionId: String, userMessage: ChatMessage) {
        val scope = scope ?: return
        if (!state.value.chat.deviceCapability.isChatSupported()) return
        generationJob?.cancel()
        sessionSummaryJob?.cancel()
        stopRequested = false

        val settings = state.value.modelSettings
        val target = modelSettingsActions.resolveTarget(settings)
        val prompt = buildPrompt(userMessage.text, userMessage.attachments)

        val generationToken = nextGenerationToken()
        streamingParentId = userMessage.id
        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    isGenerating = true,
                    isDownloading = false,
                    streamingResponse = "",
                    streamingParentId = userMessage.id,
                    downloadPercent = null,
                    downloadStatus = null,
                    downloadPhase = null,
                    hasRequestedModelDownload = true
                )
            )
        }
        rebuildChatState(sessionId)

        generationJob = scope.launch {
            val isActive = { isGenerationActive(generationToken, sessionId) }
            val progressTracker = DownloadProgressTracker()
            try {
                llmProvider.ensureModelReady(target) { progress ->
                    if (!isActive()) return@ensureModelReady
                    val resolvedProgress = progressTracker.resolve(progress)
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
            } catch (err: Throwable) {
                val cancelled = err is kotlinx.coroutines.CancellationException ||
                    err is LlmException.Cancelled
                if (!isActive()) return@launch
                streamingParentId = null
                state.update { appState ->
                    appState.copy(
                        chat = appState.chat.copy(
                            isGenerating = false,
                            isDownloading = false,
                            streamingParentId = null,
                            downloadPercent = null,
                            downloadStatus = if (cancelled) "Download cancelled" else null,
                            downloadPhase = null,
                            hasRequestedModelDownload = if (cancelled) false else appState.chat.hasRequestedModelDownload
                        )
                    )
                }
                if (!cancelled) {
                    logRepository.log(
                        LogLevel.Error,
                        "Model load failed",
                        details = err.message,
                        tag = "Model",
                        throwable = err
                    )
                }
                return@launch
            }

            if (!isActive()) return@launch

            state.update { appState ->
                appState.copy(chat = appState.chat.copy(isModelDownloaded = true))
            }

            val generationLimits = resolveGenerationLimits(target)
            val historySelection = buildHistorySelection(
                sessionId = sessionId,
                promptText = prompt.text,
                promptImageCount = prompt.imageFiles.size,
                currentMessageId = userMessage.id,
                limits = generationLimits
            )

            if (historySelection.wasTrimmed && overflowBypassMessageId != userMessage.id) {
                overflowBypassMessageId = null
                pendingOverflow = PendingOverflow(sessionId, userMessage.id)
                streamingParentId = null
                state.update { appState ->
                    appState.copy(
                        chat = appState.chat.copy(
                            isGenerating = false,
                            isDownloading = false,
                            streamingResponse = "",
                            streamingParentId = null,
                            downloadPercent = null,
                            downloadStatus = null,
                            downloadPhase = null
                        )
                    )
                }
                showOverflowDialog(historySelection, generationLimits)
                rebuildChatState(sessionId)
                return@launch
            }

            overflowBypassMessageId = null
            pendingOverflow = null
            clearOverflowDialog()

            val history = historySelection.messages
            val systemPrompt = buildSystemPrompt()
            val systemMessage = LlmMessage(
                text = systemPrompt,
                role = LlmMessageRole.System
            )
            val llmMessages = listOf(systemMessage) + history + LlmMessage(
                text = prompt.text,
                role = LlmMessageRole.User,
                hasAttachments = userMessage.attachments.isNotEmpty()
            )

            val buffer = StringBuilder()
            var tokenCount = 0

            try {
                val summary = llmProvider.generateChat(
                    target = target,
                    messages = llmMessages,
                    imageFiles = prompt.imageFiles,
                    temperature = modelSettingsActions.resolveTemperature(settings),
                    maxTokens = generationLimits.maxOutput
                ) { token ->
                    buffer.append(token)
                    tokenCount += estimateTokens(token)
                    if (isActive()) {
                        state.update { appState ->
                            appState.copy(chat = appState.chat.copy(streamingResponse = buffer.toString()))
                        }
                    }
                }

                finishGeneration(
                    sessionId,
                    userMessage,
                    buffer,
                    tokenCount,
                    summary.totalTimeMs,
                    interrupted = false,
                    shouldUpdateUi = isActive()
                )
            } catch (err: Throwable) {
                val interrupted = stopRequested || err is LlmException.Cancelled
                finishGeneration(
                    sessionId,
                    userMessage,
                    buffer,
                    tokenCount,
                    totalTimeMs = null,
                    interrupted = interrupted,
                    shouldUpdateUi = isActive()
                )
                if (!interrupted) {
                    logRepository.log(
                        LogLevel.Error,
                        "Generation failed",
                        details = err.message,
                        tag = "LLM",
                        throwable = err
                    )
                }
            }
        }
    }

    private fun finishGeneration(
        sessionId: String,
        parentMessage: ChatMessage,
        buffer: StringBuilder,
        tokenCount: Int,
        totalTimeMs: Long?,
        interrupted: Boolean,
        shouldUpdateUi: Boolean
    ) {
        val finalText = buffer.toString().trim()
        if (finalText.isNotEmpty()) {
            val tokensPerSecond = if (totalTimeMs != null && totalTimeMs > 0) {
                tokenCount.toDouble() / (totalTimeMs / 1000.0)
            } else null

            if (shouldUpdateUi) {
                val inserted = runCatching {
                    chatRepository.insertMessage(
                        sessionId = sessionId,
                        parentId = parentMessage.id,
                        author = MessageAuthor.Assistant,
                        text = finalText,
                        attachments = emptyList()
                    )
                }.getOrElse { error ->
                    logRepository.log(
                        LogLevel.Warning,
                        "Skipping assistant message persistence",
                        details = "session=$sessionId parent=${parentMessage.id} interrupted=$interrupted",
                        tag = "Chat",
                        throwable = error
                    )
                    null
                }

                if (inserted != null) {
                    val assistantMessage = inserted.copy(
                        isInterrupted = interrupted,
                        tokensPerSecond = tokensPerSecond
                    )

                    messageStore.getOrPut(sessionId) { mutableListOf() }.add(assistantMessage)
                    updateSelectionForParent(sessionId, parentMessage.id, assistantMessage.id)
                    updateCurrentSessionPreview(sessionId, finalText, assistantMessage.timestampMillis)
                }
            } else {
                logRepository.log(
                    LogLevel.Info,
                    "Dropped stale generation response",
                    details = "session=$sessionId parent=${parentMessage.id} interrupted=$interrupted",
                    tag = "Chat"
                )
            }
        }

        if (shouldUpdateUi) {
            streamingParentId = null
            val (displayMessages, branchSelectionIndices) = buildDisplayMessagesAndSelections(sessionId)
            state.update { appState ->
                appState.copy(
                    chat = appState.chat.copy(
                        isGenerating = false,
                        isDownloading = false,
                        streamingResponse = "",
                        streamingParentId = null,
                        downloadPercent = null,
                        downloadStatus = null,
                        downloadPhase = null,
                        messages = displayMessages,
                        branchSelections = branchSelectionIndices
                    )
                )
            }
        }
        scheduleSessionSummary(sessionId)
    }

    private fun updateCurrentSessionPreview(sessionId: String, preview: String, timestamp: Long) {
        state.update { appState ->
            val updatedSessions = appState.chat.sessions.map { session ->
                if (session.id == sessionId) {
                    val shouldUpdateTitle = session.title.isBlank() || session.title.equals("New Chat", ignoreCase = true)
                    val updatedTitle = if (shouldUpdateTitle) {
                        sessionTitleFromText(preview, fallback = session.title)
                    } else {
                        session.title
                    }
                    if (updatedTitle != session.title) {
                        chatRepository.updateSessionTitle(sessionId, updatedTitle)
                    }
                    session.copy(
                        title = updatedTitle,
                        lastMessagePreview = preview,
                        updatedAtMillis = timestamp
                    )
                } else {
                    session
                }
            }
            appState.copy(chat = appState.chat.copy(sessions = updatedSessions))
        }
    }

    private fun applySessionSummariesToState() {
        state.update { appState ->
            val updatedSessions = appState.chat.sessions.map { session ->
                val summary = sessionSummaries[sessionKey(session.id)]
                if (!summary.isNullOrBlank() && summary != session.title) {
                    session.copy(title = summary)
                } else {
                    session
                }
            }
            appState.copy(chat = appState.chat.copy(sessions = updatedSessions))
        }
    }

    private fun scheduleSessionSummary(sessionId: String) {
        val scope = scope ?: return
        sessionSummaryJob?.cancel()
        if (sessionSummaries.containsKey(sessionKey(sessionId))) return
        val summaryInput = buildSessionSummaryInput(sessionId) ?: return
        val target = modelSettingsActions.resolveTarget(state.value.modelSettings)

        sessionSummaryJob = scope.launch(Dispatchers.Default) {
            val summary = generateSessionSummary(
                input = summaryInput.text,
                fallback = summaryInput.fallback,
                target = target
            ) ?: return@launch
            if (!isActive) return@launch
            withContext(Dispatchers.Main) {
                applySessionSummary(sessionId, summary)
            }
        }
    }

    private data class SessionSummaryInput(val text: String, val fallback: String)

    private fun buildSessionSummaryInput(sessionId: String): SessionSummaryInput? {
        val messages = messageStore[sessionId].orEmpty()
        if (messages.isEmpty()) return null
        val firstUser = messages.filter { it.author == MessageAuthor.User }
            .minByOrNull { it.timestampMillis }
            ?: return null
        val assistants = messages.filter { it.author == MessageAuthor.Assistant }
        if (assistants.size != 1) return null
        val firstAssistant = assistants.first()
        if (firstAssistant.isInterrupted) return null

        val fallback = summarizeQuestion(firstUser.text)
        if (fallback.isBlank()) return null
        val input = "User: ${firstUser.text}\nAssistant: ${firstAssistant.text}"
        return SessionSummaryInput(text = input, fallback = fallback)
    }

    private suspend fun generateSessionSummary(
        input: String,
        fallback: String,
        target: LlmModelTarget
    ): String? {
        if (!state.value.chat.deviceCapability.isChatSupported()) {
            return sessionTitleFromText(fallback, fallback = fallback)
        }
        if (!modelDownloader.isDownloaded(target.downloadTarget)) {
            return sessionTitleFromText(fallback, fallback = fallback)
        }
        val cleanedInput = sanitizeTitleText(input)
        if (cleanedInput.isBlank()) return sessionTitleFromText(fallback, fallback = fallback)

        val messages = listOf(
            LlmMessage(text = sessionSummarySystemPrompt, role = LlmMessageRole.System),
            LlmMessage(text = cleanedInput, role = LlmMessageRole.User)
        )

        val buffer = StringBuilder()
        try {
            llmProvider.generateChat(
                target = target,
                messages = messages,
                imageFiles = emptyList(),
                temperature = 0.2f,
                maxTokens = 64
            ) { token ->
                buffer.append(token)
            }
        } catch (err: Throwable) {
            val fallbackSummary = summarizeQuestion(fallback)
            return if (fallbackSummary.isBlank()) null else sessionTitleFromText(fallbackSummary, fallback = fallback)
        }

        val raw = sanitizeTitleText(buffer.toString())
        if (raw.isBlank()) {
            return sessionTitleFromText(fallback, fallback = fallback)
        }
        val words = raw.split(" ")
            .map { word -> word.trim { ch -> !ch.isLetterOrDigit() } }
            .filter { it.isNotBlank() }
        if (words.isEmpty()) return null
        val summary = words.take(sessionSummaryMaxWords).joinToString(" ")
        return sessionTitleFromText(summary, fallback = fallback)
    }

    private fun applySessionSummary(sessionId: String, summary: String) {
        val sanitized = sessionTitleFromText(summary, fallback = "New Chat")
        if (sanitized.isBlank()) return
        val summaryKey = sessionKey(sessionId)
        if (sessionSummaries[summaryKey] == sanitized) return
        sessionSummaries[summaryKey] = sanitized
        scope?.launch { sessionPreferences.setSessionSummary(sessionId, sanitized) }
        chatRepository.updateSessionTitle(sessionId, sanitized)
        state.update { appState ->
            val updatedSessions = appState.chat.sessions.map { session ->
                if (session.id == sessionId) {
                    session.copy(title = sanitized)
                } else {
                    session
                }
            }
            appState.copy(chat = appState.chat.copy(sessions = updatedSessions))
        }
    }

    private fun summarizeQuestion(text: String): String {
        val cleaned = sanitizeTitleText(text)
        if (cleaned.isBlank()) return ""
        val words = cleaned.split(" ")
            .map { word -> word.trim { ch -> !ch.isLetterOrDigit() } }
            .filter { it.isNotBlank() }
        if (words.isEmpty()) return ""
        val summaryWords = words.take(sessionSummaryMaxWords)
        return summaryWords.joinToString(" ")
    }

    private suspend fun loadMessagesFromDb(sessionId: String) {
        val messages = withContext(Dispatchers.IO) {
            chatRepository.getMessages(sessionId)
        }
        messageStore[sessionId] = messages.toMutableList()
        branchSelections.getOrPut(sessionId) { mutableMapOf() }.clear()
        markSessionAccess(sessionId)
        trimSessionCaches()
    }

    private fun markSessionAccess(sessionId: String) {
        sessionAccessTimes[sessionId] = clock()
    }

    private fun trimSessionCaches(availableSessions: Set<String> = state.value.chat.sessions.map { it.id }.toSet()) {
        val availableKeys = availableSessions.map(::sessionKey).toSet()
        sessionSummaries.keys.retainAll(availableKeys)

        val keepIds = LinkedHashSet<String>()
        val currentSessionId = state.value.chat.currentSessionId
        if (currentSessionId != null && currentSessionId in availableSessions) {
            keepIds.add(currentSessionId)
        }
        val ordered = sessionAccessTimes.entries
            .filter { it.key in availableSessions }
            .sortedByDescending { it.value }
            .map { it.key }
        for (id in ordered) {
            if (keepIds.size >= MAX_CACHED_SESSIONS) break
            keepIds.add(id)
        }
        messageStore.keys.retainAll(keepIds)
        branchSelections.keys.retainAll(keepIds)
        sessionAccessTimes.keys.retainAll(keepIds)
    }

    private fun removeSessionCaches(sessionId: String) {
        messageStore.remove(sessionId)
        branchSelections.remove(sessionId)
        sessionAccessTimes.remove(sessionId)
    }

    private fun sessionKey(sessionId: String): String {
        return sessionId.lowercase()
    }

    private fun rebuildChatState(sessionId: String?) {
        val (displayMessages, branchSelectionIndices) = buildDisplayMessagesAndSelections(sessionId)
        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    messages = displayMessages,
                    branchSelections = branchSelectionIndices
                )
            )
        }
    }

    private fun buildDisplayMessagesAndSelections(sessionId: String?): Pair<List<ChatMessage>, Map<String, Int>> {
        if (sessionId == null) {
            return emptyList<ChatMessage>() to emptyMap()
        }

        val messages = messageStore[sessionId].orEmpty()
        val path = buildSelectedPath(sessionId)
        val childrenMap = buildChildrenMap(messages)
        val selectionMap = branchSelections.getOrPut(sessionId) { mutableMapOf() }
        val branchSelectionIndices = mutableMapOf<String, Int>()
        val byId = messages.associateBy { it.id }

        val displayMessages = path.map { message ->
            val parentKey = message.parentId?.takeIf { byId.containsKey(it) } ?: "__root__"
            val siblings = dedupeSiblings(childrenMap[parentKey].orEmpty())
            if (siblings.size > 1) {
                val selectedId = selectionMap[parentKey]
                val index = siblings.indexOfFirst { it.id == selectedId }
                branchSelectionIndices[message.id] = if (index >= 0) index + 1 else siblings.size
            }
            message.copy(branchCount = max(1, siblings.size))
        }

        val isGenerating = state.value.chat.isGenerating
        val finalMessages = buildList {
            for (i in displayMessages.indices) {
                val msg = displayMessages[i]
                add(msg)
                if (msg.author == MessageAuthor.User) {
                    val next = displayMessages.getOrNull(i + 1)
                    val isLastAndGenerating = i == displayMessages.lastIndex && isGenerating
                    if (next?.author != MessageAuthor.Assistant && !isLastAndGenerating) {
                        add(ChatMessage(
                            id = "interrupted-placeholder-${msg.id}",
                            sessionId = sessionId,
                            parentId = msg.id,
                            author = MessageAuthor.Assistant,
                            text = "Response was interrupted",
                            timestampMillis = msg.timestampMillis,
                            isInterrupted = true,
                            isSynthetic = true
                        ))
                    }
                }
            }
        }

        return finalMessages to branchSelectionIndices
    }

    private fun buildSelectedPath(sessionId: String): List<ChatMessage> {
        val messages = messageStore[sessionId].orEmpty()
        if (messages.isEmpty()) return emptyList()

        val byId = messages.associateBy { it.id }
        val childrenMap = buildChildrenMap(messages)
        val roots = dedupeSiblings(messages.filter { message ->
            val parentId = message.parentId
            parentId == null || byId[parentId] == null
        })
        if (roots.isEmpty()) return emptyList()

        val selectionMap = branchSelections.getOrPut(sessionId) { mutableMapOf() }
        var current = selectChild(selectionMap, "__root__", roots)
        val path = mutableListOf<ChatMessage>()
        val visited = mutableSetOf<String>()

        while (current != null && visited.add(current.id)) {
            path.add(current)
            if (current.id == streamingParentId) break
            val children = dedupeSiblings(childrenMap[current.id].orEmpty())
            if (children.isEmpty()) break
            current = selectChild(selectionMap, current.id, children)
        }
        return path
    }

    private fun selectChild(
        selectionMap: MutableMap<String, String>,
        selectionKey: String,
        candidates: List<ChatMessage>
    ): ChatMessage? {
        if (candidates.isEmpty()) return null
        val selectedId = selectionMap[selectionKey]
        val selected = candidates.firstOrNull { it.id == selectedId }
        return selected ?: candidates.last()
    }

    private fun buildChildrenMap(messages: List<ChatMessage>): Map<String, List<ChatMessage>> {
        val map = mutableMapOf<String, MutableList<ChatMessage>>()
        val byId = messages.associateBy { it.id }
        messages.forEach { message ->
            val parentKey = message.parentId?.takeIf { byId.containsKey(it) } ?: "__root__"
            map.getOrPut(parentKey) { mutableListOf() }.add(message)
        }
        return map
    }

    private fun dedupeSiblings(messages: List<ChatMessage>): List<ChatMessage> {
        if (messages.size <= 1) return messages.sortedBy { it.timestampMillis }
        val sorted = messages.sortedBy { it.timestampMillis }
        val result = mutableListOf<ChatMessage>()
        for (message in sorted) {
            val last = result.lastOrNull()
            if (last != null && isDuplicate(last, message)) {
                continue
            }
            result.add(message)
        }
        return result
    }

    private fun isDuplicate(left: ChatMessage, right: ChatMessage): Boolean {
        if (left.author != right.author) return false
        if (left.text != right.text) return false
        if (!attachmentsSignature(left.attachments).contentEquals(attachmentsSignature(right.attachments))) return false
        return abs(left.timestampMillis - right.timestampMillis) <= 2_000
    }

    private fun attachmentsSignature(attachments: List<Attachment>): Array<String> {
        return attachments.map { "${it.type}:${it.name}" }.toTypedArray()
    }

    private fun updateSelectionForParent(sessionId: String, parentId: String?, childId: String) {
        val selectionMap = branchSelections.getOrPut(sessionId) { mutableMapOf() }
        val selectionKey = parentId ?: "__root__"
        selectionMap[selectionKey] = childId
    }

    private data class HistorySelection(
        val messages: List<LlmMessage>,
        val inputTokens: Int,
        val inputBudget: Int,
        val wasTrimmed: Boolean
    )

    private data class GenerationLimits(
        val contextLength: Int,
        val maxOutput: Int
    )

    private data class PendingOverflow(
        val sessionId: String,
        val messageId: String
    )

    private fun buildPrompt(text: String, attachments: List<Attachment>): PromptResult {
        val builder = StringBuilder(text)
        val documents = attachments.filter { it.type == io.ente.ensu.chat.AttachmentType.Document }
        val images = attachments.filter { it.type == io.ente.ensu.chat.AttachmentType.Image }

        documents.forEachIndexed { index, attachment ->
            builder.append("\n\n----- BEGIN DOCUMENT: Document ${index + 1} -----\n")
            builder.append("Attached document: ${attachment.name}\n")
            builder.append("----- END DOCUMENT: Document ${index + 1} -----")
        }

        val imageFiles = images.mapNotNull { attachment ->
            val path = attachment.localPath ?: return@mapNotNull null
            java.io.File(path).takeIf { it.exists() }
        }

        if (imageFiles.isNotEmpty()) {
            builder.append("\n\n[")
            builder.append(imageFiles.size)
            builder.append(" image attachment")
            if (imageFiles.size > 1) builder.append("s")
            builder.append(" provided]")
            imageFiles.forEach {
                builder.append("\n")
                builder.append(MEDIA_MARKER)
            }
        }

        return PromptResult(builder.toString(), imageFiles)
    }

    private fun buildHistorySelection(
        sessionId: String,
        promptText: String,
        promptImageCount: Int,
        currentMessageId: String,
        limits: GenerationLimits
    ): HistorySelection {
        val path = buildSelectedPath(sessionId)
        val historyMessages = path.takeWhile { it.id != currentMessageId }
        val inputBudget = max(0, limits.contextLength - limits.maxOutput - OVERFLOW_SAFETY_TOKENS)
        val systemPrompt = buildSystemPrompt()
        val systemTokens = estimateTokens(systemPrompt)
        val promptTokens = estimatePromptTokens(promptText, promptImageCount)
        val historyTokens = historyMessages.sumOf { estimateTokens(historyText(it)) }
        val inputTokens = systemTokens + promptTokens + historyTokens
        val remaining = inputBudget - systemTokens - promptTokens

        if (remaining <= 0 || historyMessages.isEmpty()) {
            return HistorySelection(emptyList(), inputTokens, inputBudget, inputTokens > inputBudget)
        }

        val quantum = max(1, inputBudget / 4)
        val overflow = max(0, historyTokens - remaining)
        val quantaToDiscard = (overflow + quantum - 1) / quantum
        val discardTarget = quantaToDiscard * quantum
        var discarded = 0
        var startIndex = 0
        while (startIndex < historyMessages.size && discarded < discardTarget) {
            discarded += estimateTokens(historyText(historyMessages[startIndex]))
            startIndex++
        }

        val retained = historyMessages.drop(startIndex).ifEmpty {
            historyMessages.takeLast(1).filter { estimateTokens(historyText(it)) <= remaining }
        }

        val selected = retained.map { message ->
            val text = historyText(message)
            LlmMessage(
                text = text,
                role = if (message.author == MessageAuthor.User) LlmMessageRole.User else LlmMessageRole.Assistant,
                hasAttachments = message.attachments.isNotEmpty()
            )
        }

        return HistorySelection(selected, inputTokens, inputBudget, inputTokens > inputBudget)
    }

    private fun resolveGenerationLimits(target: LlmModelTarget): GenerationLimits {
        val contextLength = llmProvider.loadedContextLength(target)
            ?: target.contextLength
            ?: DEFAULT_CONTEXT_LENGTH
        val maxOutput = resolveMaxOutputTokens(target.maxTokens, contextLength)
        return GenerationLimits(contextLength = contextLength, maxOutput = maxOutput)
    }

    private fun resolveMaxOutputTokens(configuredMaxTokens: Int?, contextLength: Int): Int {
        val maxAllowed = max(1, contextLength - OVERFLOW_SAFETY_TOKENS)
        val implicitMax = min(DEFAULT_GENERATION_MAX_TOKENS, max(1, contextLength / 2))
        return (configuredMaxTokens ?: implicitMax).coerceIn(1, maxAllowed)
    }

    private fun showOverflowDialog(selection: HistorySelection, limits: GenerationLimits) {
        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    overflowDialog = io.ente.ensu.chat.OverflowDialogState(
                        inputTokens = selection.inputTokens,
                        inputBudget = selection.inputBudget,
                        contextLength = limits.contextLength,
                        maxOutput = limits.maxOutput
                    )
                )
            )
        }
    }

    private fun clearOverflowDialog() {
        state.update { appState ->
            appState.copy(chat = appState.chat.copy(overflowDialog = null))
        }
    }

    private fun historyText(message: ChatMessage): String {
        var text = message.text
        if (message.author == MessageAuthor.Assistant) {
            text = text.replace(Regex("<think>[\\s\\S]*?</think>"), "")
            text = text.replace(Regex("<todo_list>[\\s\\S]*?</todo_list>"), "")
        } else if (message.attachments.isNotEmpty()) {
            text += "\n\n[${message.attachments.size} attachments attached]"
        }
        return text.trim()
    }

    private fun trimToBudget(text: String, budget: Int): String {
        if (budget <= 0) return ""
        val maxChars = budget * 4
        return if (text.length <= maxChars) text else text.takeLast(maxChars)
    }

    private fun estimateTokens(text: String): Int {
        return max(1, text.length / 4)
    }

    private fun estimateImageTokens(imageCount: Int): Int {
        return imageCount * IMAGE_TOKEN_ESTIMATE
    }

    private fun estimatePromptTokens(promptText: String, imageCount: Int): Int {
        return estimateTokens(promptText) + estimateImageTokens(imageCount)
    }

    private fun cancelGeneration() {
        generationJob?.cancel()
        llmProvider.stopGeneration()
        invalidateGenerationToken()
        streamingParentId = null
        stopRequested = false
    }

    private fun resetGenerationState() {
        cancelGeneration()
        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    isGenerating = false,
                    isDownloading = false,
                    streamingResponse = "",
                    streamingParentId = null,
                    downloadPercent = null,
                    downloadStatus = null,
                    downloadPhase = null
                )
            )
        }
    }

    private fun nextGenerationToken(): Long {
        activeGenerationToken += 1
        return activeGenerationToken
    }

    private fun invalidateGenerationToken() {
        activeGenerationToken += 1
    }

    private fun isGenerationActive(token: Long, sessionId: String): Boolean {
        return token == activeGenerationToken && state.value.chat.currentSessionId == sessionId
    }

    private data class PromptResult(
        val text: String,
        val imageFiles: List<java.io.File>
    )

    private fun buildSystemPrompt(nowMillis: Long = clock()): String {
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
            .format(Date(nowMillis))
        val promptBody = state.value.developerSettings.systemPrompt.trim()
            .ifEmpty { configDefaults.mobileSystemPromptBody }
        return promptBody.replace(configDefaults.systemPromptDatePlaceholder, date)
    }

    companion object {
        private const val DEFAULT_CONTEXT_LENGTH = 12_000
        private const val DEFAULT_GENERATION_MAX_TOKENS = 8_192
        private const val MEDIA_MARKER = "<__media__>"
        private const val OVERFLOW_SAFETY_TOKENS = 256
        private const val IMAGE_TOKEN_ESTIMATE = 768
        private const val MAX_CACHED_SESSIONS = 8
    }
}
