import Flutter
import Foundation
import UIKit
import WatchConnectivity

/// iOS runner bridge from Flutter to the Ente Auth watch companion.
///
/// `syncTokens` accepts the version-1 map and forwards a property-list copy
/// through `WCSession.updateApplicationContext`. That map carries plaintext
/// base32 `secret` strings. Watch Connectivity is the transport protection;
/// this plugin does not apply an app-level cipher, does not compute OTP, and
/// must not log the dictionary, secrets, or codes. A watch copy request
/// calls Dart for the current code and sets the pasteboard. The Watch
/// Connectivity reply never includes that code.
public final class EnteWatchBridgePlugin: NSObject, FlutterPlugin, WCSessionDelegate {
    public static let channelName = "io.ente.auth/watch"

    /// `WCSession.delegate` is weak. This singleton keeps the delegate alive.
    private static let shared = EnteWatchBridgePlugin()

    /// Serializes the single pending context. WCSession callbacks hop here.
    private let sessionQueue = DispatchQueue(label: "io.ente.auth.watch.bridge")
    private var hasStartedSession = false
    /// True while `activate()` has been called and the callback has not returned.
    private var activationInFlight = false
    /// Set when activation finishes without `.activated`. Cleared on the next attempt.
    private var activationFailed = false
    /// Latest unsent context only. A newer `syncTokens` replaces it.
    private var pendingContext: [String: Any]?
    /// Result for `pendingContext` when that call is still waiting to send.
    private var pendingResult: FlutterResult?
    /// Same channel Dart uses. Native calls `currentCode` on it during a copy.
    private var methodChannel: FlutterMethodChannel?
    /// Latest watch copy. A slower Dart result for an earlier request must not paste.
    private var copyGeneration: UInt64 = 0

    private override init() {
        super.init()
    }

