import CryptoKit
import XCTest
@testable import AuthAutoFillCore

final class AutoFillStorageTests: XCTestCase {
    private var directory: URL!
    private var key: SymmetricKey?
    private var failKeyDeletion = false
    private var failFileDeletion = false
    private var failStateWrites = false
    private var keyDeletionAttempted = false
    private var fileDeletionAttempted = false
    private var storage: AutoFillStorage!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storage = AutoFillStorage(
            container: { [unowned self] in
                if failStateWrites { throw AutoFillStore.StoreError.unavailable }
                return directory
            },
            loadKey: { [unowned self] create in
                if let key { return key }
                guard create else { throw AutoFillStore.StoreError.unavailable }
                let created = SymmetricKey(size: .bits256)
                key = created
                return created
            },
            deleteKey: { [unowned self] in
                keyDeletionAttempted = true
                if failKeyDeletion { throw AutoFillStore.StoreError.unavailable }
                key = nil
            },
            removeFile: { [unowned self] file in
                fileDeletionAttempted = true
                if failFileDeletion { throw AutoFillStore.StoreError.unavailable }
                try FileManager.default.removeItem(at: file)
            }
        )
    }

    override func tearDownWithError() throws {
        storage = nil
        try FileManager.default.removeItem(at: directory)
    }

    private func snapshot(_ generation: String, includeInvalidEntry: Bool = false) -> AutoFillSnapshot {
        let valid = AutoFillEntry(id: "offline:1", issuer: "Example", account: "alice",
                                 secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", algorithm: "sha1", digits: 6, period: 30)
        let invalid = AutoFillEntry(id: "offline:2", issuer: "Invalid", account: "bob",
                                   secret: "!", algorithm: "sha1", digits: 6, period: 30)
        return AutoFillSnapshot(version: 1, generation: generation, timeOffsetMilliseconds: 1234,
                                entries: includeInvalidEntry ? [valid, invalid] : [valid])
    }

    func testEncryptedRoundTripAndTamperRejection() throws {
        let generation = try storage.invalidate()
        XCTAssertEqual(try storage.write(snapshot(generation)), 0)
        XCTAssertEqual(try storage.read().entries.first?.id, "offline:1")
        let file = directory.appendingPathComponent("autofill.enc")
        var encrypted = try Data(contentsOf: file)
        XCTAssertGreaterThan(encrypted.count, try JSONEncoder().encode(snapshot(generation)).count)
        encrypted[encrypted.count - 1] ^= 1
        try encrypted.write(to: file)
        XCTAssertThrowsError(try storage.read())
    }

    func testTombstoneRevokesWhenBothKeyAndFileCleanupFail() throws {
        let generation = try storage.invalidate()
        _ = try storage.write(snapshot(generation))
        failKeyDeletion = true
        failFileDeletion = true
        XCTAssertThrowsError(try storage.clear())
        XCTAssertTrue(keyDeletionAttempted)
        XCTAssertTrue(fileDeletionAttempted)
        XCTAssertNotNil(key)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("autofill.enc").path))
        XCTAssertThrowsError(try storage.read())
        XCTAssertThrowsError(try storage.write(snapshot(generation)))
        failKeyDeletion = false
        failFileDeletion = false
        try storage.clear()
        XCTAssertNil(key)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("autofill.enc").path))
    }

    func testFileDeletionStillRunsAfterKeychainFailure() throws {
        _ = try storage.write(snapshot(storage.invalidate()))
        failKeyDeletion = true
        XCTAssertThrowsError(try storage.clear())
        XCTAssertTrue(fileDeletionAttempted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("autofill.enc").path))
        XCTAssertThrowsError(try storage.read())
    }

    func testKeyDeletionStillRunsIfContainerIsUnavailable() throws {
        _ = try storage.write(snapshot(storage.invalidate()))
        failStateWrites = true
        XCTAssertThrowsError(try storage.clear())
        XCTAssertTrue(keyDeletionAttempted)
        XCTAssertNil(key)
        failStateWrites = false
        XCTAssertThrowsError(try storage.read())
    }

    func testStalePublicationCannotReactivateInvalidatedGeneration() throws {
        let old = try storage.invalidate()
        _ = try storage.write(snapshot(old))
        let current = try storage.invalidate()
        XCTAssertThrowsError(try storage.write(snapshot(old)))
        XCTAssertThrowsError(try storage.read())
        _ = try storage.write(snapshot(current))
        XCTAssertEqual(try storage.read().generation, current)
    }

    func testInvalidEntryDoesNotSuppressUsableEntries() throws {
        let generation = try storage.invalidate()
        XCTAssertEqual(try storage.write(snapshot(generation, includeInvalidEntry: true)), 1)
        XCTAssertEqual(try storage.read().entries.map(\.id), ["offline:1"])
    }

    func testMissingStateFailsClosedEvenWhenSnapshotAndKeyExist() throws {
        _ = try storage.write(snapshot(storage.invalidate()))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("autofill.state"))
        XCTAssertThrowsError(try storage.read())
    }

    func testOlderAuthenticatedCiphertextCannotBeReplayedIntoNewGeneration() throws {
        _ = try storage.write(snapshot(storage.invalidate()))
        let file = directory.appendingPathComponent("autofill.enc")
        let oldCiphertext = try Data(contentsOf: file)
        _ = try storage.write(snapshot(storage.invalidate()))
        try oldCiphertext.write(to: file)
        XCTAssertThrowsError(try storage.read())
    }
}
