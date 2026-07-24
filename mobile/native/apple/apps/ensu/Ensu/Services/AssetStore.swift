import BackgroundTasks
import Foundation

private let logger = EnsuLogging.shared.logger("AssetStore")

final class AssetStore: @unchecked Sendable {
    private let core: AssetStoreCore
    private let activeLock = NSLock()
    private var downloadActive = false

    @MainActor
    init() {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var assetsDir = baseDir.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? assetsDir.setResourceValues(values)
        core = AssetStoreCore(assetsDir: assetsDir.path)
        let settings = UserDefaults.standard
        let pendingSelection = settings.object(forKey: "ensu.model.id") == nil
        let legacyModelUrl = pendingSelection && settings.bool(forKey: "ensu.model.use_custom")
            ? settings.string(forKey: "ensu.model.url")
            : nil
        let presetId = migrateEnsuAssets(
            assetsDir: assetsDir.path,
            legacy: LegacyAssets(
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
            AssetDownloadBackgroundTask.register()
        }
    }

    func assetDir(_ asset: Asset) -> URL {
        URL(fileURLWithPath: core.assetDir(asset: asset))
    }

    func llmModelPath(_ asset: Asset) -> URL? {
        core.llmModelPath(asset: asset).map { URL(fileURLWithPath: $0) }
    }

    func llmMmprojPath(_ asset: Asset) -> URL? {
        core.llmMmprojPath(asset: asset).map { URL(fileURLWithPath: $0) }
    }

    func voiceActivityModelPath(_ asset: Asset) -> URL {
        URL(fileURLWithPath: core.voiceActivityModelPath(asset: asset))
    }

    func isDownloaded(_ asset: Asset) -> Bool {
        core.isDownloaded(asset: asset)
    }

    func removeDownloaded(_ asset: Asset) -> Bool {
        core.removeDownloaded(asset: asset)
    }

    func reconcileKnowledge(_ stableId: String) throws -> KnowledgeReconciliation {
        try reconcileKnowledgePack(store: core, stableId: stableId)
    }

    func cleanupKnowledgeRevisions(_ stableId: String, activeIdentity: String) throws {
        try cleanupObsoleteKnowledgePackRevisions(
            store: core,
            stableId: stableId,
            activeIdentity: activeIdentity
        )
    }

    func estimateDownloadSize(_ asset: Asset) async -> Int64? {
        await Task.detached(priority: .utility) { [core] in
            core.estimatedDownloadSize(asset: asset)
        }.value
    }

    func download(
        assets: [Asset],
        onProgress: @escaping (AssetDownloadProgress) -> Void
    ) async throws {
        let token = CancellationToken()
        let started = activeLock.withLock { () -> Bool in
            if downloadActive { return false }
            downloadActive = true
            return true
        }
        guard started else { throw DownloadAlreadyActiveError() }
        defer { activeLock.withLock { downloadActive = false } }

        if assets.allSatisfy({ self.core.isDownloaded(asset: $0) }) {
            return
        }

        if #available(iOS 26.0, *) {
            AssetDownloadBackgroundTask.begin {
                token.cancel()
            }
        }
        var succeeded = false
        defer {
            if #available(iOS 26.0, *) {
                AssetDownloadBackgroundTask.end(success: succeeded)
            }
        }

        let core = core
        let downloadTask = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let callback = AssetDownloadCallbackSink { progress in
                if let line = progress.logLine {
                    logger.info(line)
                }
                if #available(iOS 26.0, *) {
                    AssetDownloadBackgroundTask.update(
                        downloadedBytes: progress.downloadedBytes,
                        totalBytes: progress.totalBytes
                    )
                }
                onProgress(progress)
            }
            try core.download(assets: assets, callback: callback, cancellation: token)
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

private final class AssetDownloadCallbackSink: AssetDownloadCallback, @unchecked Sendable {
    private let onProgressHandler: (AssetDownloadProgress) -> Void

    init(onProgress: @escaping (AssetDownloadProgress) -> Void) {
        self.onProgressHandler = onProgress
    }

    func onProgress(progress: AssetDownloadProgress) {
        onProgressHandler(progress)
    }
}

@available(iOS 26.0, *)
private enum AssetDownloadBackgroundTask {
    private static let identifier = "io.ente.ensu.asset-download"
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
            title: "Downloading assets",
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
