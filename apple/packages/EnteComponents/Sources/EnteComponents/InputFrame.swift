import SwiftUI

struct InputFrame<Field: View, Trailing: View>: View {
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    let label: String?
    var required = false
    let message: String?
    let state: InputState
    let focused: Bool
    let focus: () -> Void
    @ViewBuilder var field: Field
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EnteRadius.large, style: .continuous)
        VStack(alignment: .leading, spacing: EnteSpacing.sm) {
            if let label {
                HStack(spacing: 2) {
                    Text(label).foregroundStyle(enabled ? palette.text : palette.disabledText)
                    if required {
                        Text("*").font(EnteTypography.bodyBold).foregroundStyle(palette.danger)
                    }
                }
                .font(EnteTypography.body)
            }
            HStack(spacing: EnteSpacing.sm) {
                field
                    .textFieldStyle(.plain)
                    .accessibilityHint(state == .error ? message ?? "" : "")
                    .font(EnteTypography.body)
                    .foregroundStyle(enabled ? palette.text : palette.disabledText)
                    .tint(palette.primary)
                    .padding(.vertical, EnteSpacing.lg)
                trailing.foregroundStyle(enabled ? palette.hintText : palette.disabledText)
            }
            .padding(.horizontal, EnteSpacing.lg)
            .frame(minHeight: 52)
            .background {
                shape.fill(enabled ? palette.surface : palette.fill)
                    .onTapGesture(perform: focus)
            }
            .overlay {
                shape.strokeBorder(
                    state != .normal
                        ? statusColor : focused ? palette.hintText : palette.faintBorder,
                    lineWidth: 1)
            }
            if let message {
                Text(message).font(EnteTypography.mini).foregroundStyle(statusColor)
            }
        }
    }

    private var statusColor: Color {
        switch state {
        case .normal: palette.mutedText
        case .error: palette.danger
        case .success: palette.primary
        }
    }
}
