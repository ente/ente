import AuthCore
import Flutter

@available(iOS 17, *)
@MainActor
final class WatchPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let companion = PhoneCompanion()
  private var events: FlutterEventSink?

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = WatchPlugin()
    let channel = FlutterMethodChannel(
      name: "io.ente.auth/watch", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
    FlutterEventChannel(name: "io.ente.auth/watch/state", binaryMessenger: registrar.messenger())
      .setStreamHandler(plugin)
    plugin.companion.onChange = { [weak plugin] in plugin?.emitState() }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "state": companion.refresh()
      case "approve": try companion.approve(id: try enrollmentID(arguments))
      case "publish":
        guard let data = (arguments["snapshot"] as? FlutterStandardTypedData)?.data else {
          throw WatchError.invalidData
        }
        guard data.count <= Envelope.maxPlaintextBytes else { throw WatchError.payloadTooLarge }
        guard let epoch = arguments["vaultEpoch"] as? String else { throw WatchError.staleVault }
        try companion.publish(
          JSONDecoder().decode(Snapshot.self, from: data), enrollmentID: enrollmentID(arguments),
          vaultEpoch: epoch)
      case "disable": try companion.disable(enrollmentID: enrollmentID(arguments))
      case "clear": try companion.clear()
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(stateValue())
    } catch {
      let code = (error as? WatchError)?.rawValue ?? "watchUnavailable"
      result(FlutterError(code: code, message: "Could not update the watch.", details: nil))
    }
  }

  private func enrollmentID(_ arguments: [String: Any]) throws -> String {
    guard let id = arguments["enrollmentID"] as? String else { throw WatchError.wrongEnrollment }
    return id
  }

  private func stateValue() -> [String: Any] {
    let state = companion.state
    return [
      "phase": state.phase.rawValue,
      "enrollmentID": (state.enrollmentID as Any?) ?? NSNull(),
      "requestID": (state.requestID as Any?) ?? NSNull(),
      "vaultEpoch": (state.vaultEpoch as Any?) ?? NSNull(),
    ]
  }

  private func emitState() { events?(stateValue()) }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    self.events = events
    companion.refresh()
    emitState()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    events = nil
    return nil
  }
}
