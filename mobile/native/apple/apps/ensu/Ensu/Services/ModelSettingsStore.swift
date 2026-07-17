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

    @Published var useCustomModel: Bool {
        didSet { persist() }
    }
    @Published var modelUrl: String {
        didSet { persist() }
    }
    @Published var mmprojUrl: String {
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
        self.useCustomModel = defaults.bool(forKey: Keys.useCustomModel)
        self.modelUrl = defaults.string(forKey: Keys.modelUrl) ?? ""
        self.mmprojUrl = defaults.string(forKey: Keys.mmprojUrl) ?? ""
        self.contextLength = defaults.string(forKey: Keys.contextLength) ?? ""
        self.maxTokens = defaults.string(forKey: Keys.maxTokens) ?? ""
        self.temperature = defaults.string(forKey: Keys.temperature) ?? ""
        self.systemPromptBody = defaults.string(forKey: Keys.systemPromptBody) ?? ""
    }

    func saveCustomModel(url: String, mmproj: String, contextLength: String, maxTokens: String, temperature: String) {
        useCustomModel = true
        modelUrl = url
        mmprojUrl = mmproj
        self.contextLength = contextLength
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    func resetToDefault() {
        useCustomModel = false
        modelUrl = ""
        mmprojUrl = ""
        contextLength = ""
        maxTokens = ""
        temperature = ""
    }

    func currentTarget() -> LlmModelTarget {
        let useCustom = useCustomModel && !modelUrl.isEmpty
        let defaults = ConfigDefaults.shared
        let defaultModel = Self.platformDefaultModel
        let url = useCustom ? modelUrl : defaultModel.url
        let mmproj = useCustom ? (mmprojUrl.isEmpty ? nil : mmprojUrl) : defaultModel.mmprojUrl
        let context = Int(contextLength)
        let maxOutput = Int(maxTokens).flatMap { $0 > 0 ? $0 : nil }
        let id: String
        if useCustom {
            let presets = [defaultModel] + defaults.mobileModelPresets
            id = presets.first(where: { $0.url == url && $0.mmprojUrl == mmproj })?.id ?? "custom:\(url)"
        } else {
            id = defaultModel.id
        }
        return LlmModelTarget(id: id, url: url, mmprojUrl: mmproj, contextLength: context, maxTokens: maxOutput)
    }

    static var defaultModelName: String { platformDefaultModel.title }
    static var defaultModelUrl: String { platformDefaultModel.url }
    static var defaultMmprojUrl: String? { platformDefaultModel.mmprojUrl }
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
        defaults.set(useCustomModel, forKey: Keys.useCustomModel)
        defaults.set(modelUrl, forKey: Keys.modelUrl)
        defaults.set(mmprojUrl, forKey: Keys.mmprojUrl)
        defaults.set(contextLength, forKey: Keys.contextLength)
        defaults.set(maxTokens, forKey: Keys.maxTokens)
        defaults.set(temperature, forKey: Keys.temperature)
        defaults.set(systemPromptBody, forKey: Keys.systemPromptBody)
    }

    fileprivate enum Keys {
        static let useCustomModel = "ensu.model.use_custom"
        static let modelUrl = "ensu.model.url"
        static let mmprojUrl = "ensu.model.mmproj"
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
