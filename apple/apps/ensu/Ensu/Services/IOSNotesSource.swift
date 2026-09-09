import Foundation
import Darwin

final class NotesReadOperation: @unchecked Sendable {
    let cancellation = NotesCancellation()
    let coordinator = NSFileCoordinator()

    func cancel() {
        cancellation.cancel()
        coordinator.cancel()
    }

    func perform<T: Sendable>(_ read: @escaping @Sendable () throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            let worker = Task.detached { [self] in
                try cancellation.check()
                return try read()
            }
            let result = await worker.result
            try Task.checkCancellation()
            return try result.get()
        } onCancel: { [self] in
            cancel()
        }
    }
}

final class IOSNotesSource: NotesSource, @unchecked Sendable {
    let root: URL
    private let cancellation: NotesCancellation
    private let coordinator: NSFileCoordinator
    private static let limits = notesLimits()
    private static let byteLimit = Int(limits.maxSourceBytes)
    private static let entryLimit = 250_000

    init(bookmark: Data, cancellation: NotesCancellation, coordinator: NSFileCoordinator = NSFileCoordinator()) throws {
        var stale = false
        let url: URL
        do { url = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) }
        catch { throw NotesError.Unavailable }
        guard !stale, url.startAccessingSecurityScopedResource() else { throw NotesError.Unavailable }
        root = url
        self.cancellation = cancellation
        self.coordinator = coordinator
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw NotesError.Unavailable }
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw NotesError.Unavailable
        }
    }

    deinit { root.stopAccessingSecurityScopedResource() }

    private func coordinate<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        try cancellation.check()
        var error: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { readable in
            result = Result { try body(readable) }
        }
        try cancellation.check()
        if let error { throw error }
        guard let result else { throw NotesError.SourceRead(detail: "Could not read the Notes folder.") }
        return try result.get()
    }

    func listDocuments() throws -> [NotesDocument] {
        do { return try inventory() } catch { throw Self.accessError(error) }
    }

    private func inventory() throws -> [NotesDocument] {
        var pending: [(URL, String)] = [(root, "")]
        var seen = Set<String>()
        var documents: [NotesDocument] = []
        var count = 0
        var total: UInt64 = 0
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        while let (directory, prefix) = pending.popLast() {
            try cancellation.check()
            let identity = directory.standardizedFileURL.resolvingSymlinksInPath().path
            guard seen.insert(identity).inserted else { throw NotesError.SourceRead(detail: "Ambiguous directory structure.") }
            let children = try coordinate(directory) {
                try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: Array(keys))
            }
            var names = Set<String>()
            for child in children {
                try cancellation.check()
                count += 1
                guard count <= Self.entryLimit else { throw NotesError.InvalidInput(detail: "The Notes folder contains too many entries.") }
                let name = child.lastPathComponent
                guard names.insert(name).inserted else { throw NotesError.SourceRead(detail: "Duplicate document names.") }
                if name.hasPrefix(".") { continue }
                let id = prefix + name
                let values = try child.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { continue }
                if values.isDirectory != true && values.isRegularFile != true { continue }
                guard values.isDirectory == true || Self.supported(name) else { continue }
                do { try validateNotesDocumentId(documentId: id) }
                catch NotesError.InvalidInput { continue }
                if values.isDirectory == true {
                    pending.append((child, id + "/"))
                } else {
                    let size: Int
                    if let advertised = values.fileSize { size = advertised }
                    else {
                        do { size = try readBounded(documentId: id).bytes.count }
                        catch ReadError.tooLarge { continue }
                    }
                    guard size <= Self.byteLimit else { continue }
                    total += UInt64(size)
                    guard documents.count < Int(Self.limits.maxCollectionDocuments), total <= Self.limits.maxCollectionSourceBytes else {
                        throw NotesError.InvalidInput(detail: "The Notes folder is too large to index.")
                    }
                    documents.append(NotesDocument(documentId: id, size: UInt64(size),
                        modifiedAtMs: values.contentModificationDate.map { Int64($0.timeIntervalSince1970 * 1000) }))
                }
            }
        }
        return documents.sorted { $0.documentId < $1.documentId }
    }

    func readDocument(documentId: String) throws -> NotesRead {
        do { return try readBounded(documentId: documentId) }
        catch ReadError.tooLarge { throw NotesError.SourceChanged }
        catch { throw Self.documentReadError(error, root: root) }
    }

    private enum ReadError: Error { case tooLarge }

    private func readBounded(documentId: String) throws -> NotesRead {
        try validateNotesDocumentId(documentId: documentId)
        let parts = documentId.split(separator: "/").map(String.init)
        guard parts.allSatisfy({ !$0.hasPrefix(".") }), Self.supported(parts.last ?? "") else { throw NotesError.SourceChanged }
        let url = parts.reduce(root) { $0.appendingPathComponent($1) }
        return try coordinate(url) { coordinated in
            guard coordinated.standardizedFileURL.path == url.standardizedFileURL.path else { throw NotesError.SourceChanged }
            var fd = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard fd >= 0 else { throw NotesError.Unavailable }
            for (index, part) in parts.enumerated() {
                let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC |
                    (index == parts.count - 1 ? O_NONBLOCK : O_DIRECTORY)
                let next = openat(fd, part, flags)
                let code = errno
                close(fd)
                guard next >= 0 else { throw Self.fileError(code) }
                fd = next
            }
            let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? file.close() }
            var before = stat()
            guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG else { throw NotesError.SourceChanged }
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
                throw Self.fileError(errno)
            }
            guard before.st_size <= Self.byteLimit else { throw ReadError.tooLarge }
            var bytes = Data()
            while true {
                try cancellation.check()
                guard let chunk = try file.read(upToCount: 8192), !chunk.isEmpty else { break }
                guard bytes.count + chunk.count <= Self.byteLimit else { throw ReadError.tooLarge }
                bytes.append(chunk)
            }
            var after = stat()
            guard fstat(fd, &after) == 0, before.st_ino == after.st_ino, before.st_size == after.st_size,
                  before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                  bytes.count == after.st_size else { throw NotesError.SourceChanged }
            return NotesRead(bytes: bytes, source: NotesDocument(documentId: documentId, size: UInt64(bytes.count),
                modifiedAtMs: Int64(after.st_mtimespec.tv_sec) * 1000 + Int64(after.st_mtimespec.tv_nsec) / 1_000_000))
        }
    }

    private static func supported(_ name: String) -> Bool {
        let name = name.lowercased()
        return name.hasSuffix(".md") || name.hasSuffix(".markdown")
    }
    private static func fileError(_ code: Int32) -> Error {
        if code == EACCES || code == EPERM { return NotesError.Unavailable }
        if code == ELOOP || code == ENOTDIR { return NotesError.SourceChanged }
        return NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    private static func documentReadError(_ error: Error, root: URL) -> Error {
        guard isMissingFile(error) else { return accessError(error) }
        let fd = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else {
            let code = errno
            if code == ENOENT || code == ENOTDIR || code == ELOOP || code == EACCES || code == EPERM {
                return NotesError.Unavailable
            }
            return accessError(error)
        }
        close(fd)
        return NotesError.SourceChanged
    }

    private static func isMissingFile(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT) { return true }
        if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileNoSuchFileError || ns.code == NSFileReadNoSuchFileError) { return true }
        return (ns.userInfo[NSUnderlyingErrorKey] as? Error).map(isMissingFile) ?? false
    }
    private static func accessError(_ error: Error) -> Error {
        if let error = error as? NotesError { return error }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError { return NotesError.Unavailable }
        return NotesError.SourceRead(detail: "Could not access the Notes folder. Please try again.")
    }
}
