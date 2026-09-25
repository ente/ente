import SwiftUI

public struct SettingsPage<Content: View>: View {
    private let title: String
    private let identifier: String?
    private let backLabel: String
    private let back: () -> Void
    private let content: Content

    public init(
        _ title: String,
        identifier: String? = nil,
        backLabel: String,
        back: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.identifier = identifier
        self.backLabel = backLabel
        self.back = back
        self.content = content()
    }

    public var body: some View {
        CollapsingPage(title, identifier: identifier, backLabel: backLabel, back: back) {
            VStack(alignment: .leading, spacing: EnteSpacing.sm) { content }
        }
    }
}
