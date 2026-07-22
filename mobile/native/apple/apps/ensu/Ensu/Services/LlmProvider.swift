import Foundation

struct LlmModelSelection: Equatable {
    let id: String
    let modelTarget: ModelTarget
    let contextLength: Int?
    let maxTokens: Int?
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

private actor AsyncSerialGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(_ operation: () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
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

final class LlmProvider {
    private struct LoadedModelKey: Equatable {
        let id: String
        let requestedContextLength: Int?
    }

    private let downloader: ModelDownloader
    private let transcriber: Transcriber
    private var loadedModel: LlmModel?
    private var loadedContext: LlmContext?
    private var currentModelKey: LoadedModelKey?
    private var currentContextLength: Int?
    private var backendInitialized = false
    private var currentJobId: Int64?
    private let modelLoadGate = AsyncSerialGate()

    init(downloader: ModelDownloader, transcriber: Transcriber) {
        self.downloader = downloader
        self.transcriber = transcriber
    }

    func ensureModelReady(
        _ selection: LlmModelSelection,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async throws {
        try await modelLoadGate.withLock {
            try await ensureModelReadyLocked(selection, onProgress: onProgress, allowRecovery: true)
        }
    }

    private func ensureModelReadyLocked(
        _ selection: LlmModelSelection,
        onProgress: @escaping (DownloadProgress) -> Void,
        allowRecovery: Bool
    ) async throws {
        let capability = currentChatDeviceCapability()
        if !capability.isChatSupported {
            throw UnsupportedDeviceMemoryError(capability: capability)
        }
        let modelKey = LoadedModelKey(id: selection.id, requestedContextLength: selection.contextLength)
        if currentModelKey == modelKey, loadedModel != nil, loadedContext != nil {
            return
        }

        unloadModel()

        if !backendInitialized {
            try llmInitBackend()
            backendInitialized = true
        }

        let wasAlreadyDownloaded = downloader.isDownloaded(selection.modelTarget)
        try await downloader.download(targets: [selection.modelTarget], onProgress: onProgress)

        onProgress(DownloadProgress(percent: 100, status: "Loading model...", phase: .loading))
        do {
            try loadModel(
                selection,
                modelPath: downloader.llmModelPath(selection.modelTarget)!
            )
        } catch {
            if allowRecovery, wasAlreadyDownloaded, downloader.removeDownloaded(selection.modelTarget) {
                onProgress(DownloadProgress(percent: 0, status: "Starting download..."))
                try await ensureModelReadyLocked(selection, onProgress: onProgress, allowRecovery: false)
                return
            }
            throw error
        }
        onProgress(DownloadProgress(percent: 100, status: "Ready", phase: .ready))
    }

    func generateChat(
        _ selection: LlmModelSelection,
        messages: [LlmMessage],
        imageFiles: [URL],
        temperature: Float,
        maxTokens: Int?,
        onToken: @escaping (String) -> Void
    ) async throws -> GenerationSummary {
        let capability = currentChatDeviceCapability()
        if !capability.isChatSupported {
            throw UnsupportedDeviceMemoryError(capability: capability)
        }
        guard let context = loadedContext else {
            throw NSError(domain: "LlmProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        currentJobId = nil

        let nativeMessages = messages.map {
            LlmChatMessage(role: $0.role.roleString, content: $0.text)
        }

        let mmprojPath = imageFiles.isEmpty
            ? nil
            : downloader.llmMmprojPath(selection.modelTarget)?.path
        let clampedTemperature = min(max(temperature, 0.35), 0.7)

        let request = LlmChatRequest(
            messages: nativeMessages,
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

        let sink = CallbackSink { event in
            switch event {
            case let .text(jobId, text, _):
                self.currentJobId = jobId
                onToken(text)
            case .done:
                self.currentJobId = nil
            }
        }

        let summary: LlmGenerationSummary = try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    self.unloadTranscriptionModelIfLoaded()
                    let summary = try context.generateChatStream(request: request, callback: sink)
                    continuation.resume(returning: summary)
                } catch {
                    self.currentJobId = nil
                    continuation.resume(throwing: error)
                }
            }
        }

        return GenerationSummary(
            jobId: summary.jobId,
            generatedTokens: Int(summary.generatedTokens ?? 0),
            totalTimeMs: summary.totalTimeMs
        )
    }

    func stopGeneration() {
        if let jobId = currentJobId {
            llmCancel(jobId: jobId)
        } else {
            llmCancel(jobId: 0)
        }
    }

    func prewarmImageInference(_ selection: LlmModelSelection) async {
        guard downloader.isDownloaded(selection.modelTarget) else { return }

        do {
            try await Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                try await self.modelLoadGate.withLock {
                    guard self.downloader.isDownloaded(selection.modelTarget) else { return }
                    guard let mmprojPath = self.downloader.llmMmprojPath(selection.modelTarget),
                          FileManager.default.fileExists(atPath: mmprojPath.path) else {
                        return
                    }

                    try await self.ensureModelReadyLocked(selection, onProgress: { _ in }, allowRecovery: true)
                    guard let context = self.loadedContext else {
                        return
                    }

                    self.unloadTranscriptionModelIfLoaded()
                    try context.prewarmMultimodal(
                        mmprojPath: mmprojPath.path,
                        mediaMarker: nil
                        )
                }
            }.value
        } catch {
            return
        }
    }

    func resetContext() {
        guard let model = loadedModel else { return }
        let contextParams = LlmContextParams(contextSize: currentContextLength.map(Int32.init), nThreads: nil, nBatch: nil)
        loadedContext = nil
        loadedContext = try? model.newContext(params: contextParams)
    }

    func loadedContextLength(_ selection: LlmModelSelection) -> Int? {
        let modelKey = LoadedModelKey(id: selection.id, requestedContextLength: selection.contextLength)
        guard currentModelKey == modelKey, loadedModel != nil, loadedContext != nil else {
            return nil
        }
        return currentContextLength
    }

    private func unloadModel() {
        loadedContext = nil
        loadedModel = nil
        currentModelKey = nil
        currentContextLength = nil
    }

    private func unloadTranscriptionModelIfLoaded() {
        transcriber.unloadModel()
    }

    private func loadModel(_ selection: LlmModelSelection, modelPath: URL) throws {
        let params = LlmModelLoadParams(modelPath: modelPath.path, nGpuLayers: 0, useMmap: true, useMlock: false)
        let model = try LlmModel.load(params: params)
        loadedModel = model

        let desiredContext = selection.contextLength ?? 12000
        let candidates = [desiredContext, 12000, 8192, 4096, 2048, 1024]
            .filter { $0 > 0 }
            .reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
        let threadCount = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)

        for contextSize in candidates {
            do {
                let contextParams = LlmContextParams(contextSize: Int32(contextSize), nThreads: Int32(threadCount), nBatch: Int32(512))
                loadedContext = try model.newContext(params: contextParams)
                currentModelKey = LoadedModelKey(id: selection.id, requestedContextLength: selection.contextLength)
                currentContextLength = contextSize
                return
            } catch {
                continue
            }
        }
        throw NSError(domain: "LlmProvider", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
    }
}

private final class CallbackSink: LlmGenerationEventCallback, @unchecked Sendable {
    private let handler: (LlmGenerationEvent) -> Void

    init(handler: @escaping (LlmGenerationEvent) -> Void) {
        self.handler = handler
    }

    func onEvent(event: LlmGenerationEvent) {
        handler(event)
    }
}
