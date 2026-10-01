@preconcurrency import Flutter

@MainActor
final class MemoriesExportChannelAdapter {
    private let channel: FlutterMethodChannel
    private var isAttached = true
    private var exportTask: Task<Void, Never>?

    init(registrar: FlutterPluginRegistrar) {
        channel = FlutterMethodChannel(
            name: "io.ente.photos.platform/memories_export",
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard isAttached else { return }
        switch call.method {
        case "memoriesExport.export":
            exportTask = Task {
                defer { exportTask = nil }
                if Task.isCancelled {
                    result(nil)
                } else {
                    result(FlutterError(code: "not_implemented", message: "Memories export is not implemented", details: nil))
                }
            }
        case "memoriesExport.cancel":
            exportTask?.cancel()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func reportProgress(_ progress: Double) {
        guard isAttached else { return }
        channel.invokeMethod("memoriesExport.progress", arguments: progress)
    }

    func detach() {
        exportTask?.cancel()
        isAttached = false
        channel.setMethodCallHandler(nil)
    }
}
