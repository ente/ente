import SwiftUI

struct NotificationPermissionContext: View {
    @ObservedObject var notifications = ResponseNotifications.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EnsuSpacing.lg) {
                VStack(alignment: .leading, spacing: EnsuSpacing.sm) {
                    Text("Let Ensu notify you").font(EnsuTypography.h3)
                    Text("Switch to another app while Ensu works.")
                        .font(EnsuTypography.body).foregroundStyle(EnsuColor.textMuted)
                }
                EnsuCard {
                    Text("Response notifications").font(EnsuTypography.large)
                    Text(
                        notifications.canRequest
                            ? "We’ll let you know when your response is ready, with the answer in the notification."
                            : "Turn on notifications in Settings to see when your response is ready, with the answer in the notification."
                    )
                    .font(EnsuTypography.small).foregroundStyle(EnsuColor.textMuted)
                    CompactButton(
                        text: notifications.canRequest ? "Enable notifications" : "Open settings",
                        prominent: true, action: notifications.enable
                    )
                }
                VStack(spacing: EnsuSpacing.xs) {
                    TextActionButton(
                        text: "Not now", underlined: true, color: EnsuColor.textPrimary
                    ) {
                        notifications.showPermissionContext = false
                    }
                    Text("You can change notification preferences later from Settings.")
                        .font(EnsuTypography.mini.weight(.regular))
                        .foregroundStyle(EnsuColor.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(EnsuColor.textPrimary)
            .padding(EnsuSpacing.lg)
        }
        .background(EnsuColor.backgroundBase)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { notifications.didShowPermissionContext() }
    }
}
