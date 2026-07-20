import BackgroundTasks
import Foundation

private let logger = EnsuLogging.shared.logger("ModelDownloader")

final class ModelDownloader {
    private let core: ModelDownloadCore
    private let activeLock = NSLock()
    private var downloadActive = false
    let transcriptionModelTarget: ModelDownloadTarget
    let voiceActivityModelTarget: ModelDownloadTarget

    @MainActor
    init() {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let modelsDir = baseDir.appendingPathComponent("models", isDirectory: true)
        core = ModelDownloadCore(modelsDir: modelsDir.path)
        let defaults = ConfigDefaults.shared
        transcriptionModelTarget = .tarGz(
            id: defaults.transcriptionModel.id,
            url: defaults.transcriptionModel.url
        )
        voiceActivityModelTarget = .onnx(
            id: defaults.voiceActivityModel.id,
            url: defaults.voiceActivityModel.url
        )
        migrateEnsuLegacyModels(
            modelsDir: modelsDir.path,
            llmLegacyDir: baseDir.appendingPathComponent("llm", isDirectory: true).path,
            transcriptionLegacyDir: baseDir.appendingPathComponent("transcription", isDirectory: true).path,
            llmTargets: Self.migrationTargets(),
            transcriptionModel: transcriptionModelTarget,
            voiceActivityModel: voiceActivityModelTarget
        )
        var excludedDir = modelsDir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excludedDir.setResourceValues(values)
    }

    static func registerBackgroundTask() {
        if #available(iOS 26.0, *) {
            ModelDownloadBackgroundTask.register()
        }
    }

    @MainActor
    private static func migrationTargets() -> [ModelDownloadTarget] {
        let config = ConfigDefaults.shared
        var targets = ([config.mobileDefaultModel] + config.mobileModelPresets).map {
            ModelDownloadTarget.gguf(id: $0.id, url: $0.url, mmprojUrl: $0.mmprojUrl)
        }
        let settings = ModelSettingsStore.shared
        if settings.useCustomModel && !settings.modelUrl.isEmpty {
            targets.append(.gguf(
                id: "custom:\(settings.modelUrl)",
                url: settings.modelUrl,
                mmprojUrl: settings.mmprojUrl.isEmpty ? nil : settings.mmprojUrl
            ))
        }
        return targets
    }

    func modelPath(target: ModelDownloadTarget) -> URL {
        URL(fileURLWithPath: core.modelPath(target: target))
    }

    func mmprojPath(target: ModelDownloadTarget) -> String? {
        core.mmprojPath(target: target)
    }

    func isDownloaded(target: ModelDownloadTarget) -> Bool {
        core.isDownloaded(target: target)
    }

    func removeDownloaded(target: ModelDownloadTarget) -> Bool {
        core.removeDownloaded(target: target)
    }

    func cancel() {
        core.cancel()
    }

    func estimateDownloadSize(target: ModelDownloadTarget) async -> Int64? {
        await Task.detached(priority: .utility) { [core] in
            core.estimatedDownloadSize(target: target)
        }.value
    }

    @discardableResult
    func download(
        targets: [ModelDownloadTarget],
        onProgress: @escaping (DownloadProgress) -> Void
    ) async throws -> Bool {
        let started = activeLock.withLock { () -> Bool in
            if downloadActive { return false }
            downloadActive = true
            return true
        }
        guard started else { throw DownloadAlreadyActiveError() }
        defer { activeLock.withLock { downloadActive = false } }

        if targets.allSatisfy({ self.core.isDownloaded(target: $0) }) {
            return false
        }

        onProgress(DownloadProgress(percent: 0, status: "Starting download..."))

        if #available(iOS 26.0, *) {
            ModelDownloadBackgroundTask.begin { [core] in
                core.cancel()
            }
        }
        var succeeded = false
        defer {
            if #available(iOS 26.0, *) {
                ModelDownloadBackgroundTask.end(success: succeeded)
            }
        }

        let core = core
        let downloadTask = Task.detached(priority: .utility) {
            let callback = ModelDownloadCallbackSink(
                onProgress: { progress in
                    if let line = progress.logLine {
                        logger.info(line)
                    }
                    if #available(iOS 26.0, *) {
                        ModelDownloadBackgroundTask.update(
                            downloadedBytes: progress.downloadedBytes,
                            totalBytes: progress.totalBytes
                        )
                    }
                    onProgress(DownloadProgress(percent: Int(progress.percent), status: progress.status))
                },
                isCancelled: { Task.isCancelled }
            )
            _ = try core.download(targets: targets, callback: callback)
        }

        try await withTaskCancellationHandler {
            try await downloadTask.value
        } onCancel: {
            core.cancel()
            downloadTask.cancel()
        }
        succeeded = true
        return true
    }
}

private struct DownloadAlreadyActiveError: Error {}

private final class ModelDownloadCallbackSink: ModelDownloadCallback, @unchecked Sendable {
    private let onProgressHandler: (ModelDownloadProgress) -> Void
    private let isCancelledHandler: () -> Bool

    init(
        onProgress: @escaping (ModelDownloadProgress) -> Void,
        isCancelled: @escaping () -> Bool
    ) {
        self.onProgressHandler = onProgress
        self.isCancelledHandler = isCancelled
    }

    func onProgress(progress: ModelDownloadProgress) {
        onProgressHandler(progress)
    }

    func isCancelled() -> Bool {
        isCancelledHandler()
    }
}

@available(iOS 26.0, *)
private enum ModelDownloadBackgroundTask {
    private static let identifier = "io.ente.ensu.model-download"
    private static let lock = NSLock()
    private static var task: BGContinuedProcessingTask?
    private static var onExpiration: (() -> Void)?
    private static var downloadActive = false

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { bgTask in
            guard let bgTask = bgTask as? BGContinuedProcessingTask else {
                bgTask.setTaskCompleted(success: false)
                return
            }
            adopt(bgTask)
        }
    }

    static func begin(onExpiration: @escaping () -> Void) {
        lock.lock()
        downloadActive = true
        Self.onExpiration = onExpiration
        lock.unlock()

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Downloading model",
            subtitle: ""
        )
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.warning("Background download task not scheduled", details: "\(error)")
        }
    }

    static func update(downloadedBytes: Int64, totalBytes: Int64?) {
        lock.lock()
        let task = task
        lock.unlock()
        guard let task, let totalBytes, totalBytes > 0 else { return }
        task.progress.totalUnitCount = totalBytes
        task.progress.completedUnitCount = min(downloadedBytes, totalBytes)
    }

    static func end(success: Bool) {
        lock.lock()
        downloadActive = false
        onExpiration = nil
        let task = task
        Self.task = nil
        lock.unlock()
        task?.setTaskCompleted(success: success)
    }

    private static func adopt(_ bgTask: BGContinuedProcessingTask) {
        lock.lock()
        guard downloadActive else {
            lock.unlock()
            bgTask.setTaskCompleted(success: true)
            return
        }
        task = bgTask
        lock.unlock()

        bgTask.expirationHandler = {
            lock.lock()
            let expired = task === bgTask
            let handler = onExpiration
            if expired {
                task = nil
            }
            lock.unlock()
            if expired {
                handler?()
                bgTask.setTaskCompleted(success: false)
            }
        }
    }
}
