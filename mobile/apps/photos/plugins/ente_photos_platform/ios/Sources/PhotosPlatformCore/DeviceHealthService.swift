import Foundation
import UIKit

@MainActor
public final class DeviceHealthService {
    private typealias Observer = @MainActor (DeviceHealthSnapshot) -> Void

    private var observer: Observer?
    private var observerTokens: [NSObjectProtocol] = []
    private var hasBatteryMonitoringLease = false
    private var lastState: HealthState?

    public init() {}

    public func snapshot() -> DeviceHealthSnapshot {
        guard Self.supportsBatteryMonitoring else { return currentSnapshot() }
        Self.acquireBatteryMonitoring()
        defer { Self.releaseBatteryMonitoring() }
        return currentSnapshot()
    }

    public func memorySnapshot() -> DeviceSignal<UInt64> {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        return totalBytes > 0
            ? .available(totalBytes)
            : .unavailable(.memoryTotalMissing)
    }

    public func startObserving(_ observer: @escaping @MainActor (DeviceHealthSnapshot) -> Void) {
        stopObserving()
        self.observer = observer

        let device = UIDevice.current
        if Self.supportsBatteryMonitoring {
            Self.acquireBatteryMonitoring()
            hasBatteryMonitoringLease = true
        }

        let center = NotificationCenter.default
        let processInfo = ProcessInfo.processInfo
        _ = processInfo.thermalState
        observerTokens = [
            center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: processInfo,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.emitSnapshot() }
            }
        ]
        if Self.supportsBatteryMonitoring {
            observerTokens += [
                center.addObserver(
                    forName: UIDevice.batteryLevelDidChangeNotification,
                    object: device,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.emitSnapshot() }
                },
                center.addObserver(
                    forName: UIDevice.batteryStateDidChangeNotification,
                    object: device,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.emitSnapshot() }
                },
            ]
        }
        emitSnapshot()
    }

    public func stopObserving() {
        observer = nil
        lastState = nil
        observerTokens.forEach(NotificationCenter.default.removeObserver)
        observerTokens.removeAll()
        if hasBatteryMonitoringLease {
            Self.releaseBatteryMonitoring()
            hasBatteryMonitoringLease = false
        }
    }

    private func emitSnapshot() {
        guard let observer else { return }
        let snapshot = currentSnapshot()
        let state = HealthState(battery: snapshot.battery, thermal: snapshot.thermal)
        guard state != lastState else { return }
        lastState = state
        observer(snapshot)
    }

    private func currentSnapshot() -> DeviceHealthSnapshot {
        DeviceHealthSnapshot(
            observedAt: Date(),
            battery: batterySnapshot(),
            thermal: thermalSnapshot()
        )
    }

    private func batterySnapshot() -> DeviceSignal<BatteryReading> {
        guard Self.supportsBatteryMonitoring else { return .unsupported }
        let level = UIDevice.current.batteryLevel
        guard level >= 0, level <= 1,
            let reading = try? BatteryReading(levelPercent: Int(level * 100))
        else {
            return .unavailable(.batteryLevelUnavailable)
        }
        return .available(reading)
    }

    private func thermalSnapshot() -> DeviceSignal<ThermalState> {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .available(.nominal)
        case .fair: .available(.moderate)
        case .serious: .available(.serious)
        case .critical: .available(.critical)
        @unknown default: .unavailable(.thermalStatusUnknown)
        }
    }

    private struct HealthState: Equatable {
        let battery: DeviceSignal<BatteryReading>
        let thermal: DeviceSignal<ThermalState>
    }

    private static var supportsBatteryMonitoring: Bool {
        #if targetEnvironment(simulator)
            false
        #else
            true
        #endif
    }

    private static var batteryMonitoringLeaseCount = 0
    private static var ownsBatteryMonitoring = false

    private static func acquireBatteryMonitoring() {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled {
            device.isBatteryMonitoringEnabled = true
            ownsBatteryMonitoring = true
        }
        batteryMonitoringLeaseCount += 1
    }

    private static func releaseBatteryMonitoring() {
        precondition(batteryMonitoringLeaseCount > 0)
        batteryMonitoringLeaseCount -= 1
        if batteryMonitoringLeaseCount == 0 && ownsBatteryMonitoring {
            UIDevice.current.isBatteryMonitoringEnabled = false
            ownsBatteryMonitoring = false
        }
    }
}
