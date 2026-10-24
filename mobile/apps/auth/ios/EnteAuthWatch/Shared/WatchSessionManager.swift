import Combine
import Foundation
import WatchConnectivity
import WatchKit

/// WCSession dictionaries are not `Sendable`. The box crosses onto the main actor without logging the payload.
private struct PropertyListContext: @unchecked Sendable {
    let dictionary: [String: Any]
}

/// Pairing facts for one delegate callback.
///
/// `WCSession.isPaired` and `sessionDidDeactivate` are `__WATCHOS_UNAVAILABLE`
/// in this SDK, so a live watch session cannot read a pairing bit and has no
/// deactivate callback to purge and then reactivate. Companion installation is
/// the relationship signal the delegate actually delivers. Tests still pass
/// `isPaired: false` through `applyLink`.
internal struct WatchLinkFacts: Equatable {
    internal var isPaired: Bool
    internal var companionInstalled: Bool
    internal var reachable: Bool

    /// Unreachable and wrist-lock are transient. They do not wipe seeds.
    internal static func shouldWipeSeeds(
        isPaired: Bool,
        companionInstalled: Bool,
        reachable _: Bool
    ) -> Bool {
        !isPaired || !companionInstalled
    }
}

/// Watch-to-phone copy request. The map is only `action` and `id`.
/// The secret and the OTP digits stay on the watch.
internal enum WatchPhoneCopy {
    internal static let title = "Copy to iPhone"
    internal static let notReachable = "iPhone not reachable"
    internal static let failed = "Could not copy"

    /// Phone copy is a tap (`_copyCurrentOTPToClipboard`) with no menu title.
    /// The watch control uses [title] so the destination is obvious.
    internal static func allowsCopy(
        shieldedMode: Bool,
        revealed: Bool,
        secretsHidden: Bool
    ) -> Bool {
        if secretsHidden {
            return false
        }
        if shieldedMode && !revealed {
            return false
        }
        return true
    }

    internal static func message(id: String) -> [String: Any]? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ["action": "copyCode", "id": trimmed]
    }

    /// Phone replies are exactly `["ok": true]` or `["ok": false, "error": ...]`.
    /// A reply that also carries `otp` (or any other key) is not a success.
    internal static func isExactPhoneReply(_ reply: [String: Any]) -> Bool {
        let keys = Set(reply.keys)
        if keys == ["ok"] {
            return bool(reply["ok"]) == true
        }
        if keys == ["ok", "error"],
           bool(reply["ok"]) == false,
           let error = reply["error"] as? String,
           !error.isEmpty {
            return true
        }
        return false
    }

    internal static func replySucceeded(_ reply: [String: Any]) -> Bool {
        isExactPhoneReply(reply) && bool(reply["ok"]) == true
    }

    /// `WCErrorCodeNotReachable` stays the unreachable string.
    /// A timeout or any other transport error is [failed], and the error is not logged.
    internal static func transportStatus(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == WCErrorDomain,
           nsError.code == WCError.Code.notReachable.rawValue {
            return notReachable
        }
        return failed
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }
}

