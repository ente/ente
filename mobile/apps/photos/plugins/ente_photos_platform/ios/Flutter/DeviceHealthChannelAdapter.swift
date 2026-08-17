@preconcurrency import Flutter
import Foundation

@MainActor
final class DeviceHealthChannelAdapter: NSObject {
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private let service = DeviceHealthService()
    private var eventSink: FlutterEventSink?
    private var isAttached = true

    init(registrar: FlutterPluginRegistrar) {
        methodChannel = FlutterMethodChannel(
            name: Self.methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        eventChannel = FlutterEventChannel(
            name: Self.eventChannelName,
            binaryMessenger: registrar.messenger()
        )
        super.init()
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        eventChannel.setStreamHandler(self)
    }

    func detach() {
        guard isAttached else { return }
        isAttached = false
        eventSink = nil
        service.stopObserving()
        methodChannel.setMethodCallHandler(nil)
        eventChannel.setStreamHandler(nil)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard isAttached else { return }
        switch call.method {
        case "deviceHealth.getSnapshot":
            result(service.snapshot().channelValue)
        case "deviceHealth.getMemorySnapshot":
            result(service.memorySnapshot().memoryChannelValue)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static let methodChannelName = "io.ente.photos.platform"
    private static let eventChannelName = "io.ente.photos.platform/device_health_events"
}

extension DeviceHealthChannelAdapter: @preconcurrency FlutterStreamHandler {
    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        guard isAttached else { return nil }
        eventSink = events
        service.startObserving { [weak self] snapshot in
            self?.eventSink?(snapshot.channelValue)
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        service.stopObserving()
        return nil
    }
}

private extension DeviceHealthSnapshot {
    var channelValue: [String: Any] {
        [
            "platform": "ios",
            "observedAtMs": Int64(observedAt.timeIntervalSince1970 * 1000),
            "battery": battery.batteryChannelValue,
            "thermal": thermal.thermalChannelValue,
        ]
    }
}

private extension DeviceSignal where Value == BatteryReading {
    var batteryChannelValue: [String: Any] {
        switch self {
        case .available(let reading):
            return [
                "status": "available",
                "levelPercent": reading.levelPercent,
            ]
        case .unsupported:
            return ["status": "unsupported"]
        case .unavailable(let error):
            return error.channelValue
        }
    }
}

private extension DeviceSignal where Value == ThermalState {
    var thermalChannelValue: [String: Any] {
        switch self {
        case .available(let state):
            return ["status": "available", "state": state.channelValue]
        case .unsupported:
            return ["status": "unsupported"]
        case .unavailable(let error):
            return error.channelValue
        }
    }
}

private extension DeviceSignal where Value == UInt64 {
    var memoryChannelValue: [String: Any] {
        switch self {
        case .available(let totalBytes):
            return ["status": "available", "totalBytes": Int64(totalBytes)]
        case .unsupported:
            return ["status": "unsupported"]
        case .unavailable(let error):
            return error.channelValue
        }
    }
}

private extension DeviceHealthError {
    var channelValue: [String: Any] {
        ["status": "unavailable", "errorCode": errorCode]
    }

    var errorCode: String {
        switch self {
        case .batteryLevelUnavailable: "battery_level_unavailable"
        case .thermalStatusUnknown: "thermal_status_unknown"
        case .memoryTotalMissing: "memory_total_missing"
        }
    }
}

private extension ThermalState {
    var channelValue: String {
        switch self {
        case .nominal: "nominal"
        case .moderate: "moderate"
        case .serious: "serious"
        case .critical: "critical"
        }
    }
}
