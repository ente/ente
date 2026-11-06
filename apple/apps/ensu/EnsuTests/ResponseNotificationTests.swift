import Foundation
import UserNotifications
import XCTest
import os
@testable import Ensu

final class ResponseNotificationTests: XCTestCase {
    func testPermissionCampaignEligibility() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cases: [(Int, TimeInterval?, Bool)] = [
            (0, nil, true),
            (1, 72 * 3600 - 1, false),
            (1, 72 * 3600, true),
            (1, -1, false),
            (2, 72 * 3600, true),
            (3, 30 * 86400, false),
        ]
        for (count, elapsed, expected) in cases {
            let campaign = ResponseNotificationCampaign(
                count: count, lastShown: elapsed.map { now.addingTimeInterval(-$0) },
                finished: false)
            XCTAssertEqual(campaign.isEligible(enabled: false, now: now), expected)
        }
        XCTAssertFalse(
            ResponseNotificationCampaign(count: 1, lastShown: nil, finished: true)
                .isEligible(enabled: false, now: now))
        XCTAssertFalse(
            ResponseNotificationCampaign(count: 0, lastShown: nil, finished: false)
                .isEligible(enabled: true, now: now))
    }

    func testPreviewOmitsFormatting() {
        XCTAssertEqual(
            responseNotificationPreview(
                "**Hello** *world*. [Read more](https://example.com)."),
            "Hello world. Read more.")
        XCTAssertEqual(
            responseNotificationPreview("## Ready"), "Ready")
        XCTAssertEqual(responseNotificationPreview("```python\na = 1\n```"), "a = 1")
    }

    func testQueryTitleTruncatesAtThirtyVisibleCharacters() {
        XCTAssertEqual(responseNotificationTitle("A short question?"), "A short question?")
        let thirty = String(repeating: "a", count: 30)
        XCTAssertEqual(responseNotificationTitle(thirty), thirty)
        XCTAssertEqual(responseNotificationTitle(thirty + "b"), thirty + "…")
        let prefix = String(repeating: "a", count: 29)
        XCTAssertEqual(responseNotificationTitle(prefix + "👨‍👩‍👧‍👦?"), prefix + "👨‍👩‍👧‍👦…")
        XCTAssertEqual(responseNotificationTitle(prefix + "e\u{301}?"), prefix + "e\u{301}…")
        XCTAssertEqual(responseNotificationTitle("  Explain\nthis  "), "Explain this")
        XCTAssertEqual(responseNotificationTitle("  "), "Ensu")
    }

    @MainActor
    func testGenerationProgressRemainsDeterminateUntilSaved() async {
        let harness = NotificationDeliveryHarness()
        addTeardownBlock { await harness.cleanup() }
        harness.state.isBackground = false
        let id = harness.begin()
        harness.background.downloadProgress(id, completed: 10, total: 100)
        harness.background.downloadProgress(id, completed: 100, total: 100)
        harness.background.update(id, status: "Preparing conversation", completed: 3, total: 4)
        harness.background.advancePreparation(id)
        harness.background.prepareAnswer(id, maxTokens: 1000)
        harness.background.promptProgress(id, completed: 0, total: 512)
        harness.background.promptProgress(id, completed: 256, total: 512)
        harness.background.promptProgress(id, completed: 512, total: 512)
        harness.background.responseProgress(id, tokens: 100)
        harness.background.responseProgress(id, tokens: 2000)
        let progress = harness.scheduler.updates.map { Double($0.completed) / Double($0.total) }
        XCTAssertTrue(
            harness.scheduler.updates.allSatisfy {
                $0.total > 0 && $0.completed < $0.total
            })
        XCTAssertTrue(zip(progress, progress.dropFirst()).allSatisfy { $0 < $1 })
        await harness.background.complete(id, message: UUID(), text: "Saved answer")
        XCTAssertEqual(harness.scheduler.updates.last?.completed, 1)
        XCTAssertEqual(harness.scheduler.updates.last?.total, 1)
        XCTAssertTrue(harness.scheduler.expirations.isEmpty)
        XCTAssertTrue(harness.center.requests.isEmpty)
        harness.state.isBackground = true
        for text in ["", "<think>outer<think>inner</think>hidden</think>"] {
            let id = harness.begin()
            await harness.background.complete(id, message: UUID(), text: text)
            harness.background.finish(id)
            XCTAssertEqual(harness.scheduler.updates.last?.completed, 1)
            XCTAssertEqual(harness.scheduler.updates.last?.total, 1)
            XCTAssertTrue(harness.scheduler.expirations.isEmpty)
            XCTAssertTrue(harness.center.requests.isEmpty)
        }
    }

    @MainActor
    func testCompletionAndFailureSurviveExpiryBeforeAcknowledgement() async {
        for succeeded in [false, true] {
            let harness = NotificationDeliveryHarness()
            addTeardownBlock { await harness.cleanup() }
            let id = harness.begin()
            var completion: Task<Void, Never>?
            if succeeded {
                let submitted = expectation(description: "Completion enqueued")
                harness.center.onEnqueue = { submitted.fulfill() }
                completion = Task { @MainActor in
                    await harness.background.complete(
                        id, message: UUID(),
                        text: "<think>outer<think>inner</think>hidden</think>**Saved answer**")
                }
                await fulfillment(of: [submitted], timeout: 1)
            } else {
                harness.background.finish(id)
            }
            XCTAssertEqual(
                harness.center.requests.map(\.content.title),
                [succeeded ? "response" : "interruption"])
            if succeeded {
                XCTAssertEqual(harness.center.requests.first?.content.body, "Saved answer")
            }
            XCTAssertEqual(harness.scheduler.expirations.keys.first, id)
            harness.scheduler.expirations[id]?()
            harness.background.finish(id)
            XCTAssertNil(harness.scheduler.expirations.keys.first)
            XCTAssertEqual(harness.center.requests.count, 1)
            harness.center.acknowledgeNext()
            await completion?.value
            await harness.notices.lastDelivery?.value
            XCTAssertTrue(harness.center.removedPending.isEmpty)
            XCTAssertTrue(harness.center.removedDelivered.isEmpty)
        }
    }

    @MainActor
    func testForegroundingDuringAcknowledgementRemovesTheNotice() async {
        for backgroundAgain in [false, true] {
            let harness = NotificationDeliveryHarness()
            addTeardownBlock { await harness.cleanup() }
            let id = harness.begin()
            harness.background.finish(id)
            if backgroundAgain { harness.scheduler.expirations[id]?() }
            harness.state.isBackground = backgroundAgain
            harness.state.foregroundEpoch += 1
            harness.center.acknowledgeNext()
            await harness.notices.lastDelivery?.value
            XCTAssertEqual(harness.center.removedPending, [id.uuidString])
            XCTAssertEqual(harness.center.removedDelivered, [id.uuidString])
        }
    }

    @MainActor
    func testNewGenerationDuringAcknowledgementRemovesOnlyTheOldNotice() async {
        let harness = NotificationDeliveryHarness()
        addTeardownBlock { await harness.cleanup() }
        let old = harness.begin()
        harness.background.finish(old)
        let new = harness.begin()
        harness.center.acknowledgeNext()
        await harness.notices.lastDelivery?.value
        XCTAssertEqual(harness.center.removedPending, [old.uuidString])
        XCTAssertEqual(harness.center.removedDelivered, [old.uuidString])
        XCTAssertEqual(harness.scheduler.expirations.keys.first, new)
        harness.background.end(new)
    }

    @MainActor
    func testUserCancellationNeverEnqueues() async {
        let harness = NotificationDeliveryHarness()
        addTeardownBlock { await harness.cleanup() }
        let cancelled = harness.begin()
        harness.background.end(cancelled)
        harness.background.finish(cancelled)
        XCTAssertTrue(harness.center.requests.isEmpty)
        XCTAssertTrue(harness.scheduler.expirations.isEmpty)
    }
    @MainActor
    func testIndependentDownloadKeepsItsLeaseWhenConcurrentResponseEnds() async throws {
        let delivery = NotificationDeliveryHarness()
        addTeardownBlock { await delivery.cleanup() }
        let response = delivery.begin()
        let background = RecordingDownloadBackgroundScheduler()
        let responseDownload = ControlledAssetDownload()
        let independentDownload = ControlledAssetDownload()
        let responseStore = AssetStore(
            core: DelayedAssetStoreCore(download: responseDownload), backgroundDownloads: background
        )
        let independentStore = AssetStore(
            core: DelayedAssetStoreCore(download: independentDownload),
            backgroundDownloads: background)
        let owned = Task {
            try await responseStore.download(
                assets: [transcriptionModelAsset()],
                context: .externallyCovered { progress in
                    Task { @MainActor in
                        delivery.background.downloadProgress(
                            response, completed: progress.downloadedBytes,
                            total: progress.totalBytes)
                    }
                }
            ) { _ in }
        }
        addTeardownBlock {
            owned.cancel(); _ = await owned.result
        }
        await fulfillment(of: [responseDownload.entered], timeout: 5)
        XCTAssertTrue(background.active.isEmpty)

        let routed = expectation(description: "Caller-owned download progress")
        delivery.scheduler.onUpdate = { update in
            if update.status == "Downloading model" { routed.fulfill() }
        }
        responseDownload.reportProgress()
        await fulfillment(of: [routed], timeout: 1)
        XCTAssertEqual(delivery.scheduler.updates.last?.id, response)

        let independent = Task {
            try await independentStore.download(assets: [transcriptionModelAsset()]) { _ in }
        }
        addTeardownBlock {
            independent.cancel(); _ = await independent.result
        }
        await fulfillment(of: [independentDownload.entered], timeout: 5)
        let lease = try XCTUnwrap(background.active.keys.first)
        XCTAssertEqual(background.active.count, 1)

        delivery.background.end(response)
        owned.cancel()
        _ = await owned.result
        XCTAssertEqual(Set(background.active.keys), [lease])
        let progress = expectation(description: "Independent download still updates its lease")
        background.onUpdate = { progress.fulfill() }
        independentDownload.reportProgress()
        await fulfillment(of: [progress], timeout: 5)
        XCTAssertEqual(background.updated, [lease])
        independentDownload.finish()
        try await independent.value
        XCTAssertTrue(background.active.isEmpty)
        XCTAssertEqual(background.ended.count, 1)
        XCTAssertEqual(background.ended.first?.id, lease)
        XCTAssertEqual(background.ended.first?.success, true)
    }

    @MainActor
    func testModelRecoveryPreservesCallerCoverageThroughBothEntryPoints() async throws {
        try llmInitBackend()
        for conversationEntry in [false, true] {
            let delivery = NotificationDeliveryHarness()
            addTeardownBlock { await delivery.cleanup() }
            let response = delivery.begin()
            let background = RecordingDownloadBackgroundScheduler()
            let download = ControlledAssetDownload()
            let store = AssetStore(
                core: DelayedAssetStoreCore(download: download, initiallyDownloaded: true),
                backgroundDownloads: background)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            let provider = LlmProvider(
                assetStore: store,
                transcriber: Transcriber(
                    modelDir: directory.path,
                    vadModelPath: directory.appendingPathComponent("vad").path),
                knowledgeEmbedding: ConfigDefaults.shared.knowledgeEmbedding)
            let selection = LlmModelSelection(
                id: resolveEffectiveModelId(
                    surface: .ios, totalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                    preferredModelId: nil),
                contextLength: nil)
            let context = AssetDownloadContext.externallyCovered { progress in
                Task { @MainActor in
                    delivery.background.downloadProgress(
                        response, completed: progress.downloadedBytes, total: progress.totalBytes)
                }
            }
            let task = Task {
                if conversationEntry {
                    try await provider.withConversationContext(selection, downloadContext: context)
                    { _, _ in
                        XCTFail("Invalid model must enter recovery before conversation work")
                    }
                } else {
                    try await provider.ensureModelReady(selection, downloadContext: context) { _ in
                    }
                }
            }
            addTeardownBlock {
                task.cancel(); _ = await task.result
            }
            await fulfillment(of: [download.entered], timeout: 5)
            XCTAssertTrue(background.active.isEmpty)
            let progress = expectation(description: "Recovery preserves caller progress")
            delivery.scheduler.onUpdate = { _ in progress.fulfill() }
            download.reportProgress()
            await fulfillment(of: [progress], timeout: 1)
            XCTAssertEqual(delivery.scheduler.updates.last?.id, response)
            task.cancel()
            _ = await task.result
            XCTAssertTrue(background.ended.isEmpty)
            XCTAssertEqual(delivery.scheduler.expirations.keys.first, response)
        }
    }

}

