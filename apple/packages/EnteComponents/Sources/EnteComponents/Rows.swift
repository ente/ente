import SwiftUI

public struct InfoRow<Leading: View>: View {
    @Environment(\.entePalette) private var palette
    private let title: String
    private let subtitle: String?
    private let leading: Leading

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
    }

    public var body: some View {
        HStack(spacing: EnteSpacing.md) {
            leading
                .frame(width: 36, height: 36)
                .foregroundStyle(palette.mutedText)
            VStack(alignment: .leading, spacing: EnteSpacing.xs) {
                Text(title)
                    .font(EnteTypography.body)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(EnteTypography.mini)
                        .foregroundStyle(palette.mutedText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, EnteSpacing.md)
        .padding(.vertical, 9)
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
    }
}

public struct MenuGroup<Content: View>: View {
    @Environment(\.entePalette) private var palette
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(palette.text)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: EnteRadius.button, style: .continuous))
    }
}

public struct PropertyRow: View {
    @Environment(\.entePalette) private var palette
    private let label: String
    private let value: String

    public init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EnteSpacing.md) {
            Text(label)
                .font(EnteTypography.mini)
                .foregroundStyle(palette.mutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(EnteTypography.body)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(EnteSpacing.md)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

public struct EnteDivider: View {
    @Environment(\.entePalette) private var palette

    public init() {}

    public var body: some View {
        palette.faintBorder.frame(height: 1)
    }
}
