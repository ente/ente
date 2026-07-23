import SwiftUI
import UIKit

struct ModelSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let embeddedInNavigation: Bool

    @ObservedObject private var settings = ModelSettingsStore.shared
    @State private var selectedModelId: String = defaultOptionId
    @State private var contextLength: String = ""
    @State private var maxTokens: String = ""
    @State private var temperature: String = ""

    @State private var contextError: String?
    @State private var maxTokensError: String?
    @State private var temperatureError: String?
    @State private var isSaving = false
    @State private var showAdvancedLimits = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    private let modelChoices: [ModelChoice] = {
        let defaults = ConfigDefaults.shared
        let defaultModel = defaults.mobileDefaultModel
        let presets = defaults.mobileModelPresets
        return [
            ModelChoice(id: Self.defaultOptionId, name: defaultModel.title, isDefault: true)
        ] + presets.map { preset in
            ModelChoice(id: preset.id, name: preset.title)
        }
    }()

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
                            Text("Model Settings")
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
                                Text("Model Settings")
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
            selectedModelId = initialSelectionId()
            contextLength = settings.contextLength
            maxTokens = settings.maxTokens
            temperature = settings.temperature
            showAdvancedLimits = !settings.contextLength.isEmpty || !settings.maxTokens.isEmpty || !settings.temperature.isEmpty
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ToastView(message: toastMessage)
                    .padding(.bottom, EnsuSpacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var selectedModel: ModelChoice {
        modelChoices.first(where: { $0.id == selectedModelId }) ?? modelChoices[0]
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EnsuSpacing.xxl) {
                sectionHeader("Select model")

                Text("Choose a built-in model.")
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Model", selection: $selectedModelId) {
                    ForEach(modelChoices) { choice in
                        Text(choice.name).tag(choice.id)
                    }
                }
                .pickerStyle(.menu)

                sectionToggle(
                    title: "Advanced limits",
                    collapsedHint: "Context length, output, temperature",
                    expanded: showAdvancedLimits
                ) {
                    showAdvancedLimits.toggle()
                }

                if showAdvancedLimits {
                    VStack(spacing: EnsuSpacing.sm) {
                        HStack(spacing: EnsuSpacing.md) {
                            field(
                                label: "Context length",
                                hint: "8192",
                                text: $contextLength,
                                error: contextError,
                                keyboardType: .numberPad
                            )

                            field(
                                label: "Max output",
                                hint: "2048",
                                text: $maxTokens,
                                error: maxTokensError,
                                keyboardType: .numberPad
                            )
                        }

                        Text("Leave blank to use model defaults")
                            .font(EnsuTypography.small)
                            .foregroundStyle(EnsuColor.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        field(
                            label: "Temperature",
                            hint: "0.7",
                            text: $temperature,
                            error: temperatureError,
                            keyboardType: .decimalPad
                        )
                    }
                }

                Divider().background(EnsuColor.border)

                VStack(spacing: EnsuSpacing.md) {
                    PrimaryButton(text: "Save Model Settings", isLoading: isSaving, isEnabled: !isSaving) {
                        saveTapped()
                    }

                    Button("Reset to defaults") {
                        resetTapped()
                    }
                    .font(EnsuTypography.body)
                    .foregroundStyle(EnsuColor.textMuted)

                    Text("Changes apply the next time the model loads.")
                        .font(EnsuTypography.small)
                        .foregroundStyle(EnsuColor.textMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(EnsuSpacing.lg)
        }
    }

    private func initialSelectionId() -> String {
        modelChoices.first(where: { $0.id == settings.modelId })?.id ?? Self.defaultOptionId
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(EnsuTypography.body)
            .foregroundStyle(EnsuColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(
        label: String,
        hint: String,
        text: Binding<String>,
        error: String?,
        keyboardType: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(EnsuTypography.small)
                .foregroundStyle(EnsuColor.textMuted)

            StyledTextField(
                hint: hint,
                text: text,
                keyboardType: keyboardType
            )

            if let error {
                Text(error)
                    .font(EnsuTypography.mini)
                    .foregroundStyle(EnsuColor.error)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionToggle(
        title: String,
        collapsedHint: String,
        expanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(EnsuTypography.body)
                    .foregroundStyle(EnsuColor.action)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !expanded {
                    Text(collapsedHint)
                        .font(EnsuTypography.small)
                        .foregroundStyle(EnsuColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func saveTapped() {
        contextError = nil
        maxTokensError = nil
        temperatureError = nil

        guard validate() else { return }

        isSaving = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            settings.saveModel(
                id: selectedModel.isDefault ? "" : selectedModel.id,
                contextLength: contextLength,
                maxTokens: maxTokens,
                temperature: temperature
            )
            isSaving = false
            toastTask?.cancel()
            toastTask = presentToast("Model settings saved") { message in
                toastMessage = message
            }
        }
    }

    private func resetTapped() {
        settings.resetToDefault()
        selectedModelId = Self.defaultOptionId
        contextLength = ""
        maxTokens = ""
        temperature = ""
        toastTask?.cancel()
        toastTask = presentToast("Model settings reset") { message in
            toastMessage = message
        }
    }

    private func validate() -> Bool {
        var isValid = true

        if !contextLength.isEmpty, Int(contextLength) == nil {
            contextError = "Enter a valid integer"
            isValid = false
        }

        if !maxTokens.isEmpty, Int(maxTokens) == nil {
            maxTokensError = "Enter a valid integer"
            isValid = false
        }

        if !temperature.isEmpty, Float(temperature) == nil {
            temperatureError = "Enter a valid number"
            isValid = false
        }

        if let contextValue = Int(contextLength), let maxValue = Int(maxTokens), maxValue > contextValue {
            maxTokensError = "Must be <= context length"
            isValid = false
        }

        return isValid
    }

    private static let defaultOptionId = "default"
}

private struct ModelChoice: Identifiable {
    let id: String
    let name: String
    let isDefault: Bool

    init(id: String, name: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}