@MainActor
private final class NotificationDeliveryState {
    var isBackground = true
    var foregroundEpoch = 0
}

@MainActor
private final class DelayedNotificationCenter: ResponseNotificationCenter {
    private(set) var requests: [UNNotificationRequest] = []
    private var acknowledgements: [@Sendable (Error?) -> Void] = []
    private(set) var removedPending: [String] = []
    private(set) var removedDelivered: [String] = []
    var onEnqueue: (() -> Void)?

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    ) {
        requests.append(request)
        if let completionHandler { acknowledgements.append(completionHandler) }
        onEnqueue?()
    }

    func acknowledgeAll() {
        while !acknowledgements.isEmpty { acknowledgeNext() }
    }

    func acknowledgeNext() {
        guard !acknowledgements.isEmpty else {
            XCTFail("No notification is awaiting acknowledgement")
            return
        }
        acknowledgements.removeFirst()(nil)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPending.append(contentsOf: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDelivered.append(contentsOf: identifiers)
    }
}

@MainActor
private final class TestResponseNotices: ResponseNotificationPosting {
    private let delivery: ResponseNotificationDelivery
    private(set) var lastDelivery: Task<Void, Never>?

    init(center: DelayedNotificationCenter, state: NotificationDeliveryState) {
        delivery = ResponseNotificationDelivery(
            center: center,
            isBackground: { state.isBackground },
            foregroundEpoch: { state.foregroundEpoch })
    }

