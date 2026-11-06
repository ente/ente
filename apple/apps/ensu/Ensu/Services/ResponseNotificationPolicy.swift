import Foundation

struct ResponseNotificationCampaign {
    static let interval: TimeInterval = 3 * 24 * 60 * 60
    var count: Int
    var lastShown: Date?
    var finished: Bool

    func isEligible(enabled: Bool, now: Date) -> Bool {
        !enabled && !finished && count < 3
            && (lastShown.map { now.timeIntervalSince($0) >= Self.interval } ?? true)
    }
}

func responseNotificationPreview(_ text: String) -> String {
    var visible = text
    visible = visible.replacingOccurrences(
        of: #"(?m)^```[^\n]*$"#, with: "", options: .regularExpression)
    if let plain = try? AttributedString(
        markdown: visible,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    {
        visible = String(plain.characters)
    }
    visible = visible.replacingOccurrences(
        of: #"(?m)^\s{0,3}(#{1,6} |> |[-*+] )"#,
        with: "", options: .regularExpression)
    return String(visible.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
}

func responseNotificationTitle(_ query: String) -> String {
    let text = query.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }.joined(separator: " ")
    guard !text.isEmpty else { return "Ensu" }
    return String(text.prefix(30)) + (text.count > 30 ? "…" : "")
}
