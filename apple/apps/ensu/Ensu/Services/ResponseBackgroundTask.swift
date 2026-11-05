import BackgroundTasks
import UIKit

@MainActor
final class ResponseBackgroundTask {
    static let shared = ResponseBackgroundTask(notifications: ResponseNotifications.shared)
    private let notifications: any ResponseNotificationPosting
    private let scheduler: any ResponseBackgroundScheduling
    private struct Attempt {
        let id: UUID
        let session: UUID
        let parent: UUID
        let query: String
        let onCancel: () -> Void
        var resolved = false
    }
    private var attempt: Attempt?
    private var latestGeneration: UUID?
    private var generation: UUID? { attempt?.id }
    private var units: Int64 = 0
    private var reportedProgress = 0.0
    private var downloadStart: Double?
    private var responseTokens: Int64 = 1

    init(
        notifications: any ResponseNotificationPosting,
        scheduler: any ResponseBackgroundScheduling = SystemResponseBackgroundScheduler()
    ) {
        self.notifications = notifications
        self.scheduler = scheduler
    }

    func begin(
        _ id: UUID, session: UUID, parent: UUID, query: String, onCancel: @escaping () -> Void
    ) {
        if let generation { end(generation, success: false) }
        attempt = Attempt(
            id: id, session: session, parent: parent, query: query, onCancel: onCancel)
        latestGeneration = id
        units = 0
        reportedProgress = 0
        downloadStart = nil
        responseTokens = 1
        scheduler.begin(id) { [weak self] in self?.expire(id) }
    }

    func update(
        _ id: UUID, status: String, completed: Int64 = 0, total: Int64 = -1
    ) {
        guard generation == id else { return }
        units = completed
        downloadStart = nil
        report(
            id, status: status,
            fraction: 0.1 * Double(completed) / Double(max(total, completed + 1)))
    }

    func prepareAnswer(_ id: UUID, maxTokens: UInt32) {
        guard generation == id else { return }
        responseTokens = max(1, Int64(maxTokens))
    }

    func promptProgress(_ id: UUID, completed: Int32, total: Int32) {
        guard generation == id else { return }
        report(
            id, status: "Reading conversation",
            fraction: 0.1 + 0.4 * Double(completed) / Double(max(1, total)))
    }

    func responseProgress(_ id: UUID, tokens: Int) {
        report(
            id, status: "Writing response",
            fraction: 0.5 + 0.5 * Double(tokens) / Double(max(responseTokens, Int64(tokens) + 1)))
    }

    func advancePreparation(_ id: UUID) {
        guard generation == id else { return }
        update(id, status: "Remembering earlier messages", completed: units + 1)
    }

    func downloadProgress(_ id: UUID, completed: Int64, total: Int64?) {
        guard generation == id else { return }
        let start = downloadStart ?? reportedProgress
        downloadStart = start
        report(
            id, status: "Downloading model",
            fraction: start + max(0, 0.1 - start) / 2
                * Double(completed) / Double(max(total ?? 0, completed + 1)))
    }

    private func report(_ id: UUID, status: String, fraction: Double) {
        guard generation == id else { return }
        reportedProgress = max(reportedProgress, min(fraction, 0.999999999))
        scheduler.update(
            id, status: status, completed: Int64(reportedProgress * 1_000_000_000),
            total: 1_000_000_000, force: false)
    }

    func complete(_ id: UUID, message: UUID, text: String) async {
        guard let attempt = resolve(id) else { return }
        let body = responseNotificationPreview(stripHiddenPartsText(text: text))
        scheduler.update(id, status: "Response ready", completed: 1, total: 1, force: true)
        if !body.isEmpty {
            let delivery = notifications.postResponse(
                id: id, session: attempt.session, message: message,
                query: attempt.query, body: body, isCurrent: { self.latestGeneration == id })
            await delivery?.value
        }
        end(id, success: true)
    }

    func finish(_ id: UUID) {
        guard let attempt = resolve(id) else { return }
        let delivery = notifications.postInterruption(
            id: id, session: attempt.session, parent: attempt.parent,
            isCurrent: { self.latestGeneration == id })
        Task { @MainActor in
            await delivery?.value
            end(id)
        }
    }

    func end(_ id: UUID, success: Bool = false) {
        guard generation == id else { return }
        attempt = nil
        scheduler.end(id, success: success)
    }

