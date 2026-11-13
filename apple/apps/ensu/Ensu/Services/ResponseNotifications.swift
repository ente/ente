import Combine
import UIKit
import UserNotifications

@MainActor
final class ResponseNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate,
    ResponseNotificationPosting
{
    static let shared = ResponseNotifications()
    struct Route: Equatable {
        let session: UUID
        let message: UUID
    }
    @Published var showPermissionContext = false
    @Published private(set) var canRequest = false
    @Published private(set) var promptOwner: UUID?
    @Published var pendingRoute: Route?
    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()
    private var checkingPermission = false
    private var countPromptOnAppearance = false
    private var foregroundObserver: NSObjectProtocol?
    private let prefix = "ensu.response."
    private var foregroundEpoch = 0
    private lazy var delivery = ResponseNotificationDelivery(
        center: center,
        isBackground: { [weak self] in self?.isBackground == true },
        foregroundEpoch: { [weak self] in self?.foregroundEpoch ?? -1 })

    var isBackground: Bool { UIApplication.shared.applicationState == .background }

    override private init() {
        super.init()
        center.delegate = self
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.foregroundEpoch += 1
                Task { @MainActor in await self?.refresh() }
            }
        }
    }

    private var campaign: ResponseNotificationCampaign {
        ResponseNotificationCampaign(
            count: defaults.integer(forKey: "ensu.notifications.count"),
            lastShown: defaults.object(forKey: "ensu.notifications.lastShown") as? Date,
            finished: defaults.bool(forKey: "ensu.notifications.finished"))
    }

    private func enabled(_ settings: UNNotificationSettings) -> Bool {
        [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            && settings.alertSetting == .enabled
    }

    func refresh() async {
        let settings = await center.notificationSettings()
        canRequest = settings.authorizationStatus == .notDetermined
        if enabled(settings) {
            defaults.set(true, forKey: "ensu.notifications.finished")
            showPermissionContext = false
        }
        if !isBackground {
            let delivered = await center.deliveredNotifications()
            guard !isBackground else { return }
            center.removeDeliveredNotifications(
                withIdentifiers: delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            )
        }
    }

    func onSend() { presentPermissionContext(automatic: true) }
    func fromSettings() { presentPermissionContext(automatic: false) }

    private func presentPermissionContext(automatic: Bool) {
        guard !checkingPermission, !showPermissionContext,
            UIApplication.shared.applicationState == .active
        else { return }
        checkingPermission = true
        Task {
            defer { checkingPermission = false }
            let settings = await center.notificationSettings()
            if enabled(settings) { defaults.set(true, forKey: "ensu.notifications.finished") }
            guard UIApplication.shared.applicationState == .active else { return }
            if !automatic && enabled(settings) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    await UIApplication.shared.open(url)
                }
                return
            }
            if automatic && !campaign.isEligible(enabled: enabled(settings), now: Date()) { return }
            canRequest = settings.authorizationStatus == .notDetermined
            countPromptOnAppearance = automatic
            promptOwner = nil
            showPermissionContext = true
        }
    }

    func claimPrompt(owner: UUID) {
        if showPermissionContext && promptOwner == nil { promptOwner = owner }
    }

    func releasePrompt(owner: UUID) {
        guard promptOwner == owner else { return }
        showPermissionContext = false
        promptOwner = nil
    }

    func didShowPermissionContext() {
        guard showPermissionContext, countPromptOnAppearance else { return }
        countPromptOnAppearance = false
        defaults.set(campaign.count + 1, forKey: "ensu.notifications.count")
        defaults.set(Date(), forKey: "ensu.notifications.lastShown")
    }

    func enable() {
        showPermissionContext = false
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            await refresh()
        }
    }

    func postResponse(
        id: UUID, session: UUID, message: UUID, query: String, body: String,
        isCurrent: @escaping @MainActor () -> Bool
    ) -> Task<Void, Never>? {
        delivery.post(
            noticeRequest(
                id: id, session: session, message: message,
                title: responseNotificationTitle(query), body: body),
            isCurrent: isCurrent)
    }

    func postInterruption(
        id: UUID, session: UUID, parent: UUID, isCurrent: @escaping @MainActor () -> Bool
    ) -> Task<Void, Never>? {
        delivery.post(
            noticeRequest(
                id: id, session: session, message: parent,
                title: "Response generation was interrupted", body: "Open Ensu to retry."),
            isCurrent: isCurrent)
    }

    private func noticeRequest(
        id: UUID, session: UUID, message: UUID, title: String, body: String
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = session.uuidString
        content.userInfo = ["session": session.uuidString, "message": message.uuidString]
        return UNNotificationRequest(
            identifier: prefix + id.uuidString, content: content, trigger: nil)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { self.isBackground ? [.banner, .list, .sound] : [] }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let session = (info["session"] as? String).flatMap(UUID.init(uuidString:))
        let message = (info["message"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            if let session, let message {
                self.pendingRoute = Route(session: session, message: message)
            }
            completionHandler()
        }
    }
}

@MainActor
protocol ResponseNotificationPosting {
    func postResponse(
        id: UUID, session: UUID, message: UUID, query: String, body: String,
        isCurrent: @escaping @MainActor () -> Bool
    ) -> Task<Void, Never>?
    func postInterruption(
        id: UUID, session: UUID, parent: UUID, isCurrent: @escaping @MainActor () -> Bool
    ) -> Task<Void, Never>?
}

@MainActor
protocol ResponseNotificationCenter: AnyObject {
    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: ResponseNotificationCenter {}

@MainActor
final class ResponseNotificationDelivery {
    private let center: any ResponseNotificationCenter
    private let isBackground: () -> Bool
    private let foregroundEpoch: () -> Int

    init(
        center: any ResponseNotificationCenter,
        isBackground: @escaping () -> Bool,
        foregroundEpoch: @escaping () -> Int
    ) {
        self.center = center
        self.isBackground = isBackground
        self.foregroundEpoch = foregroundEpoch
    }

    func post(
        _ request: UNNotificationRequest,
        isCurrent: @escaping @MainActor () -> Bool
    ) -> Task<Void, Never>? {
        guard isBackground(), isCurrent() else { return nil }
        let epoch = foregroundEpoch()
        let identifier = request.identifier
        let acknowledgement = AsyncStream<Error?> { continuation in
            center.add(request) { error in
                continuation.yield(error)
                continuation.finish()
            }
        }
        return Task { @MainActor in
            for await error in acknowledgement {
                if let error {
                    EnsuLogging.shared.logger("Notifications").warning(
                        "Could not post response notification", details: "\(error)")
                }
                if !isBackground() || foregroundEpoch() != epoch || !isCurrent() {
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    center.removeDeliveredNotifications(withIdentifiers: [identifier])
                }
            }
        }
    }
}