/// Watch-side session. Applies `updateApplicationContext` payloads.
/// A copy asks the phone to put the current code on the iPhone pasteboard.
/// The message carries the token id only.
@MainActor
internal final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    internal static let shared = WatchSessionManager()

    @Published internal private(set) var tokens: [WatchTokenDisplay] = []
    @Published internal private(set) var passcodeRequired = false
    @Published internal private(set) var wristLocked = false
    @Published internal private(set) var statusMessage: String?

    private let store: any WatchSeedStoring
    /// Latest copy request. A slower reply from an earlier request is ignored.
    private var copyGeneration: UInt64 = 0

    internal override init() {
        store = WatchKeychainManager.shared
        super.init()
    }

    internal init(store: any WatchSeedStoring) {
        self.store = store
        super.init()
    }

    internal func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Re-reads the latest application context. A locked watch cannot write Keychain;
    /// raising the wrist and unlocking should apply that same dictionary again.
    /// The dictionary is not copied into a longer-lived cache.
    ///
    /// After activation this uses the same link handler as the delegate, so a
    /// missing companion cannot write `receivedApplicationContext` back.
    /// Before activation `isCompanionAppInstalled` is not valid and is not read.
    internal func reapplyFromSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let activated = session.activationState == .activated
        let facts: WatchLinkFacts? = activated ? Self.liveLinkFacts(session) : nil
        reapplyFromSession(
            activated: activated,
            facts: facts,
            context: session.receivedApplicationContext
        )
    }

    /// `facts` is consulted only when [activated] is true. A context is not
    /// applied when those facts say the companion relationship has ended.
    internal func reapplyFromSession(
        activated: Bool,
        facts: WatchLinkFacts?,
        context: [String: Any]
    ) {
        guard activated else {
            #if DEBUG
            if installScreenshotFixtureIfNeeded() { return }
            #endif
            guard !context.isEmpty else { return }
            apply(context: context)
            return
        }
        guard let facts else { return }
        applyLink(facts, context: context)
    }

    nonisolated internal func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil, activationState == .activated else { return }
        let facts = Self.liveLinkFacts(session)
        let context = PropertyListContext(dictionary: session.receivedApplicationContext)
        Task { @MainActor in
            self.applyLink(facts, context: context.dictionary)
        }
    }

    /// `sessionDidDeactivate` is iOS-only (`__WATCHOS_UNAVAILABLE`): the phone
    /// uses it when the selected watch changes. On watchOS the matching signal
    /// is the companion iPhone app disappearing, plus `isPaired == false` when
    /// a caller can supply that bit. This SDK's watch delegate has no
    /// deactivate method to purge and reactivate.
    nonisolated internal func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        // The companion bit is not valid until activation. Reading a false
        // value earlier would wipe a healthy keychain.
        guard session.activationState == .activated else { return }
        let facts = Self.liveLinkFacts(session)
        Task { @MainActor in
            self.applyLink(facts, context: [:])
        }
    }

    /// Reachability flips while the phone is locked or out of range.
    /// Those states are transient and must not wipe seeds.
    nonisolated internal func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.noteReachability(reachable)
        }
    }

    /// Live session facts. `WCSession.isPaired` is `__WATCHOS_UNAVAILABLE` here,
    /// so the watch process reports itself paired and uses companion installation.
    nonisolated private static func liveLinkFacts(_ session: WCSession) -> WatchLinkFacts {
        WatchLinkFacts(
            isPaired: true,
            companionInstalled: session.isCompanionAppInstalled,
            reachable: session.isReachable
        )
    }

    /// Wipes when the pair or the companion relationship has ended.
    /// Does not wipe for a transient unreachable or locked state, and does not
    /// apply a context after a wipe (that would write the seeds back).
    internal func applyLink(_ facts: WatchLinkFacts, context: [String: Any]) {
        #if DEBUG
        // A debug screenshot launch owns the list. Leave those rows in place
        // and do not apply receivedApplicationContext.
        if installScreenshotFixtureIfNeeded() { return }
        #endif
        let wipe = WatchLinkFacts.shouldWipeSeeds(
            isPaired: facts.isPaired,
            companionInstalled: facts.companionInstalled,
            reachable: facts.reachable
        )
        if wipe {
            clearSecretsBecauseCompanionRemoved()
            return
        }
        guard !context.isEmpty else { return }
        apply(context: context)
    }

    /// Locked, out of range, and other unreachable states keep the seeds.
    internal func noteReachability(_ reachable: Bool) {
        _ = reachable
    }

    /// Asks the paired iPhone to copy this id's current code. Sends `action`
    /// and `id` only. Does not send the secret or the OTP. Interactive
    /// `sendMessage` only: a queued background transfer would deliver a stale code.
    internal func requestCopyToPhone(id: String) {
        guard let message = WatchPhoneCopy.message(id: id) else { return }
        let generation = beginCopyGeneration()
        guard WCSession.isSupported() else {
            statusMessage = WatchPhoneCopy.notReachable
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            statusMessage = WatchPhoneCopy.notReachable
            return
        }
        session.sendMessage(message, replyHandler: { reply in
            let ok = WatchPhoneCopy.replySucceeded(reply)
            Task { @MainActor in
                self.acceptCopyResult(generation: generation, ok: ok)
            }
        }, errorHandler: { error in
            let status = WatchPhoneCopy.transportStatus(for: error)
            Task { @MainActor in
                self.acceptCopyStatus(generation: generation, status: status)
            }
        })
    }

    /// Starts a copy generation. Replies for an older generation are ignored.
    @discardableResult
    internal func beginCopyGeneration() -> UInt64 {
        copyGeneration &+= 1
        return copyGeneration
    }

    internal func acceptCopyResult(generation: UInt64, ok: Bool) {
        guard generation == copyGeneration else { return }
        finishCopy(ok: ok)
    }

    internal func acceptCopyStatus(generation: UInt64, status: String) {
        guard generation == copyGeneration else { return }
        statusMessage = status
    }

    private func finishCopy(ok: Bool) {
        if ok {
            WKInterfaceDevice.current().play(.success)
            if statusMessage == WatchPhoneCopy.notReachable || statusMessage == WatchPhoneCopy.failed {
                statusMessage = nil
            }
            return
        }
        statusMessage = WatchPhoneCopy.failed
    }

    /// Drops every seed for this service and the in-memory list. Does not log.
    internal func clearSecretsBecauseCompanionRemoved() {
        do {
            try store.purgeAll()
        } catch {
            // Companion is gone. Do not log.
        }
        tokens = []
        passcodeRequired = false
        wristLocked = false
        statusMessage = nil
    }

    #if DEBUG
    /// Public RFC 6238 vector for `-ente-screenshot`. Keychain only.
    /// That secret is not placed on the phone reply. Compiled out of release.
    @discardableResult
    internal func installScreenshotFixtureIfNeeded() -> Bool {
        guard let mode = ScreenshotLaunch.mode() else { return false }
        switch mode {
        case "list", "next", "shielded", "copy":
            return writePublicScreenshotFixture()
        default:
            return false
        }
    }

    private func writePublicScreenshotFixture() -> Bool {
        let secret = "JBSWY3DPEHPK3PXP"
        guard let seed = Base32.decode(secret), seed.count > 0 else { return false }
        let rows: [(id: String, issuer: String, account: String, sortOrder: Int, isFavorite: Bool)] = [
            ("github", "GitHub", "octocat", 0, true),
            ("google", "Google", "ada@gmail.com", 1, false),
            ("bank", "Example Bank", "ada@example.com", 2, false),
        ]
        var displays: [WatchTokenDisplay] = []
        displays.reserveCapacity(rows.count)
        for row in rows {
            try? store.save(id: row.id, seed: seed)
            displays.append(
                WatchTokenDisplay(
                    id: row.id,
                    issuer: row.issuer,
                    account: row.account,
                    algorithm: .sha1,
                    digits: 6,
                    period: 30,
                    sortOrder: row.sortOrder,
                    isFavorite: row.isFavorite
                )
            )
        }
        tokens = displays
        passcodeRequired = false
        wristLocked = false
        statusMessage = nil
        return true
    }
    #endif

    nonisolated internal func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let activated = session.activationState == .activated
        // Do not read isCompanionAppInstalled before activation.
        let facts = activated ? Self.liveLinkFacts(session) : nil
        let context = PropertyListContext(dictionary: applicationContext)
        Task { @MainActor in
            self.reapplyFromSession(
                activated: activated,
                facts: facts,
                context: context.dictionary
            )
        }
    }

    /// Property-list dictionary from `WCSession`. Do not log `context`; it contains base32 seeds.
    internal func apply(context: [String: Any]) {
        guard let result = reduce(context) else { return }
        if result.replaceTokens {
            tokens = result.tokens
        }
        passcodeRequired = result.passcodeRequired
        wristLocked = result.wristLocked
        statusMessage = result.statusMessage
    }

    private struct ApplyResult {
        let replaceTokens: Bool
        let tokens: [WatchTokenDisplay]
        let passcodeRequired: Bool
        let wristLocked: Bool
        let statusMessage: String?
    }

    /// Passcode is gone. Stop showing codes and try to delete stored seeds.
    /// A failed wipe still surfaces passcodeRequired and is not logged.
    private func passcodeRequiredResult() -> ApplyResult {
        do {
            try store.purgeAll()
        } catch {
            // Do not log. The error must not reveal seeds.
        }
        return ApplyResult(
            replaceTokens: true,
            tokens: [],
            passcodeRequired: true,
            wristLocked: false,
            statusMessage: WatchKeychainManager.passcodeRequiredMessage
        )
    }

    private func reduce(_ context: [String: Any]) -> ApplyResult? {
        guard Self.intValue(context["version"]) == 1 else { return nil }
        guard let tokenDicts = Self.tokenDictionaries(context["tokens"]) else { return nil }
        let deletedIds: [String]
        if context["deletedIds"] == nil {
            deletedIds = []
        } else if let ids = Self.stringIDs(context["deletedIds"]) {
            deletedIds = ids
        } else {
            return nil
        }

        guard store.canStoreSecrets else {
            return passcodeRequiredResult()
        }

        let deletedSet = Set(deletedIds)
        var tokenIDs = Set<String>()
        for dict in tokenDicts {
            if let id = dict["id"] as? String, !id.isEmpty {
                tokenIDs.insert(id)
            }
        }

        var displays: [WatchTokenDisplay] = []
        displays.reserveCapacity(tokenDicts.count)
        var failedSave = false
        var wristLocked = false

        for dict in tokenDicts {
            guard let id = dict["id"] as? String, !id.isEmpty else { continue }
            // Deletion wins: an id listed in both arrays is not upserted.
            if deletedSet.contains(id) { continue }
            guard
                let issuer = dict["issuer"] as? String,
                let account = dict["account"] as? String,
                let secret = dict["secret"] as? String,
                let algorithmRaw = dict["algorithm"] as? String,
                let algorithm = WatchToken.HashAlgorithm(rawValue: algorithmRaw),
                let digits = Self.intValue(dict["digits"]),
                let period = Self.intValue(dict["period"]),
                let sortOrder = Self.intValue(dict["sortOrder"]),
                let isFavorite = Self.boolValue(dict["isFavorite"]),
                (1...10).contains(digits),
                period > 0,
                let seed = Base32.decode(secret),
                seed.count > 0
            else { continue }

            do {
                try store.save(id: id, seed: seed)
            } catch WatchKeychainError.passcodeRequired {
                return passcodeRequiredResult()
            } catch WatchKeychainError.locked {
                // Do not publish this row. Keychain still has the previous seed,
                // and a later reapply writes the new one after unlock.
                wristLocked = true
                continue
            } catch {
                failedSave = true
                continue
            }
            displays.removeAll { $0.id == id }
            displays.append(
                WatchTokenDisplay(
                    id: id,
                    issuer: issuer,
                    account: account,
                    algorithm: algorithm,
                    digits: digits,
                    period: period,
                    sortOrder: sortOrder,
                    isFavorite: isFavorite
                )
            )
        }

        if wristLocked {
            // Leave the previous list and the previous Keychain set. Deletes
            // run on the retry after the watch unlocks.
            return ApplyResult(
                replaceTokens: false,
                tokens: [],
                passcodeRequired: false,
                wristLocked: true,
                statusMessage: nil
            )
        }

        if failedSave && displays.isEmpty && !tokenDicts.isEmpty {
            return nil
        }

        for id in deletedIds {
            store.delete(id: id)
        }

        // v1 tokens are the full eligible set, so local ids missing from that list are removed.
        do {
            let localIDs = try store.allAccountIDs()
            for id in localIDs where !tokenIDs.contains(id) {
                store.delete(id: id)
            }
        } catch WatchKeychainError.passcodeRequired {
            return passcodeRequiredResult()
        } catch {
            displays.sort { $0.sortOrder < $1.sortOrder }
            return ApplyResult(
                replaceTokens: true,
                tokens: displays,
                passcodeRequired: false,
                wristLocked: false,
                statusMessage: nil
            )
        }

        displays.sort { $0.sortOrder < $1.sortOrder }
        return ApplyResult(
            replaceTokens: true,
            tokens: displays,
            passcodeRequired: false,
            wristLocked: false,
            statusMessage: nil
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let int = value as? Int {
            return int
        }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private static func tokenDictionaries(_ value: Any?) -> [[String: Any]]? {
        if let typed = value as? [[String: Any]] {
            return typed
        }
        guard let array = value as? [Any] else { return nil }
        var dictionaries: [[String: Any]] = []
        dictionaries.reserveCapacity(array.count)
        for element in array {
            guard let dict = element as? [String: Any] else { return nil }
            dictionaries.append(dict)
        }
        return dictionaries
    }

    private static func stringIDs(_ value: Any?) -> [String]? {
        if let ids = value as? [String] {
            return ids
        }
        guard let array = value as? [Any] else { return nil }
        var ids: [String] = []
        ids.reserveCapacity(array.count)
        for element in array {
            guard let id = element as? String else { return nil }
            ids.append(id)
        }
        return ids
    }
}