    private func resolve(_ id: UUID) -> Attempt? {
        guard let attempt, attempt.id == id, !attempt.resolved else { return nil }
        self.attempt?.resolved = true
        return attempt
    }

    private func expire(_ id: UUID) {
        guard let attempt, attempt.id == id else { return }
        if let attempt = resolve(id) {
            _ = notifications.postInterruption(
                id: id, session: attempt.session, parent: attempt.parent,
                isCurrent: { self.latestGeneration == id })
        }
        end(id)
        attempt.onCancel()
    }

}

@MainActor
protocol ResponseBackgroundScheduling {
    func begin(_ id: UUID, onExpiration: @escaping @MainActor () -> Void)
    func update(_ id: UUID, status: String, completed: Int64, total: Int64, force: Bool)
    func end(_ id: UUID, success: Bool)
}

@MainActor
private final class SystemResponseBackgroundScheduler: ResponseBackgroundScheduling {
    private var generation: UUID?
    private var lease: UUID?
    private var observers: [NSObjectProtocol] = []
    private var fallback: UIBackgroundTaskIdentifier = .invalid
    private var continued: BGTask?
    private var requestIdentifier: String?
    private var status = "Preparing response"
    private var units: Int64 = 0
    private var total: Int64 = 1
    private var lastUpdate = Date.distantPast

    func begin(_ id: UUID, onExpiration: @escaping @MainActor () -> Void) {
        generation = id
        status = "Preparing response"
        units = 0
        total = 1
        lastUpdate = .distantPast
        observers = [
            NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.beginBackgroundWork(id, onExpiration: onExpiration)
                }
            },
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.generation == id else { return }
                    self.endBackgroundWork(success: true)
                }
            },
        ]
        if UIApplication.shared.applicationState != .active {
            beginBackgroundWork(id, onExpiration: onExpiration)
        }
    }

    private func beginBackgroundWork(_ id: UUID, onExpiration: @escaping @MainActor () -> Void) {
        guard generation == id, lease == nil else { return }
        let lease = UUID()
        self.lease = lease
        fallback = UIApplication.shared.beginBackgroundTask(withName: "Generate response") {
            [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.lease == lease, self.continued == nil else { return }
                onExpiration()
            }
        }
        guard #available(iOS 26.0, *), UIApplication.shared.applicationState != .background else {
            return
        }
        let identifier = "io.ente.ensu.response." + lease.uuidString
        requestIdentifier = identifier
        guard
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: identifier, using: .main,
                launchHandler: { [weak self] task in
                    MainActor.assumeIsolated {
                        guard let self else { task.setTaskCompleted(success: false); return }
                        self.adopt(task, lease: lease, onExpiration: onExpiration)
                    }
                })
        else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Generating response", subtitle: status)
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request) } catch {
            EnsuLogging.shared.logger("Generation").info(
                "Using limited background time", details: "\(error)")
        }
    }

    @available(iOS 26.0, *)
    private func adopt(_ task: BGTask, lease: UUID, onExpiration: @escaping @MainActor () -> Void) {
        guard self.lease == lease, let id = generation,
            let task = task as? BGContinuedProcessingTask
        else {
            task.setTaskCompleted(success: false)
            return
        }
        continued = task
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard self?.lease == lease else { return }
                onExpiration()
            }
        }
        endFallback()
        update(id, status: status, completed: units, total: total, force: true)
    }

    func update(_ id: UUID, status: String, completed: Int64, total: Int64, force: Bool) {
        guard generation == id else { return }
        let changedStage = self.status != status
        self.status = status
        units = completed
        self.total = total
        guard #available(iOS 26.0, *), let task = continued as? BGContinuedProcessingTask,
            force || changedStage || Date().timeIntervalSince(lastUpdate) >= 0.5
        else { return }
        lastUpdate = Date()
        task.updateTitle("Generating response", subtitle: status)
        task.progress.totalUnitCount = total
        task.progress.completedUnitCount = completed
    }

    func end(_ id: UUID, success: Bool) {
        guard generation == id else { return }
        generation = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        endBackgroundWork(success: success)
    }

    private func endBackgroundWork(success: Bool) {
        lease = nil
        let task = continued
        continued = nil
        task?.setTaskCompleted(success: success)
        if let requestIdentifier {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: requestIdentifier)
        }
        requestIdentifier = nil
        endFallback()
    }

    private func endFallback() {
        guard fallback != .invalid else { return }
        UIApplication.shared.endBackgroundTask(fallback)
        fallback = .invalid
    }
}
