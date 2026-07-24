import Foundation

// Compared against the memory the OS reports (ProcessInfo.physicalMemory), which runs
// well below marketed RAM. 3.2 GB sits in the gap between 3 GB devices (~2.7-3.0 GB
// reported) and 4 GB devices (~3.4-3.8 GB reported), so 4 GB devices pass and 3 GB don't.
let chatMinimumRAMBytes: UInt64 = 3_200_000_000

enum ChatDeviceCapability: Equatable {
    case supported(totalMemoryBytes: UInt64?)
    case unsupportedLowMemory(totalMemoryBytes: UInt64, requiredMemoryBytes: UInt64)
    case unknown

    var isChatSupported: Bool {
        if case .unsupportedLowMemory = self {
            return false
        }
        return true
    }

    var totalMemoryBytes: UInt64? {
        switch self {
        case .supported(let totalMemoryBytes):
            return totalMemoryBytes
        case .unsupportedLowMemory(let totalMemoryBytes, _):
            return totalMemoryBytes
        case .unknown:
            return nil
        }
    }
}

func currentChatDeviceCapability() -> ChatDeviceCapability {
    let totalMemoryBytes = ProcessInfo.processInfo.physicalMemory
    if totalMemoryBytes < chatMinimumRAMBytes {
        return .unsupportedLowMemory(
            totalMemoryBytes: totalMemoryBytes,
            requiredMemoryBytes: chatMinimumRAMBytes
        )
    }
    return .supported(totalMemoryBytes: totalMemoryBytes)
}

struct UnsupportedDeviceMemoryError: LocalizedError {
    let capability: ChatDeviceCapability

    var errorDescription: String? {
        "Device does not have enough RAM for local chat"
    }
}

@MainActor
final class ModelSettingsStore: ObservableObject {
    static let shared = ModelSettingsStore()
    static let highRAMThresholdBytes: UInt64 = 16 * 1024 * 1024 * 1024

    @Published var modelId: String {
        didSet { persist() }
    }
    @Published var contextLength: String {
        didSet { persist() }
    }
    @Published var maxTokens: String {
        didSet { persist() }
    }
    @Published var temperature: String {
        didSet { persist() }
    }
    @Published var systemPromptBody: String {
        didSet { persist() }
    }

    private let defaults = UserDefaults.standard

    private init() {
        self.modelId = defaults.string(forKey: Keys.modelId) ?? ""
        self.contextLength = defaults.string(forKey: Keys.contextLength) ?? ""
        self.maxTokens = defaults.string(forKey: Keys.maxTokens) ?? ""
        self.temperature = defaults.string(forKey: Keys.temperature) ?? ""
        self.systemPromptBody = defaults.string(forKey: Keys.systemPromptBody) ?? ""
    }

    func saveModel(id: String, contextLength: String, maxTokens: String, temperature: String) {
        modelId = id
        self.contextLength = contextLength
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    func resetToDefault() {
        modelId = ""
        contextLength = ""
        maxTokens = ""
        temperature = ""
    }

    func currentSelection() -> LlmModelSelection {
        let defaults = ConfigDefaults.shared
        let defaultModel = Self.platformDefaultModel
        let presets = [defaultModel] + defaults.mobileModelPresets
        let preset = presets.first(where: { $0.id == modelId }) ?? defaultModel
        return LlmModelSelection(
            id: preset.id,
            modelTarget: try! mobileLlmTarget(modelId: preset.id),
            contextLength: Int(contextLength),
            maxTokens: Int(maxTokens).flatMap { $0 > 0 ? $0 : nil }
        )
    }

    static var defaultModelName: String { platformDefaultModel.title }
    static var defaultSystemPromptBody: String { platformSystemPromptBody }

    static func currentSystemPromptBody() -> String {
        let stored = UserDefaults.standard.string(forKey: Keys.systemPromptBody) ?? ""
        return resolveSystemPromptBody(stored)
    }

    static func resolveSystemPromptBody(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? platformSystemPromptBody : trimmed
    }

    private static var platformDefaultModel: ConfigModelPreset {
        ConfigDefaults.shared.mobileDefaultModel
    }

    private static var platformSystemPromptBody: String {
        ConfigDefaults.shared.mobileSystemPromptBody
    }

    private func persist() {
        defaults.set(modelId, forKey: Keys.modelId)
        defaults.set(contextLength, forKey: Keys.contextLength)
        defaults.set(maxTokens, forKey: Keys.maxTokens)
        defaults.set(temperature, forKey: Keys.temperature)
        defaults.set(systemPromptBody, forKey: Keys.systemPromptBody)
    }

    fileprivate enum Keys {
        static let modelId = "ensu.model.id"
        static let contextLength = "ensu.model.context"
        static let maxTokens = "ensu.model.max_tokens"
        static let temperature = "ensu.model.temperature"
        static let systemPromptBody = "ensu.model.system_prompt_body"
    }
}

enum EnsuAdvancedSettings {
    private static let advancedUnlockedKey = "ensu.settings.advanced_unlocked"

    static var isUnlocked: Bool {
        UserDefaults.standard.bool(forKey: advancedUnlockedKey)
    }

    static func unlock() {
        UserDefaults.standard.set(true, forKey: advancedUnlockedKey)
    }
}
