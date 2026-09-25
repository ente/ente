import Foundation

public enum MailUnavailableReason: String, Error, Sendable {
    case noMailClient
    case attachmentComposerUnavailable
    case attachmentMissing
    case attachmentUnreadable
    case attachmentTooLarge
    case composerBusy
    case presentationFailed
}

public enum MailResult: Sendable {
    case launched
    case unavailable(MailUnavailableReason)
}

public struct MailAttachment: Sendable {
    public let url: URL
    public let mimeType: String

    public init(path: String, mimeType: String) throws {
        guard path.hasPrefix("/") else {
            throw MailValidationError("Attachment path must be absolute")
        }
        guard Self.validMIMEType(mimeType) else {
            throw MailValidationError("Attachment MIME type is invalid")
        }
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent
        guard fileName.isSafeFileName else {
            throw MailValidationError("Attachment filename is invalid")
        }
        self.url = url
        self.mimeType = mimeType
    }

    private static func validMIMEType(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&^_.+-")
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy(allowed.contains)
        }
    }
}

public struct MailRequest: Sendable {
    public let recipient: String
    public let subject: String
    public let body: String
    public let attachment: MailAttachment?

    public init(
        recipient: String,
        subject: String,
        body: String,
        attachment: MailAttachment?
    ) throws {
        guard !recipient.isEmpty,
            recipient == recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw MailValidationError("Recipient is invalid")
        }
        guard ![recipient, subject, body].contains(where: { $0.contains("\0") }) else {
            throw MailValidationError("Mail text contains a null byte")
        }
        self.recipient = recipient
        self.subject = subject
        self.body = body
        self.attachment = attachment
    }

    var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            subject.isEmpty ? nil : URLQueryItem(name: "subject", value: subject),
            body.isEmpty ? nil : URLQueryItem(name: "body", value: body),
        ].compactMap { $0 }
        return components.url
    }
}

enum AttachmentLoader {
    static let maximumBytes: Int64 = 20 * 1024 * 1024

    static func validationFailure(for attachment: MailAttachment) -> MailUnavailableReason? {
        let path = attachment.url.path
        guard FileManager.default.fileExists(atPath: path) else {
            return .attachmentMissing
        }
        guard FileManager.default.isReadableFile(atPath: path),
            let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            let size = attributes[.size] as? NSNumber
        else {
            return .attachmentUnreadable
        }
        guard size.int64Value <= maximumBytes else {
            return .attachmentTooLarge
        }
        return nil
    }

    static func load(_ attachment: MailAttachment) -> Result<Data, MailUnavailableReason> {
        if let failure = validationFailure(for: attachment) {
            return .failure(failure)
        }
        do {
            return .success(try Data(contentsOf: attachment.url, options: .mappedIfSafe))
        } catch {
            return .failure(.attachmentUnreadable)
        }
    }
}

struct MailValidationError: LocalizedError {
    init(_ message: String) {
        self.message = message
    }

    let message: String
    var errorDescription: String? { message }
}

private extension String {
    var isSafeFileName: Bool {
        !isEmpty && self != "." && self != ".." && !contains("/") && !contains("\\")
            && unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}
