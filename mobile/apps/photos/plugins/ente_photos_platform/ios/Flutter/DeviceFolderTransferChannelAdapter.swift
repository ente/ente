@preconcurrency import Flutter
import Foundation

@MainActor
final class DeviceFolderTransferChannelAdapter: NSObject {
    private let methodChannel: FlutterMethodChannel
    private let service = DeviceFolderTransferService()
    private var isAttached = true
    private var isTransferring = false

    init(registrar: FlutterPluginRegistrar) {
        methodChannel = FlutterMethodChannel(
            name: "io.ente.photos.platform/device_folder_transfer",
            binaryMessenger: registrar.messenger()
        )
        super.init()
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    func detach() {
        isAttached = false
        methodChannel.setMethodCallHandler(nil)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard isAttached else { return }
        let arguments = call.arguments as? [String: Any] ?? [:]
        let source = arguments["sourceFolderID"] as? String
        let service = service
        switch call.method {
        case "deviceFolderTransfer.supportedOperations":
            run({ service.supportedOperations(sourceFolderID: source) }, result: result)
        case "deviceFolderTransfer.eligibleDestinations":
            guard let operation = arguments["operation"] as? String,
                  let candidates = arguments["candidateFolderIDs"] as? [String] else {
                result(FlutterError(code: "device_folder_transfer_invalid_arguments", message: nil, details: nil))
                return
            }
            run({
                service.eligibleDestinationIDs(
                    operation: operation,
                    sourceFolderID: source,
                    candidateIDs: candidates
                )
            }, result: result)
        case "deviceFolderTransfer.transfer":
            guard let operation = arguments["operation"] as? String,
                  let target = arguments["targetFolderID"] as? String,
                  let ids = arguments["sourceLocalIDs"] as? [String], !ids.isEmpty else {
                result(FlutterError(code: "device_folder_transfer_invalid_arguments", message: nil, details: nil))
                return
            }
            guard !isTransferring else {
                result(FlutterError(code: "device_folder_transfer_in_progress", message: nil, details: nil))
                return
            }
            isTransferring = true
            Task {
                guard isAttached else {
                    isTransferring = false
                    return
                }
                let outcome = await Task.detached(priority: .userInitiated) {
                    service.transfer(
                        operation: operation,
                        sourceFolderID: source,
                        targetFolderID: target,
                        sourceLocalIDs: ids
                    )
                }.value
                isTransferring = false
                guard isAttached else { return }
                result(["destinations": outcome.destinations, "failures": outcome.failures])
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func run<T: Sendable>(
        _ work: @escaping @Sendable () -> T,
        result: @escaping FlutterResult
    ) {
        Task {
            guard isAttached else { return }
            let value = await Task.detached(priority: .userInitiated, operation: work).value
            guard isAttached else { return }
            result(value)
        }
    }
}
