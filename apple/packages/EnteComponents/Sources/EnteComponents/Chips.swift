import SwiftUI

public struct FilterChip: View {
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    private let label: String
    private let image: Image?
    private let selected: Bool
    private let action: () -> Void

    public init(
        _ label: String,
        image: Image? = nil,
        selected: Bool,
        action: @escaping () -> Void,
    ) {
        self.label = label
        self.image = image
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: EnteSpacing.sm) {
                if let image {
                    image.resizable().renderingMode(.template).scaledToFit()
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
                Text(label)
                if selected {
                    Glyph.close.image.resizable().scaledToFit()
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                }
            }
            .font(EnteTypography.mini)
            .lineLimit(1)
            .padding(.leading, image == nil ? 18 : EnteSpacing.md)
            .padding(
                .trailing,
                selected ? EnteSpacing.md : (image == nil ? 18 : EnteSpacing.lg),
            )
            .padding(.vertical, EnteSpacing.md)
            .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .background(background)
        .clipShape(Capsule())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var background: Color {
        selected ? (palette.isDark ? Color(hex: 0xF4F4F4) : Color(hex: 0x161616)) : palette.surface
    }

    private var foreground: Color {
        selected ? palette.reverseText : (enabled ? palette.mutedText : palette.disabledText)
    }
}

public struct Tag: View {
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    private let label: String
    private let selected: Bool
    private let action: () -> Void

    public init(
        _ label: String,
        selected: Bool,
        action: @escaping () -> Void,
    ) {
        self.label = label
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(EnteTypography.body)
                .lineLimit(1)
                .padding(.horizontal, EnteSpacing.xl)
                .padding(.vertical, EnteSpacing.md)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .white : (enabled ? palette.mutedText : palette.disabledText))
        .background(selected ? palette.primary : palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: EnteRadius.large, style: .continuous))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
