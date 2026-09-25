import Flutter
import Foundation

public class BackupExclusionPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.ente.backup_exclusion",
            binaryMessenger: registrar.messenger()
        )
        let instance = BackupExclusionPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "excludeFromBackup" else {
            result(FlutterMethodNotImplemented)
            return
        }

        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing 'path'", details: nil))
            return
        }

        let url = NSURL(fileURLWithPath: path)
        do {
            try url.setResourceValue(true, forKey: URLResourceKey.isExcludedFromBackupKey)
            result(true)
        } catch {
            result(FlutterError(
                code: "EXCLUDE_BACKUP_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }
}
