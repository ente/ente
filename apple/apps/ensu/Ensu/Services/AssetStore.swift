import BackgroundTasks
import Foundation

private let logger = EnsuLogging.shared.logger("AssetStore")

final class AssetStore: Sendable {
    private let core: AssetStoreCore

    @MainActor
    init() async {
        let baseDir =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var assetsDir = baseDir.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? assetsDir.setResourceValues(values)
        core = AssetStoreCore(assetsDir: assetsDir.path)
        let settings = UserDefaults.standard
        let pendingSelection = settings.object(forKey: "ensu.model.id") == nil
        let legacyModelUrl =
            pendingSelection && settings.bool(forKey: "ensu.model.use_custom")
            ? settings.string(forKey: "ensu.model.url")
            : nil
        let legacy = LegacyAssets(
            llmDir: baseDir.appendingPathComponent("llm", isDirectory: true).path,
            transcriptionDir: baseDir.appendingPathComponent("transcription", isDirectory: true)
                .path,
            modelUrl: legacyModelUrl,
            mmprojUrl: settings.string(forKey: "ensu.model.mmproj")
        )
        let presetId = await Task.detached(priority: .userInitiated) { [assetsDir] in
            migrateEnsuAssets(assetsDir: assetsDir.path, legacy: legacy)
        }.value
        if pendingSelection {
            settings.set(presetId ?? "", forKey: "ensu.model.id")
        }
        settings.removeObject(forKey: "ensu.model.use_custom")
        settings.removeObject(forKey: "ensu.model.url")
        settings.removeObject(forKey: "ensu.model.mmproj")
    }

    @MainActor
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

    func voiceActivityModelPath() -> URL {
        URL(fileURLWithPath: core.voiceActivityModelPath())
    }

    func isDownloaded(_ asset: Asset) -> Bool {
        core.isDownloaded(asset: asset)
    }

    func removeDownloaded(_ asset: Asset) -> Bool {
        core.removeDownloaded(asset: asset)
    }

    func cleanupObsoleteChatModels(_ modelId: String) {
        do {
            try core.cleanupObsoleteChatModels(modelId: modelId)
        } catch {
            logger.warning("Unable to remove obsolete chat models", details: "\(error)")
        }
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
        await core.estimatedDownloadSize(asset: asset)
    }

    @MainActor
    func download(
        assets: [Asset],
        onProgress: @escaping @Sendable (AssetDownloadProgress) -> Void
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

        let callback = AssetDownloadCallbackSink { progress in
            if let line = progress.logLine {
                logger.info(line)
            }
            if #available(iOS 26.0, *), let leaseId {
                Task { @MainActor in
                    AssetDownloadBackgroundTask.update(
                        id: leaseId,
                        downloadedBytes: progress.downloadedBytes,
                        totalBytes: progress.totalBytes
                    )
                }
            }
            onProgress(progress)
        }

        try await withTaskCancellationHandler {
            try await core.download(assets: assets, callback: callback, cancellation: token)
        } onCancel: {
            token.cancel()
        }
        succeeded = true
    }
}

private final class AssetDownloadCallbackSink: AssetDownloadCallback {
    private let onProgressHandler: @Sendable (AssetDownloadProgress) -> Void

    init(onProgress: @escaping @Sendable (AssetDownloadProgress) -> Void) {
        self.onProgressHandler = onProgress
    }

    func onProgress(progress: AssetDownloadProgress) {
        onProgressHandler(progress)
    }
}

@available(iOS 26.0, *)
@MainActor
private enum AssetDownloadBackgroundTask {
    private static let identifier = "io.ente.ensu.asset-download"
    private static var task: BGContinuedProcessingTask?
    private static var cancellations: [UUID: @Sendable () -> Void] = [:]
    private static var allSucceeded = true

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { bgTask in
            guard let bgTask = bgTask as? BGContinuedProcessingTask else {
                bgTask.setTaskCompleted(success: false)
                return
            }
            adopt(bgTask)
        }
    }

    static func begin(onExpiration: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        let first = cancellations.isEmpty
        if first { allSucceeded = true }
        cancellations[id] = onExpiration
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
        guard cancellations[id] != nil, let task else { return }
        guard cancellations.count == 1, let totalBytes, totalBytes > 0 else {
            task.progress.totalUnitCount = -1
            task.progress.completedUnitCount = 0
            return
        }
        task.progress.totalUnitCount = totalBytes
        task.progress.completedUnitCount = min(downloadedBytes, totalBytes)
    }

    static func end(id: UUID, success: Bool) {
        guard cancellations.removeValue(forKey: id) != nil else { return }
        allSucceeded = allSucceeded && success
        guard cancellations.isEmpty else { return }
        let completed = task
        task = nil
        completed?.setTaskCompleted(success: allSucceeded)
    }

    private static func adopt(_ bgTask: BGContinuedProcessingTask) {
        guard !cancellations.isEmpty else {
            bgTask.setTaskCompleted(success: true)
            return
        }
        task = bgTask
        let taskId = ObjectIdentifier(bgTask)
        bgTask.expirationHandler = { @Sendable in
            Task { @MainActor in
                guard let expired = task, ObjectIdentifier(expired) == taskId else { return }
                task = nil
                let callbacks = Array(cancellations.values)
                cancellations.removeAll()
                guard !callbacks.isEmpty else { return }
                callbacks.forEach { $0() }
                expired.setTaskCompleted(success: false)
            }
        }
    }
}
