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
