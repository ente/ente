import CryptoKit
import XCTest
@testable import EnteAuthWatch

internal final class WatchPresentationTests: XCTestCase {
    func testCodeGroupingMatchesPhoneFormatter() {
        XCTAssertEqual(CodeFormatting.display("123456", digits: 6), "123 456")
        XCTAssertEqual(CodeFormatting.display("1234567", digits: 7), "123 4 567")
        XCTAssertEqual(CodeFormatting.display("12345678", digits: 8), "123 45 678")
        XCTAssertEqual(CodeFormatting.display("123456789", digits: 9), "123 456 789")
        XCTAssertEqual(CodeFormatting.display("12345", digits: 6), "012 345")
        XCTAssertEqual(CodeFormatting.grouped("1234"), "1234")
    }

    func testMaskedGroupingUsesBulletsThenSameSplits() {
        XCTAssertEqual(CodeFormatting.masked(digits: 6), "••• •••")
        XCTAssertEqual(CodeFormatting.masked(digits: 7), "••• • •••")
        XCTAssertEqual(CodeFormatting.masked(digits: 8), "••• •• •••")
        XCTAssertEqual(CodeFormatting.masked(digits: 0), "")
    }

    func testProgressColorFollowsPhoneFraction() {
        XCTAssertEqual(CodeTimerStyle.warningFraction, 0.4, accuracy: 0.000_000_1)
        XCTAssertFalse(CodeTimerStyle.usesWarningColor(remainingSeconds: 13, period: 30))
        XCTAssertTrue(CodeTimerStyle.usesWarningColor(remainingSeconds: 12, period: 30))
        XCTAssertTrue(CodeTimerStyle.usesWarningColor(remainingSeconds: 5, period: 30))
        XCTAssertFalse(CodeTimerStyle.usesWarningColor(remainingSeconds: 5, period: 10))
        XCTAssertTrue(CodeTimerStyle.usesWarningColor(remainingSeconds: 4, period: 10))
        XCTAssertEqual(EnteWatchColor.primary700Red, 114.0 / 255.0, accuracy: 0.000_000_1)
        XCTAssertEqual(EnteWatchColor.primary700Green, 46.0 / 255.0, accuracy: 0.000_000_1)
        XCTAssertEqual(EnteWatchColor.primary700Blue, 209.0 / 255.0, accuracy: 0.000_000_1)
        XCTAssertEqual(EnteWatchColor.timerWarningRed, 1, accuracy: 0.000_000_1)
        XCTAssertEqual(EnteWatchColor.timerWarningGreen, 152.0 / 255.0, accuracy: 0.000_000_1)
        XCTAssertEqual(EnteWatchColor.timerWarningBlue, 0, accuracy: 0.000_000_1)
    }

    func testNextCodeAppearsAtFiveSeconds() {
        XCTAssertFalse(NextCodeHint.isVisible(remainingSeconds: 6, nextIsEmpty: false))
        XCTAssertTrue(NextCodeHint.isVisible(remainingSeconds: 5, nextIsEmpty: false))
        XCTAssertTrue(NextCodeHint.isVisible(remainingSeconds: 1, nextIsEmpty: false))
        XCTAssertFalse(NextCodeHint.isVisible(remainingSeconds: 5, nextIsEmpty: true))
    }

    func testClockBoundariesAroundPeriodAndFiveSeconds() {
        let period = 30
        XCTAssertEqual(WatchPeriodClock.remainingSeconds(at: Date(timeIntervalSince1970: 24), period: period), 6)
        XCTAssertEqual(WatchPeriodClock.remainingSeconds(at: Date(timeIntervalSince1970: 25), period: period), 5)
        XCTAssertEqual(WatchPeriodClock.remainingSeconds(at: Date(timeIntervalSince1970: 29), period: period), 1)
        XCTAssertEqual(WatchPeriodClock.remainingSeconds(at: Date(timeIntervalSince1970: 30), period: period), 30)
        XCTAssertEqual(WatchPeriodClock.index(at: Date(timeIntervalSince1970: 29), period: period), 0)
        XCTAssertEqual(WatchPeriodClock.index(at: Date(timeIntervalSince1970: 30), period: period), 1)
    }

    func testShieldedAccessibilityOmitsTheCode() {
        let label = TokenRowAccessibility.shieldedLabel(issuer: "GitHub", account: "octocat")
        XCTAssertEqual(label, "GitHub, octocat, Hidden code")
        XCTAssertFalse(label.contains("755224"))
        XCTAssertFalse(label.contains("839201"))
        let hidden = TokenRowAccessibility.codeLabel(masked: true, code: "755224")
        XCTAssertEqual(hidden, "Hidden code")
        XCTAssertFalse(hidden.contains("755224"))
        XCTAssertEqual(TokenRowAccessibility.codeLabel(masked: false, code: "755224"), "755224")
        XCTAssertEqual(TokenRowAccessibility.shieldedLabel(issuer: "  ", account: ""), "Account, Hidden code")
    }

