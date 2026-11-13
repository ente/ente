import Foundation
import XCTest

@testable import MailCore

final class MailModelsTests: XCTestCase {
    func testMailtoURLPreservesContent() throws {
        let request = try MailRequest(
            recipient: "support@ente.io",
            subject: "Logs & diagnostics",
            body: "First line\nSecond line",
            attachment: nil
        )

        let components = try XCTUnwrap(
            request.mailtoURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        )
        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, "support@ente.io")
        XCTAssertEqual(
            components.queryItems,
            [
                URLQueryItem(name: "subject", value: "Logs & diagnostics"),
                URLQueryItem(name: "body", value: "First line\nSecond line"),
            ]
        )
    }

    func testAttachmentRequiresSafeMetadata() {
        XCTAssertThrowsError(
            try MailAttachment(
                path: "logs.zip",
                mimeType: "application/zip"
            )
        )
        XCTAssertThrowsError(
            try MailAttachment(
                path: "/tmp/logs.zip",
                mimeType: "zip"
            )
        )
        XCTAssertThrowsError(
            try MailAttachment(
                path: "/",
                mimeType: "application/zip"
            )
        )
    }

    func testAttachmentLoaderReportsMissingAndOversizedFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let missing = try MailAttachment(
            path: directory.appendingPathComponent("missing.zip").path,
            mimeType: "application/zip"
        )
        XCTAssertEqual(
            AttachmentLoader.validationFailure(for: missing),
            .attachmentMissing
        )

        let oversizedURL = directory.appendingPathComponent("oversized.zip")
        FileManager.default.createFile(atPath: oversizedURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: oversizedURL)
        try handle.truncate(atOffset: UInt64(AttachmentLoader.maximumBytes + 1))
        try handle.close()
        let oversized = try MailAttachment(
            path: oversizedURL.path,
            mimeType: "application/zip"
        )
        XCTAssertEqual(
            AttachmentLoader.validationFailure(for: oversized),
            .attachmentTooLarge
        )
    }
}
