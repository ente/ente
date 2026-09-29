import SwiftUI

public struct SettingsToggle: View {
    @Binding private var isOn: Bool
    private let title: String

    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    public var body: some View {
        MenuGroup {
            Toggle(title, isOn: $isOn)
                .font(EnteTypography.body)
                .toggleStyle(EnteToggleStyle())
                .padding(.horizontal, EnteSpacing.lg)
                .padding(.vertical, EnteSpacing.sm)
        }
    }
}
