@preconcurrency import Flutter
import Foundation
import UIKit

@MainActor
public final class MailPlugin: NSObject, @preconcurrency FlutterPlugin {
    private let composer = MailComposer()
    private var isDetached = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.ente.mail/composer",
            binaryMessenger: registrar.messenger()
        )
        let instance = MailPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.publish(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "compose" else {
            result(FlutterMethodNotImplemented)
            return
        }
        let request: MailRequest
        do {
            request = try call.mailRequest()
        } catch {
            result(
                FlutterError(
                    code: "invalidDraft",
                    message: error.localizedDescription,
                    details: nil
                )
            )
            return
        }
        guard let presenter = UIApplication.shared.activePresenter else {
            result(MailResult.unavailable(.presentationFailed).channelValue)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let value = await composer.compose(request, presenter: presenter).channelValue
            guard !isDetached else { return }
            result(value)
        }
    }

    public func detachFromEngine(for _: FlutterPluginRegistrar) {
        isDetached = true
        composer.close()
    }
}

private extension UIApplication {
    var activePresenter: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

private extension FlutterMethodCall {
    func mailRequest() throws -> MailRequest {
        guard let arguments = arguments as? [String: Any] else {
            throw MailValidationError("Mail draft is missing")
        }
        func string(_ name: String) throws -> String {
            guard let value = arguments[name] as? String else {
                throw MailValidationError("Mail draft has no \(name)")
            }
            return value
        }

        let attachment: MailAttachment?
        if let value = arguments["attachment"] {
            guard let map = value as? [String: Any],
                let path = map["path"] as? String,
                let mimeType = map["mimeType"] as? String
            else {
                throw MailValidationError("Attachment is invalid")
            }
            attachment = try MailAttachment(
                path: path,
                mimeType: mimeType
            )
        } else {
            attachment = nil
        }
        return try MailRequest(
            recipient: string("recipient"),
            subject: string("subject"),
            body: string("body"),
            attachment: attachment
        )
    }
}

private extension MailResult {
    var channelValue: [String: String] {
        switch self {
        case .launched:
            return ["status": "launched"]
        case let .unavailable(reason):
            return ["status": "unavailable", "reason": reason.rawValue]
        }
    }
}
