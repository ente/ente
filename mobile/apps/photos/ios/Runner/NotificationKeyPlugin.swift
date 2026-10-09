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
        // Other Flutter engines can retain a session after logout.
        if call.method == "prepare" {
          guard let token = arguments["sessionToken"] as? String,
            UserDefaults.standard.string(forKey: "flutter.token") == token else {
            throw NotificationKeyStore.StoreError.invalidRecord
          }
        }
        let response: Any?
        switch call.method {
        case "prepare":
          let recipient = try NotificationKeyStore.getOrCreate()
          guard let publicKey = recipient.publicKey else { throw NotificationKeyStore.StoreError.invalidRecord }
          _ = Self.syncPreference()
          response = ["version": 1, "publicKey": publicKey]
        case "syncPreference":
          _ = Self.syncPreference()
          response = nil
        case "clear":
          defer { NotificationKeyStore.preferences.removeObject(forKey: NotificationKeyStore.preferenceKey) }
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

  private static func syncPreference() -> Bool {
    let enabled = UserDefaults.standard.object(forKey: "flutter.notifications_enabled_shared_photos") as? Bool ?? true
    NotificationKeyStore.preferences.set(enabled, forKey: NotificationKeyStore.preferenceKey)
    return enabled
  }
}
