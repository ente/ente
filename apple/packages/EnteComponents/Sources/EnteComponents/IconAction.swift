import SwiftUI

public struct IconAction<Content: View>: View {
    private let kind: IconActionKind
    private let enabled: Bool
    private let size: CGFloat
    private let action: () -> Void
    private let content: Content

    public init(
        kind: IconActionKind = .unfilled,
        enabled: Bool = true,
        size: CGFloat = 40,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.kind = kind
        self.enabled = enabled
        self.size = size
        self.action = action
        self.content = content()
    }

    public var body: some View {
        Button(action: action) {
            content
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(
            IconActionStyle(
                kind: kind,
                cornerRadius: kind == .circular ? size / 2 : EnteRadius.medium
            )
        )
        .disabled(!enabled)
    }
}

public enum IconActionKind: Sendable {
    case primary
    case unfilled
    case accent
    case circular
    case onMedia
}

private struct IconActionStyle: ButtonStyle {
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    let kind: IconActionKind
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let colors = colors(pressed: configuration.isPressed)
        return configuration.label
            .foregroundStyle(colors.foreground)
            .background(colors.background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: EnteMotion.quick), value: configuration.isPressed)
    }

    private func colors(pressed: Bool) -> (background: Color, foreground: Color) {
        if !enabled, kind != .onMedia {
            return (kind == .unfilled ? .clear : palette.fill, palette.hintText)
        }
        return switch kind {
        case .primary, .circular: (pressed ? palette.fillDarker : palette.surface, palette.text)
        case .unfilled: (.clear, palette.text.opacity(palette.isDark ? 1 : 0.75))
        case .accent: (pressed ? palette.primaryDarker : palette.primary, .white)
        case .onMedia:
            (
                enabled && pressed ? .white.opacity(0.12) : .clear,
                .white.opacity(enabled ? 1 : 0.4)
            )
        }
    }
}
