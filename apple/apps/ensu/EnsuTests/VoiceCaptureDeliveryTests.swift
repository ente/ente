import Foundation
import XCTest
@testable import Ensu

@MainActor
final class VoiceCaptureDeliveryTests: XCTestCase {
    func testStopDrainsAnAcceptedBufferBeforeClosingTheStream() async throws {
        let owner = DictationSession(live: false)
        let stream = try DictationStream(session: owner, sampleRate: 16000, channels: 1)
        defer { try? stream.abandon(reason: .discard) }
        let copying = expectation(description: "audio copy started")
        let stopping = expectation(description: "stop requested")
        let delivered = expectation(description: "audio delivered")
        let drained = expectation(description: "capture drained")
        let releaseCopy = DispatchSemaphore(value: 0)
        let drainCompleted = DispatchSemaphore(value: 0)
        defer { releaseCopy.signal() }
        let delivery = LiveCaptureDelivery(
            stream: stream, sampleRate: 16000,
            level: { _ in delivered.fulfill() },
            interrupted: { error in
                XCTFail("Unexpected capture failure: \(String(describing: error))")
            }
        )

        DispatchQueue.global().async {
            delivery.accept(frames: 1600) {
                copying.fulfill()
                guard releaseCopy.wait(timeout: .now() + 5) == .success else {
                    XCTFail("Audio copy was not released")
                    return nil
                }
                return Array(repeating: 0.25, count: 1600)
            }
        }
        await fulfillment(of: [copying], timeout: 2)
        DispatchQueue.global().async {
            stopping.fulfill()
            delivery.close()
            delivery.drain {
                do { try stream.stop(reason: .done) } catch { XCTFail("\(error)") }
                drained.fulfill()
                drainCompleted.signal()
            }
        }
        await fulfillment(of: [stopping], timeout: 2)
        XCTAssertEqual(drainCompleted.wait(timeout: .now() + 0.1), .timedOut)
        releaseCopy.signal()
        await fulfillment(of: [delivered, drained], timeout: 2, enforceOrder: true)
        XCTAssertEqual(try stream.feed(pcmLe: Data([0, 0])), .closed)
        delivery.accept(frames: 1600) {
            XCTFail("Closed capture accepted another buffer")
            return nil
        }
    }
}
