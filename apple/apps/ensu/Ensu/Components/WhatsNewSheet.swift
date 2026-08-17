import SwiftUI

struct WhatsNewSheet: View {
    let entries: [WhatsNewEntry]
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EnsuSpacing.lg) {
            Text("What's new")
                .font(EnsuTypography.h3Bold)
                .foregroundStyle(EnsuColor.textPrimary)

            ScrollView {
                VStack(alignment: .leading, spacing: EnsuSpacing.lg) {
                    ForEach(entries, id: \.title) { entry in
                        WhatsNewEntryView(entry: entry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(text: "Continue", action: onContinue)
        }
        .padding(EnsuSpacing.lg)
        .frame(minWidth: 320)
        .presentationDetents([.medium, .large])
        .background(EnsuColor.backgroundBase)
    }
}

private struct WhatsNewEntryView: View {
    let entry: WhatsNewEntry

    var body: some View {
        VStack(alignment: .leading, spacing: EnsuSpacing.sm) {
            Text(entry.title)
                .font(EnsuTypography.large)
                .foregroundStyle(EnsuColor.textPrimary)

            Text(entry.description)
                .font(EnsuTypography.body)
                .foregroundStyle(EnsuColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
