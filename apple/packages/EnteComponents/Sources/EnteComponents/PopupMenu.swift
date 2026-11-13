import SwiftUI

public struct PopupMenu<Content: View>: View {
    @Environment(\.entePalette) private var palette
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) { content }.fixedSize(horizontal: false, vertical: true)
            ScrollView { VStack(spacing: 0) { content } }
        }
        .frame(width: 196)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: EnteRadius.button))
        .overlay(RoundedRectangle(cornerRadius: EnteRadius.button).stroke(palette.faintBorder))
    }
}

public struct MenuItem: View {
    @Environment(\.entePalette) private var palette
    private let title: String
    private let image: Image?
    private let trailing: String?
    private let selected: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        image: Image? = nil,
        trailing: String? = nil,
        selected: Bool = false,
        action: @escaping () -> Void,
    ) {
        self.title = title
        self.image = image
        self.trailing = trailing
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let image {
                    image.resizable().renderingMode(.template).scaledToFit().frame(
                        width: 18,
                        height: 18,
                    )
                    .foregroundStyle(palette.mutedText).frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                }
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    Text(trailing).foregroundStyle(palette.mutedText)
                }
            }
            .font(EnteTypography.mini).foregroundStyle(palette.text)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, EnteSpacing.lg).padding(.vertical, 12).frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
