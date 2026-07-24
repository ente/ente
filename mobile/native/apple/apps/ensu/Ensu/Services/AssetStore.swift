import BackgroundTasks
import Foundation

private let logger = EnsuLogging.shared.logger("AssetStore")

final class AssetStore: @unchecked Sendable {
    private let core: AssetStoreCore

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
        if assets.allSatisfy({ self.core.isDownloaded(asset: $0) }) {
            return
        }

        let leaseId: UUID?
        if #available(iOS 26.0, *) {
            leaseId = AssetDownloadBackgroundTask.begin {
                token.cancel()
            }
        } else {
            leaseId = nil
        }
        var succeeded = false
        defer {
            if #available(iOS 26.0, *), let leaseId {
                AssetDownloadBackgroundTask.end(id: leaseId, success: succeeded)
            }
        }

        let core = core
        let downloadTask = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let callback = AssetDownloadCallbackSink { progress in
                if let line = progress.logLine {
                    logger.info(line)
                }
                if #available(iOS 26.0, *), let leaseId {
                    AssetDownloadBackgroundTask.update(
                        id: leaseId,
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
    private static var cancellations: [UUID: () -> Void] = [:]
    private static var allSucceeded = true

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { bgTask in
            guard let bgTask = bgTask as? BGContinuedProcessingTask else {
                bgTask.setTaskCompleted(success: false)
                return
            }
            adopt(bgTask)
        }
    }

    static func begin(onExpiration: @escaping () -> Void) -> UUID {
        let id = UUID()
        let first = lock.withLock {
            let first = cancellations.isEmpty
            if first { allSucceeded = true }
            cancellations[id] = onExpiration
            return first
        }
        guard first else { return id }

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
        return id
    }

    static func update(id: UUID, downloadedBytes: Int64, totalBytes: Int64?) {
        let state: (task: BGContinuedProcessingTask?, activeCount: Int)? = lock.withLock {
            guard cancellations[id] != nil else { return nil }
            return (task, cancellations.count)
        }
        guard let state, let task = state.task else { return }
        guard state.activeCount == 1, let totalBytes, totalBytes > 0 else {
            task.progress.totalUnitCount = -1
            task.progress.completedUnitCount = 0
            return
        }
        task.progress.totalUnitCount = totalBytes
        task.progress.completedUnitCount = min(downloadedBytes, totalBytes)
    }

    static func end(id: UUID, success: Bool) {
        let completion: (BGContinuedProcessingTask?, Bool)? = lock.withLock {
            guard cancellations.removeValue(forKey: id) != nil else { return nil }
            allSucceeded = allSucceeded && success
            guard cancellations.isEmpty else { return nil }
            let completed = (task, allSucceeded)
            task = nil
            return completed
        }
        if let completion {
            completion.0?.setTaskCompleted(success: completion.1)
        }
    }

    private static func adopt(_ bgTask: BGContinuedProcessingTask) {
        let adopted = lock.withLock {
            guard !cancellations.isEmpty else { return false }
            task = bgTask
            return true
        }
        guard adopted else {
            bgTask.setTaskCompleted(success: true)
            return
        }

        bgTask.expirationHandler = {
            let callbacks = lock.withLock {
                guard task === bgTask else { return [() -> Void]() }
                task = nil
                let callbacks = Array(cancellations.values)
                cancellations.removeAll()
                return callbacks
            }
            guard !callbacks.isEmpty else { return }
            callbacks.forEach { $0() }
            bgTask.setTaskCompleted(success: false)
        }
    }

}