    func postResponse(
        id: UUID, session: UUID, message: UUID, query: String, body: String,
        isCurrent: @escaping @MainActor () -> Bool
    ) -> Task<Void, Never>? {
        post(id: id, title: "response", body: body, isCurrent: isCurrent)
    }

    func postInterruption(
        id: UUID, session: UUID, parent: UUID, isCurrent: @escaping @MainActor () -> Bool
    ) -> Task<Void, Never>? {
        post(id: id, title: "interruption", isCurrent: isCurrent)
    }

    private func post(
        id: UUID, title: String, body: String = "", isCurrent: @escaping @MainActor () -> Bool
    ) -> Task<Void, Never>? {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: id.uuidString, content: content, trigger: nil)
        lastDelivery = delivery.post(request, isCurrent: isCurrent)
        return lastDelivery
    }
}

@MainActor
private final class NotificationDeliveryHarness {
    let state = NotificationDeliveryState()
    let center = DelayedNotificationCenter()
    let notices: TestResponseNotices
    let background: ResponseBackgroundTask
    let scheduler = RecordingResponseBackgroundScheduler()

    init() {
        notices = TestResponseNotices(center: center, state: state)
        background = ResponseBackgroundTask(notifications: notices, scheduler: scheduler)
    }

    func begin() -> UUID {
        let id = UUID()
        background.begin(id, session: UUID(), parent: UUID(), query: "Question") {}
        return id
    }

