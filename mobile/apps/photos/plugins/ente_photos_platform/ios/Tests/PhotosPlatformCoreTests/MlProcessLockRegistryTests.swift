import XCTest
@testable import MlProcessLockCore

final class MlProcessLockRegistryTests: XCTestCase {
    private let registry = MlProcessLockRegistry.shared

    override func tearDown() {
        if let holder = registry.state() {
            _ = registry.reset(for: holder.pluginInstanceID)
        }
        super.tearDown()
    }

    func testConcurrentDifferentTokensHaveOneWinner() {
        let start = DispatchSemaphore(value: 0)
        let results = LockedResults()
        let group = DispatchGroup()

        for token in ["first", "second"] {
            group.enter()
            DispatchQueue.global().async {
                start.wait()
                let acquired = self.registry.tryAcquire(
                    pluginInstanceID: "instance-\(token)",
                    token: token,
                    origin: "fg",
                    operation: "fullRun"
                ).acquired
                results.append(acquired)
                group.leave()
            }
        }
        start.signal()
        start.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(results.values.filter { $0 }.count, 1)
    }

    func testOwnershipAndResetSemantics() {
        XCTAssertTrue(registry.tryAcquire(
            pluginInstanceID: "instance",
            token: "token",
            origin: "bg",
            operation: "fullRun"
        ).acquired)
        XCTAssertEqual(registry.state()?.origin, "bg")
        XCTAssertEqual(registry.state()?.operation, "fullRun")
        XCTAssertTrue(registry.tryAcquire(
            pluginInstanceID: "instance",
            token: "token",
            origin: "bg",
            operation: "fullRun"
        ).acquired)
        XCTAssertFalse(registry.tryAcquire(
            pluginInstanceID: "instance",
            token: "other",
            origin: "fg",
            operation: "indexing"
        ).acquired)
        XCTAssertFalse(registry.release(pluginInstanceID: "other", token: "token"))
        XCTAssertFalse(registry.reset(for: "other"))
        XCTAssertTrue(registry.reset(for: "instance"))
        XCTAssertNil(registry.state())
    }
}

private final class LockedResults: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool] = []

    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Bool) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
