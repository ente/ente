import SwiftUI

public struct Avatar: View {
    @Environment(\.entePalette) private var palette
    private let name: String
    private let image: Image?
    private let identity: String
    private let size: AvatarSize

    public init(
        _ name: String, image: Image? = nil, identity: String? = nil, size: AvatarSize = .regular
    ) {
        self.name = name
        self.image = image
        self.identity = identity ?? name
        self.size = size
    }

    public var body: some View {
        Group {
            if let image {
                image.resizable().renderingMode(.original).scaledToFill()
            } else {
                Text(avatarInitials(name))
                    .font(size.font)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.1)
            }
        }
        .frame(width: size.dimension, height: size.dimension)
        .background(colour)
        .clipShape(Circle())
        .contentShape(Circle())
        .overlay {
            Circle().strokeBorder(palette.background, lineWidth: size.border)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isImage)
    }

    private var colour: Color {
        [
            palette.caution,
            palette.primary,
            Color(hex: 0xF24822),
            Color(hex: 0xDF61BB),
            Color(hex: 0x9610D6),
            Color(hex: 0x1071FF),
            Color(hex: 0x00B8D4),
        ][identityHash % 7]
    }

    private var identityHash: Int {
        Int(
            identity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8
                .reduce(UInt32(0x811C_9DC5)) { ($0 ^ UInt32($1)) &* 0x0100_0193 })
    }
}

private func avatarInitials(_ name: String) -> String {
    let words = name.split(whereSeparator: { $0.isWhitespace })
    guard let first = words.first?.first else { return "?" }
    let initial = String(first).uppercased()
    guard words.count > 1, let last = words.last?.first else { return initial }
    return initial + String(last).uppercased()
}

public enum AvatarSize: Sendable {
    case extraSmall
    case small
    case regular
    case medium
    case large
    case contact

    var dimension: CGFloat {
        switch self {
        case .extraSmall: 16
        case .small: 20
        case .regular: 24
        case .medium: 28
        case .large: 32
        case .contact: 56
        }
    }

    var font: Font {
        switch self {
        case .extraSmall: EnteTypography.avatarExtraSmall
        case .small: EnteTypography.avatarSmall
        case .regular, .medium, .large: EnteTypography.mini
        case .contact: EnteTypography.heading2
        }
    }

    var border: CGFloat {
        switch self {
        case .large, .contact: 2
        default: 1
        }
    }
}
