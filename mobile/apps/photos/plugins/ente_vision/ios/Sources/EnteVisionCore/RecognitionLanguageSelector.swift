import Foundation

enum RecognitionLanguageSelector {
    static func select(
        preferredLanguages: [String],
        supportedLanguages: [String],
        limit: Int = 3
    ) -> [String] {
        guard limit > 0, !supportedLanguages.isEmpty else { return [] }

        var selected: [String] = []
        for preferred in preferredLanguages {
            let remaining = supportedLanguages.filter { !selected.contains($0) }
            if let match = bestMatch(for: preferred, in: remaining) {
                selected.append(match)
            }
            if selected.count == limit {
                return selected
            }
        }

        if selected.count < limit,
            let english = supportedLanguages.first(where: {
                normalized($0) == "en-us"
            }),
            !selected.contains(english)
        {
            selected.append(english)
        }

        return selected.isEmpty
            ? Array(supportedLanguages.prefix(1))
            : selected
    }

    private static func bestMatch(
        for preferred: String,
        in supportedLanguages: [String]
    ) -> String? {
        if let exact = supportedLanguages.first(where: {
            normalized($0) == normalized(preferred)
        }) {
            return exact
        }

        let preferredTag = LanguageTag(preferred)
        guard !preferredTag.language.isEmpty else { return nil }
        let supportedTags = supportedLanguages.map {
            (identifier: $0, tag: LanguageTag($0))
        }

        if let script = preferredTag.effectiveScript,
            let scriptMatch = supportedTags.first(where: {
                $0.tag.language == preferredTag.language && $0.tag.effectiveScript == script
            })
        {
            return scriptMatch.identifier
        }

        if let region = preferredTag.region,
            let regionMatch = supportedTags.first(where: {
                $0.tag.language == preferredTag.language && $0.tag.region == region
            })
        {
            return regionMatch.identifier
        }

        return supportedTags.first(where: {
            $0.tag.language == preferredTag.language
        })?.identifier
    }

    private static func normalized(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

private struct LanguageTag {
    let language: String
    let script: String?
    let region: String?

    init(_ identifier: String) {
        let parts =
            identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)
        language = parts.first?.lowercased() ?? ""
        script = parts.dropFirst().first(where: { part in
            part.count == 4 && part.allSatisfy(\.isLetter)
        })?.lowercased()
        region = parts.dropFirst().first(where: { part in
            (part.count == 2 && part.allSatisfy(\.isLetter)) || (part.count == 3 && part.allSatisfy(\.isNumber))
        })?.uppercased()
    }

    var effectiveScript: String? {
        if let script = script {
            return script
        }
        guard language == "zh", let region = region else { return nil }
        switch region {
        case "HK", "MO", "TW":
            return "hant"
        case "CN", "MY", "SG":
            return "hans"
        default:
            return nil
        }
    }
}
