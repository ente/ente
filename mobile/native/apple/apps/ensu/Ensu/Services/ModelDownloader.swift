import BackgroundTasks
import Foundation

private let logger = EnsuLogging.shared.logger("ModelDownloader")

final class ModelDownloader {
    private let core: ModelDownloadCore
    private let activeLock = NSLock()
    private var activeToken: CancellationToken?
    let transcriptionTarget: ModelTarget
    let voiceActivityTarget: ModelTarget

    @MainActor
    init() {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var modelsDir = baseDir.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? modelsDir.setResourceValues(values)
        core = ModelDownloadCore(modelsDir: modelsDir.path)
        transcriptionTarget = transcriptionModelTarget()
        voiceActivityTarget = voiceActivityModelTarget()
        let settings = UserDefaults.standard
        let pendingSelection = settings.object(forKey: "ensu.model.id") == nil
        let legacyModelUrl = pendingSelection && settings.bool(forKey: "ensu.model.use_custom")
            ? settings.string(forKey: "ensu.model.url")
            : nil
        let presetId = migrateMobileModels(
            modelsDir: modelsDir.path,
            legacy: LegacyModels(
                llmDir: baseDir.appendingPathComponent("llm", isDirectory: true).path,
                transcriptionDir: baseDir.appendingPathComponent("transcription", isDirectory: true).path,
                modelUrl: legacyModelUrl,
                mmprojUrl: settings.string(forKey: "ensu.model.mmproj")
            )
        )
        if pendingSelection {
            settings.set(presetId ?? "", forKey: "ensu.model.id")
        }
        settings.removeObject(forKey: "ensu.model.use_custom")
        settings.removeObject(forKey: "ensu.model.url")
        settings.removeObject(forKey: "ensu.model.mmproj")
    }

    static func registerBackgroundTask() {
        if #available(iOS 26.0, *) {
            ModelDownloadBackgroundTask.register()
        }
    }

    func modelDir(_ target: ModelTarget) -> URL {
        URL(fileURLWithPath: core.modelDir(target: target))
    }

    func llmModelPath(_ target: ModelTarget) -> URL? {
        core.llmModelPath(target: target).map { URL(fileURLWithPath: $0) }
    }

    func llmMmprojPath(_ target: ModelTarget) -> URL? {
        core.llmMmprojPath(target: target).map { URL(fileURLWithPath: $0) }
    }

    func voiceActivityModelPath() -> URL {
        URL(fileURLWithPath: core.voiceActivityModelPath())
    }

    func isDownloaded(_ target: ModelTarget) -> Bool {
        core.isDownloaded(target: target)
    }

    func removeDownloaded(_ target: ModelTarget) -> Bool {
        core.removeDownloaded(target: target)
    }

    func cancel() {
        activeLock.withLock { activeToken }?.cancel()
    }

    func estimateDownloadSize(_ target: ModelTarget) async -> Int64? {
        await Task.detached(priority: .utility) { [core] in
            core.estimatedDownloadSize(target: target)
        }.value
    }

    func download(
        targets: [ModelTarget],
        onProgress: @escaping (DownloadProgress) -> Void
    ) async throws {
        let token = CancellationToken()
        let started = activeLock.withLock { () -> Bool in
            if activeToken != nil { return false }
            activeToken = token
            return true
        }
        guard started else { throw DownloadAlreadyActiveError() }
        defer { activeLock.withLock { activeToken = nil } }

        if targets.allSatisfy({ self.core.isDownloaded(target: $0) }) {
            return
        }

        onProgress(DownloadProgress(percent: 0, status: "Starting download..."))

        if #available(iOS 26.0, *) {
            ModelDownloadBackgroundTask.begin {
                token.cancel()
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
            try Task.checkCancellation()
            let callback = ModelDownloadCallbackSink { progress in
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
            }
            try core.download(targets: targets, callback: callback, cancellation: token)
        }

        try await withTaskCancellationHandler {
            try await downloadTask.value
        } onCancel: {
            downloadTask.cancel()
            token.cancel()
        }
        succeeded = true
    }
}

private struct DownloadAlreadyActiveError: Error {}

private final class ModelDownloadCallbackSink: ModelDownloadCallback, @unchecked Sendable {
    private let onProgressHandler: (ModelDownloadProgress) -> Void

    init(onProgress: @escaping (ModelDownloadProgress) -> Void) {
        self.onProgressHandler = onProgress
    }

    func onProgress(progress: ModelDownloadProgress) {
        onProgressHandler(progress)
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
