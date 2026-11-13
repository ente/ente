import Foundation

let chatMinimumRAMBytes: UInt64 = 1_600_000_000

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
    chatDeviceCapability(totalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
}

func chatDeviceCapability(totalMemoryBytes: UInt64) -> ChatDeviceCapability {
    guard totalMemoryBytes > 0 else { return .unknown }
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

    @Published var modelId: String {
        didSet { persist() }
    }
    @Published var contextLength: String {
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
        self.temperature = defaults.string(forKey: Keys.temperature) ?? ""
        self.systemPromptBody = defaults.string(forKey: Keys.systemPromptBody) ?? ""
        defaults.removeObject(forKey: Keys.legacyMaxTokens)
    }

    func saveModel(id: String, contextLength: String, temperature: String) {
        modelId = id
        self.contextLength = contextLength
        self.temperature = temperature
    }

    func resetToDefault() {
        modelId = ""
        contextLength = ""
        temperature = ""
    }

    func currentSelection() -> LlmModelSelection {
        let modelId = resolveEffectiveModelId(
            surface: .ios,
            totalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            preferredModelId: self.modelId.isEmpty ? nil : self.modelId
        )
        return LlmModelSelection(
            id: modelId,
            contextLength: Int(contextLength)
        )
    }

    static var defaultSystemPromptBody: String { platformSystemPromptBody }

    static func currentSystemPromptBody() -> String {
        let stored = UserDefaults.standard.string(forKey: Keys.systemPromptBody) ?? ""
        return resolveSystemPromptBody(stored)
    }

    static func resolveSystemPromptBody(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? platformSystemPromptBody : trimmed
    }

    nonisolated static let modelPolicy = resolveModelPolicy(
        surface: .ios,
        totalMemoryBytes: ProcessInfo.processInfo.physicalMemory
    )

    private static var platformSystemPromptBody: String {
        ConfigDefaults.shared.mobileSystemPromptBody
    }

    private func persist() {
        defaults.set(modelId, forKey: Keys.modelId)
        defaults.set(contextLength, forKey: Keys.contextLength)
        defaults.set(temperature, forKey: Keys.temperature)
        defaults.set(systemPromptBody, forKey: Keys.systemPromptBody)
    }

    fileprivate enum Keys {
        static let modelId = "ensu.model.id"
        static let contextLength = "ensu.model.context"
        static let legacyMaxTokens = "ensu.model.max_tokens"
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
