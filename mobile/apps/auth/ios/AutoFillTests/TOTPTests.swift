import XCTest
@testable import AuthAutoFillCore

final class TOTPTests: XCTestCase {
    private let sha1 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    private let sha256 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA===="
    private let sha512 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA="

    private func entry(_ secret: String, algorithm: String = "sha1", digits: Int = 8, period: Int = 30) -> AutoFillEntry {
        AutoFillEntry(id: "offline:1", issuer: "Example", account: "alice", secret: secret,
                      algorithm: algorithm, digits: digits, period: period)
    }

    func testRFC6238Vectors() throws {
        let vectors: [(TimeInterval, String, String, String)] = [
            (59, "94287082", "46119246", "90693936"),
            (1111111109, "07081804", "68084774", "25091201"),
            (1111111111, "14050471", "67062674", "99943326"),
            (1234567890, "89005924", "91819424", "93441116"),
            (2000000000, "69279037", "90698825", "38618901"),
            (20000000000, "65353130", "77737706", "47863826"),
        ]
        for (time, expectedSHA1, expectedSHA256, expectedSHA512) in vectors {
            XCTAssertEqual(try TOTP.generate(entry(sha1), time: time), expectedSHA1)
            XCTAssertEqual(try TOTP.generate(entry(sha256, algorithm: "sha256"), time: time), expectedSHA256)
            XCTAssertEqual(try TOTP.generate(entry(sha512, algorithm: "sha512"), time: time), expectedSHA512)
        }
    }

    func testCustomPeriodAndSixDigits() throws {
        XCTAssertEqual(try TOTP.generate(entry(sha1, digits: 6, period: 60), time: 119), "287082")
        XCTAssertNotEqual(try TOTP.generate(entry(sha1, digits: 6, period: 60), time: 120), "287082")
    }

    func testLowercaseAndSpaces() throws {
        XCTAssertEqual(try TOTP.generate(entry("  gezdgnbv gy3tqojq gezdgnbv gy3tqojq  "), time: 59), "94287082")
    }

    func testInvalidParametersAndSecrets() {
        for secret in ["", "!", "A", "M=Y", "MY=BAD"] {
            XCTAssertThrowsError(try TOTP.generate(entry(secret), time: 59))
        }
        XCTAssertThrowsError(try TOTP.generate(entry(sha1, period: 0), time: 59))
        XCTAssertThrowsError(try TOTP.generate(entry(sha1, digits: 0), time: 59))
        XCTAssertThrowsError(try TOTP.generate(entry(sha1, digits: 11), time: 59))
        XCTAssertThrowsError(try TOTP.generate(entry(sha1, algorithm: "md5"), time: 59))
        XCTAssertThrowsError(try TOTP.generate(entry(sha1), time: -1))
        XCTAssertThrowsError(try TOTP.generate(entry(sha1), time: .infinity))
    }
}
