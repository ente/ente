import SwiftUI

public enum BannerKind: Sendable {
    case failure
    case information
    case success
    case warning
    case neutral
}

public struct Banner: View {
    @Environment(\.entePalette) private var palette
    private let title: String
    private let subtitle: String?
    private let kind: BannerKind
    private let image: Image?
    private let action: (() -> Void)?

    public init(
        _ title: String,
        subtitle: String? = nil,
        kind: BannerKind = .neutral,
        image: Image? = nil,
        action: (() -> Void)? = nil,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.image = image
        self.action = action
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: EnteRadius.button, style: .continuous))
    }

    private var content: some View {
        HStack(spacing: EnteSpacing.lg) {
            if let image {
                image.resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: EnteSpacing.xs) {
                Text(title)
                    .font(EnteTypography.bodyBold)
                    .foregroundStyle(kind == .neutral ? palette.text : accent)
                    .lineLimit(subtitle == nil ? 2 : 1)
                if let subtitle {
                    Text(subtitle)
                        .font(EnteTypography.mini)
                        .foregroundStyle(palette.mutedText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, EnteSpacing.lg)
        .padding(.vertical, EnteSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var accent: Color {
        switch kind {
        case .failure: palette.danger
        case .information: palette.information
        case .success, .neutral: palette.primaryDark
        case .warning: palette.caution
        }
    }
}
