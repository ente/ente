import SwiftUI
import Foundation

struct SettingsView: View {
    let onSignIn: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var query: String = ""
    @State private var buildVersionTapCount = 0
    @State private var lastBuildVersionTapAt: Date?
    @State private var isAdvancedUnlocked = EnsuAdvancedSettings.isUnlocked
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EnsuSpacing.lg) {
                    if let aboutItem = filteredAboutItem {
                        Button(action: aboutItem.action) {
                            settingsCard(title: aboutItem.title, iconName: aboutItem.iconName, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(filteredItems) { item in
                        NavigationLink {
                            item.destination
                        } label: {
                            settingsCard(title: item.title, iconName: item.iconName, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }

                    if shouldShowSignInRow {
                        Button(action: onSignIn) {
                            settingsCard(title: signInTitle, iconName: "Upload01Icon", showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(filteredLegalLinkItems) { item in
                        Button(action: item.action) {
                            settingsCard(title: item.title, iconName: item.iconName, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }

                    if shouldShowAdvancedSection {
                        Text("Advanced")
                            .font(EnsuTypography.small)
                            .foregroundStyle(EnsuColor.textMuted)
                            .padding(.top, EnsuSpacing.xs)

                        ForEach(filteredAdvancedItems) { item in
                            NavigationLink {
                                item.destination
                            } label: {
                                settingsCard(title: item.title, iconName: item.iconName, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button(action: handleBuildVersionTap) {
                        Text(buildVersionText)
                            .font(EnsuTypography.small)
                            .foregroundStyle(EnsuColor.textMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(EnsuSpacing.lg)
            }
            .background(EnsuColor.backgroundBase)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(EnsuTypography.large)
                        .foregroundStyle(EnsuColor.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    ToastView(message: toastMessage)
                        .padding(.bottom, EnsuSpacing.xl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var filteredItems: [SettingsItem] {
        guard !trimmedQuery.isEmpty else { return allItems }
        let q = trimmedQuery.lowercased()
        return allItems.filter { item in
            item.title.lowercased().contains(q)
        }
    }

    private var filteredAdvancedItems: [SettingsItem] {
        guard isAdvancedUnlocked else { return [] }
        guard !trimmedQuery.isEmpty else { return advancedItems }
        let q = trimmedQuery.lowercased()
        return advancedItems.filter { item in
            item.title.lowercased().contains(q)
        }
    }

    private var aboutItem: SettingsActionItem {
        SettingsActionItem(
            title: "About",
            iconName: "InformationCircleIcon",
            action: { openExternalLink("https://ente.com/blog/ensu/") }
        )
    }

    private var legalLinkItems: [SettingsActionItem] {
        [
            SettingsActionItem(
                title: "Privacy Policy",
                iconName: "ViewIcon",
                action: { openExternalLink("https://ente.com/privacy") }
            ),
            SettingsActionItem(
                title: "Terms of Service",
                iconName: "DescriptionIcon",
                action: { openExternalLink("https://ente.com/terms") }
            )
        ]
    }

    private var filteredAboutItem: SettingsActionItem? {
        guard !trimmedQuery.isEmpty else { return aboutItem }
        let q = trimmedQuery.lowercased()
        return aboutItem.title.lowercased().contains(q) ? aboutItem : nil
    }

    private var filteredLegalLinkItems: [SettingsActionItem] {
        guard !trimmedQuery.isEmpty else { return legalLinkItems }
        let q = trimmedQuery.lowercased()
        return legalLinkItems.filter { item in
            item.title.lowercased().contains(q)
        }
    }

    private var shouldShowSignInRow: Bool {
        guard !trimmedQuery.isEmpty else { return true }
        let q = trimmedQuery.lowercased()
        return signInTitle.lowercased().contains(q)
    }

    private var signInTitle: String { "Sign In to Backup" }

    private var allItems: [SettingsItem] {
        [
            SettingsItem(
                title: "Logs",
                iconName: "Bug01Icon",
                destination: AnyView(LogsView(embeddedInNavigation: true))
            )
        ]
    }

    private var advancedItems: [SettingsItem] {
        [
            SettingsItem(
                title: "Model settings",
                iconName: "Settings01Icon",
                destination: AnyView(ModelSettingsView(embeddedInNavigation: true))
            ),
            SettingsItem(
                title: "System prompt",
                iconName: "Edit01Icon",
                destination: AnyView(SystemPromptSettingsView(embeddedInNavigation: true))
            )
        ]
    }

    private var shouldShowAdvancedSection: Bool {
        isAdvancedUnlocked && !filteredAdvancedItems.isEmpty
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var buildVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "Build \(version) (\(build))"
    }

    private func handleBuildVersionTap() {
        guard !isAdvancedUnlocked else { return }
        let now = Date()
        if let last = lastBuildVersionTapAt, now.timeIntervalSince(last) > 2 {
            buildVersionTapCount = 0
        }
        lastBuildVersionTapAt = now
        buildVersionTapCount += 1
        guard buildVersionTapCount >= 5 else { return }
        EnsuAdvancedSettings.unlock()
        isAdvancedUnlocked = true
        buildVersionTapCount = 0
        toastTask?.cancel()
        toastTask = presentToast("Advanced settings unlocked") { message in
            toastMessage = message
        }
    }

    private func openExternalLink(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }

    private func settingsCard(title: String, iconName: String, showsChevron: Bool) -> some View {
        HStack(spacing: EnsuSpacing.md) {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(EnsuColor.textPrimary)

            Text(title)
                .font(EnsuTypography.body)
                .foregroundStyle(EnsuColor.textPrimary)
            Spacer()
            if showsChevron {
                Image("ArrowRight01Icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(EnsuColor.textMuted)
            }
        }
        .padding(EnsuSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EnsuColor.fillFaint)
        .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.card, style: .continuous))
    }
}

private struct SystemPromptSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let embeddedInNavigation: Bool

    @ObservedObject private var settings = ModelSettingsStore.shared
    @State private var promptBody: String = ""
    @State private var isSaving = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    init(embeddedInNavigation: Bool = false) {
        self.embeddedInNavigation = embeddedInNavigation
    }

    var body: some View {
        Group {
            if embeddedInNavigation {
                content
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("System Prompt")
                                .font(EnsuTypography.large)
                                .foregroundStyle(EnsuColor.textPrimary)
                        }
                    }
            } else {
                NavigationStack {
                    content
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Text("System Prompt")
                                    .font(EnsuTypography.large)
                                    .foregroundStyle(EnsuColor.textPrimary)
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            }
        }
        .onAppear {
            promptBody = ModelSettingsStore.resolveSystemPromptBody(settings.systemPromptBody)
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ToastView(message: toastMessage)
                    .padding(.bottom, EnsuSpacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EnsuSpacing.xxl) {
                sectionHeader("Prompt text")

                Text("This prompt is used as-is. Use $date anywhere to insert the current date.")
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.textMuted)

                TextEditor(text: $promptBody)
                    .font(EnsuTypography.body)
                    .foregroundStyle(EnsuColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .padding(.horizontal, EnsuSpacing.inputHorizontal)
                    .padding(.vertical, EnsuSpacing.inputVertical)
                    .background(EnsuColor.fillFaint)
                    .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.input, style: .continuous))

                Text("Leave this blank to use the default prompt.")
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.textMuted)

                Divider().background(EnsuColor.border)

                VStack(spacing: EnsuSpacing.md) {
                    PrimaryButton(text: "Save Prompt", isLoading: isSaving, isEnabled: !isSaving) {
                        saveTapped()
                    }

                    Button("Use Default Prompt") {
                        resetTapped()
                    }
                    .font(EnsuTypography.body)
                    .foregroundStyle(EnsuColor.textMuted)
                }
            }
            .padding(EnsuSpacing.lg)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(EnsuTypography.body)
            .foregroundStyle(EnsuColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveTapped() {
        isSaving = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            let trimmedPrompt = promptBody.trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultPrompt = ModelSettingsStore.defaultSystemPromptBody.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.systemPromptBody = trimmedPrompt == defaultPrompt ? "" : trimmedPrompt
            promptBody = ModelSettingsStore.resolveSystemPromptBody(settings.systemPromptBody)
            isSaving = false
            toastTask?.cancel()
            toastTask = presentToast("Prompt saved") { message in
                toastMessage = message
            }
        }
    }

    private func resetTapped() {
        settings.systemPromptBody = ""
        promptBody = ModelSettingsStore.defaultSystemPromptBody
        toastTask?.cancel()
        toastTask = presentToast("Prompt reset") { message in
            toastMessage = message
        }
    }
}

private struct SettingsItem: Identifiable {
    let id = UUID()
    let title: String
    let iconName: String
    let destination: AnyView
}

private struct SettingsActionItem: Identifiable {
    let id = UUID()
    let title: String
    let iconName: String
    let action: () -> Void
}
