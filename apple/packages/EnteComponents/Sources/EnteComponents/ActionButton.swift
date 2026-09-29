import SwiftUI

public enum ActionVariant: Sendable {
    case primary
    case secondary
    case neutral
    case critical
    case criticalText
    case link
}

public enum ActionDensity: Sendable {
    case regular
    case compact
}

public enum ActionSize: Sendable {
    case small
    case large
}

public struct ActionButton: View {
    @Environment(\.isEnabled) private var enabled
    private let title: String
    private let variant: ActionVariant
    private let size: ActionSize
    private let density: ActionDensity
    private let loading: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        variant: ActionVariant = .primary,
        size: ActionSize = .large,
        density: ActionDensity = .regular,
        loading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.size = size
        self.density = density
        self.loading = loading
        self.action = action
    }

    public var body: some View {
        let inlineLink = variant == .link && size == .small
        Button(action: action) {
            Text(title)
                .underline(variant == .criticalText || variant == .link)
                .lineLimit(2)
                .font(density == .regular ? EnteTypography.bodyBold : EnteTypography.body)
                .opacity(loading ? 0 : 1)
                .overlay {
                    if loading {
                        ActionProgress()
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: size == .large ? .infinity : nil, minHeight: inlineLink ? nil : 24)
                .padding(.horizontal, inlineLink ? 0 : EnteSpacing.xl)
                .padding(.vertical, inlineLink ? 4 : density == .regular ? 14 : 12)
        }
        .buttonStyle(
            ActionStyle(
                variant: variant,
                enabled: enabled,
                cornerRadius: inlineLink ? 0 : EnteRadius.button
            )
        )
        .disabled(loading)
        .accessibilityLabel(title)
    }
}

private struct ActionStyle: ButtonStyle {
    @Environment(\.entePalette) private var palette
    let variant: ActionVariant
    let enabled: Bool
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let colors = colors(pressed: configuration.isPressed)
        return configuration.label
            .foregroundStyle(colors.foreground)
            .background(colors.background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: EnteMotion.quick), value: configuration.isPressed)
    }

    private func colors(pressed: Bool) -> (background: Color, foreground: Color) {
        guard enabled else {
            return (
                variant == .criticalText || variant == .link ? .clear : palette.fill,
                palette.disabledText
            )
        }
        return switch variant {
        case .primary: (pressed ? palette.primaryDarker : palette.primary, .white)
        case .secondary: (pressed ? palette.fillDarkest : palette.fill, palette.text)
        case .neutral: (palette.text, palette.reverseText)
        case .critical: (pressed ? palette.dangerDarker : palette.danger, .white)
        case .criticalText: (.clear, pressed ? palette.dangerDarker : palette.danger)
        case .link: (.clear, pressed ? palette.primaryDarker : palette.primary)
        }
    }
}

private struct ActionProgress: View {
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 20, height: 20)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
    }
}
