import Foundation
import Intents
import MessageUI
import UIKit

@MainActor
public final class MailComposer: NSObject, MFMailComposeViewControllerDelegate {
    private var preparationID: UUID?
    private var activeController: UIViewController?
    private var isClosed = false

    public override init() {
        super.init()
    }

    public func compose(_ request: MailRequest, presenter: UIViewController) async -> MailResult {
        guard !isClosed else {
            return .unavailable(.presentationFailed)
        }
        guard preparationID == nil, activeController == nil else {
            return .unavailable(.composerBusy)
        }
        let identifier = UUID()
        preparationID = identifier
        defer {
            if preparationID == identifier {
                preparationID = nil
            }
        }

        guard let attachment = request.attachment else {
            guard let url = request.mailtoURL else {
                return .unavailable(.presentationFailed)
            }
            let opened = await withCheckedContinuation { continuation in
                UIApplication.shared.open(url, options: [:]) { success in
                    continuation.resume(returning: success)
                }
            }
            guard preparationID == identifier else {
                return .unavailable(.presentationFailed)
            }
            if opened {
                return .launched
            }
            if #unavailable(iOS 18.0) {
                return .unavailable(.noMailClient)
            }
            return await presentShareSheet(for: request, attachment: nil, from: presenter)
        }

        if !MFMailComposeViewController.canSendMail() {
            let failure = await Task.detached(priority: .userInitiated) {
                AttachmentLoader.validationFailure(for: attachment)
            }.value
            guard preparationID == identifier else {
                return .unavailable(.presentationFailed)
            }
            if let failure {
                return .unavailable(failure)
            }
            if #unavailable(iOS 18.0) {
                return .unavailable(.attachmentComposerUnavailable)
            }
            return await presentShareSheet(
                for: request,
                attachment: attachment,
                from: presenter
            )
        }

        let loaded = await Task.detached(priority: .userInitiated) {
            AttachmentLoader.load(attachment)
        }.value
        guard preparationID == identifier else {
            return .unavailable(.presentationFailed)
        }
        let attachmentData: Data
        switch loaded {
        case let .success(data):
            attachmentData = data
        case let .failure(reason):
            return .unavailable(reason)
        }

        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = self
        controller.setToRecipients([request.recipient])
        controller.setSubject(request.subject)
        controller.setMessageBody(request.body, isHTML: false)
        controller.addAttachmentData(
            attachmentData,
            mimeType: attachment.mimeType,
            fileName: attachment.url.lastPathComponent
        )
        return await present(controller, from: presenter)
    }

    private func presentShareSheet(
        for request: MailRequest,
        attachment: MailAttachment?,
        from presenter: UIViewController
    ) async -> MailResult {
        let draft = DraftItemSource(
            recipient: request.recipient,
            subject: request.subject,
            body: request.body
        )
        var activityItems: [Any] = [draft]
        if let attachment {
            activityItems.append(attachment.url)
        }
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { [weak self, weak controller] _, _, _, _ in
            Task { @MainActor in
                guard let self, self.activeController === controller else { return }
                self.activeController = nil
            }
        }
        return await present(controller, from: presenter)
    }

    private func present(
        _ controller: UIViewController,
        from presenter: UIViewController
    ) async -> MailResult {
        let visiblePresenter = presenter.visibleController
        guard visiblePresenter.viewIfLoaded?.window != nil else {
            return .unavailable(.presentationFailed)
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = visiblePresenter.view
            popover.sourceRect = CGRect(
                x: visiblePresenter.view.bounds.midX,
                y: visiblePresenter.view.bounds.midY,
                width: 0,
                height: 0
            )
        }
        activeController = controller
        await withCheckedContinuation { continuation in
            visiblePresenter.present(controller, animated: true) {
                continuation.resume()
            }
        }
        guard controller.presentingViewController != nil else {
            activeController = nil
            return .unavailable(.presentationFailed)
        }
        return .launched
    }

    public func close() {
        isClosed = true
        preparationID = nil
        activeController?.dismiss(animated: false)
        activeController = nil
    }

    public nonisolated func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith _: MFMailComposeResult,
        error _: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self, activeController === controller else { return }
            activeController = nil
            controller.dismiss(animated: true)
        }
    }
}

private final class DraftItemSource: NSObject, UIActivityItemSource {
    private let recipient: String
    private let subject: String
    private let body: String

    init(recipient: String, subject: String, body: String) {
        self.recipient = recipient
        self.subject = subject
        self.body = body
    }

    func activityViewControllerPlaceholderItem(_: UIActivityViewController) -> Any {
        body
    }

    func activityViewController(
        _: UIActivityViewController,
        itemForActivityType _: UIActivity.ActivityType?
    ) -> Any? {
        body
    }

    func activityViewController(
        _: UIActivityViewController,
        subjectForActivityType _: UIActivity.ActivityType?
    ) -> String {
        subject
    }

    @available(iOS 18.0, *)
    func activityViewControllerShareRecipients(_: UIActivityViewController) -> [INPerson] {
        let handle = INPersonHandle(value: recipient, type: .emailAddress)
        return [
            INPerson(
                personHandle: handle,
                nameComponents: nil,
                displayName: recipient,
                image: nil,
                contactIdentifier: nil,
                customIdentifier: nil
            )
        ]
    }
}

private extension UIViewController {
    var visibleController: UIViewController {
        if let presented = presentedViewController, !presented.isBeingDismissed {
            return presented.visibleController
        }
        if let navigation = self as? UINavigationController,
            let visible = navigation.visibleViewController
        {
            return visible.visibleController
        }
        if let tab = self as? UITabBarController,
            let selected = tab.selectedViewController
        {
            return selected.visibleController
        }
        return self
    }
}