    /// Registers the channel and activates `WCSession` when the device supports it.
    ///
    /// From `AppDelegate`:
    /// `EnteWatchBridgePlugin.register(with: self.registrar(forPlugin: "EnteWatchBridgePlugin")!)`
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = shared
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.activateSessionIfSupported()
    }

    /// Same registration when the caller already has a binary messenger.
    public static func register(with messenger: FlutterBinaryMessenger) {
        let instance = shared
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: messenger
        )
        instance.methodChannel = channel
        channel.setMethodCallHandler { call, result in
            instance.handle(call, result: result)
        }
        instance.activateSessionIfSupported()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "syncTokens":
            syncTokens(call.arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error _: Error?
    ) {
        // The NSError from activation is not logged and is not copied into the
        // Flutter error. The latest context is sent only after `.activated`.
        let activated = activationState == .activated
        // Valid only after activation. An unpaired watch must not receive the
        // buffered context on a later pairing.
        let paired = activated && session.isPaired
        sessionQueue.async {
            self.activationInFlight = false
            if activated {
                self.activationFailed = false
                if !paired {
                    self.dropPendingContextBecauseUnpaired()
                    return
                }
                self.sendPendingContext(on: session)
                return
            }
            self.activationFailed = true
            self.failPendingResult()
        }
    }

    public func sessionDidBecomeInactive(_: WCSession) {
        // Required by WCSessionDelegate while the session moves to a new watch.
        // The pending context stays until deactivate, which drops it.
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        // Apple's sample reactivates so the replacement watch can take the session.
        // Drop the unsent context before activate so the new session cannot flush it.
        sessionQueue.sync {
            self.dropPendingContextBecauseUnpaired()
            self.activationFailed = false
            self.activationInFlight = true
        }
        session.activate()
    }

    public func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.activationState == .activated, !session.isPaired else { return }
        sessionQueue.async {
            self.dropPendingContextBecauseUnpaired()
        }
    }

    public func sessionReachabilityDidChange(_: WCSession) {
        // Unreachable is transient (locked phone, out of range). Keep pendingContext.
    }

    public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard (message["action"] as? String) == "copyCode" else {
            replyHandler(["ok": false, "error": "invalid"])
            return
        }
        guard let id = message["id"] as? String, !id.isEmpty else {
            replyHandler(["ok": false, "error": "invalid"])
            return
        }
        // The message is the id only. Do not read or log any other key.
        _ = session
        DispatchQueue.main.async {
            self.copyCodeFromDart(id: id, replyHandler: replyHandler)
        }
    }

    private func activateSessionIfSupported() {
        guard WCSession.isSupported() else {
            return
        }
        let session = WCSession.default
        session.delegate = self
        let shouldActivate: Bool = sessionQueue.sync {
            if hasStartedSession {
                return false
            }
            hasStartedSession = true
            activationInFlight = true
            return true
        }
        if shouldActivate {
            session.activate()
        }
    }

    /// Starts activation again after a failed attempt. A second call while one
    /// is in flight is ignored.
    private func ensureActivating(_ session: WCSession) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard session.activationState != .activated else { return }
        guard !activationInFlight else { return }
        activationFailed = false
        activationInFlight = true
        session.activate()
    }

    private func syncTokens(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let arguments else {
            result(BridgeFailure.invalidPayload.flutterError)
            return
        }
        let context: [String: Any]
        do {
            context = try propertyListDictionary(from: arguments)
        } catch {
            result(BridgeFailure.invalidPayload.flutterError)
            return
        }
        guard WCSession.isSupported() else {
            result(BridgeFailure.connectivityUnavailable.flutterError)
            return
        }
        let session = WCSession.default
        sessionQueue.async {
            self.deliver(context, to: session, result: result)
        }
    }

    private func deliver(
        _ context: [String: Any],
        to session: WCSession,
        result: @escaping FlutterResult
    ) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard session.activationState == .activated else {
            // The replaced call was not submitted. Do not report success.
            if let previous = pendingResult {
                pendingResult = nil
                reply(previous, BridgeFailure.syncFailed.flutterError)
            }
            pendingContext = context
            pendingResult = result
            ensureActivating(session)
            return
        }
        // `isPaired` is valid once the session is activated. Do not call
        // `updateApplicationContext` while unpaired: that dictionary holds
        // plaintext seeds, and a later pairing must not inherit it.
        guard session.isPaired else {
            reply(result, BridgeFailure.connectivityUnavailable.flutterError)
            return
        }
        activationFailed = false
        if let previous = pendingResult {
            pendingResult = nil
            reply(previous, BridgeFailure.syncFailed.flutterError)
        }
        pendingContext = nil
        do {
            try session.updateApplicationContext(context)
            reply(result, nil)
        } catch {
            reply(result, BridgeFailure.syncFailed.flutterError)
        }
    }

    private func sendPendingContext(on session: WCSession) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard session.activationState == .activated, let context = pendingContext else {
            return
        }
        let result = pendingResult
        pendingResult = nil
        pendingContext = nil
        do {
            try session.updateApplicationContext(context)
            if let result {
                reply(result, nil)
            }
        } catch {
            if pendingContext == nil {
                pendingContext = context
            }
            if let result {
                reply(result, BridgeFailure.syncFailed.flutterError)
            }
        }
    }

    /// The phone does not keep a second copy of the seeds. Dropping the unsent
    /// context avoids flushing it to a watch that is paired later. The next
    /// CodesUpdatedEvent or cold start syncs again from Dart. This does not
    /// delete the phone vault.
    private func dropPendingContextBecauseUnpaired() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        pendingContext = nil
        failPendingResult()
    }

    private func failPendingResult() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard let result = pendingResult else {
            return
        }
        pendingResult = nil
        reply(result, BridgeFailure.syncFailed.flutterError)
    }

    /// Asks Dart for the current code (phone clock, including the user's time
    /// offset via `getOTP`) and writes the pasteboard. The Watch Connectivity
    /// reply is only `ok` and a short error code.
    private func copyCodeFromDart(id: String, replyHandler: @escaping ([String: Any]) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        copyGeneration &+= 1
        let generation = copyGeneration
        guard let methodChannel else {
            replyHandler(["ok": false, "error": "unavailable"])
            return
        }
        let task = WatchCopyBackgroundTask()
        task.begin()
        methodChannel.invokeMethod("currentCode", arguments: ["id": id]) { result in
            DispatchQueue.main.async {
                defer { task.end() }
                // A later copy of another account owns the pasteboard.
                guard generation == self.copyGeneration else {
                    replyHandler(["ok": false, "error": "unavailable"])
                    return
                }
                replyHandler(Self.copyReply(for: result))
            }
        }
    }

    /// iOS can ignore pasteboard writes when Watch Connectivity wakes the
    /// phone app in the background. `setItems` runs on the main queue, inside
    /// the caller's background task, with `localOnly` and an expiration of one
    /// period. Do not log the code, store it, or put it in the reply.
    private static func copyReply(for result: Any?) -> [String: Any] {
        dispatchPrecondition(condition: .onQueue(.main))
        if result is FlutterError {
            return ["ok": false, "error": "unavailable"]
        }
        guard let payload = pastePayload(from: result) else {
            return ["ok": false, "error": "not_found"]
        }
        let pasteboard = UIPasteboard.general
        let before = pasteboard.changeCount
        pasteboard.setItems(
            [[UIPasteboard.typeAutomatic: payload.code]],
            options: [
                UIPasteboard.OptionsKey.localOnly: true,
                UIPasteboard.OptionsKey.expirationDate: Date(
                    timeIntervalSinceNow: TimeInterval(payload.seconds)
                ),
            ]
        )
        guard pasteboard.changeCount > before else {
            return ["ok": false, "error": "unavailable"]
        }
        return ["ok": true]
    }

    /// `code` is the only string written to the pasteboard. `period` is seconds.
    /// A missing or non-positive period expires after one default TOTP step.
    private static func pastePayload(from result: Any?) -> (code: String, seconds: Int)? {
        if let code = result as? String {
            guard !code.isEmpty else { return nil }
            return (code, 30)
        }
        guard let fields = stringKeyedDictionary(result) else { return nil }
        guard let code = fields["code"] as? String, !code.isEmpty else { return nil }
        return (code, periodSeconds(fields["period"]))
    }

    private static func periodSeconds(_ value: Any?) -> Int {
        let parsed: Int?
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                parsed = nil
            } else {
                parsed = number.intValue
            }
        } else if let int = value as? Int {
            parsed = int
        } else {
            parsed = nil
        }
        guard let parsed, parsed > 0 else { return 30 }
        return parsed
    }

    private static func stringKeyedDictionary(_ value: Any?) -> [String: Any]? {
        if let typed = value as? [String: Any] {
            return typed
        }
        guard let object = value as? NSDictionary else { return nil }
        var converted: [String: Any] = [:]
        converted.reserveCapacity(object.count)
        for (key, element) in object {
            guard let key = key as? String else { return nil }
            converted[key] = element
        }
        return converted
    }

    private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
        if Thread.isMainThread {
            result(value)
            return
        }
        DispatchQueue.main.async {
            result(value)
        }
    }
}

