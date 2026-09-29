import Foundation
import os

func automaticMaxOutputTokens(contextLength: Int) -> Int {
    min(2048, max(1, contextLength / 4))
}

struct LlmModelSelection: Equatable {
    let id: String
    let contextLength: Int?
}

struct DownloadProgress: Equatable {
    let percent: Int?
    let status: String
    var phase: DownloadPhase = .downloading
}

enum DownloadPhase {
    case downloading
    case loading
    case ready
}

extension Error {
    var isOutOfDiskSpace: Bool {
        var current: NSError? = self as NSError
        while let nsError = current {
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
                return true
            }
            if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) {
                return true
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

enum LlmMessageRole {
    case user
    case assistant
    case system

    var roleString: String {
        switch self {
        case .user:
            return "user"
        case .assistant:
            return "assistant"
        case .system:
            return "system"
        }
    }
}

struct LlmMessage {
    let text: String
    let role: LlmMessageRole
    let hasAttachments: Bool
}

struct GenerationSummary {
    let jobId: Int64
    let generatedTokens: Int
    let totalTimeMs: Int64?
}

struct RequiredModelValidationError: LocalizedError {
    let modelId: String

    var errorDescription: String? {
        "Downloaded model failed validation: \(modelId)"
    }
}

struct EmbeddingAssetInvalidError: LocalizedError {
    var errorDescription: String? { "Embedding model asset is invalid" }
}

actor AsyncSerialGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async throws -> T
    ) async throws -> T {
        await acquire()
        do {
            try Task.checkCancellation()
            let result = try await operation()
            await release()
            return result
        } catch {
            await release()
            throw error
        }
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}

actor LlmProvider {
    private struct LoadedModelKey: Equatable {
        let id: String
        let requestedContextLength: Int?
    }

    private let assetStore: AssetStore
    private let transcriber: Transcriber
    private let knowledgeEmbedding: KnowledgeEmbeddingConfig
    private let embeddingAsset: Asset
    private var loadedModel: LlmModel?
    private var loadedContext: LlmContext?
    private var currentModelKey: LoadedModelKey?
    private var currentContextLength: Int?
    private var backendInitialized = false
    private var chatWarmupOwner: UUID?
    private nonisolated let currentJobId = OSAllocatedUnfairLock<Int64?>(initialState: nil)
    private nonisolated let generationControl = OSAllocatedUnfairLock<ChatGenerationControl?>(
        initialState: nil)
    private let modelLoadGate = AsyncSerialGate()
    @MainActor weak var modelMaintenance: (any ModelMaintenance)?

    private func withModelLock<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async throws -> T
    ) async throws -> T {
        let maintenance = await modelMaintenance
        let scope = await maintenance?.suspendMaintenance()
        defer { scope?.close() }
        await maintenance?.awaitMaintenance()
        return try await modelLoadGate.withLock(operation)
    }

    init(
        assetStore: AssetStore, transcriber: Transcriber,
        knowledgeEmbedding: KnowledgeEmbeddingConfig
    ) {
        self.assetStore = assetStore
        self.transcriber = transcriber
        self.knowledgeEmbedding = knowledgeEmbedding
        self.embeddingAsset = knowledgeEmbeddingModelAsset()
    }

    nonisolated func isEmbeddingModelReady() -> Bool {
        assetStore.isDownloaded(embeddingAsset)
    }

    nonisolated func isChatModelReady(_ selection: LlmModelSelection) -> Bool {
        assetStore.isDownloaded(chatAsset(selection))
    }

    nonisolated func isModelDownloaded(_ selection: LlmModelSelection) -> Bool {
        isChatModelReady(selection) && (!isEnsuPacksEnabled || isEmbeddingModelReady())
    }

    func missingModelDownloadSize(_ selection: LlmModelSelection) async -> Int64? {
        var total: Int64 = 0
        let asset = chatAsset(selection)
        if !assetStore.isDownloaded(asset) {
            guard let chatSize = await assetStore.estimateDownloadSize(asset) else {
                return nil
            }
            total += chatSize
        }
        if isEnsuPacksEnabled && !isEmbeddingModelReady() {
            guard let embeddingSize = await assetStore.estimateDownloadSize(embeddingAsset) else {
                return nil
            }
            total += embeddingSize
        }
        return total > 0 ? total : nil
    }

