import SwiftUI

public struct MenuRow<Leading: View>: View {
    @Environment(\.entePalette) private var palette
    private let title: String
    private let subtitle: String?
    private let leading: Leading?
    private let selected: Bool
    private let showsChevron: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading,
        selected: Bool = false,
        showsChevron: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.selected = selected
        self.showsChevron = showsChevron
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: EnteSpacing.md) {
                if let leading {
                    leading
                        .frame(width: 36, height: 36)
                        .foregroundStyle(palette.mutedText)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: EnteSpacing.xs) {
                    Text(title)
                        .font(EnteTypography.body)
                        .lineLimit(subtitle?.isEmpty == false ? 1 : 2)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(EnteTypography.mini)
                            .foregroundStyle(palette.mutedText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if selected || showsChevron {
                    HStack(spacing: EnteSpacing.xs) {
                        if selected {
                            Glyph.check.image.resizable().scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundStyle(palette.primary)
                        }
                        if showsChevron {
                            Glyph.chevron.image.resizable().scaledToFit()
                                .frame(width: 24, height: 24)
                                .flipsForRightToLeftLayoutDirection(true)
                                .foregroundStyle(palette.mutedText)
                        }
                    }
                    .frame(minWidth: 36, minHeight: 36)
                    .accessibilityHidden(true)
                }
            }
            .padding(.leading, leading == nil ? EnteSpacing.lg : EnteSpacing.md)
            .padding(.trailing, EnteSpacing.md)
            .padding(.vertical, 9)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

public extension MenuRow where Leading == EmptyView {
    init(
        _ title: String,
        subtitle: String? = nil,
        selected: Bool = false,
        showsChevron: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        leading = nil
        self.selected = selected
        self.showsChevron = showsChevron
        self.action = action
    }
}

private struct MenuRowStyle: ButtonStyle {
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? palette.text : palette.disabledText)
            .background(configuration.isPressed ? palette.fillDarker : palette.surface)
            .animation(.easeOut(duration: EnteMotion.quick), value: configuration.isPressed)
    }
}
