import CryptoKit
import XCTest
@testable import Ensu

private final class FailingNotesSource: NotesSource {
    let error: NotesError?
    let documents: [NotesDocument]

    init(error: NotesError? = .Unavailable, documents: [NotesDocument] = []) {
        self.error = error
        self.documents = documents
    }

    func listDocuments() throws -> [NotesDocument] {
        if let error { throw error }
        return documents
    }
    func readDocument(documentId: String) throws -> NotesRead {
        throw NotesError.Unavailable
    }
}

final class NotesIntegrationTests: XCTestCase {
    func testContentRevisionReadsBorrowedBytes() {
        let bytes = Data((0..<131_073).map { UInt8(truncatingIfNeeded: $0) })
        for input in [Data(), Data([0]), bytes, bytes.dropFirst()] {
            let expected = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(notesContentRevision(bytes: input), expected)
        }
    }

    func testNativeSourceFailureAndCancellationCrossTheBridge() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let collection = try NotesCollection(
            indexRoot: root.path, collectionId: UUID().uuidString.lowercased())
        let source = FailingNotesSource()
        XCTAssertThrowsError(
            try collection.inspectFreshness(source: source, cancellation: NotesCancellation())
        ) {
            XCTAssertEqual($0 as? NotesError, .Unavailable)
        }
        XCTAssertThrowsError(
            try collection.inspectFreshness(
                source: FailingNotesSource(error: .InvalidInput(detail: "Too many folder entries")),
                cancellation: NotesCancellation())
        ) {
            XCTAssertEqual($0 as? NotesError, .SourceRead(detail: "Too many folder entries"))
        }
        let document = NotesDocument(documentId: "a.md", size: 0, modifiedAtMs: nil)
        for documents in [
            (0..<65).map {
                NotesDocument(documentId: "\($0).md", size: 2 * 1024 * 1024, modifiedAtMs: nil)
            },
            [document, document],
        ] {
            XCTAssertThrowsError(
                try collection.inspectFreshness(
                    source: FailingNotesSource(error: nil, documents: documents),
                    cancellation: NotesCancellation())
            ) {
                guard case NotesError.SourceRead = $0 else {
                    return XCTFail("Expected a recoverable source failure, got \($0)")
                }
            }
        }
        let cancellation = NotesCancellation()
        cancellation.cancel()
        XCTAssertThrowsError(
            try collection.inspectFreshness(source: source, cancellation: cancellation)
        ) {
            XCTAssertEqual($0 as? NotesError, .Cancelled)
        }
    }
}
