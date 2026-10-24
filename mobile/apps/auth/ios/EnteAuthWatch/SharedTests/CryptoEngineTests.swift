import XCTest
@testable import EnteAuthWatch

internal final class CryptoEngineTests: XCTestCase {
    private let sha1Key = Data("12345678901234567890".utf8)
    private let sha256Key = Data("12345678901234567890123456789012".utf8)
    private let sha512Key = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)

    func testRFC4226CountZeroAndOne() {
        XCTAssertEqual(sha1Key.count, 20)
        XCTAssertEqual(
            TOTPCalculator.hotp(key: sha1Key, counter: 0, algorithm: .sha1, digits: 6),
            "755224"
        )
        XCTAssertEqual(
            TOTPCalculator.hotp(key: sha1Key, counter: 1, algorithm: .sha1, digits: 6),
            "287082"
        )
    }

    func testRFC6238Time59EightDigits() {
        let date = Date(timeIntervalSince1970: 59)
        XCTAssertEqual(sha256Key.count, 32)
        XCTAssertEqual(sha512Key.count, 64)

        let sha1 = TOTPCalculator.generateCode(
            secret: SecretBuffer(data: sha1Key),
            algorithm: .sha1,
            digits: 8,
            period: 30,
            date: date
        )
        XCTAssertEqual(sha1.current, "94287082")
        XCTAssertEqual(sha1.remainingSeconds, 1)

        let sha256 = TOTPCalculator.generateCode(
            secret: SecretBuffer(data: sha256Key),
            algorithm: .sha256,
            digits: 8,
            period: 30,
            date: date
        )
        XCTAssertEqual(sha256.current, "46119246")

        let sha512 = TOTPCalculator.generateCode(
            secret: SecretBuffer(data: sha512Key),
            algorithm: .sha512,
            digits: 8,
            period: 30,
            date: date
        )
        XCTAssertEqual(sha512.current, "90693936")
    }

    func testRFC6238LeadingZero() {
        let code = TOTPCalculator.generateCode(
            secret: SecretBuffer(data: sha1Key),
            algorithm: .sha1,
            digits: 8,
            period: 30,
            date: Date(timeIntervalSince1970: 1_111_111_109)
        )
        XCTAssertEqual(code.current, "07081804")
    }

    func testNextCodeIsFollowingCounter() {
        let date = Date(timeIntervalSince1970: 59)
        let secret = SecretBuffer(data: sha1Key)
        let generated = TOTPCalculator.generateCode(
            secret: secret,
            algorithm: .sha1,
            digits: 8,
            period: 30,
            date: date
        )
        let following = TOTPCalculator.hotp(key: sha1Key, counter: 2, algorithm: .sha1, digits: 8)
        XCTAssertTrue(generated.next == following, "next code must be HOTP at counter+1")
    }

    func testRemainingSecondsAtWindowBoundary() {
        let secret = SecretBuffer(data: sha1Key)
        let started = TOTPCalculator.generateCode(
            secret: secret,
            algorithm: .sha1,
            digits: 8,
            period: 30,
            date: Date(timeIntervalSince1970: 60)
        )
        XCTAssertEqual(started.remainingSeconds, 30)
        let epoch = TOTPCalculator.generateCode(
            secret: secret,
            algorithm: .sha1,
            digits: 8,
            period: 30,
            date: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(epoch.remainingSeconds, 30)
    }

    func testRFC4226AppendixDSixDigits() {
        let vectors = [
            "755224", "287082", "359152", "969429", "338314",
            "254676", "287922", "162583", "399871", "520489",
        ]
        for (count, expected) in vectors.enumerated() {
            XCTAssertEqual(
                TOTPCalculator.hotp(key: sha1Key, counter: UInt64(count), algorithm: .sha1, digits: 6),
                expected,
                "RFC 4226 count \(count)"
            )
        }
    }

    func testRFC6238AppendixBRemainingTimes() {
        let rows: [(TimeInterval, String, String, String)] = [
            (1_111_111_109, "07081804", "68084774", "25091201"),
            (1_111_111_111, "14050471", "67062674", "99943326"),
            (1_234_567_890, "89005924", "91819424", "93441116"),
            (2_000_000_000, "69279037", "90698825", "38618901"),
            (20_000_000_000, "65353130", "77737706", "47863826"),
        ]
        for row in rows {
            let date = Date(timeIntervalSince1970: row.0)
            XCTAssertEqual(code(sha1Key, .sha1, 8, 30, date), row.1, "SHA1 \(row.0)")
            XCTAssertEqual(code(sha256Key, .sha256, 8, 30, date), row.2, "SHA256 \(row.0)")
            XCTAssertEqual(code(sha512Key, .sha512, 8, 30, date), row.3, "SHA512 \(row.0)")
        }
    }

    func testSevenDigitsAndNonDefaultPeriod() {
        XCTAssertEqual(
            TOTPCalculator.hotp(key: sha1Key, counter: 0, algorithm: .sha1, digits: 7),
            "4755224"
        )
        XCTAssertEqual(TOTPCalculator.modulus(digits: 7), 10_000_000)
        let before = TOTPCalculator.generateCode(
            secret: SecretBuffer(data: sha1Key),
            algorithm: .sha1,
            digits: 8,
            period: 60,
            date: Date(timeIntervalSince1970: 59)
        )
        XCTAssertEqual(before.current, "84755224")
        XCTAssertEqual(before.next, "94287082")
        XCTAssertEqual(before.remainingSeconds, 1)
        let after = TOTPCalculator.generateCode(
            secret: SecretBuffer(data: sha1Key),
            algorithm: .sha1,
            digits: 8,
            period: 60,
            date: Date(timeIntervalSince1970: 60)
        )
        XCTAssertEqual(after.current, "94287082")
        XCTAssertEqual(after.remainingSeconds, 60)
    }

    func testPeriodRolloverChangesCounter() {
        let secret = SecretBuffer(data: sha1Key)
        let before = TOTPCalculator.generateCode(
            secret: secret,
            algorithm: .sha1,
            digits: 6,
            period: 30,
            date: Date(timeIntervalSince1970: 29)
        )
        let after = TOTPCalculator.generateCode(
            secret: secret,
            algorithm: .sha1,
            digits: 6,
            period: 30,
            date: Date(timeIntervalSince1970: 30)
        )
        XCTAssertEqual(before.current, "755224")
        XCTAssertEqual(before.remainingSeconds, 1)
        XCTAssertEqual(after.current, "287082")
        XCTAssertEqual(after.remainingSeconds, 30)
        XCTAssertEqual(before.next, after.current)
    }

    func testSecretBufferWipeZeroesBytes() throws {
        var bytes: [UInt8] = [0x11, 0x22, 0x33, 0x44]
        SecretBuffer.wipe(&bytes)
        XCTAssertEqual(bytes, [0, 0, 0, 0])
        let source = try String(contentsOf: sharedSource("SecretBuffer.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("memset_s"))
        XCTAssertTrue(source.contains("deinit"))
    }

    func testIntegerModulus() throws {
        XCTAssertEqual(TOTPCalculator.modulus(digits: 6), 1_000_000)
        XCTAssertEqual(TOTPCalculator.modulus(digits: 8), 100_000_000)
        XCTAssertEqual(TOTPCalculator.modulus(digits: 10), 10_000_000_000)
        let source = try String(contentsOf: sharedSource("TOTPCalculator.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("pow("))
        XCTAssertFalse(source.contains("WCSession"))
        XCTAssertTrue(source.contains("value *= 10"))
    }

    func testSHA256DoesNotReturnSHA1Code() {
        XCTAssertEqual(sha256Key.count, 32)
        let sha256 = TOTPCalculator.hotp(key: sha256Key, counter: 1, algorithm: .sha256, digits: 8)
        let sha1 = TOTPCalculator.hotp(key: sha256Key, counter: 1, algorithm: .sha1, digits: 8)
        XCTAssertEqual(sha256, "46119246")
        XCTAssertTrue(sha256 != sha1, "SHA-256 must not return the SHA-1 code")
    }

    func testBase32SpecFixtureAndUnpaddedHello() throws {
        let fixture = try XCTUnwrap(Base32.decode("JBSWY3DPEHPK3PXP"))
        let fixtureBytes = fixture.withUnsafeBytes { [UInt8]($0) }
        let hello = [UInt8]("Hello!".utf8)
        // 16 alphabet characters are 10 bytes under RFC 4648: ASCII Hello! then 0xDEADBEEF.
        XCTAssertEqual(Array(fixtureBytes.prefix(hello.count)), hello)
        XCTAssertEqual(fixtureBytes, hello + [0xde, 0xad, 0xbe, 0xef])

        let unpadded = try XCTUnwrap(Base32.decode("JBSWY3DPEE"))
        XCTAssertEqual(unpadded.withUnsafeBytes { [UInt8]($0) }, hello)
        let padded = try XCTUnwrap(Base32.decode("JBSWY3DPEE======"))
        XCTAssertEqual(padded.withUnsafeBytes { [UInt8]($0) }, hello)
    }

    func testBase32RejectsInvalidAlphabet() {
        XCTAssertNil(Base32.decode("JBSWY3DPEHPK3PX1"))
        XCTAssertNil(Base32.decode("JBSWY3DP EHPK"))
        XCTAssertNil(Base32.decode("M"))
        XCTAssertNil(Base32.decode("MZX"))
        XCTAssertNil(Base32.decode("JBSWY3DPEE====="))
    }

    func testBase32LowercaseMatchesUppercase() throws {
        let upper = try XCTUnwrap(Base32.decode("JBSWY3DPEE"))
        let lower = try XCTUnwrap(Base32.decode("jbswy3dpee"))
        let paddedLower = try XCTUnwrap(Base32.decode("jbswy3dpee======"))
        let upperBytes = upper.withUnsafeBytes { [UInt8]($0) }
        XCTAssertEqual(lower.withUnsafeBytes { [UInt8]($0) }, upperBytes)
        XCTAssertEqual(paddedLower.withUnsafeBytes { [UInt8]($0) }, upperBytes)
        XCTAssertEqual(upperBytes, [UInt8]("Hello!".utf8))
    }

    func testBase32RFC4648Foobar() throws {
        let unpadded = try XCTUnwrap(Base32.decode("MZXW6YTBOI"))
        XCTAssertEqual(unpadded.withUnsafeBytes { [UInt8]($0) }, [UInt8]("foobar".utf8))
        let padded = try XCTUnwrap(Base32.decode("MY======"))
        XCTAssertEqual(padded.withUnsafeBytes { [UInt8]($0) }, [UInt8]("f".utf8))
        let missingPad = try XCTUnwrap(Base32.decode("MY"))
        XCTAssertEqual(missingPad.withUnsafeBytes { [UInt8]($0) }, [UInt8]("f".utf8))
    }

    func testEnvelopeJSONRoundTripFieldNames() throws {
        let envelope = WatchSyncEnvelope(
            version: 1,
            timestamp: 1_775_736_000,
            syncType: "DELTA",
            tokens: [
                WatchToken(
                    id: "42",
                    issuer: "GitHub",
                    account: "octocat@github.com",
                    secret: "JBSWY3DPEHPK3PXP",
                    algorithm: .sha1,
                    digits: 6,
                    period: 30,
                    isFavorite: true,
                    sortOrder: 0
                ),
            ],
            deletedIds: ["7"]
        )
        let data = try JSONEncoder().encode(envelope)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            Set(["version", "timestamp", "syncType", "tokens", "deletedIds"])
        )
        let tokenObject = try XCTUnwrap((object["tokens"] as? [[String: Any]])?.first)
        XCTAssertEqual(
            Set(tokenObject.keys),
            Set(["id", "issuer", "account", "secret", "algorithm", "digits", "period", "isFavorite", "sortOrder"])
        )
        XCTAssertEqual(tokenObject["algorithm"] as? String, "SHA1")
        XCTAssertEqual(tokenObject["secret"] as? String, "JBSWY3DPEHPK3PXP")

        let decoded = try JSONDecoder().decode(WatchSyncEnvelope.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.timestamp, 1_775_736_000)
        XCTAssertEqual(decoded.syncType, "DELTA")
        XCTAssertEqual(decoded.deletedIds, ["7"])
        XCTAssertEqual(decoded.tokens.count, 1)
        XCTAssertEqual(decoded.tokens[0].id, "42")
        XCTAssertEqual(decoded.tokens[0].issuer, "GitHub")
        XCTAssertEqual(decoded.tokens[0].account, "octocat@github.com")
        XCTAssertEqual(decoded.tokens[0].secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(decoded.tokens[0].algorithm, .sha1)
        XCTAssertEqual(decoded.tokens[0].digits, 6)
        XCTAssertEqual(decoded.tokens[0].period, 30)
        XCTAssertTrue(decoded.tokens[0].isFavorite)
        XCTAssertEqual(decoded.tokens[0].sortOrder, 0)
    }

    func testDisplayHasNoSecretField() {
        let display = WatchTokenDisplay(
            id: "42",
            issuer: "GitHub",
            account: "octocat@github.com",
            algorithm: .sha256,
            digits: 6,
            period: 30,
            sortOrder: 1,
            isFavorite: false
        )
        let labels = Mirror(reflecting: display).children.compactMap(\.label)
        XCTAssertFalse(labels.contains("secret"))
        XCTAssertEqual(display.algorithm, .sha256)
    }

    func testSourcesDoNotLogOrStoreSeedsOutsideKeychain() throws {
        let folder = sharedSource("WatchToken.swift").deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let swiftFiles = files.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(swiftFiles.isEmpty)
        for file in swiftFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            let name = file.lastPathComponent
            XCTAssertFalse(text.contains("UserDefaults"), name)
            XCTAssertFalse(text.contains("print("), name)
            XCTAssertFalse(text.contains("NSLog"), name)
            XCTAssertFalse(text.contains("debugPrint"), name)
            XCTAssertFalse(text.contains("dump("), name)
            XCTAssertFalse(text.contains("Logger("), name)
            XCTAssertFalse(text.contains("os.Logger"), name)
            XCTAssertFalse(text.contains("transferUserInfo"), name)
            XCTAssertFalse(text.contains("23456789BCDFGHJKMNPQRTVWXY"), name)
            if name == "TOTPCalculator.swift" {
                XCTAssertFalse(text.contains("WCSession"), name)
            }
        }
    }

    private func code(
        _ key: Data,
        _ algorithm: WatchToken.HashAlgorithm,
        _ digits: Int,
        _ period: Int,
        _ date: Date
    ) -> String {
        TOTPCalculator.generateCode(
            secret: SecretBuffer(data: key),
            algorithm: algorithm,
            digits: digits,
            period: period,
            date: date
        ).current
    }

    private func sharedSource(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Shared")
            .appendingPathComponent(name)
    }
}
