import XCTest
@testable import Ensu

private actor ModelOperationBarrier {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        open = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class ModelMemoryCoordinationTests: XCTestCase {
    func testOptionalWorkWaitsForBothCleanupAndCooldown() {
        var pressure = ModelMemoryPressureState()
        pressure.recordPressure(now: 10)
        XCTAssertTrue(pressure.suppressesOptionalWork(now: 100))
        XCTAssertTrue(pressure.requiresCleanup(appForeground: true, now: 100))
        pressure.didCleanUp()
        XCTAssertFalse(pressure.suppressesOptionalWork(now: 100))
        XCTAssertFalse(pressure.requiresCleanup(appForeground: true, now: 100))

        pressure.recordPressure(now: 100)
        pressure.didCleanUp()
        XCTAssertTrue(pressure.suppressesOptionalWork(now: 129.9))
        XCTAssertFalse(pressure.suppressesOptionalWork(now: 130))
        XCTAssertTrue(pressure.requiresCleanup(appForeground: false, now: 130))
    }

    func testNewPressureRestartsCooldownAndRequiresAnotherCleanup() {
        var pressure = ModelMemoryPressureState()
        pressure.recordPressure(now: 10)
        pressure.didCleanUp()
        pressure.recordPressure(now: 35)
        XCTAssertTrue(pressure.suppressesOptionalWork(now: 100))
        pressure.didCleanUp()
        XCTAssertTrue(pressure.suppressesOptionalWork(now: 64.9))
        XCTAssertFalse(pressure.suppressesOptionalWork(now: 65))
    }

    func testGateKeepsCleanupInsideLock() async {
        let gate = AsyncSerialGate()
        let barrier = ModelOperationBarrier()
        let cleaning = expectation(description: "cleanup started")
        let queued = expectation(description: "second operation queued")
        let completed = expectation(description: "operations completed")
        completed.expectedFulfillmentCount = 2
        var events: [String] = []
        Task {
            defer { completed.fulfill() }
            do {
                try await gate.withLock(
                    onEnter: { events.append("enter") },
                    onExit: {
                        cleaning.fulfill()
                        await barrier.wait()
                        events.append("cleanup")
                    }
                ) { events.append("work") }
            } catch { XCTFail("Unexpected failure: \(error)") }
        }
        await fulfillment(of: [cleaning], timeout: 2)
        Task {
            defer { completed.fulfill() }
            queued.fulfill()
            do {
                try await gate.withLock { events.append("next") }
            } catch { XCTFail("Unexpected failure: \(error)") }
        }
        await fulfillment(of: [queued], timeout: 2)
        XCTAssertEqual(events, ["enter", "work"])
        await barrier.release()
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(events, ["enter", "work", "cleanup", "next"])
    }

    func testGateRunsCleanupAfterFailureAndCancellation() async {
        enum Failure: Error { case inference }
        for cancel in [false, true] {
            let gate = AsyncSerialGate()
            let barrier = ModelOperationBarrier()
            let started = expectation(description: "operation started")
            let completed = expectation(description: "operation cleaned up")
            var events: [String] = []
            let task = Task {
                defer { completed.fulfill() }
                do {
                    try await gate.withLock(onExit: { events.append("cleanup") }) {
                        events.append("work")
                        started.fulfill()
                        await barrier.wait()
                        try Task.checkCancellation()
                        throw Failure.inference
                    }
                } catch {
                    XCTAssertTrue(cancel ? error is CancellationError : error is Failure)
                }
            }
            await fulfillment(of: [started], timeout: 2)
            if cancel { task.cancel() }
            await barrier.release()
            await fulfillment(of: [completed], timeout: 2)
            XCTAssertEqual(events, ["work", "cleanup"])
        }
    }
}