    func cleanup() async {
        if let id = scheduler.expirations.keys.first { background.end(id) }
        center.acknowledgeAll()
        await notices.lastDelivery?.value
    }
}

@MainActor
private final class RecordingResponseBackgroundScheduler: ResponseBackgroundScheduling {
    struct Update {
        let id: UUID
        let status: String
        let completed: Int64
        let total: Int64
    }
    private(set) var expirations: [UUID: @MainActor () -> Void] = [:]
    private(set) var updates: [Update] = []
    var onUpdate: ((Update) -> Void)?

    func begin(_ id: UUID, onExpiration: @escaping @MainActor () -> Void) {
        expirations[id] = onExpiration
    }

    func update(_ id: UUID, status: String, completed: Int64, total: Int64, force: Bool) {
        guard expirations[id] != nil else { return }
        let update = Update(id: id, status: status, completed: completed, total: total)
        updates.append(update)
        onUpdate?(update)
    }

    func end(_ id: UUID, success: Bool) {
        expirations[id] = nil
    }
}

@MainActor
private final class RecordingDownloadBackgroundScheduler: AssetDownloadBackgroundScheduling {
    private(set) var active: [UUID: @Sendable () -> Void] = [:]
    private(set) var updated: [UUID] = []
    private(set) var ended: [(id: UUID, success: Bool)] = []
    var onUpdate: (() -> Void)?

