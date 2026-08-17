@preconcurrency import Flutter
import Foundation

@MainActor
final class ProcessLockChannelAdapter: NSObject {
    private let methodChannel: FlutterMethodChannel
    private let instanceId = UUID().uuidString
    private var isAttached = true

    init(registrar: FlutterPluginRegistrar) {
        methodChannel = FlutterMethodChannel(
            name: Self.methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        super.init()
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    func detach() {
        guard isAttached else { return }
        isAttached = false
        ProcessLockRegistry.shared.releaseAll(instanceId: instanceId)
        methodChannel.setMethodCallHandler(nil)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard isAttached else {
            result(
                FlutterError(code: "detached", message: "adapter detached", details: nil)
            )
            return
        }
        switch call.method {
        case "processLock.tryAcquire":
            handleTryAcquire(call, result: result)
        case "processLock.release":
            handleRelease(call, result: result)
        case "processLock.state":
            handleState(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleTryAcquire(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
            let name = args["name"] as? String, !name.isEmpty,
            let origin = args["origin"] as? String, !origin.isEmpty,
            let operation = args["operation"] as? String, !operation.isEmpty
        else {
            result(
                FlutterError(
                    code: "invalidArguments",
                    message: "name, origin and operation are required",
                    details: nil
                )
            )
            return
        }
        result(
            ProcessLockRegistry.shared.tryAcquire(
                name: name,
                instanceId: instanceId,
                origin: origin,
                operation: operation
            )
        )
    }

    private func handleRelease(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
            let name = args["name"] as? String, !name.isEmpty
        else {
            result(
                FlutterError(
                    code: "invalidArguments",
                    message: "name is required",
                    details: nil
                )
            )
            return
        }
        result(ProcessLockRegistry.shared.release(name: name, instanceId: instanceId))
    }

    private func handleState(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
            let name = args["name"] as? String, !name.isEmpty
        else {
            result(
                FlutterError(
                    code: "invalidArguments",
                    message: "name is required",
                    details: nil
                )
            )
            return
        }
        result(ProcessLockRegistry.shared.state(name: name))
    }

    private static let methodChannelName = "io.ente.photos.platform/process_lock"
}