    func testIssuerAssetsAndLetterFallback() {
        XCTAssertEqual(IssuerIconCatalog.assetName(for: "GitHub"), "IssuerGitHub")
        XCTAssertEqual(IssuerIconCatalog.assetName(for: " GitHub "), "IssuerGitHub")
        XCTAssertEqual(IssuerIconCatalog.assetName(for: "AWS"), "IssuerAWS")
        XCTAssertEqual(IssuerIconCatalog.assetName(for: "Amazon Web Services"), "IssuerAWS")
        XCTAssertEqual(IssuerIconCatalog.assetName(for: "Google"), "IssuerGoogle")
        XCTAssertEqual(IssuerIconCatalog.assetName(for: "Proton"), "IssuerProton")
        XCTAssertEqual(IssuerIconCatalog.assetName(for: "Proton.me"), "IssuerProton")
        XCTAssertEqual(IssuerIconCatalog.assetName(for: "Discord"), "IssuerDiscord")
        XCTAssertEqual(IssuerIconCatalog.assetName(for: "Cloudflare"), "IssuerCloudflare")
        XCTAssertNil(IssuerIconCatalog.assetName(for: "Example Bank"))

        XCTAssertEqual(IssuerMark.label(for: "GitHub"), "GI")
        XCTAssertEqual(IssuerMark.label(for: "a"), "A")
        XCTAssertEqual(IssuerMark.label(for: "  "), "?")

        let github = IssuerMark.rgb(for: "GitHub")
        XCTAssertEqual(IssuerMark.rgb(for: "GitHub").red, github.red)
        XCTAssertEqual(IssuerMark.rgb(for: "GitHub").green, github.green)
        XCTAssertEqual(IssuerMark.rgb(for: "GitHub").blue, github.blue)
        let digest = Array(SHA256.hash(data: Data("GitHub".utf8)))
        XCTAssertEqual(github.red, digest[0])
        XCTAssertEqual(github.green, digest[1])
        XCTAssertEqual(github.blue, digest[2])
        XCTAssertNotEqual(IssuerMark.rgb(for: "github").red, github.red)
    }

    func testIssuerRenderingMatchesPhoneMarks() {
        XCTAssertEqual(IssuerIconCatalog.mark(for: "GitHub")?.rendering, .template)
        XCTAssertEqual(IssuerIconCatalog.mark(for: "Google")?.rendering, .original)
        XCTAssertEqual(IssuerIconCatalog.mark(for: "Proton.me")?.rendering, .original)
        XCTAssertEqual(IssuerIconCatalog.mark(for: "Cloudflare")?.rendering, .original)
        XCTAssertEqual(
            IssuerIconCatalog.mark(for: "Discord")?.rendering,
            .tinted(red: 88.0 / 255.0, green: 101.0 / 255.0, blue: 242.0 / 255.0)
        )
        XCTAssertEqual(
            IssuerIconCatalog.mark(for: "Amazon Web Services")?.rendering,
            .tinted(red: 1, green: 153.0 / 255.0, blue: 0)
        )
        XCTAssertNil(IssuerIconCatalog.mark(for: "Example Bank"))
        XCTAssertEqual(EnteWatchColor.pinGlyphRed, 150.0 / 255.0, accuracy: 0.000_000_1)
        XCTAssertEqual(EnteWatchColor.pinGlyphGreen, 16.0 / 255.0, accuracy: 0.000_000_1)
        XCTAssertEqual(EnteWatchColor.pinGlyphBlue, 214.0 / 255.0, accuracy: 0.000_000_1)
        XCTAssertEqual(EnteWatchColor.buttonPrimaryRed, 150.0 / 255.0, accuracy: 0.000_000_1)
        XCTAssertEqual(EnteWatchColor.buttonPrimaryGreen, 16.0 / 255.0, accuracy: 0.000_000_1)
        XCTAssertEqual(EnteWatchColor.buttonPrimaryBlue, 214.0 / 255.0, accuracy: 0.000_000_1)
        XCTAssertNotEqual(EnteWatchColor.buttonPrimaryRed, EnteWatchColor.primary700Red)
    }

    func testPrivacyMaskFollowsInactiveAndDimmed() {
        XCTAssertFalse(WatchPrivacyMask.hidesSecrets(isActive: true, isLuminanceReduced: false))
        XCTAssertTrue(WatchPrivacyMask.hidesSecrets(isActive: false, isLuminanceReduced: false))
        XCTAssertTrue(WatchPrivacyMask.hidesSecrets(isActive: true, isLuminanceReduced: true))
        XCTAssertTrue(WatchPrivacyMask.hidesSecrets(isActive: false, isLuminanceReduced: true))
    }

