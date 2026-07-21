import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    private struct ModelReadyKey: Equatable {
        let id: String
        let requestedContextLength: Int?
    }

    private static let defaultTemperature: Float = 0.5
    private static let systemPromptDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private static let systemPromptDatePlaceholder = ConfigDefaults.shared.systemPromptDatePlaceholder
    private static let defaultGenerationMaxTokens = 8_192
    private static let overflowSafetyTokens = 256
    private static let imageTokenEstimate = 768
    private nonisolated static let sessionTitleMaxLength = 40
    private static let sessionSummaryMaxWords = 7
    private static let sessionSummaryStoreKey = "ensu.session_summaries"
    private static let sessionSummarySystemPrompt = ConfigDefaults.shared.sessionSummarySystemPrompt

    private func systemPrompt() -> String {
        let date = Self.systemPromptDateFormatter.string(from: Date())
        let promptBody = ModelSettingsStore.currentSystemPromptBody()
        return promptBody.replacingOccurrences(of: Self.systemPromptDatePlaceholder, with: date)
    }

    private let logger = EnsuLogging.shared.logger("ChatViewModel")

    @Published var sessions: [ChatSession]
    @Published var currentSessionId: UUID?
    @Published var messages: [RenderedChatMessage]
    @Published var streamingResponse: String = ""
    @Published var streamingParentId: UUID? = nil
    @Published var overflowAlert: OverflowAlertState? = nil

    var displayedStreamingResponse: String {
        guard let activeSession = activeGenerationSessionId,
              activeSession == currentSessionId,
              activeGenerationId != nil else {
            return ""
        }
        return streamingResponse
    }

    var displayedStreamingParentId: UUID? {
        guard let activeSession = activeGenerationSessionId,
              activeSession == currentSessionId,
              activeGenerationId != nil else {
            return nil
        }
        return streamingParentId
    }
    @Published var isGenerating: Bool = false
    @Published var isDownloading: Bool = false
    @Published var isProcessingAttachments: Bool = false
    @Published var draftText: String = ""
    @Published var draftAttachments: [ChatAttachment] = []
    private var draftImageAttachmentCount: Int {
        draftAttachments.filter { $0.kind == .image }.count
    }

    @Published var editingMessageId: UUID?
    @Published var downloadToast: DownloadToastState?
    @Published var isModelDownloaded: Bool = false
    @Published var modelDownloadSizeBytes: Int64?
    @Published var hasRequestedModelDownload: Bool = false
    @Published var deviceCapability: ChatDeviceCapability = .unknown
    @Published var showUnsupportedDeviceDialog: Bool = false
    @Published var generationErrorMessage: String?
    @Published var voiceInputState: VoiceInputState = .idle
    @Published var draftCursorMoveToken = UUID()

    private let provider: LlmProvider
    private let downloader: ModelDownloader
    private let voiceTranscriber: VoiceTranscriptionService
    private var chatDb: EnsuDb
    private let attachmentsDir: URL
    private let chatDbPath: String
    private let chatDbKey: Data
    private let modelSettings = ModelSettingsStore.shared

    private var messageStore: [UUID: [MessageNode]] = [:]
    private var branchSelections: [UUID: [String: UUID]] = [:]
    private var childrenByParentCache: [UUID: [UUID: [MessageNode]]] = [:]
    private var sessionSummaries: [String: String] = [:]
    private var sessionSummaryTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private let rootId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private var generationTask: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private var voiceTransientErrorTask: Task<Void, Never>?
    private var sharedModelReadyTask: Task<Void, Error>?
    private var sharedModelReadyTaskId: UUID?
    private var sharedModelReadyKey: ModelReadyKey?
    private var stopRequested = false
    private var activeGenerationId: UUID?
    private var activeGenerationSessionId: UUID?
    private var modelDownloadLoggedStart = false
    private let downloadProgressTracker = DownloadProgressTracker()
    private var pendingOverflow: PendingOverflow?
    private var overflowBypassMessageId: UUID?

    init() {
        logger.info("Initializing")
        let summaries = Self.loadSessionSummaries().reduce(into: [String: String]()) { result, item in
            result[item.key.lowercased()] = item.value
        }
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        let downloader = ModelDownloader()
        let transcriber = Transcriber(
            modelDir: downloader.modelPath(target: downloader.transcriptionModelTarget).path,
            vadModelPath: downloader.modelPath(target: downloader.voiceActivityModelTarget).path
        )
        let provider = LlmProvider(downloader: downloader, transcriber: transcriber)
        let voiceTranscriber = VoiceTranscriptionService(transcriber: transcriber, downloader: downloader)

        // Chat DB + attachments.
        let dbDir = baseDir.appendingPathComponent("llmchat", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true, attributes: nil)
        let attachmentsDir = dbDir.appendingPathComponent("chat_attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true, attributes: nil)

        let chatDbPath = dbDir.appendingPathComponent("llmchat.db").path
        let hasChatData = FileManager.default.fileExists(atPath: chatDbPath) ||
            (try? FileManager.default.contentsOfDirectory(atPath: attachmentsDir.path).isEmpty) != true
        let chatDbKey: Data
        do {
            chatDbKey = try CredentialStore.shared.getOrCreateChatDbKey(hasChatData: hasChatData)
        } catch {
            fatalError("Failed to load chat DB key: \(error)")
        }

        let chatDb: EnsuDb
        do {
            chatDb = try EnsuDb.open(mainDbPath: chatDbPath, key: chatDbKey)
        } catch {
            fatalError("Failed to open chat DB: \(error)")
        }

        // Load sessions/messages.
        let loadedResult = try? chatDb.listSessions()
        if let loadedResult {
            Self.pruneOrphanedAttachments(
                sessions: loadedResult,
                chatDb: chatDb,
                attachmentsDir: attachmentsDir
            )
        }
        let loaded = loadedResult ?? []
        let sessions = Self.buildSessions(from: loaded, chatDb: chatDb, summaries: summaries)

        // Stored properties.
        self.provider = provider
        self.downloader = downloader
        self.voiceTranscriber = voiceTranscriber
        self.chatDb = chatDb
        self.attachmentsDir = attachmentsDir
        self.chatDbPath = chatDbPath
        self.chatDbKey = chatDbKey
        self.sessionSummaries = summaries

        self.sessions = sessions
        self.currentSessionId = nil
        self.messages = []

        for session in sessions {
            self.messageStore[session.id] = []
            self.branchSelections[session.id] = [:]
        }

        if let current = self.currentSessionId {
            loadMessagesFromDb(for: current)
        }

        refreshDeviceCapability()
        refreshModelDownloadInfo()
    }

    var isChatUnsupported: Bool {
        !deviceCapability.isChatSupported
    }

    var unsupportedDeviceMessage: String {
        Self.unsupportedDeviceMessage
    }

    func refreshDeviceCapability() {
        let capability = currentChatDeviceCapability()
        deviceCapability = capability
        logger.info("Chat device capability evaluated", details: "\(capability)")
        guard !capability.isChatSupported else { return }
        showUnsupportedDeviceDialog = true
        isDownloading = false
        downloadToast = nil
        modelDownloadSizeBytes = nil
        hasRequestedModelDownload = false
        modelDownloadTask?.cancel()
        sharedModelReadyTask?.cancel()
        clearSharedModelReadyTask()
        discardUnstoredAttachments(draftAttachments)
        editingMessageId = nil
        draftText = ""
        draftAttachments = []
        downloader.cancel()
    }

    func dismissUnsupportedDeviceDialog() {
        showUnsupportedDeviceDialog = false
    }

    static let unsupportedDeviceMessage =
        "This device doesn't have enough memory to run Ensu's AI model. " +
        "You can view existing chats, but can't send new messages."

    private func reopenChatStoreIfNeeded(force: Bool = false) {
        let hasChatDb = FileManager.default.fileExists(atPath: chatDbPath)
        if !force && hasChatDb {
            return
        }

        do {
            try? FileManager.default.createDirectory(
                at: attachmentsDir,
                withIntermediateDirectories: true,
                attributes: nil
            )

            chatDb = try EnsuDb.open(
                mainDbPath: chatDbPath,
                key: chatDbKey
            )
        } catch {
            logger.error("Failed to reopen chat store: \(error)")
        }
    }

    var currentSession: ChatSession? {
        guard let currentSessionId else { return nil }
        return sessions.first { $0.id == currentSessionId }
    }

    var modelDownloadSizeText: String {
        guard let bytes = modelDownloadSizeBytes else { return "Approx. size varies by model" }
        return "Approx. \(bytes.formattedFileSize)"
    }

    private func resetGenerationState(stopRequested: Bool = false) {
        generationTask?.cancel()
        provider.stopGeneration()
        self.stopRequested = stopRequested
        activeGenerationId = nil
        activeGenerationSessionId = nil
        isGenerating = false
        isDownloading = false
        streamingResponse = ""
        streamingParentId = nil
        downloadToast = nil
    }

    func sessionTitle(for sessionId: UUID) -> String {
        guard let title = sessions.first(where: { $0.id == sessionId })?.title else { return "Chat" }
        return Self.sessionTitle(from: title, fallback: "Chat")
    }

    func startNewSession() {
        guard !isDownloading else { return }

        resetGenerationState()
        cancelVoiceInput()
        discardUnstoredAttachments(draftAttachments)
        draftText = ""
        draftAttachments = []
        editingMessageId = nil

        currentSessionId = nil
        messages = []
    }

    func selectSession(_ session: ChatSession) {
        resetGenerationState()
        cancelVoiceInput()
        currentSessionId = session.id
        messages = []
        loadMessagesFromDb(for: session.id)
    }

    func deleteSession(_ session: ChatSession) {
        if currentSessionId == session.id {
            resetGenerationState()
        }

        if let nodes = messageStore[session.id] {
            for node in nodes {
                logger.info("Message deleted", details: "id=\(node.id.uuidString) session=\(session.id.uuidString) role=\(node.role.rawValue)")
            }
        }
        logger.info("Session deleted", details: "id=\(session.id.uuidString)")
        guard let attachmentIds = try? chatDb.deleteSession(uuid: session.id.uuidString) else {
            return
        }
        if currentSessionId == session.id {
            discardUnstoredAttachments(draftAttachments)
        }
        for id in attachmentIds {
            try? FileManager.default.removeItem(at: attachmentsDir.appendingPathComponent(id))
        }
        sessionSummaries.removeValue(forKey: sessionSummaryKey(session.id))
        persistSessionSummaries()

        sessions.removeAll { $0.id == session.id }
        messageStore[session.id] = nil
        branchSelections[session.id] = nil
        childrenByParentCache[session.id] = nil
        if currentSessionId == session.id {
            currentSessionId = sessions.first?.id
            if let next = currentSessionId {
                messages = []
                loadMessagesFromDb(for: next)
            } else {
                messages = []
            }
        }
    }

    func beginEditing(message: RenderedChatMessage) {
        guard !isChatUnsupported else {
            showUnsupportedDeviceDialog = true
            return
        }
        guard message.role == .user else { return }
        editingMessageId = message.id
        draftText = message.text
        draftAttachments = message.attachments
    }

    func cancelEditing() {
        discardUnstoredAttachments(draftAttachments)
        editingMessageId = nil
        draftText = ""
        draftAttachments = []
    }

    func toggleVoiceInput() {
        if voiceInputState.isRecording {
            voiceTranscriber.stopAndTranscribe(
                onState: { [weak self] state in
                    self?.setVoiceInputState(state)
                },
                onTranscript: { [weak self] transcript in
                    self?.appendVoiceTranscript(transcript)
                }
            )
            return
        }

        guard !isGenerating,
              !isDownloading,
              editingMessageId == nil else {
            return
        }

        let voiceSessionId = currentSessionId
        voiceTranscriber.startRecording(
            onState: { [weak self] state in
                self?.setVoiceInputState(state)
            },
            shouldStartRecording: { [weak self] in
                guard let self else { return false }
                return self.currentSessionId == voiceSessionId &&
                    !self.isGenerating &&
                    !self.isDownloading &&
                    self.editingMessageId == nil
            }
        )
    }

    func cancelVoiceInput() {
        voiceTransientErrorTask?.cancel()
        voiceTransientErrorTask = nil
        voiceTranscriber.cancel()
        voiceInputState = .idle
    }

    private func setVoiceInputState(_ state: VoiceInputState) {
        voiceTransientErrorTask?.cancel()
        voiceTransientErrorTask = nil
        voiceInputState = state

        guard state.isNoSpeechError else { return }
        voiceTransientErrorTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            } catch {
                return
            }
            if self.voiceInputState == state {
                self.voiceInputState = .idle
            }
            self.voiceTransientErrorTask = nil
        }
    }

    private func appendVoiceTranscript(_ transcript: String) {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let trimmedDraft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDraft.isEmpty {
            draftText = cleaned
        } else {
            draftText = "\(trimmedDraft) \(cleaned)"
        }
        draftCursorMoveToken = UUID()
    }

    func addImageAttachment(data: Data, fileName: String?) {
        guard !isGenerating,
              !isDownloading,
              draftImageAttachmentCount < ChatAttachmentLimits.maxImagesPerMessage else { return }
        isProcessingAttachments = true

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let id = UUID()
                let compressed = try compressAttachmentImage(data: data)
                let url = try self.writeAttachment(data: compressed, attachmentId: id)
                let attachment = ChatAttachment(
                    id: id,
                    name: self.normalizedJpegAttachmentName(fileName),
                    size: Int64(compressed.count),
                    kind: .image,
                    url: url,
                    isUploading: false
                )
                await MainActor.run {
                    if self.draftImageAttachmentCount >= ChatAttachmentLimits.maxImagesPerMessage {
                        try? FileManager.default.removeItem(at: url)
                        self.isProcessingAttachments = false
                        return
                    }
                    self.draftAttachments.append(attachment)
                    self.isProcessingAttachments = false
                    self.prewarmImageInferenceIfDownloaded()
                }
            } catch {
                await MainActor.run { self.isProcessingAttachments = false }
            }
        }
    }

    private func prewarmImageInferenceIfDownloaded() {
        guard !isGenerating && !isDownloading else { return }
        guard !isChatUnsupported else { return }
        let target = modelSettings.currentTarget()
        guard downloader.isDownloaded(target: target.downloadTarget) else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.provider.prewarmImageInference(target: target)
        }
    }

    private nonisolated func normalizedJpegAttachmentName(_ fileName: String?) -> String {
        let raw = fileName?
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = raw?.isEmpty == false ? raw! : "photo"
        let base = (cleaned as NSString).deletingPathExtension
        return "\(base.isEmpty ? "photo" : base).jpg"
    }

    func addDocumentAttachment(url: URL) {
        guard !isGenerating && !isDownloading else { return }
        isProcessingAttachments = true

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let id = UUID()
                let storedUrl = try self.copyAttachment(from: url, attachmentId: id)
                let size = (try? FileManager.default.attributesOfItem(atPath: storedUrl.path)[.size] as? NSNumber)?.int64Value ?? 0
                let attachment = ChatAttachment(
                    id: id,
                    name: url.lastPathComponent,
                    size: size,
                    kind: .document,
                    url: storedUrl,
                    isUploading: false
                )
                await MainActor.run {
                    self.draftAttachments.append(attachment)
                    self.isProcessingAttachments = false
                }
            } catch {
                await MainActor.run { self.isProcessingAttachments = false }
            }
        }
    }

    func removeAttachment(_ attachment: ChatAttachment) {
        draftAttachments.removeAll { $0.id == attachment.id }
        discardUnstoredAttachments([attachment])
    }

    private func discardUnstoredAttachments(_ attachments: [ChatAttachment]) {
        let storedIds = Set(messageStore.values.flatMap { messages in
            messages.flatMap { $0.attachments.map(\.id) }
        })
        for attachment in attachments where !storedIds.contains(attachment.id) {
            if let url = attachment.url {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func pruneOrphanedAttachments(
        sessions: [DbSession],
        chatDb: EnsuDb,
        attachmentsDir: URL
    ) {
        let referenced: Set<String>
        do {
            referenced = Set(try sessions.flatMap { session in
                try chatDb.getMessages(sessionUuid: session.uuid)
                    .flatMap { $0.attachments.map(\.id) }
            })
        } catch {
            return
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: attachmentsDir,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where !referenced.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func sendDraft() {
        guard !isGenerating && !isDownloading else { return }
        guard !isChatUnsupported else {
            showUnsupportedDeviceDialog = true
            return
        }

        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = draftAttachments
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        Task { @MainActor in
            let target = self.modelSettings.currentTarget()
            self.hasRequestedModelDownload = true

            do {
                try await self.ensureModelReadyShared(target: target)
                self.isModelDownloaded = true
            } catch {
                if self.isCancellation(error) {
                    return
                }
                self.isModelDownloaded = false
                self.isDownloading = false
                self.downloadToast = DownloadToastState(
                    phase: .errorDownload,
                    percent: nil,
                    status: self.userFacingModelReadyError(error, wasDownloaded: false),
                    offerRetryDownload: true
                )
                self.logger.error("Model readiness check failed before send", error)
                return
            }

            let sessionId = self.currentSessionId ?? self.createSessionForDraft()
            self.sendDraftMessage(trimmed: trimmed, attachments: attachments, sessionId: sessionId)
        }
    }

    private func sendDraftMessage(trimmed: String, attachments: [ChatAttachment], sessionId: UUID) {
        let parentId: UUID? = {
            if let editingId = editingMessageId {
                let existing = messageStore[sessionId]?.first { $0.id == editingId }
                return existing?.parentId
            }
            let childrenMap = childrenByParent(sessionId: sessionId)
            return buildSelectedPath(for: sessionId, childrenMap: childrenMap).last?.id
        }()

        let meta: [DbAttachmentMeta] = attachments.map { attachment in
            DbAttachmentMeta(
                id: attachment.id.uuidString.lowercased(),
                kind: attachment.kind == .image ? .image : .document,
                size: attachment.size,
                name: attachment.name
            )
        }

        guard let inserted = try? chatDb.insertMessage(
            sessionUuid: sessionId.uuidString,
            sender: .selfUser,
            text: trimmed,
            parentMessageUuid: parentId?.uuidString,
            attachments: meta
        ), let messageId = UUID(uuidString: inserted.uuid) else {
            return
        }

        logger.info(
            "Sent message",
            details: "id=\(messageId.uuidString) session=\(sessionId.uuidString) len=\(trimmed.count) attachments=\(attachments.count) edited=\(editingMessageId != nil)"
        )

        let timestamp = Date(timeIntervalSince1970: Double(inserted.createdAtUs) / 1_000_000.0)

        let userNode = MessageNode(
            id: messageId,
            sessionId: sessionId,
            parentId: parentId,
            role: .user,
            text: trimmed,
            timestamp: timestamp,
            attachments: attachments,
            isInterrupted: false,
            tokensPerSecond: nil
        )

        messageStore[sessionId, default: []].append(userNode)
        invalidateChildrenCache(for: sessionId)
        updateSelection(for: sessionId, parentId: parentId, childId: userNode.id)

        draftText = ""
        draftAttachments = []
        editingMessageId = nil

        updateSessionPreview(sessionId: sessionId, preview: trimmed, date: timestamp)
        rebuildMessages(for: sessionId)
        startGeneration(for: userNode)
    }

    func stopGenerating() {
        stopRequested = true
        provider.stopGeneration()
        generationTask?.cancel()
    }

    func confirmOverflowTrim() {
        guard let pendingOverflow else { return }
        guard let node = messageStore[pendingOverflow.sessionId]?.first(where: { $0.id == pendingOverflow.messageId }) else {
            cancelOverflowDialog()
            return
        }
        overflowBypassMessageId = pendingOverflow.messageId
        self.pendingOverflow = nil
        overflowAlert = nil
        startGeneration(for: node)
    }

    func cancelOverflowDialog() {
        pendingOverflow = nil
        overflowBypassMessageId = nil
        overflowAlert = nil
    }

    func refreshModelDownloadInfo() {
        guard !isChatUnsupported else {
            isDownloading = false
            downloadToast = nil
            modelDownloadSizeBytes = nil
            hasRequestedModelDownload = false
            return
        }
        let target = modelSettings.currentTarget()
        isModelDownloaded = downloader.isDownloaded(target: target.downloadTarget)
        if isModelDownloaded {
            clearDownloadProgressMemory()
            modelDownloadSizeBytes = nil
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let size = await downloader.estimateDownloadSize(target: target.downloadTarget)
            await MainActor.run {
                guard self.modelReadyKey(for: self.modelSettings.currentTarget()) == self.modelReadyKey(for: target) else {
                    return
                }
                if self.sharedModelReadyTask == nil &&
                    (self.downloadToast?.phase == .downloading || self.downloadToast?.phase == .loading) {
                    self.downloadToast = nil
                    self.isDownloading = false
                    self.clearDownloadProgressMemory()
                }
                self.modelDownloadSizeBytes = size ?? self.modelDownloadSizeBytes
            }
        }
    }

    private func clearSharedModelReadyTask() {
        sharedModelReadyTask = nil
        sharedModelReadyTaskId = nil
        sharedModelReadyKey = nil
    }

    private func modelReadyKey(for target: LlmModelTarget) -> ModelReadyKey {
        ModelReadyKey(id: target.id, requestedContextLength: target.contextLength)
    }

    private func ensureModelReadyShared(target: LlmModelTarget) async throws {
        if isChatUnsupported {
            throw UnsupportedDeviceMemoryError(capability: deviceCapability)
        }
        let modelKey = modelReadyKey(for: target)
        if let existingTask = sharedModelReadyTask, sharedModelReadyKey == modelKey {
            try await existingTask.value
            return
        }

        if let existingTask = sharedModelReadyTask, sharedModelReadyKey != modelKey {
            existingTask.cancel()
            downloader.cancel()
            clearSharedModelReadyTask()
        }

        let taskId = UUID()
        let task = Task {
            var retryCount = 0
            while true {
                do {
                    try await provider.ensureModelReady(target: target) { progress in
                        Task { @MainActor in
                            self.handleProgress(progress)
                        }
                    }
                    return
                } catch {
                    if self.isCancellation(error) {
                        throw error
                    }
                    if !self.shouldRetryModelDownload(error, retryCount: retryCount) {
                        throw error
                    }
                    retryCount += 1
                    try await Task.sleep(nanoseconds: self.retryDelayNanoseconds(for: retryCount))
                }
            }
        }

        sharedModelReadyTask = task
        sharedModelReadyTaskId = taskId
        sharedModelReadyKey = modelKey

        do {
            try await task.value
        } catch {
            if sharedModelReadyTaskId == taskId {
                clearSharedModelReadyTask()
            }
            throw error
        }

        if sharedModelReadyTaskId == taskId {
            clearSharedModelReadyTask()
        }
    }

    func startModelDownload(userInitiated: Bool = true) {
        guard !isDownloading && !isGenerating else { return }
        guard !isChatUnsupported else {
            showUnsupportedDeviceDialog = true
            return
        }
        if userInitiated {
            hasRequestedModelDownload = true
        }

        let target = modelSettings.currentTarget()
        let isDownloaded = downloader.isDownloaded(target: target.downloadTarget)
        if isDownloaded {
            isModelDownloaded = true
            modelDownloadSizeBytes = nil
            return
        }

        isDownloading = true
        seedDownloadProgressMemory()
        modelDownloadLoggedStart = true
        logger.info("Model download started", details: "model=\(target.id)")

        modelDownloadTask?.cancel()
        modelDownloadTask = Task {
            do {
                try await self.ensureModelReadyShared(target: target)
            } catch {
                if isCancellation(error) {
                    return
                }
                if self.modelDownloadLoggedStart {
                    self.logger.error("Model download failed", error)
                    self.modelDownloadLoggedStart = false
                } else {
                    self.logger.error("Model load failed", error)
                }
                await MainActor.run {
                    self.downloadToast = DownloadToastState(
                        phase: .errorDownload,
                        percent: nil,
                        status: self.userFacingModelReadyError(error, wasDownloaded: false),
                        offerRetryDownload: true
                    )
                    self.isDownloading = false
                    self.isModelDownloaded = false
                }
            }
        }
    }

    func autoStartModelDownloadIfNeeded() {
        guard !isDownloading && !isGenerating else { return }
        guard !isChatUnsupported else {
            isDownloading = false
            downloadToast = nil
            return
        }
        let target = modelSettings.currentTarget()
        let isDownloaded = downloader.isDownloaded(target: target.downloadTarget)
        isModelDownloaded = isDownloaded
        if !isDownloaded {
            return
        }
        modelDownloadSizeBytes = nil
        modelDownloadTask?.cancel()
        modelDownloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.ensureModelReadyShared(target: target)
            } catch {
                if self.isCancellation(error) {
                    return
                }
                await MainActor.run {
                    self.downloadToast = DownloadToastState(
                        phase: .errorLoad,
                        percent: nil,
                        status: self.userFacingModelReadyError(error, wasDownloaded: true),
                        offerRetryDownload: true
                    )
                    self.isDownloading = false
                    self.isModelDownloaded = false
                }
            }
        }
    }

    func cancelDownload() {
        resetGenerationState(stopRequested: true)
        modelDownloadTask?.cancel()
        modelDownloadTask = nil
        sharedModelReadyTask?.cancel()
        clearSharedModelReadyTask()
        downloader.cancel()
        if modelDownloadLoggedStart {
            logger.info("Model download cancelled")
            modelDownloadLoggedStart = false
        }
        hasRequestedModelDownload = false
        clearDownloadProgressMemory()
        refreshModelDownloadInfo()
    }

    func retryDownload() {
        startModelDownload(userInitiated: true)
    }

    func retryAssistantResponse(_ message: RenderedChatMessage) {
        guard message.role == .assistant else { return }
        if isGenerating {
            stopGenerating()
        }
        guard !isChatUnsupported else {
            showUnsupportedDeviceDialog = true
            return
        }
        guard let sessionId = currentSessionId else { return }

        let userNode: MessageNode?
        if message.isSynthetic {
            guard let syntheticIndex = messages.firstIndex(where: { $0.id == message.id }),
                  syntheticIndex > 0 else { return }
            let parentMessage = messages[syntheticIndex - 1]
            guard parentMessage.role == .user else { return }
            userNode = messageStore[sessionId]?.first(where: { $0.id == parentMessage.id })
        } else {
            guard let parentId = messageStore[sessionId]?.first(where: { $0.id == message.id })?.parentId else { return }
            userNode = messageStore[sessionId]?.first(where: { $0.id == parentId })
        }
        guard let userNode else { return }
        provider.resetContext()
        startGeneration(for: userNode)
    }

    func changeBranch(for message: RenderedChatMessage, delta: Int) {
        if isGenerating {
            stopGenerating()
        }
        guard let sessionId = currentSessionId else { return }
        guard let node = messageStore[sessionId]?.first(where: { $0.id == message.id }) else { return }
        let parentKey = node.parentId?.uuidString ?? "__root__"
        let parentId = node.parentId ?? rootId
        let siblings = dedupeSiblings(childrenFor(sessionId: sessionId, parentId: parentId))
        guard !siblings.isEmpty else { return }
        let selectionMap = branchSelections[sessionId] ?? [:]
        let currentId = selectionMap[parentKey] ?? siblings.last?.id
        let currentIndex = siblings.firstIndex { $0.id == currentId } ?? (siblings.count - 1)
        let nextIndex = max(0, min(siblings.count - 1, currentIndex + delta))
        branchSelections[sessionId, default: [:]][parentKey] = siblings[nextIndex].id
        rebuildMessages(for: sessionId)
    }

    private func createSessionForDraft() -> UUID {
        let created = (try? chatDb.createSession(title: "New chat"))
        let sessionId = created.flatMap { UUID(uuidString: $0.uuid) } ?? UUID()
        let updatedAt = created.map { Date(timeIntervalSince1970: Double($0.updatedAtUs) / 1_000_000.0) } ?? Date()

        logger.info("Session created", details: "id=\(sessionId.uuidString)")
        let session = ChatSession(id: sessionId, title: created?.title ?? "New chat", lastMessage: "", updatedAt: updatedAt)
        sessions.insert(session, at: 0)
        currentSessionId = session.id
        messageStore[session.id] = []
        branchSelections[session.id] = [:]
        invalidateChildrenCache(for: session.id)
        return session.id
    }

    private func startGeneration(for userNode: MessageNode) {
        guard !isChatUnsupported else {
            showUnsupportedDeviceDialog = true
            return
        }
        generationTask?.cancel()
        sessionSummaryTask?.cancel()
        stopRequested = false

        let target = modelSettings.currentTarget()
        let prompt = buildPrompt(text: userNode.text, attachments: userNode.attachments)

        let generationId = UUID()
        activeGenerationId = generationId
        activeGenerationSessionId = userNode.sessionId
        isGenerating = true
        isDownloading = false
        hasRequestedModelDownload = true
        streamingResponse = ""
        streamingParentId = userNode.id
        downloadToast = nil
        seedDownloadProgressMemory()
        rebuildMessages(for: userNode.sessionId)

        generationTask = Task {
            do {
                try await self.ensureModelReadyShared(target: target)
            } catch {
                if isCancellation(error) {
                    self.sharedModelReadyTask?.cancel()
                    self.downloader.cancel()
                    self.clearSharedModelReadyTask()
                    if self.activeGenerationId == generationId {
                        isGenerating = false
                        isDownloading = false
                        streamingParentId = nil
                        downloadToast = nil
                        activeGenerationId = nil
                        activeGenerationSessionId = nil
                    }
                    return
                }
                if self.activeGenerationId == generationId {
                    isGenerating = false
                    isDownloading = false
                    isModelDownloaded = false
                    streamingParentId = nil
                    downloadToast = DownloadToastState(
                        phase: .errorDownload,
                        percent: nil,
                        status: self.userFacingModelReadyError(error, wasDownloaded: self.downloader.isDownloaded(target: target.downloadTarget)),
                        offerRetryDownload: true
                    )
                    activeGenerationId = nil
                    activeGenerationSessionId = nil
                }
                return
            }

            let generationLimits = resolveGenerationLimits(target: target)
            let historySelection = buildHistorySelection(
                sessionId: userNode.sessionId,
                promptText: prompt.text,
                promptImageCount: prompt.imageFiles.count,
                currentMessageId: userNode.id,
                limits: generationLimits
            )

            if historySelection.wasTrimmed && overflowBypassMessageId != userNode.id {
                overflowBypassMessageId = nil
                pendingOverflow = PendingOverflow(sessionId: userNode.sessionId, messageId: userNode.id)
                activeGenerationId = nil
                activeGenerationSessionId = nil
                isGenerating = false
                isDownloading = false
                streamingResponse = ""
                streamingParentId = nil
                overflowAlert = OverflowAlertState(
                    inputTokens: historySelection.inputTokens,
                    inputBudget: historySelection.inputBudget,
                    contextLength: generationLimits.contextLength,
                    maxOutput: generationLimits.maxOutput
                )
                rebuildMessages(for: userNode.sessionId)
                return
            }

            overflowBypassMessageId = nil
            pendingOverflow = nil
            overflowAlert = nil

            let history = historySelection.messages
            let systemMessage = LlmMessage(text: systemPrompt(), role: .system, hasAttachments: false)
            let messages = [systemMessage] + history + [LlmMessage(text: prompt.text, role: .user, hasAttachments: !userNode.attachments.isEmpty)]

            let bufferLock = NSLock()
            var buffer = ""
            var tokenCount = 0
            let uiUpdateInterval: TimeInterval = 0.05
            var lastUiUpdate = Date.distantPast
            var pendingSnapshot: String?
            var updateWorkItem: DispatchWorkItem?

            let scheduleStreamingUpdate = {
                bufferLock.lock()
                if updateWorkItem != nil {
                    bufferLock.unlock()
                    return
                }
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    bufferLock.lock()
                    let snapshot = pendingSnapshot
                    pendingSnapshot = nil
                    updateWorkItem = nil
                    lastUiUpdate = Date()
                    bufferLock.unlock()
                    guard let snapshot else { return }
                    Task { @MainActor in
                        guard self.activeGenerationId == generationId else { return }
                        self.streamingResponse = snapshot
                    }
                }
                updateWorkItem = workItem
                bufferLock.unlock()
                DispatchQueue.main.asyncAfter(deadline: .now() + uiUpdateInterval, execute: workItem)
            }

            do {
                let summary = try await provider.generateChat(
                    target: target,
                    messages: messages,
                    imageFiles: prompt.imageFiles,
                    temperature: resolveTemperature(),
                    maxTokens: generationLimits.maxOutput,
                    onToken: { token in
                        let tokenEstimate = max(1, token.count / 4)
                        var snapshot = ""
                        var shouldUpdateNow = false

                        bufferLock.lock()
                        buffer.append(token)
                        tokenCount += tokenEstimate
                        snapshot = buffer
                        pendingSnapshot = snapshot
                        let now = Date()
                        shouldUpdateNow = now.timeIntervalSince(lastUiUpdate) >= uiUpdateInterval
                        if shouldUpdateNow {
                            lastUiUpdate = now
                            pendingSnapshot = nil
                            updateWorkItem?.cancel()
                            updateWorkItem = nil
                        }
                        bufferLock.unlock()

                        if shouldUpdateNow {
                            Task { @MainActor in
                                guard self.activeGenerationId == generationId else { return }
                                self.streamingResponse = snapshot
                            }
                        } else {
                            scheduleStreamingUpdate()
                        }
                    }
                )

                finishGeneration(parent: userNode, response: buffer, tokenCount: tokenCount, totalTimeMs: summary.totalTimeMs, interrupted: false, generationId: generationId)
            } catch {
                let wasCancelled = stopRequested || isCancellation(error)
                if activeGenerationId == generationId && !wasCancelled {
                    let details = "session=\(userNode.sessionId.uuidString) promptLen=\(prompt.text.count) responseLen=\(buffer.count) tokens=\(tokenCount)"
                    logger.error("Generation failed", error, details: details)
                    generationErrorMessage = "Response failed. Try again."
                }
                finishGeneration(parent: userNode, response: buffer, tokenCount: tokenCount, totalTimeMs: nil, interrupted: true, generationId: generationId)
            }
        }
    }

    private func finishGeneration(parent: MessageNode, response: String, tokenCount: Int, totalTimeMs: Int64?, interrupted: Bool, generationId: UUID) {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let isActiveGeneration = activeGenerationId == generationId
        if trimmed.isEmpty {
            if isActiveGeneration && !interrupted && generationErrorMessage == nil {
                let details = "session=\(parent.sessionId.uuidString) promptLen=\(parent.text.count)"
                logger.warning("Generation returned empty response", details: details)
                generationErrorMessage = "No response from model. Try again."
            }
        } else {
            let tokensPerSecond: Double? = {
                guard let totalTimeMs, totalTimeMs > 0 else { return nil }
                return Double(tokenCount) / (Double(totalTimeMs) / 1000.0)
            }()

            if isActiveGeneration {
                let meta: [DbAttachmentMeta] = []
                do {
                    let inserted = try chatDb.insertMessage(
                        sessionUuid: parent.sessionId.uuidString,
                        sender: .other,
                        text: trimmed,
                        parentMessageUuid: parent.id.uuidString,
                        attachments: meta
                    )

                    if let assistantId = UUID(uuidString: inserted.uuid) {
                        logger.info("Message created", details: "id=\(assistantId.uuidString) session=\(parent.sessionId.uuidString) role=assistant")
                        let timestamp = Date(timeIntervalSince1970: Double(inserted.createdAtUs) / 1_000_000.0)
                        let assistant = MessageNode(
                            id: assistantId,
                            sessionId: parent.sessionId,
                            parentId: parent.id,
                            role: .assistant,
                            text: trimmed,
                            timestamp: timestamp,
                            attachments: [],
                            isInterrupted: interrupted,
                            tokensPerSecond: tokensPerSecond
                        )

                        messageStore[parent.sessionId, default: []].append(assistant)
                        invalidateChildrenCache(for: parent.sessionId)
                        updateSelection(for: parent.sessionId, parentId: parent.id, childId: assistant.id)
                        updateSessionPreview(sessionId: parent.sessionId, preview: trimmed, date: assistant.timestamp)
                    } else {
                        logger.warning(
                            "Skipping assistant message persistence",
                            details: "session=\(parent.sessionId.uuidString) parent=\(parent.id.uuidString) interrupted=\(interrupted) reason=invalid_uuid"
                        )
                    }
                } catch {
                    logger.warning(
                        "Skipping assistant message persistence",
                        details: "session=\(parent.sessionId.uuidString) parent=\(parent.id.uuidString) interrupted=\(interrupted) error=\(error)"
                    )
                }
            } else {
                logger.info(
                    "Dropped stale generation response",
                    details: "session=\(parent.sessionId.uuidString) parent=\(parent.id.uuidString) interrupted=\(interrupted)"
                )
            }
        }

        if isActiveGeneration {
            isGenerating = false
            isDownloading = false
            streamingResponse = ""
            streamingParentId = nil
            downloadToast = nil
            activeGenerationId = nil
            activeGenerationSessionId = nil
        }

        if currentSessionId == parent.sessionId {
            rebuildMessages(for: parent.sessionId)
        }
        scheduleSessionSummary(for: parent.sessionId)
    }

    private func handleProgress(_ progress: DownloadProgress) {
        let resolvedProgress = downloadProgressTracker.resolve(progress)

        if resolvedProgress.isLoading {
            downloadToast = DownloadToastState(
                phase: .loading,
                percent: resolvedProgress.percent ?? progress.percent,
                status: resolvedProgress.status,
                offerRetryDownload: false
            )
            isDownloading = true
            return
        }

        if resolvedProgress.isReady {
            if modelDownloadLoggedStart {
                logger.info("Model download complete", details: progress.status)
                modelDownloadLoggedStart = false
            }
            downloadToast = DownloadToastState(phase: .ready, percent: 100, status: progress.status, offerRetryDownload: false)
            isDownloading = false
            isModelDownloaded = true
            modelDownloadSizeBytes = nil
            clearDownloadProgressMemory()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self.downloadToast?.phase == .ready {
                    self.downloadToast = nil
                }
            }
            return
        }

        downloadToast = DownloadToastState(
            phase: .downloading,
            percent: resolvedProgress.percent ?? 0,
            status: resolvedProgress.status,
            offerRetryDownload: false
        )
        isDownloading = true
    }

    private nonisolated static func buildSessions(
        from loaded: [DbSession],
        chatDb: EnsuDb,
        summaries: [String: String]
    ) -> [ChatSession] {
        let sessions: [ChatSession] = loaded.compactMap { session in
            guard let id = UUID(uuidString: session.uuid) else { return nil }
            let messages = (try? chatDb.getMessages(sessionUuid: session.uuid)) ?? []
            let sortedMessages = messages.sorted { $0.createdAtUs < $1.createdAtUs }
            let firstUserMessage = sortedMessages.first(where: { $0.sender == .selfUser })?.text ?? ""
            let lastMessageNode = sortedMessages.last
            let lastMessage = lastMessageNode?.text ?? ""
            let summary = summaries[session.uuid.lowercased()]
            let isPlaceholderTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                session.title.caseInsensitiveCompare("New chat") == .orderedSame
            let seedTitle = summary ?? (isPlaceholderTitle ? firstUserMessage : session.title)
            let title = Self.sessionTitle(from: seedTitle, fallback: session.title)
            let updatedAtUs = lastMessageNode?.createdAtUs ?? session.updatedAtUs
            return ChatSession(
                id: id,
                title: title,
                lastMessage: lastMessage,
                updatedAt: Date(timeIntervalSince1970: Double(updatedAtUs) / 1_000_000.0)
            )
        }
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func reloadFromDb() {
        reloadTask?.cancel()
        reopenChatStoreIfNeeded()
        let chatDb = chatDb
        let summaries = sessionSummaries
        let selected = currentSessionId

        reloadTask = Task.detached { [weak self, chatDb, summaries, selected] in
            let loaded = (try? chatDb.listSessions()) ?? []
            let refreshed = Self.buildSessions(from: loaded, chatDb: chatDb, summaries: summaries)

            let resolved = selected.flatMap { id in
                refreshed.first(where: { $0.id == id })?.id
            } ?? (selected == nil ? nil : refreshed.first?.id)

            if Task.isCancelled { return }

            await MainActor.run {
                guard let self else { return }
                if Task.isCancelled { return }

                let previousSessionId = self.currentSessionId
                let shouldPreserveMessages = resolved == previousSessionId && !self.messages.isEmpty
                let preservedMessages = self.messages
                let preservedMessageStore = self.messageStore
                let preservedBranchSelections = self.branchSelections

                self.sessions = refreshed
                self.currentSessionId = resolved
                self.messageStore = [:]
                self.branchSelections = [:]
                self.childrenByParentCache = [:]

                for session in refreshed {
                    if shouldPreserveMessages, session.id == resolved, let nodes = preservedMessageStore[session.id] {
                        self.messageStore[session.id] = nodes
                        self.branchSelections[session.id] = preservedBranchSelections[session.id] ?? [:]
                    } else {
                        self.messageStore[session.id] = []
                        self.branchSelections[session.id] = [:]
                    }
                }

                if shouldPreserveMessages {
                    self.messages = preservedMessages
                } else {
                    self.messages = []
                }

                if let current = resolved {
                    self.loadMessagesFromDb(for: current)
                }
            }
        }
    }

    private func loadMessagesFromDb(for sessionId: UUID) {
        reopenChatStoreIfNeeded()
        if messageStore[sessionId] == nil {
            messageStore[sessionId] = []
            branchSelections[sessionId] = [:]
        }

        let chatDb = chatDb
        let attachmentsDir = attachmentsDir

        Task.detached { [weak self, chatDb, attachmentsDir] in
            guard let self else { return }

            let rawMessages = (try? chatDb.getMessages(sessionUuid: sessionId.uuidString)) ?? []

            let nodes: [MessageNode] = rawMessages.compactMap { msg in
                guard let messageId = UUID(uuidString: msg.uuid) else { return nil }
                let parentId = msg.parentMessageUuid.flatMap { UUID(uuidString: $0) }
                let role: RenderedChatMessage.Role = (msg.sender == .selfUser) ? .user : .assistant
                let timestamp = Date(timeIntervalSince1970: Double(msg.createdAtUs) / 1_000_000.0)

                let attachments: [ChatAttachment] = msg.attachments.compactMap { meta in
                    guard let attachmentId = UUID(uuidString: meta.id) else { return nil }
                    let kind: ChatAttachment.Kind = (meta.kind == .image) ? .image : .document
                    let file = attachmentsDir.appendingPathComponent(meta.id)
                    return ChatAttachment(
                        id: attachmentId,
                        name: meta.name,
                        size: meta.size,
                        kind: kind,
                        url: FileManager.default.fileExists(atPath: file.path) ? file : nil,
                        isUploading: false
                    )
                }

                return MessageNode(
                    id: messageId,
                    sessionId: sessionId,
                    parentId: parentId,
                    role: role,
                    text: msg.text,
                    timestamp: timestamp,
                    attachments: attachments,
                    isInterrupted: false,
                    tokensPerSecond: nil
                )
            }

            await MainActor.run {
                guard self.messageStore[sessionId] != nil else { return }
                self.messageStore[sessionId] = nodes
                // Branch selection is computed in-memory.
                self.branchSelections[sessionId] = [:]
                self.invalidateChildrenCache(for: sessionId)
                if self.currentSessionId == sessionId {
                    self.rebuildMessages(for: sessionId)
                }
            }
        }
    }

    private func rebuildMessages(for sessionId: UUID) {
        let childrenMap = childrenByParent(sessionId: sessionId)
        let path = buildSelectedPath(for: sessionId, childrenMap: childrenMap)
        let selectionMap = branchSelections[sessionId, default: [:]]

        messages = path.map { node in
            let parentKey = node.parentId?.uuidString ?? "__root__"
            let parentId = node.parentId ?? rootId
            let siblings = dedupeSiblings(childrenMap[parentId] ?? [])
            let selectedId = selectionMap[parentKey]
            let index = siblings.firstIndex { $0.id == selectedId } ?? (siblings.count - 1)

            return RenderedChatMessage(
                id: node.id,
                role: node.role,
                text: node.text,
                timestamp: node.timestamp,
                attachments: node.attachments,
                isInterrupted: node.isInterrupted,
                isSynthetic: false,
                tokensPerSecond: node.tokensPerSecond,
                branchIndex: max(1, index + 1),
                branchCount: max(1, siblings.count)
            )
        }

        var augmented: [RenderedChatMessage] = []
        for (i, msg) in messages.enumerated() {
            augmented.append(msg)
            if msg.role == .user {
                let next = i + 1 < messages.count ? messages[i + 1] : nil
                let isLastAndGenerating = i == messages.count - 1 && isGenerating
                if next?.role != .assistant && !isLastAndGenerating {
                    augmented.append(RenderedChatMessage(
                        id: deterministicSyntheticMessageId(parentId: msg.id),
                        role: .assistant,
                        text: "Response was interrupted",
                        timestamp: msg.timestamp,
                        isInterrupted: true,
                        isSynthetic: true
                    ))
                }
            }
        }
        messages = augmented
    }

    private func deterministicSyntheticMessageId(parentId: UUID) -> UUID {
        var uuid = parentId.uuid
        uuid.0 ^= 0xA5
        uuid.15 ^= 0x5A
        return UUID(uuid: uuid)
    }

    private func buildSelectedPath(for sessionId: UUID, childrenMap: [UUID: [MessageNode]]) -> [MessageNode] {
        guard let nodes = messageStore[sessionId], !nodes.isEmpty else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let roots = dedupeSiblings(nodes.filter { node in
            guard let parentId = node.parentId else { return true }
            return byId[parentId] == nil
        })
        guard !roots.isEmpty else { return [] }

        let selectionMap = branchSelections[sessionId, default: [:]]
        var current = selectChild(selectionMap: selectionMap, selectionKey: "__root__", candidates: roots)
        var path: [MessageNode] = []
        var visited = Set<UUID>()

        while let node = current, visited.insert(node.id).inserted {
            path.append(node)
            if node.id == streamingParentId { break }
            let children = dedupeSiblings(childrenMap[node.id] ?? [])
            if children.isEmpty { break }
            current = selectChild(selectionMap: selectionMap, selectionKey: node.id.uuidString, candidates: children)
        }
        return path
    }

    private func selectChild(selectionMap: [String: UUID], selectionKey: String, candidates: [MessageNode]) -> MessageNode? {
        guard !candidates.isEmpty else { return nil }
        if let selectedId = selectionMap[selectionKey],
           let selected = candidates.first(where: { $0.id == selectedId }) {
            return selected
        }
        return candidates.last
    }

    private func invalidateChildrenCache(for sessionId: UUID) {
        childrenByParentCache[sessionId] = nil
    }

    private func childrenByParent(sessionId: UUID) -> [UUID: [MessageNode]] {
        if let cached = childrenByParentCache[sessionId] {
            return cached
        }
        var map: [UUID: [MessageNode]] = [:]
        guard let nodes = messageStore[sessionId] else { return map }
        let byId = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for node in nodes {
            let parent = node.parentId.flatMap { byId[$0] != nil ? $0 : nil } ?? rootId
            map[parent, default: []].append(node)
        }
        childrenByParentCache[sessionId] = map
        return map
    }

    private func childrenFor(sessionId: UUID, parentId: UUID) -> [MessageNode] {
        let map = childrenByParent(sessionId: sessionId)
        return map[parentId] ?? []
    }

    private func dedupeSiblings(_ nodes: [MessageNode]) -> [MessageNode] {
        guard nodes.count > 1 else { return nodes.sorted(by: { $0.timestamp < $1.timestamp }) }
        let sorted = nodes.sorted(by: { $0.timestamp < $1.timestamp })
        var result: [MessageNode] = []
        for node in sorted {
            if let last = result.last, isDuplicate(last, node) {
                continue
            }
            result.append(node)
        }
        return result
    }

    private func isDuplicate(_ lhs: MessageNode, _ rhs: MessageNode) -> Bool {
        guard lhs.role == rhs.role else { return false }
        guard lhs.text == rhs.text else { return false }
        guard attachmentSignature(lhs.attachments) == attachmentSignature(rhs.attachments) else { return false }
        return abs(lhs.timestamp.timeIntervalSince(rhs.timestamp)) <= 2
    }

    private func attachmentSignature(_ attachments: [ChatAttachment]) -> [String] {
        attachments.map { "\($0.kind)-\($0.name)" }
    }

    private func updateSelection(for sessionId: UUID, parentId: UUID?, childId: UUID) {
        let key = parentId?.uuidString ?? "__root__"
        branchSelections[sessionId, default: [:]][key] = childId
    }

    private func updateSessionPreview(sessionId: UUID, preview: String, date: Date) {
        sessions = sessions.map { session in
            guard session.id == sessionId else { return session }
            var updated = session
            let isPlaceholderTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                session.title.caseInsensitiveCompare("New chat") == .orderedSame
            if isPlaceholderTitle {
                let updatedTitle = Self.sessionTitle(from: preview, fallback: session.title)
                if updatedTitle != session.title {
                    _ = try? chatDb.updateSessionTitle(uuid: sessionId.uuidString, title: updatedTitle)
                }
                updated.title = updatedTitle
            }
            updated.lastMessage = preview
            updated.updatedAt = date
            return updated
        }
    }

    private func scheduleSessionSummary(for sessionId: UUID) {
        guard !isChatUnsupported else { return }
        sessionSummaryTask?.cancel()
        let summaryKey = sessionSummaryKey(sessionId)
        guard sessionSummaries[summaryKey] == nil else { return }
        guard let summaryInput = buildSessionSummaryInput(sessionId: sessionId) else { return }
        let existingSummary = sessionSummaries[summaryKey]
        let target = modelSettings.currentTarget()
        let provider = provider

        sessionSummaryTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let summary = await Self.generateSessionSummary(
                input: summaryInput.text,
                fallback: summaryInput.fallback,
                existingSummary: existingSummary,
                provider: provider,
                target: target
            )
            guard let summary else { return }

            await MainActor.run {
                self.applySessionSummary(sessionId: sessionId, summary: summary)
            }
        }
    }

    private func buildSessionSummaryInput(sessionId: UUID) -> (text: String, fallback: String)? {
        guard let nodes = messageStore[sessionId], !nodes.isEmpty else { return nil }
        let sorted = nodes.sorted(by: { $0.timestamp < $1.timestamp })
        guard let firstUser = sorted.first(where: { $0.role == .user }) else { return nil }
        let input = "User: \(firstUser.text)"
        let fallback = Self.summarizeQuestion(firstUser.text)
        return (text: input, fallback: fallback)
    }

    private func applySessionSummary(sessionId: UUID, summary: String) {
        let sanitized = Self.sessionTitle(from: summary, fallback: "New chat")
        guard !sanitized.isEmpty else { return }
        let summaryKey = sessionSummaryKey(sessionId)
        if sessionSummaries[summaryKey] == sanitized { return }
        sessionSummaries[summaryKey] = sanitized
        persistSessionSummaries()
        _ = try? chatDb.updateSessionTitle(uuid: sessionId.uuidString, title: sanitized)
        sessions = sessions.map { session in
            guard session.id == sessionId else { return session }
            var updated = session
            updated.title = sanitized
            return updated
        }
    }

    private func persistSessionSummaries() {
        guard let data = try? JSONEncoder().encode(sessionSummaries) else { return }
        UserDefaults.standard.set(data, forKey: Self.sessionSummaryStoreKey)
    }

    private func sessionSummaryKey(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private func sessionSummaryKey(_ id: String) -> String {
        id.lowercased()
    }

    private static func loadSessionSummaries() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionSummaryStoreKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func summarizeQuestion(_ text: String) -> String {
        let cleaned = sanitizeTitleText(text)
        guard !cleaned.isEmpty else { return "" }
        let words = cleaned.split(separator: " ").map {
            String($0).trimmingCharacters(in: .punctuationCharacters)
        }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return "" }
        let summaryWords = words.prefix(Self.sessionSummaryMaxWords)
        return summaryWords.joined(separator: " ")
    }

    private nonisolated static func sanitizeTitleText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[\\r\\n\\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func sessionTitle(from text: String, fallback: String = "New chat") -> String {
        let trimmed = sanitizeTitleText(text)
        guard !trimmed.isEmpty else { return fallback }
        if trimmed.count <= Self.sessionTitleMaxLength {
            return trimmed
        }
        let prefix = trimmed.prefix(Self.sessionTitleMaxLength)
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func generateSessionSummary(
        input: String,
        fallback: String,
        existingSummary: String?,
        provider: LlmProvider,
        target: LlmModelTarget
    ) async -> String? {
        if let existingSummary, !existingSummary.isEmpty { return nil }
        let cleanedInput = sanitizeTitleText(input)
        guard !cleanedInput.isEmpty else { return sessionTitle(from: fallback, fallback: fallback) }

        let messages = [
            LlmMessage(text: sessionSummarySystemPrompt, role: .system, hasAttachments: false),
            LlmMessage(text: cleanedInput, role: .user, hasAttachments: false)
        ]

        let bufferLock = NSLock()
        var buffer = ""

        do {
            _ = try await provider.generateChat(
                target: target,
                messages: messages,
                imageFiles: [],
                temperature: 0.2,
                maxTokens: 64
            ) { token in
                bufferLock.lock()
                buffer.append(token)
                bufferLock.unlock()
            }
        } catch {
            let fallbackSummary = summarizeQuestion(fallback)
            return fallbackSummary.isEmpty ? nil : sessionTitle(from: fallbackSummary, fallback: fallback)
        }

        let raw = sanitizeTitleText(buffer)
        guard !raw.isEmpty else { return sessionTitle(from: fallback, fallback: fallback) }
        let words = raw.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let summaryWords = words.prefix(Self.sessionSummaryMaxWords)
        let summary = summaryWords.joined(separator: " ")
        return sessionTitle(from: summary, fallback: fallback)
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case LlmError.Cancelled = error { return true }
        return (error as? URLError)?.code == .cancelled
    }

    private func seedDownloadProgressMemory() {
        downloadProgressTracker.seed(from: downloadToast)
    }

    private func clearDownloadProgressMemory() {
        downloadProgressTracker.clear()
    }

    private func shouldRetryModelDownload(_ error: Error, retryCount: Int) -> Bool {
        if retryCount >= 5 { return false }
        if isCancellation(error) { return false }
        if isOutOfStorageError(error) { return false }

        if case let LlmError.Download(inner) = error {
            switch inner {
            case .validation:
                return false
            case let .http(status):
                if status == 401 || status == 403 || status == 404 { return false }
            default:
                break
            }
        }

        return true
    }

    private func retryDelayNanoseconds(for retryCount: Int) -> UInt64 {
        let shift = max(0, retryCount - 1)
        let multiplier = UInt64(1 << shift)
        let delayMs = min(12_000, 1_500 * Int(multiplier))
        return UInt64(delayMs) * 1_000_000
    }

    private func userFacingModelReadyError(_ error: Error, wasDownloaded: Bool) -> String {
        if error is UnsupportedDeviceMemoryError {
            return Self.unsupportedDeviceMessage
        }
        if isOutOfStorageError(error) {
            return "Not enough storage space to download the model. Please free up space and try again."
        }
        return wasDownloaded ? "Model load failed" : "Download failed. Please try again."
    }

    private func isOutOfStorageError(_ error: Error) -> Bool {
        if case LlmError.Download(.storageFull) = error { return true }
        return error.isOutOfDiskSpace
    }

    private nonisolated func attachmentsDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("llmchat", isDirectory: true)
            .appendingPathComponent("chat_attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    private nonisolated func writeAttachment(data: Data, attachmentId: UUID) throws -> URL {
        let dir = try attachmentsDirectory()
        let destination = dir.appendingPathComponent(attachmentId.uuidString.lowercased())
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private nonisolated func copyAttachment(from url: URL, attachmentId: UUID) throws -> URL {
        let dir = try attachmentsDirectory()
        let destination = dir.appendingPathComponent(attachmentId.uuidString.lowercased())

        let needsSecurity = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurity {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    private struct HistorySelection {
        let messages: [LlmMessage]
        let inputTokens: Int
        let inputBudget: Int
        let wasTrimmed: Bool
    }

    private struct GenerationLimits {
        let contextLength: Int
        let maxOutput: Int
    }

    private struct PendingOverflow {
        let sessionId: UUID
        let messageId: UUID
    }

    private func buildPrompt(text: String, attachments: [ChatAttachment]) -> PromptResult {
        var prompt = text
        let documents = attachments.filter { $0.kind == .document }
        let images = attachments.filter { $0.kind == .image }

        for (index, attachment) in documents.enumerated() {
            prompt += "\n\n----- BEGIN DOCUMENT: Document \(index + 1) -----\n"
            prompt += "Attached document: \(attachment.name)\n"
            prompt += "----- END DOCUMENT: Document \(index + 1) -----"
        }

        let imageFiles = images.compactMap { $0.url }
        if !imageFiles.isEmpty {
            let mediaMarker = "<__media__>"
            prompt += "\n\n[\(imageFiles.count) image attachment"
            if imageFiles.count > 1 { prompt += "s" }
            prompt += " provided]"
            for _ in imageFiles {
                prompt += "\n\(mediaMarker)"
            }
        }

        return PromptResult(text: prompt, imageFiles: imageFiles)
    }

    private func buildHistorySelection(
        sessionId: UUID,
        promptText: String,
        promptImageCount: Int,
        currentMessageId: UUID,
        limits: GenerationLimits
    ) -> HistorySelection {
        let childrenMap = childrenByParent(sessionId: sessionId)
        let path = buildSelectedPath(for: sessionId, childrenMap: childrenMap)
        let historyMessages = path.prefix { $0.id != currentMessageId }

        let inputBudget = max(0, limits.contextLength - limits.maxOutput - Self.overflowSafetyTokens)
        let systemTokens = estimateTokens(systemPrompt())
        let promptTokens = estimatePromptTokens(promptText: promptText, imageCount: promptImageCount)
        let historyTokens = historyMessages.reduce(0) { total, node in
            total + estimateTokens(historyText(node))
        }
        let inputTokens = systemTokens + promptTokens + historyTokens
        let remaining = inputBudget - systemTokens - promptTokens

        if remaining <= 0 || historyMessages.isEmpty {
            return HistorySelection(messages: [], inputTokens: inputTokens, inputBudget: inputBudget, wasTrimmed: inputTokens > inputBudget)
        }

        let quantum = max(1, inputBudget / 4)
        let overflow = max(0, historyTokens - remaining)
        let quantaToDiscard = (overflow + quantum - 1) / quantum
        let discardTarget = quantaToDiscard * quantum
        var discarded = 0
        var startIndex = historyMessages.startIndex
        while startIndex < historyMessages.endIndex && discarded < discardTarget {
            discarded += estimateTokens(historyText(historyMessages[startIndex]))
            startIndex = historyMessages.index(after: startIndex)
        }

        var retained = historyMessages[startIndex...]
        if retained.isEmpty, let last = historyMessages.last, estimateTokens(historyText(last)) <= remaining {
            retained = historyMessages.suffix(1)
        }

        let selected = retained.map { node in
            let text = historyText(node)
            return LlmMessage(text: text, role: node.role == .user ? .user : .assistant, hasAttachments: !node.attachments.isEmpty)
        }

        return HistorySelection(messages: selected, inputTokens: inputTokens, inputBudget: inputBudget, wasTrimmed: inputTokens > inputBudget)
    }

    private func resolveGenerationLimits(target: LlmModelTarget) -> GenerationLimits {
        let contextLength = provider.loadedContextLength(target: target) ?? target.contextLength ?? 12000
        let maxOutput = resolveMaxOutputTokens(configuredMaxTokens: target.maxTokens, contextLength: contextLength)
        return GenerationLimits(contextLength: contextLength, maxOutput: maxOutput)
    }

    private func resolveMaxOutputTokens(configuredMaxTokens: Int?, contextLength: Int) -> Int {
        let maxAllowed = max(1, contextLength - Self.overflowSafetyTokens)
        let implicitMax = min(Self.defaultGenerationMaxTokens, max(1, contextLength / 2))
        return min(maxAllowed, configuredMaxTokens ?? implicitMax)
    }

    private func historyText(_ node: MessageNode) -> String {
        var text = node.text
        if node.role == .assistant {
            if let regex = ChatMessageTagRegex.think {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            } else {
                text = text.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
            }
            if let regex = ChatMessageTagRegex.todoList {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            } else {
                text = text.replacingOccurrences(of: "<todo_list>[\\s\\S]*?</todo_list>", with: "", options: .regularExpression)
            }
        } else if !node.attachments.isEmpty {
            text += "\n\n[\(node.attachments.count) attachments attached]"
        }
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private func trimToBudget(_ text: String, budget: Int) -> String {
        guard budget > 0 else { return "" }
        let maxChars = budget * 4
        if text.count <= maxChars { return text }
        return String(text.suffix(maxChars))
    }

    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    private func estimateImageTokens(_ imageCount: Int) -> Int {
        imageCount * Self.imageTokenEstimate
    }

    private func estimatePromptTokens(promptText: String, imageCount: Int) -> Int {
        estimateTokens(promptText) + estimateImageTokens(imageCount)
    }

    private func resolveTemperature() -> Float {
        let value = Float(modelSettings.temperature.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
        let resolved = value.map { max(0, $0) } ?? Self.defaultTemperature
        return min(max(resolved, 0.35), 0.7)
    }

    private struct MessageNode: Identifiable {
        let id: UUID
        let sessionId: UUID
        let parentId: UUID?
        let role: RenderedChatMessage.Role
        let text: String
        let timestamp: Date
        let attachments: [ChatAttachment]
        let isInterrupted: Bool
        let tokensPerSecond: Double?
    }

    private struct PromptResult {
        let text: String
        let imageFiles: [URL]
    }
}

private struct ResolvedDownloadProgress {
    let percent: Int?
    let status: String
    let isLoading: Bool
    let isReady: Bool
}

private final class DownloadProgressTracker {
    private var lastVisiblePercent: Int?
    private var lastVisibleStatus: String?

    func seed(from toast: DownloadToastState?) {
        if let toast, let percent = toast.percent {
            lastVisiblePercent = percent
            lastVisibleStatus = toast.status
        } else {
            lastVisiblePercent = 0
            lastVisibleStatus = "Starting download..."
        }
    }

    func clear() {
        lastVisiblePercent = nil
        lastVisibleStatus = nil
    }

    func resolve(_ progress: DownloadProgress) -> ResolvedDownloadProgress {
        let isLoading = progress.phase == .loading
        let isReady = progress.phase == .ready
        let rawPercent = progress.percent
        let previousPercent = lastVisiblePercent
        let previousStatus = lastVisibleStatus

        let resolvedPercent: Int? = {
            if isReady { return 100 }
            if let rawPercent {
                if let previousPercent {
                    return max(rawPercent, previousPercent)
                }
                return rawPercent
            }
            return previousPercent
        }()
        let regressed = {
            guard let rawPercent, let previousPercent else { return false }
            return rawPercent < previousPercent
        }()
        let resolvedStatus: String = {
            if isReady || isLoading {
                return progress.status
            }
            if regressed {
                return previousStatus ?? progress.status
            }
            return progress.status
        }()

        if !isReady {
            lastVisiblePercent = resolvedPercent
            lastVisibleStatus = resolvedStatus
        }

        return ResolvedDownloadProgress(
            percent: resolvedPercent,
            status: resolvedStatus,
            isLoading: isLoading,
            isReady: isReady
        )
    }
}
