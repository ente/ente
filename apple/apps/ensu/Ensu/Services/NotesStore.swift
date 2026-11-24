import Foundation
import SwiftUI

enum NotesStatus {
    case pending, updateScheduled, updateRequested, indexing, updating, ready, unavailable, error
}

struct NoteCollectionState: Identifiable {
    let id: String
    let label: String
    var status: NotesStatus = .pending
    var documentCount: UInt64 = 0
    var lastUpdatedAtMs: Int64?
    var indexAvailable = false
    var progress: UInt8?
    var error: String?
    var completedEmpty = false
    var canRequestUpdate: Bool {
        status == .updateScheduled || status == .updateRequested
    }
    var eligible: Bool {
        indexAvailable && status != .error && status != .unavailable
    }
}

@MainActor
final class NotesStore: ObservableObject, ModelMaintenance {
    @Published private(set) var collections: [NoteCollectionState] = []
    @Published var operationError: String?
    @Published var preview: NotesPreview?
    @Published private(set) var disabledIDs: Set<String>
    private let sourceDefaults: UserDefaults
    private static let disabledDefaultsKey = "ensu.notes.disabledByDefault"

    private enum IndexTrigger {
        case maintenance, changesDetected, manual
    }
    private enum IndexFailure {
        case sourceAccess, indexing
    }
    private struct Pending {
        let generation: UInt64
        let forced: Set<String>
        let rebuild: Bool
        var due: Date
        var trigger: IndexTrigger

        var waitingStatus: NotesStatus {
            switch trigger {
            case .maintenance: .pending
            case .changesDetected: .updateScheduled
            case .manual: .updateRequested
            }
        }
    }
    private struct Run {
        let operation: NotesReadOperation
        let task: Task<Void, Never>
    }

    private let modelProvider: LlmProvider
    private let provider: NotesProvider
    private let limits = notesLimits()
    private var pending: [String: Pending] = [:]
    private var scans = Set<String>()
    private var failed: [String: IndexFailure] = [:]
    private var sourceRevisions: [String: String] = [:]
    private var generation: UInt64 = 0
    private var active: Run?
    private var scopes = 0
    private var foreground = false
    private var loaded = false
    private var disabled = false
    private var bootstrapTask: Task<Void, Never>?
    private var wake: Task<Void, Never>?
    private static let emptyNotes = "No supported non-empty UTF-8 notes were found"

    init(
        provider: LlmProvider, notesProvider: NotesProvider = NotesProvider(),
        defaults: UserDefaults = .standard
    ) {
        sourceDefaults = defaults
        disabledIDs = Set(defaults.stringArray(forKey: Self.disabledDefaultsKey) ?? [])
        modelProvider = provider
        self.provider = notesProvider
    }

    func setEnabled(_ id: String, enabled: Bool) {
        if enabled { disabledIDs.remove(id) } else { disabledIDs.insert(id) }
        sourceDefaults.set(Array(disabledIDs), forKey: Self.disabledDefaultsKey)
    }

    var inventoryReady: Bool { loaded }