    func testRolloverHapticFiresOncePerBoundaryAndOnlyWhenEnabled() {
        var memory = RolloverHapticMemory()
        XCTAssertFalse(memory.consume(period: 0, periodIndex: 1, enabled: true))
        XCTAssertFalse(memory.consume(period: 30, periodIndex: 4, enabled: true))
        XCTAssertFalse(memory.consume(period: 30, periodIndex: 4, enabled: true))
        XCTAssertFalse(memory.consume(period: 30, periodIndex: 5, enabled: false))
        XCTAssertFalse(memory.consume(period: 30, periodIndex: 5, enabled: true))
        XCTAssertTrue(memory.consume(period: 30, periodIndex: 6, enabled: true))
        XCTAssertFalse(memory.consume(period: 30, periodIndex: 6, enabled: true))

        var sharedBoundary = RolloverHapticMemory()
        XCTAssertFalse(sharedBoundary.consume(period: 30, periodIndex: 1, enabled: true))
        XCTAssertTrue(sharedBoundary.consume(period: 30, periodIndex: 2, enabled: true))
        XCTAssertFalse(sharedBoundary.consume(period: 60, periodIndex: 0, enabled: true))
        XCTAssertFalse(sharedBoundary.consume(period: 60, periodIndex: 1, enabled: true))
    }

    func testListKeepsCrownScrollingAndSortOrder() throws {
        let list = try watchAppSource("TokenListView.swift")
        XCTAssertTrue(list.contains("EmptyChick"))
        XCTAssertTrue(list.contains("EmptyStateBlob"))
        XCTAssertFalse(list.contains("Scan a QR code"))
        XCTAssertFalse(list.contains("Import codes"))
        XCTAssertTrue(list.contains(".listStyle(.plain)"))
        XCTAssertFalse(list.contains("scrollDisabled"))
        XCTAssertFalse(list.contains("digitalCrownRotation"))
        XCTAssertTrue(list.contains("$0.sortOrder < $1.sortOrder"))
        XCTAssertFalse(list.contains("isFavorite"))

        let row = try watchAppSource("TokenRowView.swift")
        XCTAssertTrue(row.contains(".privacySensitive()"))
        XCTAssertTrue(row.contains("isLuminanceReduced"))
        XCTAssertTrue(row.contains("scenePhase"))
        XCTAssertTrue(row.contains("WatchPhoneCopy.title"))
        XCTAssertTrue(row.contains("swipeActions"))
        XCTAssertTrue(row.contains("Image(systemName: \"iphone\")"))
        XCTAssertTrue(row.contains(".accessibilityLabel(WatchPhoneCopy.title)"))
        XCTAssertTrue(row.contains("allowsCopy"))
        XCTAssertFalse(row.contains("contextMenu"))
        XCTAssertEqual(WatchPhoneCopy.title, "Copy to iPhone")
        XCTAssertFalse(row.contains("sendMessage"))
        XCTAssertFalse(row.contains("UIPasteboard"))
        XCTAssertFalse(row.contains("transferUserInfo"))
        XCTAssertFalse(row.contains("print("))
    }

    private func watchAppSource(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WatchApp")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testDisplayPreferencesAreNotSecrets() throws {
        XCTAssertEqual(WatchDisplayPreference.shieldedModeKey, "ente.auth.watch.shieldedMode")
        XCTAssertEqual(WatchDisplayPreference.rolloverHapticKey, "ente.auth.watch.rolloverHaptic")
        XCTAssertFalse(WatchDisplayPreference.shieldedModeKey.contains("secret"))
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WatchApp")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let swiftFiles = files.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(swiftFiles.isEmpty)
        for file in swiftFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("UserDefaults.standard.set"), file.lastPathComponent)
            XCTAssertFalse(text.contains("kSecAttr"), file.lastPathComponent)
            XCTAssertFalse(text.contains("print("), file.lastPathComponent)
        }
    }

    func testEmptyStatesUseShortCopy() {
        XCTAssertFalse(WatchListCopy.emptyTitle.isEmpty)
        XCTAssertTrue(WatchListCopy.emptyDetail.contains("#watch"))
        XCTAssertEqual(WatchListCopy.passcodeTitle, "Passcode required")
        XCTAssertEqual(
            WatchKeychainManager.passcodeRequiredMessage,
            "Passcode required on Apple Watch to sync tokens"
        )
        XCTAssertFalse(WatchListCopy.lockedDetail.contains("755224"))
        XCTAssertLessThan(WatchListCopy.emptyTitle.count, 40)
        XCTAssertLessThan(WatchListCopy.lockedTitle.count, 40)
    }
}
