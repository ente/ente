import Foundation

public enum DeviceSignal<Value: Equatable & Sendable>: Equatable, Sendable {
    case available(Value)
    case unsupported
    case unavailable(DeviceHealthError)
}

public enum DeviceHealthError: Equatable, Sendable {
    case batteryLevelUnavailable
    case thermalStatusUnknown
    case memoryTotalMissing
}

public struct BatteryReading: Equatable, Sendable {
    public let levelPercent: Int

    public init(levelPercent: Int) throws {
        guard (0...100).contains(levelPercent) else {
            throw DeviceHealthModelError.invalidBatteryReading
        }
        self.levelPercent = levelPercent
    }
}

public enum ThermalState: Equatable, Sendable {
    case nominal
    case moderate
    case serious
    case critical
}

public struct DeviceHealthSnapshot: Equatable, Sendable {
    public let observedAt: Date
    public let battery: DeviceSignal<BatteryReading>
    public let thermal: DeviceSignal<ThermalState>

    public init(
        observedAt: Date,
        battery: DeviceSignal<BatteryReading>,
        thermal: DeviceSignal<ThermalState>
    ) {
        self.observedAt = observedAt
        self.battery = battery
        self.thermal = thermal
    }
}

public enum DeviceHealthModelError: Error {
    case invalidBatteryReading
}