    func ensureRequiredModelsReady(
        _ selection: LlmModelSelection,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws {
        let capability = currentChatDeviceCapability()
        if !capability.isChatSupported {
            throw UnsupportedDeviceMemoryError(capability: capability)
        }

        let asset = chatAsset(selection)
        let missingAssets: [Asset] = try await withModelLock {
            let embeddingReady = isEmbeddingModelReady()
            if isEnsuPacksEnabled && !embeddingReady {
                _ = assetStore.removeDownloaded(embeddingAsset)
            }

            return [
                assetStore.isDownloaded(asset) ? nil : asset,
                (!isEnsuPacksEnabled || embeddingReady) ? nil : embeddingAsset,
            ].compactMap { $0 }
        }

        if !missingAssets.isEmpty {
            try await downloadAssets(missingAssets, onProgress: onProgress)
        }

        try await withModelLock {
            guard !isEnsuPacksEnabled || isEmbeddingModelReady() else {
                _ = assetStore.removeDownloaded(embeddingAsset)
                throw RequiredModelValidationError(modelId: knowledgeEmbedding.targetId)
            }
            try await ensureModelReadyLocked(
                selection,
                onProgress: onProgress,
                allowRecovery: false,
                shouldDownload: false
            )
            guard assetStore.isDownloaded(asset) else {
                throw RequiredModelValidationError(modelId: selection.id)
            }
        }
    }

    func ensureModelReady(
        _ selection: LlmModelSelection,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws {
        try await withModelLock {
            try await ensureModelReadyLocked(selection, onProgress: onProgress, allowRecovery: true)
        }
    }

    func prewarmChatModelIfDownloaded(
        _ selection: LlmModelSelection, owner: UUID
    ) async throws {
        try await withModelLock {
            guard isChatModelReady(selection) else { return }
            unloadTranscriptionModelIfLoaded()
            try Task.checkCancellation()
            guard loadedContextLength(selection) == nil else { return }
            do {
                try await ensureModelReadyLocked(
                    selection, onProgress: { _ in }, allowRecovery: false, shouldDownload: false)
                try Task.checkCancellation()
                chatWarmupOwner = owner
            } catch {
                unloadModel()
                throw error
            }
        }
    }

    func releaseChatWarmup(owner: UUID) async {
        try? await modelLoadGate.withLock {
            if chatWarmupOwner == owner { unloadModel() }
        }
    }

    private func ensureModelReadyLocked(
        _ selection: LlmModelSelection,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void,
        allowRecovery: Bool,
        shouldDownload: Bool = true
    ) async throws {
        chatWarmupOwner = nil
        let capability = currentChatDeviceCapability()
        if !capability.isChatSupported {
            throw UnsupportedDeviceMemoryError(capability: capability)
        }
        let modelKey = LoadedModelKey(
            id: selection.id, requestedContextLength: selection.contextLength)
        if currentModelKey == modelKey, loadedModel != nil, loadedContext != nil {
            return
        }

        unloadModel()

        if !backendInitialized {
            try llmInitBackend()
            backendInitialized = true
        }

        let asset = chatAsset(selection)
        let wasAlreadyDownloaded = assetStore.isDownloaded(asset)
        if shouldDownload {
            try await downloadAssets([asset], onProgress: onProgress)
        }

        onProgress(DownloadProgress(percent: 100, status: "Loading model...", phase: .loading))
        do {
            guard let modelPath = assetStore.llmModelPath(asset) else {
                throw RequiredModelValidationError(modelId: selection.id)
            }
            try loadModel(selection, modelPath: modelPath)
        } catch {
            if allowRecovery, wasAlreadyDownloaded, assetStore.removeDownloaded(asset) {
                onProgress(DownloadProgress(percent: 0, status: "Starting download..."))
                try await ensureModelReadyLocked(
                    selection, onProgress: onProgress, allowRecovery: false)
                return
            }
            throw error
        }
        onProgress(DownloadProgress(percent: 100, status: "Ready", phase: .ready))
    }

    private func downloadAssets(
        _ assets: [Asset],
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws {
        try await assetStore.download(assets: assets) { progress in
            onProgress(
                DownloadProgress(
                    percent: min(max(Int(progress.percentage), 0), 99),
                    status: progress.status
                )
            )
        }
    }

    func generateChat(
        _ selection: LlmModelSelection,
        messages: [LlmMessage],
        imageFiles: [URL],
        temperature: Float,
        maxTokens: Int?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> GenerationSummary {
        try await withModelLock {
            try await generateChatLocked(
                selection,
                messages: messages.map {
                    LlmChatMessage(role: $0.role.roleString, content: $0.text)
                },
                imageFiles: imageFiles,
                temperature: temperature,
                maxTokens: maxTokens,
                onToken: onToken
            )
        }
    }

    func generateTitle(
        _ selection: LlmModelSelection,
        messages: [LlmMessage],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        let control = ChatGenerationControl()
        try await withTaskCancellationHandler {
            try await withModelLock {
                try control.checkCancellation()
                try await ensureModelReadyLocked(
                    selection, onProgress: { _ in }, allowRecovery: true)
                try control.checkCancellation()
                unloadTranscriptionModelIfLoaded()
                guard let model = loadedModel, let loadedContext else { throw CancellationError() }
                generationControl.withLock { $0 = control }
                defer { generationControl.withLock { $0 = nil } }
                let context = try model.newContext(
                    params: LlmContextParams(
                        contextSize: Int32(min(2048, loadedContext.contextSize())),
                        nThreads: Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1)),
                        nBatch: 128
                    ))
                let outputTokens = 48
                let inputTokens = max(0, min(2000, Int(context.contextSize()) - outputTokens))
                let titleMessages = try context.truncateTextChatMessages(
                    messages: messages.map {
                        LlmChatMessage(role: $0.role.roleString, content: $0.text)
                    },
                    maxTokens: UInt32(inputTokens)
                )
                _ = try await generateChatLocked(
                    selection,
                    messages: titleMessages,
                    imageFiles: [], temperature: 0.2, maxTokens: outputTokens,
                    contextOverride: context, control: control, onToken: onToken
                )
            }
        } onCancel: {
            control.cancel(invalidatePreparation: false)
        }
    }

    func withConversationContext<T: Sendable>(
        _ selection: LlmModelSelection,
        _ operation: @MainActor (LlmContext, ChatGenerationControl) async throws -> T
    ) async throws -> T {
        let control = ChatGenerationControl()
        return try await withTaskCancellationHandler {
            try await withModelLock {
                try control.checkCancellation()
                generationControl.withLock { $0 = control }
                defer { generationControl.withLock { $0 = nil } }
                try await ensureModelReadyLocked(
                    selection, onProgress: { _ in }, allowRecovery: true)
                try control.checkCancellation()
                guard let context = loadedContext else {
                    throw CancellationError()
                }
                unloadTranscriptionModelIfLoaded()
                try control.checkCancellation()
                return try await operation(context, control)
            }
        } onCancel: {
            control.cancel(invalidatePreparation: false)
        }
    }

    func generatePreparedChat(
        _ selection: LlmModelSelection,
        messages: [LlmChatMessage],
        temperature: Float,
        maxTokens: UInt32,
        control: ChatGenerationControl,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> GenerationSummary {
        try await generateChatLocked(
            selection,
            messages: messages,
            imageFiles: [],
            temperature: temperature,
            maxTokens: Int(maxTokens),
            control: control,
            onToken: onToken
        )
    }

    private func generateChatLocked(
        _ selection: LlmModelSelection,
        messages: [LlmChatMessage],
        imageFiles: [URL],
        temperature: Float,
        maxTokens: Int?,
        contextOverride: LlmContext? = nil,
        control: ChatGenerationControl? = nil,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> GenerationSummary {
        let capability = currentChatDeviceCapability()
        if !capability.isChatSupported {
            throw UnsupportedDeviceMemoryError(capability: capability)
        }
        guard let context = contextOverride ?? loadedContext else {
            throw NSError(
                domain: "LlmProvider", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        currentJobId.withLock { $0 = nil }

        let asset = chatAsset(selection)
        let mmprojPath =
            imageFiles.isEmpty
            ? nil
            : assetStore.llmMmprojPath(asset)?.path
        let clampedTemperature = min(max(temperature, 0.35), 0.7)

        let request = LlmChatRequest(
            messages: messages,
            templateOverride: nil,
            addAssistant: true,
            imagePaths: imageFiles.map { $0.path },
            mmprojPath: mmprojPath,
            mediaMarker: nil,
            maxTokens: maxTokens.map(Int32.init),
            temperature: clampedTemperature,
            topP: 0.9,
            topK: 50,
            repeatPenalty: 1.18,
            frequencyPenalty: 0,
            presencePenalty: 0,
            seed: nil,
            stopSequences: nil,
            grammar: nil
        )

        let sink = CallbackSink { [currentJobId] event in
            switch event {
            case let .text(jobId, text, _):
                currentJobId.withLock { $0 = jobId }
                control?.setJob(jobId)
                onToken(text)
            case .done:
                currentJobId.withLock { $0 = nil }
            }
        }

        unloadTranscriptionModelIfLoaded()
        defer { currentJobId.withLock { $0 = nil } }
        let summary = try await Task.detached {
            try control?.checkCancellation()
            return try context.generateChatStream(request: request, callback: sink)
        }.value

        return GenerationSummary(
            jobId: summary.jobId,
            generatedTokens: Int(summary.generatedTokens ?? 0),
            totalTimeMs: summary.totalTimeMs
        )
    }

    func withChatModelReleasedForRetrieval<T: Sendable>(
        _ operation: @Sendable (_ embed: @Sendable (String) throws -> [Float]) async throws -> T
    ) async throws -> T {
        let maintenance = await modelMaintenance
        let scope = await maintenance?.suspendMaintenance()
        defer { scope?.close() }
        await maintenance?.awaitMaintenance()
        return try await withEmbeddingContext { context in
            try await operation { try context.embed(text: $0) }
        }
    }

    func withEmbeddingContext<T: Sendable>(
        checkCancellation: @Sendable () throws -> Void = {},
        _ operation: @Sendable (LlmContext) async throws -> T
    ) async throws -> T {
        try await modelLoadGate.withLock {
            try checkCancellation()
            let capability = currentChatDeviceCapability()
            if !capability.isChatSupported {
                throw UnsupportedDeviceMemoryError(capability: capability)
            }
            guard isEmbeddingModelReady() else {
                throw EmbeddingAssetInvalidError()
            }

            unloadTranscriptionModelIfLoaded()
            unloadModel()
            if !backendInitialized {
                try llmInitBackend()
                backendInitialized = true
            }

            guard let embeddingModelPath = assetStore.llmModelPath(embeddingAsset) else {
                throw EmbeddingAssetInvalidError()
            }
            var embeddingModel: LlmModel? = try LlmModel.load(
                params: LlmModelLoadParams(
                    modelPath: embeddingModelPath.path,
                    nGpuLayers: 0,
                    useMmap: true,
                    useMlock: false
                )
            )
            var embeddingContext: LlmContext?
            defer {
                embeddingContext = nil
                embeddingModel = nil
            }
            guard let model = embeddingModel else {
                throw EmbeddingAssetInvalidError()
            }
            let threadCount = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
            embeddingContext = try model.newEmbeddingContext(
                nThreads: Int32(threadCount)
            )
            guard let context = embeddingContext else {
                throw EmbeddingAssetInvalidError()
            }
            return try await operation(context)
        }
    }

    nonisolated func stopGeneration(invalidatePreparation: Bool = false) {
        if let control = generationControl.withLock({ $0 }) {
            control.cancel(invalidatePreparation: invalidatePreparation)
            return
        }
        if let jobId = currentJobId.withLock({ $0 }) {
            llmCancel(jobId: jobId)
        } else {
            llmCancel(jobId: 0)
        }
    }

    func prewarmImageInference(_ selection: LlmModelSelection) async {
        guard isChatModelReady(selection) else { return }

        do {
            try await self.withModelLock {
                let asset = self.chatAsset(selection)
                guard self.assetStore.isDownloaded(asset) else { return }
                guard let mmprojPath = self.assetStore.llmMmprojPath(asset),
                    FileManager.default.fileExists(atPath: mmprojPath.path)
                else {
                    return
                }

                try await self.ensureModelReadyLocked(
                    selection, onProgress: { _ in }, allowRecovery: true)
                guard let context = self.loadedContext else {
                    return
                }

                self.unloadTranscriptionModelIfLoaded()
                try context.prewarmMultimodal(
                    mmprojPath: mmprojPath.path,
                    mediaMarker: nil
                )
            }
        } catch {
            return
        }
    }

    func resetContext() async {
        try? await withModelLock {
            guard let model = loadedModel else { return }
            let contextParams = LlmContextParams(
                contextSize: currentContextLength.map(Int32.init), nThreads: nil, nBatch: nil)
            loadedContext = nil
            loadedContext = try? model.newContext(params: contextParams)
        }
    }

    func loadedContextLength(_ selection: LlmModelSelection) -> Int? {
        let modelKey = LoadedModelKey(
            id: selection.id, requestedContextLength: selection.contextLength)
        guard currentModelKey == modelKey, loadedModel != nil, loadedContext != nil else {
            return nil
        }
        return currentContextLength
    }

    private func unloadModel() {
        chatWarmupOwner = nil
        loadedContext = nil
        loadedModel = nil
        currentModelKey = nil
        currentContextLength = nil
    }

    private func unloadTranscriptionModelIfLoaded() {
        transcriber.unloadModel()
    }

    private nonisolated func chatAsset(_ selection: LlmModelSelection) -> Asset {
        llmAsset(modelId: selection.id)
    }

    private func loadModel(_ selection: LlmModelSelection, modelPath: URL) throws {
        let params = LlmModelLoadParams(
            modelPath: modelPath.path, nGpuLayers: 0, useMmap: true, useMlock: false)
        let model = try LlmModel.load(params: params)
        loadedModel = model

        let desiredContext = selection.contextLength ?? 12000
        let candidates = [desiredContext, 12000, 8192, 4096, 2048, 1024]
            .filter { $0 > 0 }
            .reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
        let threadCount = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)

        for contextSize in candidates {
            do {
                let contextParams = LlmContextParams(
                    contextSize: Int32(contextSize), nThreads: Int32(threadCount),
                    nBatch: Int32(512))
                loadedContext = try model.newContext(params: contextParams)
                currentModelKey = LoadedModelKey(
                    id: selection.id, requestedContextLength: selection.contextLength)
                currentContextLength = contextSize
                return
            } catch {
                continue
            }
        }
        throw NSError(
            domain: "LlmProvider", code: -5,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
    }
}

private final class CallbackSink: LlmGenerationEventCallback {
    private let handler: @Sendable (LlmGenerationEvent) -> Void

    init(handler: @escaping @Sendable (LlmGenerationEvent) -> Void) {
        self.handler = handler
    }

    func onEvent(event: LlmGenerationEvent) {
        handler(event)
    }
}

final class ChatGenerationControl: Sendable {
    private struct State {
        var cancelled = false
        var cancelPreparation: (@Sendable () -> Void)?
        var preparing = true
        var jobId: Int64?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func checkCancellation() throws {
        if state.withLock({ $0.cancelled }) { throw CancellationError() }
    }

    func setPreparationCancellation(_ cancel: @escaping @Sendable () -> Void) {
        let shouldCancel = state.withLock {
            $0.cancelPreparation = cancel
            return $0.cancelled
        }
        if shouldCancel { cancel() }
    }

    func beginAnswer() throws {
        try state.withLock {
            if $0.cancelled { throw CancellationError() }
            $0.preparing = false
        }
    }

    func setJob(_ jobId: Int64) {
        let shouldCancel = state.withLock {
            $0.jobId = jobId
            return $0.cancelled
        }
        if shouldCancel { llmCancel(jobId: jobId) }
    }

    func cancel(invalidatePreparation: Bool) {
        let (cancelPreparation, jobId) = state.withLock {
            $0.cancelled = true
            return ($0.preparing || invalidatePreparation ? $0.cancelPreparation : nil, $0.jobId)
        }
        cancelPreparation?()
        if let jobId { llmCancel(jobId: jobId) }
    }
}
