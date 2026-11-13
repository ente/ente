import SwiftUI

public struct InputField<Leading: View, Trailing: View>: View {
    @Binding private var text: String
    @FocusState private var focused: Bool
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    private let label: String?
    private let required: Bool
    private let placeholder: String
    private let message: String?
    private let state: InputState
    private let lines: ClosedRange<Int>
    private let leading: Leading
    private let trailing: Trailing

    public init(
        text: Binding<String>,
        label: String? = nil,
        required: Bool = false,
        placeholder: String = "",
        message: String? = nil,
        state: InputState = .normal,
        lines: ClosedRange<Int> = 1...1,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
    ) {
        _text = text
        self.label = label
        self.required = required
        self.placeholder = placeholder
        self.message = message
        self.state = state
        self.lines = lines
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        let prompt = Text(placeholder)
            .foregroundColor(enabled ? palette.hintText : palette.disabledText)
        InputFrame(
            label: label, required: required, message: message, state: state, focused: focused,
            focus: { focused = true }
        ) {
            HStack(spacing: EnteSpacing.sm) {
                leading.foregroundStyle(enabled ? palette.hintText : palette.disabledText)
                TextField(
                    label ?? placeholder, text: $text, prompt: prompt,
                    axis: lines.upperBound == 1 ? .horizontal : .vertical
                )
                .lineLimit(lines)
                .focused($focused)
                .accessibilityLabel(label ?? placeholder)
            }
        } trailing: {
            trailing
        }
    }
}
