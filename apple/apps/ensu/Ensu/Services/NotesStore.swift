import Foundation
import SwiftUI

enum NotesStatus {
    case pending, indexing, updating, ready, unavailable, error
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
    var eligible: Bool {
        indexAvailable && status != .error && status != .unavailable
    }
}

@MainActor
final class NotesStore: ObservableObject, ModelMaintenance {
    @Published private(set) var collections: [NoteCollectionState] = []
    @Published var operationError: String?
    @Published var preview: NotesPreview?

    private struct Pending {
        let generation: UInt64
        let forced: Set<String>
        let rebuild: Bool
        let due: Date
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
    private var failed = Set<String>()
    private var generation: UInt64 = 0
    private var active: Run?
    private var scopes = 0
    private var foreground = false
    private var loaded = false
    private var disabled = false
    private var bootstrapTask: Task<Void, Never>?
    private var wake: Task<Void, Never>?
    private static let emptyNotes = "No supported non-empty UTF-8 notes were found"

    init(provider: LlmProvider, notesProvider: NotesProvider = NotesProvider()) {
        modelProvider = provider
        self.provider = notesProvider
    }

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
                        collections.append(NoteCollectionState(id: record.id, label: record.label, status: .error,
                            error: Self.message(error)))
                    }
                }
                loaded = true
                scans.formUnion(records.map(\.id))
                pump()
            } catch {
                disabled = true
                operationError = "Could not load Your Notes. Existing indexes have been preserved."
            }
        }
        bootstrapTask = task
        await task.value
    }

    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value
        if value {
            failed.removeAll()
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
                    collections.append(NoteCollectionState(id: record.id, label: record.label))
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
                    failed.remove(id)
                    operationError = nil
                }
            } catch {
                operationError = Self.message(error)
            }
        }
    }

    func retry(_ id: String) {
        guard let collection = collections.first(where: { $0.id == id }),
              collection.status == .error || collection.status == .unavailable else {
            return
        }
        failed.remove(id)
        scans.insert(id)
        if pending[id] != nil {
            enqueue(id, due: .distantPast)
        }
        update(id) {
            $0.status = .pending
            $0.error = nil
            $0.progress = nil
        }
        pump()
    }

    func retrieve(query: [Float]) async throws -> [NotesHit] {
        var hits: [NotesHit] = []
        for collection in collections where collection.eligible {
            try Task.checkCancellation()
            do {
                hits += try await provider.search(collection.id, query: query)
            } catch NotesError.RebuildRequired {
                enqueue(collection.id, rebuild: true, due: .distantPast)
                update(collection.id) {
                    $0.status = .pending
                    $0.indexAvailable = false
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                fail(collection.id, error)
            }
        }
        return hits
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
                  collections.contains(where: { $0.id == reference.collectionId }) else {
                continue
            }
            do {
                let reference = try await provider.verify(reference)
                result.append(GroundedExcerpt(
                    score: excerpt.score,
                    source: .localNote(reference: reference),
                    text: excerpt.text
                ))
                accepted += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch NotesError.SourceChanged {
                enqueue(reference.collectionId, forced: [reference.documentId], due: .distantPast)
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

    private func enqueue(_ id: String, forced: Set<String> = [], rebuild: Bool = false, due: Date? = nil) {
        guard collections.contains(where: { $0.id == id }) else { return }
        let old = pending[id]
        generation &+= 1
        pending[id] = Pending(
            generation: generation,
            forced: (old?.forced ?? []).union(forced),
            rebuild: rebuild || old?.rebuild == true,
            due: due ?? old?.due ?? Date().addingTimeInterval(300)
        )
    }

    private func pump() {
        guard loaded, !disabled, foreground, scopes == 0, active == nil else { return }
        wake?.cancel()
        let embeddingReady = modelProvider.isEmbeddingModelReady()
        let request = embeddingReady ?
            pending.filter { !failed.contains($0.key) && $0.value.due <= Date() }.min { $0.key < $1.key } : nil
        guard let id = request?.key ?? scans.filter({ pending[$0] == nil && !failed.contains($0) }).min(),
              let collection = collections.first(where: { $0.id == id }) else {
            let due = embeddingReady ? pending.filter { !failed.contains($0.key) }.values.map(\.due).min() : nil
            let seconds = min(300, max(0.1, due?.timeIntervalSinceNow ?? 300))
            wake = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                } catch {
                    return
                }
                guard let self else { return }
                self.scans.formUnion(self.collections.filter { $0.status != .unavailable &&
                    ($0.status != .error || $0.completedEmpty) }.map(\.id))
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
        let task = Task { @MainActor in
            defer {
                if active?.operation === operation {
                    active = nil
                }
                pump()
            }
            do {
                try cancellation.check()
                if let snapshot {
                    update(id) {
                        $0.status = hadIndex ? .updating : .indexing
                        $0.error = nil
                    }
                    let result = try await modelProvider.withEmbeddingContext(checkCancellation: cancellation.check) { context in
                        try await self.provider.index(
                            id,
                            context: context,
                            operation: operation,
                            options: NotesIndexOptions(
                                forcedDocumentIds: Array(snapshot.forced),
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
                            due: same ? Date().addingTimeInterval(300) : nil
                        )
                    }
                    update(id) {
                        if pending[id] == nil {
                            $0 = Self.state(record, result.summary)
                        } else {
                            $0.status = .pending
                            $0.documentCount = result.summary.documentCount
                            $0.lastUpdatedAtMs = result.summary.lastUpdatedAtMs
                            $0.indexAvailable = hadIndex && result.summary.initialComplete && result.summary.documentCount > 0
                        }
                    }
                } else {
                    let result = try await provider.inspectFreshness(id, operation: operation)
                    update(id) {
                        $0 = Self.state(record, result.summary, progress: $0.progress)
                    }
                    if result.changed {
                        enqueue(id, forced: Set(result.forcedDocumentIds), due: result.summary.initialComplete ? nil : .distantPast)
                        update(id) {
                            $0.status = .pending
                            $0.error = nil
                        }
                    }
                }
            } catch NotesError.Cancelled {
                if snapshot == nil { scans.insert(id) }
                let saved = try? await provider.inspect(id)
                update(id) {
                    $0.status = .pending
                    if let saved { $0.lastUpdatedAtMs = saved.lastUpdatedAtMs }
                    $0.indexAvailable = hadIndex && saved?.initialComplete == true && (saved?.documentCount ?? 0) > 0
                }
            } catch NotesError.RebuildRequired {
                if snapshot == nil {
                    enqueue(id, rebuild: true, due: .distantPast)
                    update(id) {
                        $0.status = .pending
                        $0.indexAvailable = false
                    }
                } else {
                    fail(id, NotesError.RebuildRequired)
                }
            } catch {
                fail(id, error)
            }
        }
        active = Run(operation: operation, task: task)
    }

    private func fail(_ id: String, _ error: Error) {
        guard collections.contains(where: { $0.id == id }) else { return }
        failed.insert(id)
        scans.remove(id)
        update(id) {
            $0.status = (error as? NotesError) == .Unavailable ? .unavailable : .error
            $0.progress = nil
            $0.error = Self.message(error)
            $0.completedEmpty = false
        }
    }
    private static func message(_ error: Error) -> String {
        guard let error = error as? NotesError else { return "Could not update Your Notes. Please try again." }
        switch error {
        case .Unavailable: return "This Notes folder is unavailable. Check access and try again. If access has expired, remove the folder and add it again."
        case .SourceChanged: return "The folder changed. Retry to update Your Notes."
        case .SourceRead(let detail), .InvalidInput(let detail): return detail
        case .Storage: return "Could not save the Notes index. Check storage and try again."
        case .RebuildRequired: return "The Notes index needs rebuilding. Retry to update Your Notes."
        default: return "Could not update Your Notes. Please try again."
        }
    }

    private func update(_ id: String, _ body: (inout NoteCollectionState) -> Void) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        body(&collections[index])
    }
    private static func state(_ record: NotesCollectionInfo, _ summary: NotesSummary, progress: UInt8? = nil) -> NoteCollectionState {
        let ready = summary.initialComplete && summary.documentCount > 0
        let empty = summary.initialComplete && !ready
        return NoteCollectionState(id: record.id, label: record.label,
            status: ready ? .ready : summary.initialComplete ? .error : .pending,
            documentCount: summary.documentCount, lastUpdatedAtMs: summary.lastUpdatedAtMs, indexAvailable: ready,
            progress: summary.initialComplete ? nil : progress,
            error: empty ? emptyNotes : nil,
            completedEmpty: empty)
    }
}

struct NotesPreview: Identifiable {
    let id = UUID()
    let url: URL
}