    func begin(onExpiration: @escaping @Sendable () -> Void) -> UUID? {
        let id = UUID()
        active[id] = onExpiration
        return id
    }

    func update(id: UUID, downloadedBytes: Int64, totalBytes: Int64?) {
        guard active[id] != nil else { return }
        updated.append(id)
        onUpdate?()
    }

    func end(id: UUID, success: Bool) {
        active[id] = nil
        ended.append((id, success))
    }
}

@MainActor
private final class ControlledAssetDownload {
    let entered = XCTestExpectation(description: "Asset download entered")
    private var continuation: CheckedContinuation<Void, Error>?
    private var callback: (any AssetDownloadCallback)?

    func run(callback: any AssetDownloadCallback) async throws {
        self.callback = callback
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        } onCancel: {
            Task { @MainActor in self.finish(error: CancellationError()) }
        }
    }

    func reportProgress() {
        callback?.onProgress(
            progress: .init(
                label: "Independent pack", queued: false, downloadedBytes: 10, totalBytes: 100,
                percentage: 10, status: "Downloading", logLine: nil))
    }

    func finish(error: Error? = nil) {
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}

private final class DelayedAssetStoreCore: AssetStoreCore, @unchecked Sendable {
    private let controlledDownload: ControlledAssetDownload
    private let downloaded: OSAllocatedUnfairLock<Bool>

    init(download: ControlledAssetDownload, initiallyDownloaded: Bool = false) {
        controlledDownload = download
        downloaded = OSAllocatedUnfairLock(initialState: initiallyDownloaded)
        super.init(noHandle: NoHandle())
    }

    required init(unsafeFromHandle: UInt64) {
        fatalError("Only the controlled initializer is used")
    }

    override func isDownloaded(asset: Asset) -> Bool { downloaded.withLock { $0 } }
    override func llmModelPath(asset: Asset) -> String? { nil }
    override func cleanupObsoleteChatModels(modelId: String) throws {}
    override func removeDownloaded(asset: Asset) -> Bool {
        downloaded.withLock {
            let existed = $0
            $0 = false
            return existed
        }
    }

    override func download(
        assets: [Asset], callback: any AssetDownloadCallback, cancellation: CancellationToken
    ) async throws {
        try await controlledDownload.run(callback: callback)
    }
}
