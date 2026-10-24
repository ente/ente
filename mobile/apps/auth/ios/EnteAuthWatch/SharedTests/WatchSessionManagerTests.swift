import Security
import WatchConnectivity
import XCTest
@testable import EnteAuthWatch

@MainActor
internal final class WatchSessionManagerTests: XCTestCase {
    func testApplyUpsertsSortsAndDropsOrphans() throws {
        let store = MemorySeedStore()
        store.items["9"] = [0x01]
        store.items["42"] = [0x02]
        let manager = WatchSessionManager(store: store)
        manager.apply(context: sampleContext(deletedIds: ["7"]))

        XCTAssertFalse(manager.passcodeRequired)
        XCTAssertNil(manager.statusMessage)
        XCTAssertEqual(manager.tokens.map(\.id), ["42", "7b"])
        XCTAssertEqual(manager.tokens.map(\.sortOrder), [0, 2])
        XCTAssertEqual(manager.tokens.map(\.isFavorite), [true, false])
        XCTAssertEqual(manager.tokens.map(\.algorithm), [.sha1, .sha256])
        XCTAssertEqual(Set(store.items.keys), Set(["42", "7b"]))
        let kept = try XCTUnwrap(store.items["42"])
        XCTAssertEqual(kept, [UInt8]("Hello!".utf8) + [0xde, 0xad, 0xbe, 0xef])
        XCTAssertNil(store.items["9"])
        XCTAssertEqual(store.lockedDeleteCount, 0)
    }

    func testDeletionWinsOverUpsert() {
        let store = MemorySeedStore()
        store.items["42"] = [0x11]
        let manager = WatchSessionManager(store: store)
        manager.apply(context: sampleContext(deletedIds: ["42"]))

        XCTAssertEqual(manager.tokens.map(\.id), ["7b"])
        XCTAssertNil(store.items["42"])
        XCTAssertEqual(store.saveIDs, ["7b"])
    }

    func testSameContextTwiceIsIdempotent() {
        let store = MemorySeedStore()
        let manager = WatchSessionManager(store: store)
        let context = sampleContext(deletedIds: ["7"])
        manager.apply(context: context)
        let afterFirst = store.items
        manager.apply(context: context)
        XCTAssertEqual(store.items.keys.sorted(), afterFirst.keys.sorted())
        XCTAssertEqual(store.items["42"], afterFirst["42"])
        XCTAssertEqual(store.items["7b"], afterFirst["7b"])
        XCTAssertEqual(manager.tokens.map(\.id), ["42", "7b"])
    }

    func testUnknownVersionWritesNothing() {
        let store = MemorySeedStore()
        store.items["42"] = [0x01]
        let manager = WatchSessionManager(store: store)
        var context = sampleContext(deletedIds: ["42"])
        context["version"] = NSNumber(value: 2)
        manager.apply(context: context)
        XCTAssertEqual(store.items["42"], [0x01])
        XCTAssertFalse(manager.passcodeRequired)
        XCTAssertNil(manager.statusMessage)
        XCTAssertTrue(manager.tokens.isEmpty)
    }

