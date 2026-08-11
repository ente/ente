@preconcurrency import Flutter
import Foundation

@MainActor
public final class PhotosPlatformPlugin: NSObject, @preconcurrency FlutterPlugin {
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private let healthService = DeviceHealthService()
    private var eventSink: FlutterEventSink?
    private let pluginInstanceID = UUID().uuidString

    private init(registrar: FlutterPluginRegistrar) {
        methodChannel = FlutterMethodChannel(
            name: Self.methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        eventChannel = FlutterEventChannel(
            name: Self.eventChannelName,
            binaryMessenger: registrar.messenger()
        )
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PhotosPlatformPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)
        instance.eventChannel.setStreamHandler(instance)
        registrar.publish(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "deviceHealth.getSnapshot":
            result(healthService.snapshot().channelValue)
        case "deviceHealth.getMemorySnapshot":
            result(healthService.memorySnapshot().memoryChannelValue)
        case "mlLock.tryAcquire":
            tryAcquireMlLock(call, result: result)
        case "mlLock.release":
            releaseMlLock(call, result: result)
        case "mlLock.state":
            result(MlProcessLockRegistry.shared.state()?.channelValue)
        case "mlLock.resetForInstance":
            result(MlProcessLockRegistry.shared.reset(for: pluginInstanceID))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        MlProcessLockRegistry.shared.reset(for: pluginInstanceID)
        eventSink = nil
        healthService.stopObserving()
        methodChannel.setMethodCallHandler(nil)
        eventChannel.setStreamHandler(nil)
    }

    private func tryAcquireMlLock(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard
            let arguments = call.arguments as? [String: Any],
            let token = nonEmptyString(arguments["token"]),
            let origin = nonEmptyString(arguments["origin"]),
            let operation = nonEmptyString(arguments["operation"])
        else {
            result(FlutterError(
                code: "invalid_argument",
                message: "token, origin, and operation must be non-empty strings",
                details: nil
            ))
            return
        }
        let acquireResult = MlProcessLockRegistry.shared.tryAcquire(
            pluginInstanceID: pluginInstanceID,
            token: token,
            origin: origin,
            operation: operation
        )
        result([
            "acquired": acquireResult.acquired,
            "holder": acquireResult.holder.channelValue,
        ])
    }

    private func releaseMlLock(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard
            let arguments = call.arguments as? [String: Any],
            let token = nonEmptyString(arguments["token"])
        else {
            result(FlutterError(
                code: "invalid_argument",
                message: "token must be a non-empty string",
                details: nil
            ))
            return
        }
        result(MlProcessLockRegistry.shared.release(pluginInstanceID: pluginInstanceID, token: token))
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static let methodChannelName = "io.ente.photos.platform"
    private static let eventChannelName = "io.ente.photos.platform/device_health_events"
}

private extension MlProcessLockState {
    var channelValue: [String: Any] {
        let now = DispatchTime.now().uptimeNanoseconds
        return [
            "origin": origin,
            "operation": operation,
            "heldDurationMs": Int64(now >= acquiredAtUptimeNanoseconds ? (now - acquiredAtUptimeNanoseconds) / 1_000_000 : 0),
        ]
    }
}

extension PhotosPlatformPlugin: @preconcurrency FlutterStreamHandler {
    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        healthService.startObserving { [weak self] snapshot in
            self?.eventSink?(snapshot.channelValue)
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        healthService.stopObserving()
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