    func bootstrap() async {
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }
        let task = Task { @MainActor in
            do {
                let records = try await provider.load()
                for record in records {
                    do {
                        let summary = try await provider.inspect(record.id)
                        collections.append(Self.state(record, summary))
                        if !summary.initialComplete {
                            enqueue(record.id, due: .distantPast)
                        }
                    } catch NotesError.RebuildRequired {
                        collections.append(NoteCollectionState(id: record.id, label: record.label))
                        enqueue(record.id, rebuild: true, due: .distantPast)
                    } catch {
                        collections.append(
                            NoteCollectionState(
                                id: record.id, label: record.label, status: .error,
                                error: Self.message(error)))
                    }
                }
                loaded = true
                disabled = false
                operationError = nil
                scans.formUnion(records.map(\.id))
                pump()
            } catch {
                disabled = true
                operationError = "Could not load Your Notes. Existing indexes have been preserved."
            }
        }
        bootstrapTask = task
        await task.value
        if !loaded { bootstrapTask = nil }
    }

    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value
        if value {
            scans.formUnion(collections.map(\.id))
            pump()
        } else {
            wake?.cancel()
            active?.operation.cancel()
        }
    }
    func modelReadinessChanged() {
        pump()
    }

    func suspendMaintenance() -> ModelUseScope {
        scopes += 1
        active?.operation.cancel()
        return ModelUseScope { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.scopes -= 1
                self.pump()
            }
        }
    }
    func awaitMaintenance() async {
        await active?.task.value
    }

    func add(_ url: URL) {
        Task {
            await bootstrap()
            guard !disabled else { return }
            do {
                try await withMaintenanceSuspended {
                    let record = try await provider.add(url)
                    if !collections.contains(where: { $0.id == record.id }) {
                        setEnabled(record.id, enabled: true)
                        collections.append(NoteCollectionState(id: record.id, label: record.label))
                    }
                    operationError = nil
                    enqueue(record.id, due: .distantPast)
                }
            } catch {
                operationError = Self.message(error)
            }
        }
    }

    func remove(_ id: String) {
        Task {
            await bootstrap()
            guard !disabled else { return }
            do {
                try await withMaintenanceSuspended {
                    try await provider.remove(id)
                    collections.removeAll { $0.id == id }
                    pending.removeValue(forKey: id)
                    scans.remove(id)
                    failed.removeValue(forKey: id)
                    sourceRevisions.removeValue(forKey: id)
                    operationError = nil
                }
            } catch {
                operationError = Self.message(error)
            }
        }
    }

    func updateNow(_ id: String) {
        guard
            collections.contains(where: { $0.id == id && $0.canRequestUpdate }),
            let trigger = pending[id]?.trigger,
            trigger == .changesDetected || trigger == .manual
        else { return }

        pending[id]?.trigger = .manual
        pending[id]?.due = .distantPast
        update(id) { $0.status = .updateRequested }
        pump()
    }

    func retry(_ id: String) {
        guard let collection = collections.first(where: { $0.id == id }),
            collection.status == .error || collection.status == .unavailable
        else {
            return
        }
        failed.removeValue(forKey: id)
        enqueue(id, due: .distantPast)
        pending[id]?.trigger = .manual
        update(id) {
            $0.status = pending[id]?.waitingStatus ?? .pending
            $0.error = nil
            $0.progress = nil
        }
        pump()
    }

    func retrieve(query: [Float], collectionIDs: Set<String>) async throws -> [NotesHit] {
        var hits: [NotesHit] = []
        for collection in collections
        where collection.eligible && collectionIDs.contains(collection.id) {
            try Task.checkCancellation()
            do {
                hits += try await provider.search(collection.id, query: query)
            } catch NotesError.RebuildRequired {
                requestRebuild(collection.id)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                fail(collection.id, error)
            }
        }
        return hits
    }

    func reload(_ locator: NotePassageLocator, collectionIDs: Set<String>) async throws
        -> GroundedExcerpt?
    {
        guard collectionIDs.contains(locator.collectionId),
            collections.contains(where: { $0.id == locator.collectionId && $0.eligible })
        else { return nil }
        do {
            guard let hit = try await provider.reload(locator) else { return nil }
            return try await verify(
                selectMixedGroundingCandidates(packHits: [], notesHits: [hit], notesLimit: 1)
            ).first
        } catch NotesError.RebuildRequired {
            requestRebuild(locator.collectionId)
            return nil
        }
    }

    func verify(_ excerpts: [GroundedExcerpt]) async throws -> [GroundedExcerpt] {
        var result: [GroundedExcerpt] = []
        var accepted = 0
        for excerpt in excerpts {
            try Task.checkCancellation()
            guard case .localNote(let reference) = excerpt.source else {
                result.append(excerpt)
                continue
            }
            guard accepted < Int(limits.maxGroundingHits),
                collections.contains(where: { $0.id == reference.collectionId })
            else {
                continue
            }
            do {
                let reference = try await provider.verify(reference)
                var verifiedExcerpt = excerpt
                verifiedExcerpt.source = .localNote(reference: reference)
                result.append(verifiedExcerpt)
                accepted += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch NotesError.SourceChanged {
                enqueue(
                    reference.collectionId, forced: [reference.documentId], changesDetected: true,
                    due: .distantPast)
                update(reference.collectionId) {
                    if failed[reference.collectionId] == nil {
                        $0.status = pending[reference.collectionId]?.waitingStatus ?? .pending
                    }
                }
            } catch {
                fail(reference.collectionId, error)
            }
        }
        return result
    }

    func open(_ reference: NoteSourceReference) {
        Task {
            operationError = nil
            do {
                let url = try await withMaintenanceSuspended {
                    try await provider.preview(reference)
                }
                preview = NotesPreview(url: url)
                operationError = nil
            } catch NotesError.SourceChanged {
                operationError = "This note changed after the answer was generated."
            } catch NotesError.Unavailable {
                operationError = "This note is unavailable."
            } catch {
                operationError = "Could not open this note. Check folder access and try again."
            }
        }
    }

    private func requestRebuild(_ id: String) {
        enqueue(id, rebuild: true, due: .distantPast)
        update(id) {
            if failed[id] == nil { $0.status = pending[id]?.waitingStatus ?? .pending }
            $0.indexAvailable = false
        }
    }

    private func enqueue(
        _ id: String, forced: Set<String> = [], rebuild: Bool = false,
        changesDetected: Bool = false,
        due: Date? = nil
    ) {
        guard collections.contains(where: { $0.id == id }) else { return }
        let old = pending[id]
        var trigger = old?.trigger ?? .maintenance
        if trigger == .maintenance && changesDetected { trigger = .changesDetected }
        generation &+= 1
        pending[id] = Pending(
            generation: generation,
            forced: (old?.forced ?? []).union(forced),
            rebuild: rebuild || old?.rebuild == true,
            due: due ?? old?.due ?? Date().addingTimeInterval(300),
            trigger: trigger
        )
    }

    private func pump() {
        guard loaded, !disabled, foreground, scopes == 0, active == nil else { return }
        wake?.cancel()
        let embeddingReady = modelProvider.isEmbeddingModelReady()
        let request =
            embeddingReady
            ? pending.filter { failed[$0.key] == nil && $0.value.due <= Date() }.min {
                lhs, rhs in
                let lhsManual = lhs.value.trigger == .manual
                let rhsManual = rhs.value.trigger == .manual
                return lhsManual == rhsManual ? lhs.key < rhs.key : lhsManual
            } : nil
        guard
            let id = request?.key
                ?? scans.filter({ pending[$0] == nil || failed[$0] != nil }).min(),
            let collection = collections.first(where: { $0.id == id })
        else {
            let due =
                embeddingReady
                ? pending.filter { failed[$0.key] == nil }.values.map(\.due).min() : nil
            let seconds = min(300, max(0.1, due?.timeIntervalSinceNow ?? 300))
            wake = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                } catch {
                    return
                }
                guard let self else { return }
                self.scans.formUnion(self.collections.map(\.id))
                self.pump()
            }
            return
        }
        scans.remove(id)
        let snapshot = request?.value
        let operation = NotesReadOperation()
        let cancellation = operation.cancellation
        let record = NotesCollectionInfo(id: collection.id, label: collection.label)
        let hadIndex = collection.indexAvailable
        let task = Task { @MainActor [self] in
            defer {
                if active?.operation === operation {
                    active = nil
                }
                pump()
            }
            do {
                try cancellation.check()
                if let snapshot {
                    sourceRevisions.removeValue(forKey: id)
                    let result = try await modelProvider.withEmbeddingContext(
                        for: snapshot.trigger == .manual ? .manualIndexing : .automaticIndexing,
                        checkCancellation: cancellation.check
                    ) { context in
                        var forced = snapshot.forced
                        do {
                            let freshness = try await self.provider.inspectFreshness(
                                id, operation: operation)
                            if let revision = freshness.sourceRevision {
                                await MainActor.run { self.sourceRevisions[id] = revision }
                            }
                            forced.formUnion(freshness.forcedDocumentIds)
                        } catch NotesError.RebuildRequired {
                            if let revision = try await self.provider.inspectSourceRevision(
                                id, operation: operation)
                            {
                                await MainActor.run { self.sourceRevisions[id] = revision }
                            }
                        }
                        return try await self.provider.index(
                            id,
                            context: context,
                            operation: operation,
                            options: NotesIndexOptions(
                                forcedDocumentIds: Array(forced),
                                rebuild: snapshot.rebuild
                            )
                        ) { [weak self] progress in
                            Task { @MainActor in
                                guard let self, self.active?.operation === operation else { return }
                                self.update(id) {
                                    $0.progress = progress.percentage
                                    $0.documentCount = progress.indexedDocumentCount
                                }
                            }
                        }
                    }
                    let same = pending[id]?.generation == snapshot.generation
                    if same {
                        pending.removeValue(forKey: id)
                    }
                    if let changed = result.changedDocumentId {
                        enqueue(
                            id,
                            forced: Set(result.uncheckedDocumentIds).union([changed]),
                            changesDetected: result.summary.initialComplete,
                            due: same ? Date().addingTimeInterval(300) : nil
                        )
                    }
                    update(id) {
                        if let next = pending[id] {
                            $0.status = next.waitingStatus
                            $0.progress = nil
                            $0.documentCount = result.summary.documentCount
                            $0.lastUpdatedAtMs = result.summary.lastUpdatedAtMs
                            $0.indexAvailable =
                                hadIndex && !next.rebuild && result.summary.initialComplete
                                && result.summary.documentCount > 0
                        } else {
                            $0 = Self.state(record, result.summary)
                        }
                    }
                } else {
                    let result = try await provider.inspectFreshness(id, operation: operation)
                    var recovery: Pending?
                    if let failure = failed[id] {
                        if failure == .indexing
                            && !hasNewSourceRevision(id, result.sourceRevision)
                        {
                            return
                        }
                        failed.removeValue(forKey: id)
                        recovery = pending.removeValue(forKey: id)
                    }
                    if let revision = result.sourceRevision { sourceRevisions[id] = revision }
                    if result.changed || recovery?.rebuild == true {
                        enqueue(
                            id, forced: Set(result.forcedDocumentIds).union(recovery?.forced ?? []),
                            rebuild: recovery?.rebuild == true,
                            changesDetected: result.summary.initialComplete,
                            due: result.summary.initialComplete ? nil : .distantPast)
                    }
                    update(id) {
                        $0 = Self.state(record, result.summary, progress: $0.progress)
                        if let next = pending[id] {
                            $0.status = next.waitingStatus
                            $0.indexAvailable = $0.indexAvailable && !next.rebuild
                            $0.error = nil
                        }
                    }
                }
            } catch is ModelMemoryDeferred {
                enqueue(id, due: Date().addingTimeInterval(30))
                update(id) {
                    $0.status = pending[id]?.waitingStatus ?? .pending
                    $0.progress = nil
                }
            } catch NotesError.Cancelled {
                if snapshot == nil { scans.insert(id) }
                if failed[id] != nil { return }
                let saved = try? await provider.inspect(id)
                update(id) {
                    $0.status = pending[id]?.waitingStatus ?? .pending
                    $0.progress = nil
                    if let saved { $0.lastUpdatedAtMs = saved.lastUpdatedAtMs }
                    $0.indexAvailable =
                        hadIndex && pending[id]?.rebuild != true && saved?.initialComplete == true
                        && (saved?.documentCount ?? 0) > 0
                }
            } catch NotesError.RebuildRequired {
                if snapshot == nil {
                    await recoverRebuild(id, operation: operation)
                } else if failed[id] == nil {
                    fail(id, NotesError.RebuildRequired)
                }
            } catch {
                if snapshot == nil && (failed[id] != nil || pending[id]?.trigger == .manual) {
                    return
                }
                fail(id, error)
            }
        }
        active = Run(operation: operation, task: task)
        if snapshot != nil {
            update(id) {
                $0.status = hadIndex ? .updating : .indexing
                $0.error = nil
            }
        }
    }

    private func hasNewSourceRevision(_ id: String, _ revision: String?) -> Bool {
        guard let revision else { return false }
        guard let failedRevision = sourceRevisions[id] else {
            sourceRevisions[id] = revision
            return false
        }
        return revision != failedRevision
    }

    private func recoverRebuild(_ id: String, operation: NotesReadOperation) async {
        requestRebuild(id)
        guard failed[id] != nil else { return }
        do {
            let revision = try await provider.inspectSourceRevision(id, operation: operation)
            try operation.cancellation.check()
            guard let failure = failed[id] else { return }
            if failure == .indexing && !hasNewSourceRevision(id, revision) { return }
            let recovery = pending.removeValue(forKey: id)
            failed.removeValue(forKey: id)
            if let revision { sourceRevisions[id] = revision }
            enqueue(
                id, forced: recovery?.forced ?? [], rebuild: true,
                changesDetected: failure == .indexing,
                due: failure == .indexing ? nil : .distantPast)
            update(id) {
                $0.status = pending[id]?.waitingStatus ?? .pending
                $0.indexAvailable = false
                $0.error = nil
                $0.progress = nil
            }
        } catch NotesError.Cancelled {
            scans.insert(id)
        } catch {}
    }

    private func fail(_ id: String, _ error: Error) {
        guard collections.contains(where: { $0.id == id }) else { return }
        switch error as? NotesError {
        case .Unavailable?, .SourceRead?, .SourceChanged?:
            failed[id] = .sourceAccess
        default:
            failed[id] = .indexing
        }
        scans.remove(id)
        update(id) {
            $0.status = (error as? NotesError) == .Unavailable ? .unavailable : .error
            $0.progress = nil
            $0.error = Self.message(error)
            $0.completedEmpty = false
        }
    }
    private static func message(_ error: Error) -> String {
        if error is ModelMemoryUnavailable { return error.localizedDescription }
        guard let error = error as? NotesError else {
            return "Could not update Your Notes. Please try again."
        }
        switch error {
        case .Unavailable:
            return
                "This Notes folder is unavailable. Check access and try again. If access has expired, remove the folder and add it again."
        case .SourceChanged: return "The folder changed. Retry to update Your Notes."
        case .SourceRead(let detail), .InvalidInput(let detail): return detail
        case .Storage: return "Could not save the Notes index. Check storage and try again."
        case .RebuildRequired:
            return "The Notes index needs rebuilding. Retry to update Your Notes."
        default: return "Could not update Your Notes. Please try again."
        }
    }

    private func update(_ id: String, _ body: (inout NoteCollectionState) -> Void) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        body(&collections[index])
    }
    private static func state(
        _ record: NotesCollectionInfo, _ summary: NotesSummary, progress: UInt8? = nil
    ) -> NoteCollectionState {
        let ready = summary.initialComplete && summary.documentCount > 0
        let empty = summary.initialComplete && !ready
        return NoteCollectionState(
            id: record.id, label: record.label,
            status: ready ? .ready : summary.initialComplete ? .error : .pending,
            documentCount: summary.documentCount, lastUpdatedAtMs: summary.lastUpdatedAtMs,
            indexAvailable: ready,
            progress: summary.initialComplete ? nil : progress,
            error: empty ? emptyNotes : nil,
            completedEmpty: empty)
    }
}

struct NotesPreview: Identifiable {
    let id = UUID()
    let url: URL
}