    func testPasscodeRequiredWritesNothing() {
        let store = MemorySeedStore()
        let manager = WatchSessionManager(store: store)
        manager.tokensPublishProbe()
        XCTAssertEqual(manager.tokens.map(\.id), ["probe"])
        store.items["42"] = [0x01]
        store.canStoreSecrets = false
        let savesBefore = store.saveIDs.count
        manager.apply(context: sampleContext(deletedIds: ["42"]))

        XCTAssertTrue(manager.passcodeRequired)
        XCTAssertEqual(
            manager.statusMessage,
            "Passcode required on Apple Watch to sync tokens"
        )
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.saveIDs.count, savesBefore)
        XCTAssertEqual(store.lockedDeleteCount, 0)
        XCTAssertTrue(manager.tokens.isEmpty)
    }

    func testPasscodeRequiredDuringSavePurgesSeedsAndClearsTokens() {
        let store = MemorySeedStore()
        let manager = WatchSessionManager(store: store)
        manager.apply(context: sampleContext(deletedIds: ["7"]))
        XCTAssertEqual(manager.tokens.map(\.id), ["42", "7b"])
        XCTAssertFalse(store.items.isEmpty)
        XCTAssertTrue(store.canStoreSecrets)
        XCTAssertEqual(store.purgeCount, 0)

        store.forcedSaveError = .passcodeRequired
        manager.apply(context: sampleContext(deletedIds: ["7"]))

        XCTAssertEqual(store.purgeCount, 1)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(manager.passcodeRequired)
        XCTAssertFalse(manager.wristLocked)
        XCTAssertTrue(manager.tokens.isEmpty)
        XCTAssertEqual(
            manager.statusMessage,
            WatchKeychainManager.passcodeRequiredMessage
        )
    }

    func testPasscodeRequiredDuringAccountListingPurgesSeedsAndClearsTokens() {
        let store = MemorySeedStore()
        let manager = WatchSessionManager(store: store)
        manager.apply(context: sampleContext(deletedIds: ["7"]))
        XCTAssertFalse(manager.tokens.isEmpty)
        XCTAssertFalse(store.items.isEmpty)
        XCTAssertTrue(store.canStoreSecrets)
        XCTAssertEqual(store.purgeCount, 0)

        store.forcedAccountIDsError = .passcodeRequired
        manager.apply(context: sampleContext(deletedIds: ["7"]))

        XCTAssertEqual(store.purgeCount, 1)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(manager.passcodeRequired)
        XCTAssertFalse(manager.wristLocked)
        XCTAssertTrue(manager.tokens.isEmpty)
        XCTAssertEqual(
            manager.statusMessage,
            WatchKeychainManager.passcodeRequiredMessage
        )
    }

    func testPasscodeRequiredStillSurfacesWhenPurgeThrows() {
        let store = MemorySeedStore()
        let manager = WatchSessionManager(store: store)
        manager.apply(context: sampleContext(deletedIds: ["7"]))
        XCTAssertFalse(manager.tokens.isEmpty)
        XCTAssertTrue(store.canStoreSecrets)

        store.forcedSaveError = .passcodeRequired
        store.purgeError = WatchKeychainError.passcodeRequired
        manager.apply(context: sampleContext(deletedIds: ["7"]))

        XCTAssertEqual(store.purgeCount, 0)
        XCTAssertFalse(store.items.isEmpty)
        XCTAssertTrue(manager.passcodeRequired)
        XCTAssertFalse(manager.wristLocked)
        XCTAssertTrue(manager.tokens.isEmpty)
        XCTAssertEqual(
            manager.statusMessage,
            WatchKeychainManager.passcodeRequiredMessage
        )
    }

    func testUnpairedActivationPurgesAndDoesNotRestoreSeeds() {
        let store = MemorySeedStore()
        store.items["42"] = [0x01]
        let manager = WatchSessionManager(store: store)
        manager.tokensPublishProbe()
        XCTAssertFalse(manager.tokens.isEmpty)
        let savesBefore = store.saveIDs.count

        manager.applyLink(
            WatchLinkFacts(isPaired: false, companionInstalled: true, reachable: true),
            context: sampleContext(deletedIds: ["7"])
        )

        XCTAssertEqual(store.purgeCount, 1)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(manager.tokens.isEmpty)
        XCTAssertEqual(store.saveIDs.count, savesBefore)
        XCTAssertFalse(manager.passcodeRequired)
    }

    func testUnreachableDoesNotPurge() {
        let store = MemorySeedStore()
        let manager = WatchSessionManager(store: store)
        manager.apply(context: sampleContext(deletedIds: ["7"]))
        let items = store.items
        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(store.purgeCount, 0)

        manager.noteReachability(false)
        manager.applyLink(
            WatchLinkFacts(isPaired: true, companionInstalled: true, reachable: false),
            context: [:]
        )

        XCTAssertEqual(store.purgeCount, 0)
        XCTAssertEqual(store.items["42"], items["42"])
        XCTAssertEqual(store.items["7b"], items["7b"])
        XCTAssertEqual(manager.tokens.map(\.id), ["42", "7b"])
        XCTAssertFalse(
            WatchLinkFacts.shouldWipeSeeds(
                isPaired: true,
                companionInstalled: true,
                reachable: false
            )
        )
    }

    func testCompanionMissingLinkPurges() {
        let store = MemorySeedStore()
        store.items["42"] = [0x01]
        let manager = WatchSessionManager(store: store)
        manager.tokensPublishProbe()

        manager.applyLink(
            WatchLinkFacts(isPaired: true, companionInstalled: false, reachable: false),
            context: sampleContext(deletedIds: ["7"])
        )

        XCTAssertGreaterThanOrEqual(store.purgeCount, 1)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(manager.tokens.isEmpty)
    }

    func testCopyMessageIsActionAndIdOnly() throws {
        let message = try XCTUnwrap(WatchPhoneCopy.message(id: "42"))
        XCTAssertEqual(Set(message.keys), Set(["action", "id"]))
        XCTAssertEqual(message["action"] as? String, "copyCode")
        XCTAssertEqual(message["id"] as? String, "42")
        XCTAssertEqual(message.count, 2)
        XCTAssertNil(message["secret"])
        XCTAssertNil(message["otp"])
        XCTAssertNil(message["code"])
        XCTAssertNil(WatchPhoneCopy.message(id: "  "))
        let values = message.values.compactMap { $0 as? String }
        XCTAssertFalse(values.contains("JBSWY3DPEHPK3PXP"))
        XCTAssertFalse(values.contains("755224"))

        XCTAssertFalse(WatchPhoneCopy.allowsCopy(shieldedMode: true, revealed: false, secretsHidden: false))
        XCTAssertTrue(WatchPhoneCopy.allowsCopy(shieldedMode: true, revealed: true, secretsHidden: false))
        XCTAssertFalse(WatchPhoneCopy.allowsCopy(shieldedMode: false, revealed: true, secretsHidden: true))
        XCTAssertTrue(WatchPhoneCopy.allowsCopy(shieldedMode: false, revealed: false, secretsHidden: false))
        XCTAssertTrue(WatchPhoneCopy.replySucceeded(["ok": true]))
        XCTAssertTrue(WatchPhoneCopy.isExactPhoneReply(["ok": true]))
        XCTAssertTrue(WatchPhoneCopy.isExactPhoneReply(["ok": false, "error": "not_found"]))
        XCTAssertTrue(WatchPhoneCopy.isExactPhoneReply(["ok": false, "error": "unavailable"]))
        XCTAssertTrue(WatchPhoneCopy.isExactPhoneReply(["ok": false, "error": "invalid"]))
        XCTAssertFalse(WatchPhoneCopy.replySucceeded(["ok": true, "otp": "755224"]))
        XCTAssertFalse(WatchPhoneCopy.isExactPhoneReply(["ok": true, "otp": "755224"]))
        XCTAssertFalse(WatchPhoneCopy.replySucceeded(["ok": false, "error": "not_found", "otp": "755224"]))
        XCTAssertFalse(WatchPhoneCopy.isExactPhoneReply(["ok": false, "error": "not_found", "otp": "755224"]))
        XCTAssertFalse(WatchPhoneCopy.replySucceeded(["ok": false, "error": "not_found"]))
        XCTAssertFalse(WatchPhoneCopy.isExactPhoneReply(["ok": false]))
        XCTAssertFalse(WatchPhoneCopy.isExactPhoneReply(["error": "not_found"]))
        XCTAssertEqual(WatchPhoneCopy.title, "Copy to iPhone")
        XCTAssertEqual(WatchPhoneCopy.notReachable, "iPhone not reachable")
        XCTAssertEqual(WatchPhoneCopy.failed, "Could not copy")
        XCTAssertFalse(WatchPhoneCopy.notReachable.contains("755224"))

        let unreachable = NSError(domain: WCErrorDomain, code: WCError.Code.notReachable.rawValue)
        XCTAssertEqual(WatchPhoneCopy.transportStatus(for: unreachable), WatchPhoneCopy.notReachable)
        let timeout = NSError(domain: WCErrorDomain, code: WCError.Code.messageReplyTimedOut.rawValue)
        XCTAssertEqual(WatchPhoneCopy.transportStatus(for: timeout), WatchPhoneCopy.failed)
        let other = NSError(domain: NSPOSIXErrorDomain, code: 1)
        XCTAssertEqual(WatchPhoneCopy.transportStatus(for: other), WatchPhoneCopy.failed)
    }

    func testPurgeSurvivesReapplyFromSessionWhileCompanionIsGone() {
        let store = MemorySeedStore()
        store.items["42"] = [0x01]
        let manager = WatchSessionManager(store: store)
        manager.tokensPublishProbe()
        XCTAssertFalse(manager.tokens.isEmpty)

        manager.applyLink(
            WatchLinkFacts(isPaired: true, companionInstalled: false, reachable: false),
            context: sampleContext(deletedIds: ["7"])
        )
        XCTAssertGreaterThanOrEqual(store.purgeCount, 1)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(manager.tokens.isEmpty)
        let purgeAfterRemoval = store.purgeCount
        let savesAfterRemoval = store.saveIDs.count

        manager.reapplyFromSession(
            activated: true,
            facts: WatchLinkFacts(isPaired: true, companionInstalled: false, reachable: true),
            context: sampleContext(deletedIds: ["7"])
        )

        XCTAssertEqual(store.saveIDs.count, savesAfterRemoval)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(manager.tokens.isEmpty)
        XCTAssertGreaterThanOrEqual(store.purgeCount, purgeAfterRemoval)
        XCTAssertFalse(manager.passcodeRequired)
    }

    func testReapplyBeforeActivationDoesNotReadCompanionBit() {
        let store = MemorySeedStore()
        store.items["keep"] = [0xAB]
        let manager = WatchSessionManager(store: store)
        manager.reapplyFromSession(
            activated: false,
            facts: WatchLinkFacts(isPaired: true, companionInstalled: false, reachable: false),
            context: sampleContext(deletedIds: ["7"])
        )
        XCTAssertEqual(store.purgeCount, 0)
        XCTAssertEqual(Set(store.items.keys), Set(["42", "7b"]))
        XCTAssertEqual(manager.tokens.map(\.id), ["42", "7b"])
        XCTAssertFalse(manager.passcodeRequired)
    }

    func testStaleCopyReplyDoesNotOverwriteLaterStatus() {
        let manager = WatchSessionManager(store: MemorySeedStore())
        let first = manager.beginCopyGeneration()
        let second = manager.beginCopyGeneration()
        XCTAssertGreaterThan(second, first)

        manager.acceptCopyResult(generation: second, ok: true)
        XCTAssertNil(manager.statusMessage)

        manager.acceptCopyResult(generation: first, ok: false)
        XCTAssertNil(manager.statusMessage)

        let third = manager.beginCopyGeneration()
        manager.acceptCopyStatus(generation: third, status: WatchPhoneCopy.notReachable)
        XCTAssertEqual(manager.statusMessage, WatchPhoneCopy.notReachable)
        manager.acceptCopyResult(generation: first, ok: true)
        manager.acceptCopyStatus(generation: second, status: WatchPhoneCopy.failed)
        XCTAssertEqual(manager.statusMessage, WatchPhoneCopy.notReachable)

        let fourth = manager.beginCopyGeneration()
        manager.acceptCopyStatus(generation: fourth, status: WatchPhoneCopy.failed)
        XCTAssertEqual(manager.statusMessage, WatchPhoneCopy.failed)
        manager.acceptCopyResult(
            generation: third,
            ok: WatchPhoneCopy.replySucceeded(["ok": true, "otp": "755224"])
        )
        XCTAssertEqual(manager.statusMessage, WatchPhoneCopy.failed)
    }

    func testWatchDelegateWipesOnCompanionLossAndNotOnDeactivate() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Shared")
                .appendingPathComponent("WatchSessionManager.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("sessionCompanionAppInstalledDidChange"))
        XCTAssertTrue(source.contains("sessionReachabilityDidChange"))
        XCTAssertTrue(source.contains("__WATCHOS_UNAVAILABLE"))
        XCTAssertFalse(source.contains("func sessionDidDeactivate"))
        XCTAssertFalse(source.contains("session.isPaired"))
        XCTAssertTrue(source.contains("activationState == .activated"))
        XCTAssertTrue(source.contains("copyGeneration"))
        XCTAssertTrue(source.contains("sendMessage"))
        XCTAssertFalse(source.contains("transferUserInfo"))
        XCTAssertFalse(source.contains("print("))

        let bridge = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Runner")
                .appendingPathComponent("EnteWatchBridgePlugin.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(bridge.contains("sessionWatchStateDidChange"))
        XCTAssertTrue(bridge.contains("isPaired"))
        XCTAssertTrue(bridge.contains("pendingContext = nil"))
        XCTAssertFalse(bridge.contains("UIPasteboard.general.string"))
        XCTAssertTrue(bridge.contains("setItems"))
        XCTAssertTrue(bridge.contains("UIPasteboard.OptionsKey.localOnly"))
        XCTAssertTrue(bridge.contains("UIPasteboard.OptionsKey.expirationDate"))
        XCTAssertTrue(bridge.contains("changeCount"))
        XCTAssertTrue(bridge.contains("copyGeneration"))
        XCTAssertTrue(bridge.contains("beginBackgroundTask"))
        XCTAssertTrue(bridge.contains("\"copyCode\""))
        XCTAssertTrue(bridge.contains("\"currentCode\""))
        XCTAssertTrue(bridge.contains("[\"ok\": true]"))
        XCTAssertTrue(bridge.contains("[\"ok\": false, \"error\": \"not_found\"]"))
        XCTAssertTrue(bridge.contains("[\"ok\": false, \"error\": \"unavailable\"]"))
        XCTAssertTrue(bridge.contains("[\"ok\": false, \"error\": \"invalid\"]"))
        XCTAssertFalse(bridge.contains("\"otp\""))
        XCTAssertFalse(bridge.contains("transferUserInfo"))
        XCTAssertFalse(bridge.contains("print("))
        XCTAssertFalse(bridge.contains("NSLog"))
    }

    func testCompanionRemovalPurgesSeeds() {
        let store = MemorySeedStore()
        store.items["42"] = [0x01]
        let manager = WatchSessionManager(store: store)
        manager.tokensPublishProbe()
        XCTAssertFalse(manager.tokens.isEmpty)

        manager.clearSecretsBecauseCompanionRemoved()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(manager.tokens.isEmpty)
        XCTAssertFalse(manager.passcodeRequired)
        XCTAssertNil(manager.statusMessage)
    }

    func testEmptyEligibleSetDeletesLocalIDs() {
        let store = MemorySeedStore()
        store.items["42"] = [0x01]
        store.items["9"] = [0x02]
        let manager = WatchSessionManager(store: store)
        manager.apply(context: [
            "version": NSNumber(value: 1),
            "timestamp": NSNumber(value: 1_775_736_000),
            "syncType": "DELTA",
            "tokens": [[String: Any]](),
            "deletedIds": [String](),
        ])
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(manager.tokens.isEmpty)
        XCTAssertFalse(manager.passcodeRequired)
    }

    func testLockedSaveKeepsTokensAndDoesNotPurge() throws {
        let store = MemorySeedStore()
        let manager = WatchSessionManager(store: store)
        manager.apply(context: sampleContext(deletedIds: ["7"]))
        let idsBefore = manager.tokens.map(\.id)
        XCTAssertEqual(idsBefore, ["42", "7b"])
        XCTAssertFalse(manager.wristLocked)
        let saved = store.items
        store.forcedSaveError = .locked

        manager.apply(context: sampleContext(deletedIds: ["42"]))

        XCTAssertTrue(manager.wristLocked)
        XCTAssertFalse(manager.passcodeRequired)
        XCTAssertNil(manager.statusMessage)
        XCTAssertEqual(manager.tokens.map(\.id), idsBefore)
        XCTAssertEqual(store.items["42"], saved["42"])
        XCTAssertEqual(store.items["7b"], saved["7b"])
        XCTAssertEqual(store.lockedDeleteCount, 0)
        XCTAssertEqual(store.purgeCount, 0)
    }

    func testKeychainQueryUsesThisDeviceOnlyAndPasscode() throws {
        let query = WatchKeychainContract.accountQuery(account: "42")
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "io.ente.auth.watch")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "42")
        XCTAssertNil(query[kSecValueData as String])
        XCTAssertNil(query[kSecAttrAccessible as String])

        let purge = WatchKeychainContract.purgeQuery()
        XCTAssertEqual(purge[kSecAttrService as String] as? String, "io.ente.auth.watch")
        XCTAssertNil(purge[kSecAttrAccount as String])
        XCTAssertNil(purge[kSecValueData as String])

        XCTAssertEqual(WatchKeychainContract.flags, SecAccessControlCreateFlags.devicePasscode)
        XCTAssertEqual(
            WatchKeychainContract.protection as String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        XCTAssertNotEqual(
            WatchKeychainContract.protection as String,
            kSecAttrAccessibleAfterFirstUnlock as String
        )
        XCTAssertNotEqual(
            WatchKeychainContract.protection as String,
            kSecAttrAccessibleWhenUnlocked as String
        )

        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Shared")
                .appendingPathComponent("WatchKeychainManager.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("WatchKeychainContract.purgeQuery()"))
        XCTAssertTrue(source.contains("WatchKeychainContract.accountQuery"))
        XCTAssertTrue(source.contains("WatchKeychainContract.makeAccessControl()"))
        XCTAssertFalse(source.contains("kSecAttrAccessibleAfterFirstUnlock"))
        XCTAssertFalse(source.contains("kSecAttrAccessibleAlways"))
        XCTAssertFalse(source.contains("UserDefaults"))
    }

    func testSharedDartFixtureUpsertsSortsDeletesAndIgnoresUnknownVersion() throws {
        let context = try dartContractFixture()
        XCTAssertEqual(
            Set(context.keys),
            Set(["version", "timestamp", "syncType", "tokens", "deletedIds"])
        )
        let tokenValues = try XCTUnwrap(context["tokens"] as? [Any])
        XCTAssertEqual(tokenValues.count, 2)
        for value in tokenValues {
            let token = try XCTUnwrap(value as? [String: Any])
            XCTAssertEqual(
                Set(token.keys),
                Set(["id", "issuer", "account", "secret", "algorithm", "digits", "period", "isFavorite", "sortOrder"])
            )
        }
        XCTAssertEqual(context["syncType"] as? String, "DELTA")
        let deleted = try XCTUnwrap(context["deletedIds"] as? [Any])
        XCTAssertEqual(deleted as? [String] ?? deleted.map { $0 as? String ?? "" }, ["9"])

        let store = MemorySeedStore()
        store.items["9"] = [0x01]
        store.items["stale"] = [0x02]
        let manager = WatchSessionManager(store: store)
        manager.apply(context: context)

        XCTAssertEqual(manager.tokens.map(\.id), ["42", "7"])
        XCTAssertEqual(manager.tokens.map(\.sortOrder), [0, 1])
        XCTAssertEqual(manager.tokens.map(\.isFavorite), [true, false])
        XCTAssertEqual(manager.tokens.map(\.issuer), ["GitHub", "Example"])
        XCTAssertEqual(manager.tokens.map(\.account), ["octocat@github.com", "ada@example.com"])
        XCTAssertEqual(manager.tokens.map(\.algorithm), [.sha1, .sha256])
        XCTAssertEqual(manager.tokens.map(\.digits), [6, 8])
        XCTAssertEqual(Set(store.items.keys), Set(["42", "7"]))
        let kept = try XCTUnwrap(store.items["42"])
        XCTAssertEqual(kept, [UInt8]("Hello!".utf8) + [0xde, 0xad, 0xbe, 0xef])
        XCTAssertNil(store.items["9"])
        XCTAssertNil(store.items["stale"])
        XCTAssertFalse(manager.passcodeRequired)

        let afterFirst = store.items
        manager.apply(context: context)
        XCTAssertEqual(store.items["42"], afterFirst["42"])
        XCTAssertEqual(store.items["7"], afterFirst["7"])
        XCTAssertEqual(manager.tokens.map(\.id), ["42", "7"])

        let untouched = MemorySeedStore()
        untouched.items["42"] = [0x09]
        let other = WatchSessionManager(store: untouched)
        var unknown = context
        unknown["version"] = NSNumber(value: 2)
        other.apply(context: unknown)
        XCTAssertEqual(untouched.items["42"], [0x09])
        XCTAssertEqual(untouched.saveIDs, [])
        XCTAssertTrue(other.tokens.isEmpty)
        XCTAssertFalse(other.passcodeRequired)
    }

    func testWatchAppActivatesSessionOnLaunch() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("WatchApp")
                .appendingPathComponent("EnteAuthWatchApp.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("WatchSessionManager.shared.activate()"))
    }

    func testKeychainContractConstants() {
        XCTAssertEqual(WatchKeychainManager.service, "io.ente.auth.watch")
        XCTAssertEqual(
            WatchKeychainManager.passcodeRequiredMessage,
            "Passcode required on Apple Watch to sync tokens"
        )
    }

    private func dartContractFixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("test")
            .appendingPathComponent("fixtures")
            .appendingPathComponent("watch_sync_contract_v1.json")
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func sampleContext(deletedIds: [String]) -> [String: Any] {
        [
            "version": NSNumber(value: 1),
            "timestamp": NSNumber(value: 1_775_736_000),
            "syncType": "DELTA",
            "tokens": [
                token(
                    id: "7b",
                    issuer: "Example",
                    account: "ada@example.com",
                    secret: "JBSWY3DPEHPK3PXP",
                    algorithm: "SHA256",
                    digits: 8,
                    period: 30,
                    isFavorite: false,
                    sortOrder: 2
                ),
                token(
                    id: "42",
                    issuer: "GitHub",
                    account: "octocat@github.com",
                    secret: "JBSWY3DPEHPK3PXP",
                    algorithm: "SHA1",
                    digits: 6,
                    period: 30,
                    isFavorite: true,
                    sortOrder: 0
                ),
            ],
            "deletedIds": deletedIds,
        ]
    }

    private func token(
        id: String,
        issuer: String,
        account: String,
        secret: String,
        algorithm: String,
        digits: Int,
        period: Int,
        isFavorite: Bool,
        sortOrder: Int
    ) -> [String: Any] {
        [
            "id": id,
            "issuer": issuer,
            "account": account,
            "secret": secret,
            "algorithm": algorithm,
            "digits": NSNumber(value: digits),
            "period": NSNumber(value: period),
            "isFavorite": NSNumber(value: isFavorite),
            "sortOrder": NSNumber(value: sortOrder),
        ]
    }
}

