import Flutter
import Foundation

final class NotificationKeyPlugin: NSObject, FlutterPlugin {
  private static let queue = DispatchQueue(label: "io.ente.frame.notifications.keys")

  static func register(in registry: FlutterPluginRegistry) {
    if let registrar = registry.registrar(forPlugin: "NotificationKeyPlugin") {
      register(with: registrar)
    }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: NotificationKeyStore.service, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NotificationKeyPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    Self.queue.async {
      do {
        let arguments = call.arguments as? [String: Any] ?? [:]
        if call.method == "getPrivateKey" || call.method == "setPrivateKey" {
          guard let token = arguments["sessionToken"] as? String,
            UserDefaults.standard.string(forKey: "flutter.token") == token else {
            throw NotificationKeyStore.StoreError.invalidRecord
          }
        }
        let response: Any?
        switch call.method {
        case "getPrivateKey":
          let recipient = try NotificationKeyStore.readForPreparation()
          response = recipient?.privateKey
        case "setPrivateKey":
          guard let privateKey = arguments["privateKey"] as? String else {
            throw NotificationKeyStore.StoreError.invalidRecord
          }
          try NotificationKeyStore.write(privateKey: privateKey)
          response = nil
        case "clear":
          try NotificationKeyStore.clear()
          response = nil
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(response) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "notification_key_store", message: "\(error)", details: nil))
        }
      }
    }
  }
}
