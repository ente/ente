import CryptoKit
import SwiftUI

enum IssuerMark {
    /// SHA-256 of the issuer as stored (UTF-8, no trim, no case fold).
    /// Background is digest bytes 0, 1, and 2 as RGB.
    static func rgb(for issuer: String) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let digest = Array(SHA256.hash(data: Data(issuer.utf8)))
        return (digest[0], digest[1], digest[2])
    }

    static func colors(for issuer: String) -> (background: Color, foreground: Color) {
        let rgb = rgb(for: issuer)
        let brightness = (Double(rgb.red) + Double(rgb.green) + Double(rgb.blue)) / (3.0 * 255.0)
        let foreground: Color = brightness > 0.62 ? .black : .white
        return (
            Color(
                red: Double(rgb.red) / 255.0,
                green: Double(rgb.green) / 255.0,
                blue: Double(rgb.blue) / 255.0
            ),
            foreground
        )
    }

    /// First two Unicode scalars of the trimmed issuer. ASCII letters are uppercased.
    /// A single scalar is shown once. An empty issuer is "?".
    static func label(for issuer: String) -> String {
        let scalars = issuer.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.prefix(2)
        guard let first = scalars.first else { return "?" }
        var label = String(display(first))
        if let second = scalars.dropFirst().first {
            label.append(display(second))
        }
        return label
    }

    private static func display(_ scalar: Unicode.Scalar) -> Character {
        let character = Character(scalar)
        guard scalar.isASCII, character.isLetter else { return character }
        return character.uppercased().first ?? character
    }
}

/// How a cached issuer mark is drawn.
/// GitHub stays a template so it turns black in light mode and white in dark mode,
/// matching `IconUtils._getAdaptiveColor` for `#181717`.
/// Google, Proton, and Cloudflare are the phone's color custom icons.
/// Discord uses the simple-icons hex `#5865F2`. AWS uses Amazon's `#FF9900`
/// from `custom-icons.json`, which stays visible on both card fills.
enum IssuerIconRendering: Equatable {
    case template
    case tinted(red: Double, green: Double, blue: Double)
    case original
}

/// Asset names for the six issuers named in the watch spec.
/// Lookup follows `IconUtils._getProviderTitle`: spaces removed, lowercased,
/// then the segment before `(` or `.`.
enum IssuerIconCatalog {
    struct Mark: Equatable {
        let assetName: String
        let rendering: IssuerIconRendering
    }

    static func assetName(for issuer: String) -> String? {
        mark(for: issuer)?.assetName
    }

    static func mark(for issuer: String) -> Mark? {
        let title = normalized(issuer.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !title.isEmpty else { return nil }
        var candidates = [title]
        for separator in ["(", "."] {
            if let range = title.range(of: separator) {
                let head = String(title[..<range.lowerBound])
                if !head.isEmpty {
                    candidates.append(head)
                }
            }
        }
        for candidate in candidates {
            if let mark = assets[candidate] {
                return mark
            }
        }
        return nil
    }

    private static func normalized(_ issuer: String) -> String {
        issuer.replacingOccurrences(of: " ", with: "").lowercased()
    }

    /// Discord `#5865F2` from simple-icons. AWS `#FF9900` from the Amazon entry
    /// in `assets/custom-icons/_data/custom-icons.json`.
    private static let discord = IssuerIconRendering.tinted(
        red: 88.0 / 255.0,
        green: 101.0 / 255.0,
        blue: 242.0 / 255.0
    )
    private static let aws = IssuerIconRendering.tinted(
        red: 255.0 / 255.0,
        green: 153.0 / 255.0,
        blue: 0
    )

    private static let assets: [String: Mark] = [
        "github": Mark(assetName: "IssuerGitHub", rendering: .template),
        "google": Mark(assetName: "IssuerGoogle", rendering: .original),
        "proton": Mark(assetName: "IssuerProton", rendering: .original),
        "protonmail": Mark(assetName: "IssuerProton", rendering: .original),
        "discord": Mark(assetName: "IssuerDiscord", rendering: discord),
        "cloudflare": Mark(assetName: "IssuerCloudflare", rendering: .original),
        "aws": Mark(assetName: "IssuerAWS", rendering: aws),
        "amazonaws": Mark(assetName: "IssuerAWS", rendering: aws),
        "amazonwebservices": Mark(assetName: "IssuerAWS", rendering: aws),
    ]
}

struct IssuerAvatarView: View {
    let issuer: String
    @Environment(\.colorScheme) private var colorScheme

    /// Phone `IconUtils.getIcon` default width is 24. A hair smaller fits the watch card.
    private let side: CGFloat = 22

    var body: some View {
        let palette = EnteWatchPalette(scheme: colorScheme)
        Group {
            if let mark = IssuerIconCatalog.mark(for: issuer) {
                logo(mark, palette: palette)
            } else {
                letterMark
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func logo(_ mark: IssuerIconCatalog.Mark, palette: EnteWatchPalette) -> some View {
        switch mark.rendering {
        case .template:
            Image(mark.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(palette.textBase)
        case .tinted(let red, let green, let blue):
            Image(mark.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(red: red, green: green, blue: blue))
        case .original:
            Image(mark.assetName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        }
    }

    /// Letter fallback stays a circle, matching the phone `CircleAvatar`.
    /// The two-character label and SHA-256 color are the watch rule in R22.
    private var letterMark: some View {
        let mark = IssuerMark.colors(for: issuer)
        let label = IssuerMark.label(for: issuer)
        return Text(label)
            .font(EnteWatchType.semibold(label.count > 1 ? 9 : 12))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(mark.foreground)
            .frame(width: side, height: side)
            .background(Circle().fill(mark.background))
    }
}
