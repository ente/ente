import AuthenticationServices
import Flutter
import LocalAuthentication

final class AutoFillBridge {
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "io.ente.auth/autofill", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            // Revocation must also work during startup and on older OS versions.
            // These operations do not use the iOS 18 credential APIs.
            if call.method == "clear" || call.method == "invalidate" {
                do {
                    if call.method == "clear" { try AutoFillStore.clear(); result(nil) }
                    else { result(try AutoFillStore.invalidate()) }
                } catch {
                    result(FlutterError(code: "autofill_failed", message: "Could not revoke AutoFill data", details: nil))
                }
                return
            }
            guard #available(iOS 18.0, *) else {
                if call.method == "isSupported" { result(false) }
                else { result(FlutterMethodNotImplemented) }
                return
            }
            do {
                switch call.method {
                case "isSupported": result(true)
                case "publish":
                    guard let json = call.arguments as? String, let data = json.data(using: .utf8) else {
                        result(FlutterError(code: "invalid_snapshot", message: "Invalid AutoFill data", details: nil))
                        return
                    }
                    let snapshot = try JSONDecoder().decode(AutoFillSnapshot.self, from: data)
                    result(try AutoFillStore.write(snapshot))
                case "authenticate":
                    let context = LAContext()
                    context.evaluatePolicy(.deviceOwnerAuthentication,
                                           localizedReason: "Enable verification code AutoFill") { success, _ in
                        DispatchQueue.main.async { result(success) }
                    }
                case "openSettings":
                    ASSettingsHelper.openCredentialProviderAppSettings { error in
                        DispatchQueue.main.async {
                            if error != nil {
                                result(FlutterError(code: "settings_failed", message: "Could not open AutoFill settings", details: nil))
                            } else { result(nil) }
                        }
                    }
                default: result(FlutterMethodNotImplemented)
                }
            } catch {
                // Never include secrets or the original decoding error in platform logs.
                result(FlutterError(code: "autofill_failed", message: "Could not update AutoFill data", details: nil))
            }
        }
    }
}
