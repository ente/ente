import Foundation

struct TaskConfiguration: Codable, Equatable {
  let identifier: String
  let kind: String
  let frequencyMs: Int64
  let initialDelayMs: Int64
  let flexMs: Int64?
  let requiresNetwork: Bool
  let requiresCharging: Bool
  let requiresDeviceIdle: Bool
  let runBudgetMs: Int64?
  let foregroundStopTimeoutMs: Int64?
  let callbackHandle: Int64

  func hasSameSchedule(as other: TaskConfiguration) -> Bool {
    identifier == other.identifier && kind == other.kind && frequencyMs == other.frequencyMs
      && initialDelayMs == other.initialDelayMs && requiresNetwork == other.requiresNetwork
      && requiresCharging == other.requiresCharging
  }

  init(_ data: [String: Any], callbackHandle: Int64) throws {
    guard let identifier = data["identifier"] as? String, !identifier.isEmpty,
      let kind = data["kind"] as? String, ["refresh", "processing"].contains(kind),
      let frequency = data["frequencyMs"] as? NSNumber, frequency.int64Value > 0,
      callbackHandle != 0
    else {
      throw ConfigurationError.invalidTask
    }
    self.identifier = identifier
    self.kind = kind
    self.frequencyMs = frequency.int64Value
    self.initialDelayMs = (data["initialDelayMs"] as? NSNumber)?.int64Value ?? 0
    self.flexMs = (data["flexMs"] as? NSNumber)?.int64Value
    self.requiresNetwork = data["requiresNetwork"] as? Bool ?? false
    self.requiresCharging = data["requiresCharging"] as? Bool ?? false
    self.requiresDeviceIdle = data["requiresDeviceIdle"] as? Bool ?? false
    self.runBudgetMs = (data["runBudgetMs"] as? NSNumber)?.int64Value
    self.foregroundStopTimeoutMs = (data["foregroundStopTimeoutMs"] as? NSNumber)?.int64Value
    self.callbackHandle = callbackHandle
    guard
      [initialDelayMs, flexMs, runBudgetMs, foregroundStopTimeoutMs]
        .compactMap({ $0 }).allSatisfy({ $0 >= 0 })
    else {
      throw ConfigurationError.invalidDuration
    }
    guard flexMs == nil, !requiresDeviceIdle,
      kind == "processing" || (!requiresNetwork && !requiresCharging)
    else {
      throw ConfigurationError.unsupportedConstraint
    }
  }

  enum ConfigurationError: Error {
    case invalidTask
    case invalidDuration
    case unsupportedConstraint
    case unregisteredIdentifier
    case duplicateIdentifier
  }
}

struct StoredConfiguration: Codable {
  var enabled: Bool
  var tasks: [TaskConfiguration]
  var submitted: [TaskConfiguration]? = nil

  static func load() -> StoredConfiguration {
    guard let data = UserDefaults.standard.data(forKey: "ente_background_manager"),
      let value = try? JSONDecoder().decode(StoredConfiguration.self, from: data)
    else {
      return StoredConfiguration(enabled: false, tasks: [])
    }
    return value
  }

  func save() throws {
    UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "ente_background_manager")
  }
}
