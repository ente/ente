import SwiftUI

private enum SourceSetupScreen: Hashable {
    case packs, notes
}

struct SourceIntroductionSheet: View {
    let knowledgeStore: KnowledgeStore
    let notesStore: NotesStore
    @Environment(\.dismiss) private var dismiss
    @State private var setupPath: [SourceSetupScreen] = []

    var body: some View {
        NavigationStack(path: $setupPath) {
            introduction
                .toolbar {
                    if !setupPath.isEmpty {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
                }
                .navigationDestination(for: SourceSetupScreen.self) { screen in
                    switch screen {
                    case .packs:
                        KnowledgeSettingsView(store: knowledgeStore)
                    case .notes:
                        NotesSettingsView(store: notesStore, allowsRemoval: false)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var introduction: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EnsuSpacing.lg) {
                VStack(alignment: .leading, spacing: EnsuSpacing.sm) {
                    Text("Give Ensu more context").font(EnsuTypography.h3)
                    Text("Add a knowledge pack or your notes to help Ensu answer accurately.")
                        .font(EnsuTypography.body).foregroundStyle(EnsuColor.textMuted)
                }
                VStack(spacing: EnsuSpacing.md) {
                    EnsuCard {
                        Text("Ensu Packs").font(EnsuTypography.large)
                        Text("Knowledge from Wikipedia to help Ensu get factual questions right.")
                            .font(EnsuTypography.small).foregroundStyle(EnsuColor.textMuted)
                        CompactButton(text: "Set up", prominent: true) { setupPath.append(.packs) }
                            .accessibilityLabel("Set up Ensu Packs")
                    }
                    EnsuCard {
                        Text("Your Notes").font(EnsuTypography.large)
                        Text(
                            "Use a local Markdown notes folder to chat with your own knowledge base."
                        )
                        .font(EnsuTypography.small).foregroundStyle(EnsuColor.textMuted)
                        CompactButton(text: "Set up", prominent: true) { setupPath.append(.notes) }
                            .accessibilityLabel("Set up Your Notes")
                    }
                }
                VStack(spacing: EnsuSpacing.xs) {
                    TextActionButton(
                        text: "Not now", underlined: true, color: EnsuColor.textPrimary
                    ) {
                        dismiss()
                    }
                    Text("You can set up Ensu Packs and Your Notes later from Settings.")
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
    }
}
