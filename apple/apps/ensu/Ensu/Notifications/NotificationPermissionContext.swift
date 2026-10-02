import SwiftUI

struct NotificationPermissionContext: View {
    @ObservedObject var notifications = ResponseNotifications.shared

    var body: some View {
        VStack(alignment: .leading, spacing: EnsuSpacing.lg) {
            ScrollView {
                VStack(alignment: .leading, spacing: EnsuSpacing.lg) {
                    Text("Let Ensu notify you")
                        .font(EnsuTypography.h3Bold)
                        .foregroundStyle(EnsuColor.textPrimary)
                    Text(
                        notifications.canRequest
                            ? "Switch to another app while Ensu works. We’ll let you know when your response is ready."
                            : "Switch to another app while Ensu works. Turn on notifications in Settings, and we’ll let you know when your response is ready."
                    )
                    .font(EnsuTypography.body)
                    .foregroundStyle(EnsuColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            PrimaryButton(
                text: notifications.canRequest ? "Enable notifications" : "Open settings",
                action: notifications.enable
            )
            Button {
                notifications.showPermissionContext = false
            } label: {
                Text("Not now")
                    .font(EnsuTypography.body)
                    .foregroundStyle(EnsuColor.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(EnsuSpacing.lg)
        .background(EnsuColor.backgroundBase)
        .presentationDetents([.medium, .large])
        .onAppear { notifications.didShowPermissionContext() }
    }
}
