@preconcurrency import Flutter
import UIKit

@MainActor
public final class BackgroundManagerPlugin: NSObject, @preconcurrency FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var observesOutcomes = false

  private init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(
      name: "io.ente.background/control",
      binaryMessenger: registrar.messenger()
    )
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BackgroundManagerPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: instance.channel)
    registrar.publish(instance)
    BackgroundRuntime.shared.attach(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    observesOutcomes = false
    BackgroundRuntime.shared.detach(self)
    channel.setMethodCallHandler(nil)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      observesOutcomes = true
      BackgroundRuntime.shared.configure(call.arguments as? [String: Any], result: result)
    case "stopActiveRun":
      BackgroundRuntime.shared.requestStop(result: result)
    case "scheduledTasks":
      BackgroundRuntime.shared.scheduledTasks(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  var canReport: Bool { observesOutcomes }

  func report(_ event: [String: Any], fallback: @escaping () -> Void) {
    guard observesOutcomes else {
      fallback()
      return
    }
    channel.invokeMethod("outcome", arguments: event) { response in
      if (response as? Bool) != true { fallback() }
    }
  }

  public static func install(
    isEnabled: @escaping () -> Bool,
    registrant: @escaping (FlutterPluginRegistry) -> Void
  ) {
    BackgroundRuntime.shared.install(isEnabled: isEnabled, registrant: registrant)
  }

  @discardableResult
  public static func registerTask(identifier: String, processing: Bool) -> Bool {
    BackgroundRuntime.shared.register(identifier: identifier, processing: processing)
  }
}