private extension WatchSessionManager {
    func tokensPublishProbe() {
        apply(context: [
            "version": NSNumber(value: 1),
            "timestamp": NSNumber(value: 1),
            "syncType": "DELTA",
            "tokens": [[
                "id": "probe",
                "issuer": "Probe",
                "account": "probe@example.com",
                "secret": "JBSWY3DPEE",
                "algorithm": "SHA1",
                "digits": NSNumber(value: 6),
                "period": NSNumber(value: 30),
                "isFavorite": NSNumber(value: false),
                "sortOrder": NSNumber(value: 0),
            ] as [String: Any]],
            "deletedIds": [String](),
        ])
    }
}

@MainActor
private final class MemorySeedStore: WatchSeedStoring {
    var canStoreSecrets: Bool
    var items: [String: [UInt8]] = [:]
    var saveIDs: [String] = []
    var lockedDeleteCount = 0
    var purgeCount = 0
    var forcedSaveError: WatchKeychainError?
    var forcedAccountIDsError: WatchKeychainError?
    var purgeError: WatchKeychainError?

    init(canStoreSecrets: Bool = true) {
        self.canStoreSecrets = canStoreSecrets
    }

    func save(id: String, seed: SecretBuffer) throws {
        if let forcedSaveError {
            throw forcedSaveError
        }
        guard canStoreSecrets else { throw WatchKeychainError.passcodeRequired }
        saveIDs.append(id)
        items[id] = seed.withUnsafeBytes { [UInt8]($0) }
    }

    func load(id: String) -> SecretBuffer? {
        guard canStoreSecrets, let bytes = items[id] else { return nil }
        return SecretBuffer(bytes: bytes)
    }

    func delete(id: String) {
        guard canStoreSecrets else {
            lockedDeleteCount += 1
            return
        }
        items.removeValue(forKey: id)
    }

    func purgeAll() throws {
        if let purgeError {
            throw purgeError
        }
        purgeCount += 1
        items.removeAll()
    }

    func allAccountIDs() throws -> [String] {
        if let forcedAccountIDsError {
            throw forcedAccountIDsError
        }
        guard canStoreSecrets else { throw WatchKeychainError.passcodeRequired }
        return Array(items.keys)
    }
}
