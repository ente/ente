import EnteFonts
import SwiftUI
import UIKit

public struct PasswordField<Trailing: View>: View {
    @Binding private var text: String
    @State private var focused = false
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    private let label: String?
    private let required: Bool
    private let isRevealed: Bool
    private let placeholder: String
    private let message: String?
    private let state: InputState
    private let contentType: UITextContentType
    private let returnKeyType: UIReturnKeyType
    private let onSubmit: () -> Void
    private let trailing: Trailing

    public init(
        _ label: String? = nil,
        text: Binding<String>,
        required: Bool = false,
        isRevealed: Bool = false,
        placeholder: String = "",
        message: String? = nil,
        state: InputState = .normal,
        contentType: UITextContentType = .password,
        returnKeyType: UIReturnKeyType = .done,
        onSubmit: @escaping () -> Void = {},
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
    ) {
        self.label = label
        self.required = required
        _text = text
        self.isRevealed = isRevealed
        self.placeholder = placeholder
        self.message = message
        self.state = state
        self.contentType = contentType
        self.returnKeyType = returnKeyType
        self.onSubmit = onSubmit
        self.trailing = trailing()
    }

    public var body: some View {
        InputFrame(
            label: label, required: required, message: message, state: state, focused: focused,
            focus: { focused = true }
        ) {
            PasswordEditor(
                text: $text, focused: $focused, isRevealed: isRevealed,
                label: label ?? placeholder, placeholder: placeholder, enabled: enabled,
                textColor: UIColor(enabled ? palette.text : palette.disabledText),
                hintColor: UIColor(enabled ? palette.hintText : palette.disabledText),
                tintColor: UIColor(palette.primary), contentType: contentType,
                returnKeyType: returnKeyType, onSubmit: onSubmit
            )
            .privacySensitive()
        } trailing: {
            trailing
        }
        .onChange(of: enabled) { enabled in
            if !enabled { focused = false }
        }
    }
}

private struct PasswordEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let isRevealed: Bool
    let label: String
    let placeholder: String
    let enabled: Bool
    let textColor: UIColor
    let hintColor: UIColor
    let tintColor: UIColor
    let contentType: UITextContentType
    let returnKeyType: UIReturnKeyType
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator, action: #selector(Coordinator.changed), for: .editingChanged)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.font = .inter(size: 14, weight: .medium)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = textColor
        field.tintColor = tintColor
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder, attributes: [.foregroundColor: hintColor])
        field.accessibilityLabel = label
        field.isEnabled = enabled
        field.textContentType = contentType
        field.returnKeyType = returnKeyType
        if field.text != text { field.text = text }
        if field.isSecureTextEntry == isRevealed {
            let selection = field.selectedTextRange
            field.isSecureTextEntry = !isRevealed
            if field.isFirstResponder {
                field.text = ""
                field.insertText(text)
                field.selectedTextRange = selection
            }
        }
        if focused && enabled && !field.isFirstResponder { field.becomeFirstResponder() }
        if (!focused || !enabled) && field.isFirstResponder { field.resignFirstResponder() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context)
        -> CGSize?
    {
        CGSize(
            width: proposal.width ?? uiView.intrinsicContentSize.width,
            height: uiView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PasswordEditor
        init(_ parent: PasswordEditor) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            let value = field.text ?? ""
            if parent.text != value { parent.text = value }
        }
        func textFieldDidBeginEditing(_ field: UITextField) { parent.focused = true }
        func textFieldDidEndEditing(_ field: UITextField) { parent.focused = false }
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }
    }
}
