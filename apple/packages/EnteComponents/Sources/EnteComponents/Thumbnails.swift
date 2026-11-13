import SwiftUI

public struct ThumbnailTile<Cover: View>: View {
    @Environment(\.entePalette) private var palette
    private let title: String
    private let subtitle: String?
    private let titleLines: Int
    private let action: () -> Void
    private let cover: Cover

    public init(
        _ title: String,
        subtitle: String? = nil,
        titleLines: Int = 2,
        action: @escaping () -> Void,
        @ViewBuilder cover: () -> Cover
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleLines = titleLines
        self.action = action
        self.cover = cover()
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                palette.fill
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { cover }
                    .clipShape(
                        RoundedRectangle(cornerRadius: EnteRadius.button, style: .continuous)
                    )
                    .accessibilityHidden(true)
                ThumbnailCaption(title: title, subtitle: subtitle, titleLines: titleLines)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

public struct ThumbnailRow<Cover: View, Trailing: View>: View {
    @Environment(\.entePalette) private var palette
    private let title: String
    private let subtitle: String?
    private let action: () -> Void
    private let cover: Cover
    private let trailing: Trailing

    public init(
        _ title: String,
        subtitle: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder cover: () -> Cover
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.cover = cover()
        self.trailing = trailing()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: EnteSpacing.md) {
                palette.fill
                    .frame(width: 52, height: 52)
                    .overlay { cover }
                    .clipShape(
                        RoundedRectangle(cornerRadius: EnteRadius.medium, style: .continuous)
                    )
                    .accessibilityHidden(true)
                ThumbnailCaption(title: title, subtitle: subtitle, titleLines: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing.foregroundStyle(palette.mutedText)
            }
            .padding(8)
            .contentShape(RoundedRectangle(cornerRadius: EnteRadius.button, style: .continuous))
        }
        .buttonStyle(ThumbnailRowStyle())
    }
}

private struct ThumbnailRowStyle: ButtonStyle {
    @Environment(\.entePalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? palette.fillDarker : palette.surface,
                in: RoundedRectangle(cornerRadius: EnteRadius.button, style: .continuous)
            )
            .animation(.easeOut(duration: EnteMotion.quick), value: configuration.isPressed)
    }
}

private struct ThumbnailCaption: View {
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    let title: String
    let subtitle: String?
    let titleLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(EnteTypography.body)
                .foregroundStyle(enabled ? palette.text : palette.disabledText)
                .lineLimit(titleLines)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(EnteTypography.mini)
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(2)
            }
        }
    }
}
