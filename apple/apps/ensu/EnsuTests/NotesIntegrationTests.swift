import CryptoKit
import XCTest
@testable import Ensu

private final class UnavailableNotesSource: NotesSource {
    func listDocuments() throws -> [NotesDocument] {
        throw NotesError.Unavailable
    }
    func readDocument(documentId: String) throws -> NotesRead {
        throw NotesError.Unavailable
    }
}

private final class SnapshotNotesSource: NotesSource {
    let text: String
    let changing: Bool

    init(text: String, changing: Bool) {
        self.text = text
        self.changing = changing
    }

    func listDocuments() -> [NotesDocument] {
        [NotesDocument(documentId: "note.md", size: UInt64(text.utf8.count), modifiedAtMs: nil)]
    }

    func readDocument(documentId: String) throws -> NotesRead {
        if changing { throw NotesError.SourceChanged }
        return NotesRead(bytes: Data(text.utf8), source: listDocuments()[0])
    }
}

final class NotesIntegrationTests: XCTestCase {
    func testFreshnessDistinguishesNewContentFromAnUnchangedPendingUpdate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let collection = try NotesCollection(
            indexRoot: root.path, collectionId: UUID().uuidString.lowercased())
        func inspect(_ text: String = "first", changing: Bool = false) throws -> NotesFreshness {
            try collection.inspectFreshness(
                source: SnapshotNotesSource(text: text, changing: changing),
                cancellation: NotesCancellation())
        }
        let first = try inspect()
        XCTAssertTrue(first.changed)
        XCTAssertNotNil(first.sourceRevision)
        XCTAssertEqual(first.sourceRevision, try inspect().sourceRevision)
        let newer = try inspect("newer")
        XCTAssertTrue(newer.changed)
        XCTAssertNotEqual(first.sourceRevision, newer.sourceRevision)
        XCTAssertEqual(newer.sourceRevision, try inspect("newer").sourceRevision)
        XCTAssertNil(try inspect(changing: true).sourceRevision)
    }

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
        let source = UnavailableNotesSource()
        XCTAssertThrowsError(
            try collection.inspectFreshness(source: source, cancellation: NotesCancellation())
        ) {
            XCTAssertEqual($0 as? NotesError, .Unavailable)
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
