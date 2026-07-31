import Foundation

struct KnowledgeSearchHit: Sendable {
    let dataset: KnowledgeDatasetConfig
    let hit: RetrievalHit
}

struct KnowledgeDownloadProgress: Sendable {
    let label: String
    let percentage: Double
}

private struct KnowledgePackValidationError: LocalizedError {
    var errorDescription: String? {
        "Downloaded knowledge pack failed current revision validation"
    }
}

actor KnowledgeProvider {
    private final class Mutation: @unchecked Sendable {
        let task: Task<Void, Error>

        init(
            assetStore: AssetStore,
            dataset: KnowledgeDatasetConfig,
            onProgress: @escaping @Sendable (KnowledgeDownloadProgress) -> Void
        ) throws {
            let asset = try knowledgePackAsset(stableId: dataset.stableId)
            task = Task.detached(priority: .utility) {
                try await assetStore.download(assets: [asset]) {
                    onProgress(KnowledgeDownloadProgress(
                        label: $0.label,
                        percentage: $0.percentage
                    ))
                }
            }
        }

        func cancel() {
            task.cancel()
        }
    }

    private struct OpenIndex {
        let directory: String
        let index: RetrievalIndex
    }

    private let assetStore: AssetStore
    private var mutations: [String: Mutation] = [:]
    private var lifecycleGates: [String: AsyncSerialGate] = [:]
    private var indexes: [String: OpenIndex] = [:]
    private let indexGate = AsyncSerialGate()

    init(assetStore: AssetStore) {
        self.assetStore = assetStore
    }

    func reconcile(dataset: KnowledgeDatasetConfig) async throws -> KnowledgeReconciliation {
        let gate = lifecycleGate(dataset.stableId)
        return try await gate.withLock {
            if let mutation = mutations[dataset.stableId] {
                _ = try? await mutation.task.value
            }
            return try await withIndexGate {
                try await reconcileAndActivateLocked(dataset: dataset)
            }
        }
    }

    func download(
        dataset: KnowledgeDatasetConfig,
        onProgress: @escaping @Sendable (KnowledgeDownloadProgress) -> Void
    ) async throws -> KnowledgeReconciliation {
        let gate = lifecycleGate(dataset.stableId)
        let mutation = try await gate.withLock {
            if let current = mutations[dataset.stableId] {
                return current
            }
            let created = try Mutation(
                assetStore: assetStore,
                dataset: dataset,
                onProgress: onProgress
            )
            mutations[dataset.stableId] = created
            return created
        }

        do {
            try await mutation.task.value
        } catch {
            if mutations[dataset.stableId] === mutation {
                mutations.removeValue(forKey: dataset.stableId)
            }
            _ = try? await withIndexGate { try await reconcileAndActivateLocked(dataset: dataset) }
            throw error
        }

        do {
            let result = try await reconcile(dataset: dataset)
            guard result.activeIdentity == dataset.currentDownloadIdentity else {
                throw KnowledgePackValidationError()
            }
            if mutations[dataset.stableId] === mutation {
                mutations.removeValue(forKey: dataset.stableId)
            }
            return result
        } catch {
            if mutations[dataset.stableId] === mutation {
                mutations.removeValue(forKey: dataset.stableId)
            }
            throw error
        }
    }

    func cancel(dataset: KnowledgeDatasetConfig) async -> KnowledgeReconciliation? {
        let mutation = mutations[dataset.stableId]
        mutation?.cancel()
        _ = try? await mutation?.task.value
        if let mutation, mutations[dataset.stableId] === mutation {
            mutations.removeValue(forKey: dataset.stableId)
        }
        return try? await withIndexGate {
            try await reconcileAndActivateLocked(dataset: dataset)
        }
    }

    func search(
        datasets: [KnowledgeDatasetConfig],
        query: [Float],
        maxHits: UInt32
    ) async -> [KnowledgeSearchHit] {
        do {
            return try await withIndexGate {
                let selected = datasets.compactMap { dataset -> (KnowledgeDatasetConfig, RetrievalIndex)? in
                    guard let index = indexes[dataset.stableId]?.index else { return nil }
                    return (dataset, index)
                }
                let searchTask = Task.detached(priority: .utility) { () -> [KnowledgeSearchHit] in
                    var merged: [KnowledgeSearchHit] = []
                    for (dataset, index) in selected {
                        if Task.isCancelled { return [] }
                        let hits: [RetrievalHit]
                        do {
                            hits = try index.search(
                                query: query,
                                maxHits: maxHits,
                                threshold: dataset.relevanceThreshold
                            )
                        } catch {
                            continue
                        }
                        if Task.isCancelled { return [] }
                        merged.append(contentsOf: hits.map {
                            KnowledgeSearchHit(dataset: dataset, hit: $0)
                        })
                    }
                    return merged
                        .sorted { $0.hit.score > $1.hit.score }
                        .prefix(Int(maxHits))
                        .map { $0 }
                }
                return await withTaskCancellationHandler {
                    await searchTask.value
                } onCancel: {
                    searchTask.cancel()
                }
            }
        } catch {
            return []
        }
    }

    private func reconcileAndActivateLocked(
        dataset: KnowledgeDatasetConfig
    ) async throws -> KnowledgeReconciliation {
        let assetStore = assetStore
        let result = try await Task.detached(priority: .utility) {
            try assetStore.reconcileKnowledge(dataset.stableId)
        }.value
        try activate(result: result, dataset: dataset)
        if let activeIdentity = result.activeIdentity {
            _ = try? await Task.detached(priority: .utility) {
                try assetStore.cleanupKnowledgeRevisions(
                    dataset.stableId,
                    activeIdentity: activeIdentity
                )
            }.value
        }
        return result
    }

    private func activate(
        result: KnowledgeReconciliation,
        dataset: KnowledgeDatasetConfig
    ) throws {
        guard let directory = result.activeDirectory else {
            indexes.removeValue(forKey: dataset.stableId)
            return
        }
        guard indexes[dataset.stableId]?.directory != directory else { return }
        let replacement = try RetrievalIndex.open(
            directory: directory,
            stableId: dataset.stableId
        )
        indexes[dataset.stableId] = OpenIndex(directory: directory, index: replacement)
    }

    private func withIndexGate<T>(_ operation: () async throws -> T) async throws -> T {
        try await indexGate.withLock(operation)
    }

    private func lifecycleGate(_ stableId: String) -> AsyncSerialGate {
        if let gate = lifecycleGates[stableId] {
            return gate
        }
        let gate = AsyncSerialGate()
        lifecycleGates[stableId] = gate
        return gate
    }
}
