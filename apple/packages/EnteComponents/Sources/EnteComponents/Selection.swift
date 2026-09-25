import SwiftUI

public struct Checkmark: View {
    @Binding private var isOn: Bool
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    private let label: String
    private let subtitle: String?

    public init(_ label: String, isOn: Binding<Bool>, subtitle: String? = nil) {
        _isOn = isOn
        self.label = label
        self.subtitle = subtitle
    }

    public var body: some View {
        let fill = isOn ? (enabled ? palette.primary : palette.fillDarkest) : .clear
        Button {
            isOn.toggle()
        } label: {
            LabeledControl(label, subtitle: subtitle) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(
                                isOn ? fill : (enabled ? palette.mutedText : palette.faintBorder),
                                lineWidth: 1,
                            )
                    }
                    .overlay {
                        if isOn {
                            Glyph.checkRounded.image.resizable().scaledToFit()
                                .frame(width: 12, height: 12)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 16, height: 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(label, isOn: $isOn).toggleStyle(.automatic)
        }
        .accessibilityHint(subtitle ?? "")
    }
}

public struct Radio: View {
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    private let selected: Bool
    private let label: String
    private let subtitle: String?
    private let action: () -> Void

    public init(
        _ label: String,
        selected: Bool,
        subtitle: String? = nil,
        action: @escaping () -> Void,
    ) {
        self.selected = selected
        self.label = label
        self.subtitle = subtitle
        self.action = action
    }

    public var body: some View {
        let active = enabled ? palette.primary : palette.fillDarkest
        Button(action: action) {
            LabeledControl(label, subtitle: subtitle) {
                Circle()
                    .stroke(selected ? active : palette.border, lineWidth: selected ? 2 : 1)
                    .overlay {
                        if selected {
                            Circle().fill(active).padding(3)
                        }
                    }
                    .frame(width: 16, height: 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(subtitle ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

public struct EnteToggleStyle: ToggleStyle {
    @Environment(\.entePalette) private var palette

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: EnteSpacing.md)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isOn ? palette.primary : palette.fill)
                    .overlay {
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                            .padding(2)
                            .frame(
                                maxWidth: .infinity,
                                alignment: configuration.isOn ? .trailing : .leading,
                            )
                    }
                    .frame(width: 40, height: 24)
                    .animation(.easeInOut(duration: EnteMotion.quick), value: configuration.isOn)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.automatic)
        }
    }
}

private struct LabeledControl<Control: View>: View {
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    private let label: String
    private let subtitle: String?
    private let control: Control

    init(
        _ label: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Control,
    ) {
        self.label = label
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(spacing: EnteSpacing.md) {
            control
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(EnteTypography.body)
                    .foregroundStyle(enabled ? palette.text : palette.disabledText)
                if let subtitle {
                    Text(subtitle)
                        .font(EnteTypography.mini)
                        .foregroundStyle(palette.mutedText)
                }
            }
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
