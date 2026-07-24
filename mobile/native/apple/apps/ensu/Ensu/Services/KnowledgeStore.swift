import Foundation
import SwiftUI

@MainActor
final class KnowledgeStore: ObservableObject {
    @Published private(set) var packs: [KnowledgePackState]
    @Published var downloadsAllowed = false

    private let provider: KnowledgeProvider
    private let preferences: KnowledgePreferences
    private var bootstrapTask: Task<Void, Never>?
    private var mutationTasks: [String: Task<Void, Never>] = [:]

    init(
        datasets: [KnowledgeDatasetConfig],
        provider: KnowledgeProvider,
        defaults: UserDefaults = .standard
    ) {
        packs = datasets.map { KnowledgePackState(config: $0) }
        self.provider = provider
        preferences = KnowledgePreferences(defaults: defaults)
    }

    var enabledReadyDatasets: [KnowledgeDatasetConfig] {
        packs.compactMap { pack in
            guard pack.enabled,
                  pack.status == .ready || pack.status == .updateAvailable else {
                return nil
            }
            return pack.config
        }
    }

    func bootstrap() async {
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await bootstrapEnabledDatasets()
        }
        bootstrapTask = task
        await task.value
    }

    private func bootstrapEnabledDatasets() async {
        let requestedEnabled = preferences.enabledDatasetIds
        let datasets = packs.map(\.config)
        for dataset in datasets where requestedEnabled.contains(dataset.stableId) {
            await reconcileForBootstrap(dataset, enabled: true)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for dataset in datasets where !requestedEnabled.contains(dataset.stableId) {
                await reconcileForBootstrap(dataset, enabled: false)
            }
        }
    }

    private func reconcileForBootstrap(
        _ dataset: KnowledgeDatasetConfig,
        enabled: Bool
    ) async {
        do {
            let result = try await provider.reconcile(dataset: dataset)
            applyReconciliation(
                result,
                stableId: dataset.stableId,
                enabled: enabled
            )
        } catch {
            updatePack(dataset.stableId) { pack in
                pack.status = .download
                pack.enabled = false
                pack.errorMessage = userFacingKnowledgeError(error)
            }
        }
    }

    func downloadOrUpdate(stableId: String) {
        guard downloadsAllowed,
              mutationTasks[stableId] == nil,
              let index = packs.firstIndex(where: { $0.id == stableId }) else {
            return
        }
        let dataset = packs[index].config
        let wasInstalled = packs[index].activeIdentity != nil
        updatePack(stableId) { pack in
            pack.isMutating = true
            pack.progressPercent = 0
            pack.progressLabel = "Starting download..."
            pack.errorMessage = nil
        }

        mutationTasks[stableId] = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await provider.download(dataset: dataset) { progress in
                    Task { @MainActor [weak self] in
                        self?.updatePack(stableId) { pack in
                            pack.progressPercent = min(100, max(0, Int(progress.percentage)))
                            pack.progressLabel = progress.label
                        }
                    }
                }
                let shouldEnable = !wasInstalled && result.status == .ready
                if shouldEnable {
                    preferences.setDatasetEnabled(id: stableId, enabled: true)
                }
                let preservedEnablement = packs
                    .first(where: { $0.id == stableId })?.enabled == true
                applyReconciliation(
                    result,
                    stableId: stableId,
                    enabled: wasInstalled ? preservedEnablement : shouldEnable
                )
            } catch {
                if let result = try? await provider.reconcile(dataset: dataset) {
                    let enabled = packs
                        .first(where: { $0.id == stableId })?.enabled == true
                    applyReconciliation(
                        result,
                        stableId: stableId,
                        enabled: enabled
                    )
                }
                updatePack(stableId) { pack in
                    pack.errorMessage = userFacingKnowledgeError(error)
                }
            }
            updatePack(stableId) { pack in
                pack.isMutating = false
                pack.progressPercent = nil
                pack.progressLabel = nil
            }
            mutationTasks.removeValue(forKey: stableId)
        }
    }

    func cancel(stableId: String) {
        guard let dataset = packs.first(where: { $0.id == stableId })?.config else {
            return
        }
        let ownerTask = mutationTasks[stableId]
        Task { [weak self] in
            guard let self else { return }
            let result = await provider.cancel(dataset: dataset)
            await ownerTask?.value
            if let result {
                let enabled = packs
                    .first(where: { $0.id == stableId })?.enabled == true
                applyReconciliation(result, stableId: stableId, enabled: enabled)
            }
            updatePack(stableId) { pack in
                pack.isMutating = false
                pack.progressPercent = nil
                pack.progressLabel = nil
            }
        }
    }

    func setEnabled(stableId: String, enabled: Bool) {
        guard let index = packs.firstIndex(where: { $0.id == stableId }),
              packs[index].activeIdentity != nil,
              !packs[index].isMutating else {
            return
        }
        updatePack(stableId) { pack in
            pack.enabled = enabled
        }
        preferences.setDatasetEnabled(id: stableId, enabled: enabled)
    }

    private func applyReconciliation(
        _ result: KnowledgeReconciliation,
        stableId: String,
        enabled: Bool
    ) {
        updatePack(stableId) { pack in
            pack.status = result.status
            pack.activeIdentity = result.activeIdentity
            pack.enabled = enabled && result.activeIdentity != nil
            pack.errorMessage = nil
        }
    }

    private func updatePack(
        _ stableId: String,
        update: (inout KnowledgePackState) -> Void
    ) {
        guard let index = packs.firstIndex(where: { $0.id == stableId }) else {
            return
        }
        var updated = packs
        update(&updated[index])
        packs = updated
    }

    private func userFacingKnowledgeError(_ error: Error) -> String {
        guard case let KnowledgeDownloadError.Download(downloadError) = error else {
            return "Knowledge pack setup failed. Please try again."
        }
        switch downloadError {
        case .cancelled:
            return "Download cancelled"
        case .storageFull:
            return "Not enough storage space to download this knowledge pack."
        case .network:
            return "Couldn't download the knowledge pack. Check your connection and try again."
        case .http:
            return "The knowledge pack is currently unavailable. Please try again later."
        case .validation, .sizeMismatch, .`protocol`, .invalidTarget:
            return "The knowledge pack couldn't be verified. Please try again."
        case .io:
            return "Couldn't save the knowledge pack. Please try again."
        }
    }
}

struct KnowledgePackState: Identifiable, Sendable {
    var id: String { config.stableId }
    let config: KnowledgeDatasetConfig
    var status: KnowledgeReconciliationStatus?
    var activeIdentity: String?
    var enabled = false
    var isMutating = false
    var progressPercent: Int?
    var progressLabel: String?
    var errorMessage: String?
}

private final class KnowledgePreferences {
    private enum Keys {
        static let enabledDatasetIds = "ensu.knowledge.enabled_dataset_ids"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var enabledDatasetIds: Set<String> {
        Set(defaults.stringArray(forKey: Keys.enabledDatasetIds) ?? [])
    }

    func setDatasetEnabled(id: String, enabled: Bool) {
        var ids = enabledDatasetIds
        if enabled {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        defaults.set(ids.sorted(), forKey: Keys.enabledDatasetIds)
    }
}
