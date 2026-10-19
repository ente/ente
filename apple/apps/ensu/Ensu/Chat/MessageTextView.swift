import SwiftUI
import UIKit

struct MessageTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let moveCursorToEndToken: UUID
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = TextView(usingTextLayoutManager: true)
        view.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onSubmit()
        }
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: 15)
        view.textColor = UIColor(EnsuColor.textPrimary)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = true
        view.alwaysBounceVertical = false
        view.autocapitalizationType = .sentences
        view.accessibilityLabel = "Ask Ensu"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.undoManager?.removeAllActions()
            uiView.text = text
        }
        if context.coordinator.lastCursorToken != moveCursorToEndToken {
            context.coordinator.lastCursorToken = moveCursorToEndToken
            uiView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        if isFocused != uiView.isFirstResponder {
            DispatchQueue.main.async { [weak uiView, weak coordinator = context.coordinator] in
                guard let uiView, let coordinator else { return }
                if coordinator.parent.isFocused {
                    uiView.becomeFirstResponder()
                } else {
                    uiView.resignFirstResponder()
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize?
    {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        return CGSize(width: width, height: Self.height(for: text, width: width))
    }

    private static func height(for text: String, width: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 15)
        let maximumHeight = ceil(font.lineHeight * 5)
        let scalars = text.unicodeScalars.prefix(1025)
        guard scalars.count <= 1024 else { return maximumHeight }
        let sample = String(String.UnicodeScalarView(scalars)) + "\u{200B}"
        let bounds = (sample as NSString).boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font], context: nil)
        return ceil(min(maximumHeight, max(font.lineHeight, bounds.height)))
    }

    private final class TextView: UITextView {
        var onSubmit: (() -> Void)?

        override var keyCommands: [UIKeyCommand]? {
            let submit = UIKeyCommand(
                input: "\r", modifierFlags: .command, action: #selector(submitMessage))
            submit.wantsPriorityOverSystemBehavior = true
            return (super.keyCommands ?? []) + [submit]
        }

        @objc private func submitMessage() {
            guard markedTextRange == nil else { return }
            onSubmit?()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MessageTextView
        var lastCursorToken: UUID?

        init(_ parent: MessageTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}