extension EnteWatchBridgePlugin {
    fileprivate enum BridgeFailure: String {
        case invalidPayload = "invalid_payload"
        case connectivityUnavailable = "watch_connectivity_unavailable"
        case syncFailed = "watch_sync_failed"

        var message: String {
            switch self {
            case .invalidPayload:
                return "invalid payload"
            case .connectivityUnavailable:
                return "watch connectivity unavailable"
            case .syncFailed:
                return "Watch sync failed"
            }
        }

        var flutterError: FlutterError {
            FlutterError(code: rawValue, message: message, details: nil)
        }
    }

    /// Converts a Flutter map into strings, integers, bools, arrays, and dictionaries.
    /// Nulls, floats, and typed data are rejected. Failures carry no payload.
    fileprivate func propertyListDictionary(from value: Any) throws -> [String: Any] {
        let converted = try propertyListValue(value)
        guard let dictionary = converted as? [String: Any] else {
            throw PayloadError.invalid
        }
        return dictionary
    }

    fileprivate func propertyListValue(_ value: Any) throws -> Any {
        if value is NSNull {
            throw PayloadError.invalid
        }
        if let number = value as? NSNumber {
            // Flutter bools arrive as CFBoolean. Check that before integer bridging;
            // an integer NSNumber can also satisfy `as? Bool`.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            let cfNumber = number as CFNumber
            if CFNumberIsFloatType(cfNumber) {
                throw PayloadError.invalid
            }
            var int64: Int64 = 0
            guard CFNumberGetValue(cfNumber, .sInt64Type, &int64) else {
                throw PayloadError.invalid
            }
            return int64
        }
        if let string = value as? String {
            return string
        }
        if let bool = value as? Bool {
            return bool
        }
        if let int = value as? Int {
            return int
        }
        if let int64 = value as? Int64 {
            return int64
        }
        if let array = value as? [Any] {
            return try array.map { try propertyListValue($0) }
        }
        if let dictionary = value as? [String: Any] {
            var converted: [String: Any] = [:]
            converted.reserveCapacity(dictionary.count)
            for (key, element) in dictionary {
                converted[key] = try propertyListValue(element)
            }
            return converted
        }
        if let dictionary = value as? NSDictionary {
            var converted: [String: Any] = [:]
            converted.reserveCapacity(dictionary.count)
            for (key, element) in dictionary {
                guard let key = key as? String else {
                    throw PayloadError.invalid
                }
                converted[key] = try propertyListValue(element)
            }
            return converted
        }
        throw PayloadError.invalid
    }

    fileprivate enum PayloadError: Error {
        case invalid
    }
}

/// Keeps the phone process alive across the Dart lookup and the pasteboard write.
/// Ending is idempotent so the expiration handler and the reply path can both call it.
private final class WatchCopyBackgroundTask {
    private let lock = NSLock()
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        var created: UIBackgroundTaskIdentifier = .invalid
        created = UIApplication.shared.beginBackgroundTask(withName: "io.ente.auth.watch.copy") { [weak self] in
            self?.end()
        }
        lock.lock()
        identifier = created
        lock.unlock()
    }

    func end() {
        lock.lock()
        let current = identifier
        identifier = .invalid
        lock.unlock()
        if current != .invalid {
            UIApplication.shared.endBackgroundTask(current)
        }
    }
}
