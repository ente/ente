import Foundation

struct NotesCollectionInfo: Sendable {
    let id: String
    let label: String
}

actor NotesProvider {
    private struct Registration: Codable, Sendable {
        let id: String
        let label: String
        let bookmark: Data
        var canonicalPath: String?

        var info: NotesCollectionInfo {
            NotesCollectionInfo(id: id, label: label)
        }
    }

    private struct Registry: Codable {
        let schemaVersion: Int
        let collections: [Registration]
    }

    private let root: URL
    private let diskGate = AsyncSerialGate()
    private var registrations: [Registration] = []

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("notes", isDirectory: true)) {
        self.root = root
    }

    func load() async throws -> [NotesCollectionInfo] {
        try await diskGate.withLock {
            let root = self.root
            let records = try await Task.detached {
                try Self.load(root: root)
            }.value
            self.registrations = records
            return records.map(\.info)
        }
    }

    func add(_ url: URL) async throws -> NotesCollectionInfo {
        try await diskGate.withLock {
            let root = self.root
            let records = self.registrations
            let record = try await Task.detached {
                guard url.startAccessingSecurityScopedResource() else {
                    throw NotesError.Unavailable
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let canonical = url.standardizedFileURL.resolvingSymlinksInPath().path
                let selectedPrefix = canonical.hasSuffix("/") ? canonical : canonical + "/"
                for registered in records {
                    guard let path = Self.identityPath(registered) else { continue }
                    let existingPrefix = path.hasSuffix("/") ? path : path + "/"
                    guard canonical != path,
                          !canonical.hasPrefix(existingPrefix),
                          !path.hasPrefix(selectedPrefix) else {
                        throw NotesError.InvalidInput(
                            detail: "This folder overlaps a folder already added to Your Notes."
                        )
                    }
                }

                let bookmark = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: [.pathKey],
                    relativeTo: nil
                )
                let source = try IOSNotesSource(bookmark: bookmark, cancellation: NotesCancellation())
                let record = Registration(
                    id: UUID().uuidString.lowercased(),
                    label: source.root.lastPathComponent,
                    bookmark: bookmark,
                    canonicalPath: canonical
                )
                try Self.save(records + [record], root: root)
                return record
            }.value
            self.registrations.append(record)
            return record.info
        }
    }

    func remove(_ id: String) async throws {
        try await diskGate.withLock {
            let root = self.root
            let records = self.registrations.filter { $0.id != id }
            try await Task.detached {
                try Self.save(records, root: root)
            }.value
            self.registrations = records
            await Task.detached {
                try? Self.handle(root, id).remove()
            }.value
        }
    }

    func inspect(_ id: String) async throws -> NotesSummary {
        try await diskGate.withLock {
            let root = self.root
            return try await Task.detached {
                try Self.handle(root, id).inspect()
            }.value
        }
    }

    func inspectFreshness(_ id: String, operation: NotesReadOperation) async throws -> NotesFreshness {
        try await diskGate.withLock {
            let root = self.root
            let record = try self.registration(id)
            return try await operation.perform {
                let source = try Self.source(record, operation: operation)
                return try Self.handle(root, id).inspectFreshness(
                    source: source,
                    cancellation: operation.cancellation
                )
            }
        }
    }

    func index(
        _ id: String,
        context: LlmContext,
        operation: NotesReadOperation,
        options: NotesIndexOptions,
        onProgress: @escaping @Sendable (NotesProgress) -> Void
    ) async throws -> NotesOutcome {
        try await diskGate.withLock {
            let root = self.root
            let record = try self.registration(id)
            return try await operation.perform {
                let source = try Self.source(record, operation: operation)
                return try Self.handle(root, id).index(
                    source: source,
                    context: context,
                    cancellation: operation.cancellation,
                    progress: NativeNotesProgress(onProgress),
                    options: options
                )
            }
        }
    }

    func search(_ id: String, query: [Float]) async throws -> [NotesHit] {
        try await diskGate.withLock {
            let root = self.root
            return try await Task.detached {
                try Self.handle(root, id).search(query: query)
            }.value
        }
    }

    func verify(_ reference: NoteSourceReference) async throws -> NoteSourceReference {
        try await diskGate.withLock {
            let record = try self.registration(reference.collectionId)
            let operation = NotesReadOperation()
            try await operation.perform {
                _ = try Self.readVerified(record, reference, operation: operation)
            }
            return withNotesCollectionLabel(reference: reference, label: record.label)
        }
    }

    func preview(_ reference: NoteSourceReference) async throws -> URL {
        try await diskGate.withLock {
            let record = try self.registration(reference.collectionId)
            let operation = NotesReadOperation()
            return try await operation.perform {
                let bytes = try Self.readVerified(record, reference, operation: operation)
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("note-preview-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                do {
                    let url = folder.appendingPathComponent((reference.documentId as NSString).lastPathComponent)
                    try bytes.write(to: url, options: [.atomic, .completeFileProtection])
                    return url
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    throw error
                }
            }
        }
    }

    private func registration(_ id: String) throws -> Registration {
        guard let record = registrations.first(where: { $0.id == id }) else {
            throw NotesError.Unavailable
        }
        return record
    }

    private static func source(_ record: Registration, operation: NotesReadOperation) throws -> IOSNotesSource {
        try IOSNotesSource(
            bookmark: record.bookmark,
            cancellation: operation.cancellation,
            coordinator: operation.coordinator
        )
    }

    private static func readVerified(
        _ record: Registration,
        _ reference: NoteSourceReference,
        operation: NotesReadOperation
    ) throws -> Data {
        let source = try source(record, operation: operation)
        let bytes = try source.readDocument(documentId: reference.documentId).bytes
        guard notesContentRevision(bytes: bytes) == reference.indexedRevision else {
            throw NotesError.SourceChanged
        }
        return bytes
    }

    private static func identityPath(_ record: Registration) -> String? {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: record.bookmark,
            options: [.withoutUI, .withoutMounting],
            bookmarkDataIsStale: &stale
        ) {
            return url.standardizedFileURL.resolvingSymlinksInPath().path
        }
        return record.canonicalPath ??
            (NSURL.resourceValues(forKeys: [.pathKey], fromBookmarkData: record.bookmark)?[.pathKey] as? String)
    }

    private static func handle(_ root: URL, _ id: String) throws -> NotesCollection {
        try NotesCollection(indexRoot: root.path, collectionId: id)
    }

    private static func load(root: URL) throws -> [Registration] {
        let url = root.appendingPathComponent("collections.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: 1024 * 1024 + 1) ?? Data()
        guard data.count <= 1024 * 1024 else {
            throw NotesError.InvalidInput(detail: "Notes registry is too large.")
        }
        let registry = try JSONDecoder().decode(Registry.self, from: data)
        let registeredIds = Set(registry.collections.map(\.id))
        guard registry.schemaVersion == 1,
              registeredIds.count == registry.collections.count,
              registry.collections.allSatisfy({ UUID(uuidString: $0.id)?.uuidString.lowercased() == $0.id }) else {
            throw NotesError.InvalidInput(detail: "Invalid Notes registry.")
        }
        for child in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let id = child.lastPathComponent
            if !registeredIds.contains(id), UUID(uuidString: id)?.uuidString.lowercased() == id {
                try? handle(root, id).remove()
            }
        }
        var records = registry.collections
        for index in records.indices where records[index].canonicalPath == nil {
            records[index].canonicalPath = identityPath(records[index])
        }
        if zip(registry.collections, records).contains(where: { $0.canonicalPath != $1.canonicalPath }) {
            try? save(records, root: root)
        }
        return records
    }

    private static func save(_ records: [Registration], root: URL) throws {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var root = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        let data = try JSONEncoder().encode(Registry(schemaVersion: 1, collections: records))
        guard data.count <= 1024 * 1024 else {
            throw NotesError.InvalidInput(detail: "Notes registry is too large.")
        }
        try data.write(to: root.appendingPathComponent("collections.json"), options: [.atomic, .completeFileProtection])
    }
}

private final class NativeNotesProgress: NotesProgressCallback {
    private let callback: @Sendable (NotesProgress) -> Void

    init(_ callback: @escaping @Sendable (NotesProgress) -> Void) {
        self.callback = callback
    }

    func onProgress(progress: NotesProgress) {
        callback(progress)
    }
}
