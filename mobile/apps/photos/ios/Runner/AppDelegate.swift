import AVFoundation
import Flutter
import UIKit
import UserNotifications
import ente_background_manager
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let workmanagerDebugThreadIdentifier =
    "io.ente.frame.workmanager.debug"
  private let startupTrace: BackgroundStartupTrace = {
    let trace = BackgroundStartupTrace(scope: "app")
    trace.event("app.delegate.initializing")
    return trace
  }()

  override func application(
    _ application: UIApplication,
    willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    startupTrace.event(
      "app.willFinishLaunching.begin",
      detail: "applicationState=\(application.applicationState.rawValue)")
    defer { startupTrace.event("app.willFinishLaunching.end") }
    return super.application(application, willFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    startupTrace.event(
      "app.didFinishLaunching.begin",
      detail: "applicationState=\(application.applicationState.rawValue)")
    defer { startupTrace.event("app.didFinishLaunching.end") }
    startupTrace.measure("app.debugHandler") {
      configureWorkmanagerDebugHandler()
    }

    // Prevent interrupting background audio from other apps on launch
    do {
      try startupTrace.measure("app.audioSession") {
        try AVAudioSession.sharedInstance().setCategory(
          .ambient,
          mode: .default,
          options: [.mixWithOthers]
        )
      }
    } catch {
      print("Failed to configure initial audio session: \(error)")
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    startupTrace.measure("app.backgroundManager.install") {
      BackgroundManagerPlugin.install(
        isEnabled: { Self.shouldUseNativeBackgroundManager() },
        registrant: { registry in
          GeneratedPluginRegistrant.register(with: registry)
          NotificationKeyPlugin.register(in: registry)
        }
      )
    }
    BackgroundManagerPlugin.registerTask(
      identifier: "io.ente.photos.nativeBackgroundRefresh", processing: false)
    BackgroundManagerPlugin.registerTask(
      identifier: "io.ente.photos.nativeBackgroundProcessing", processing: true)
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      BackgroundStartupTrace(scope: "workmanager").measure("task.plugins") {
        GeneratedPluginRegistrant.register(with: registry)
        NotificationKeyPlugin.register(in: registry)
      }
    }
    startupTrace.measure("app.workmanager.register") {
      let freqInMinutes = 30 * 60
      WorkmanagerPlugin.registerPeriodicTask(
        withIdentifier: "io.ente.frame.iOSBackgroundAppRefresh",
        frequency: NSNumber(value: freqInMinutes))
      WorkmanagerPlugin.registerBGProcessingTask(
        withIdentifier: "io.ente.frame.iOSBackgroundProcessing")
    }

    return startupTrace.measure("app.super.didFinishLaunching") {
      super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    startupTrace.measure("app.plugins") {
      GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
      NotificationKeyPlugin.register(in: engineBridge.pluginRegistry)
    }
  }

  private func configureWorkmanagerDebugHandler() {
    guard shouldEnableWorkmanagerDebugNotifications() else {
      return
    }

    WorkmanagerDebug.setCurrent(
      NotificationDebugHandler(threadIdentifier: Self.workmanagerDebugThreadIdentifier)
    )
  }

  private static func shouldUseNativeBackgroundManager() -> Bool {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: "flutter.ls.internal_user_disabled") else {
      return false
    }
    guard let remoteFlags = defaults.string(forKey: "flutter.remote_flags"),
      let data = remoteFlags.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return false
    }
    return json["internalUser"] as? Bool ?? false
  }

  private func shouldEnableWorkmanagerDebugNotifications() -> Bool {
    let defaults = UserDefaults.standard
    if defaults.bool(forKey: "flutter.ls.internal_user_disabled") {
      return false
    }
    if !defaults.bool(forKey: "flutter.ls.bg_debug_notifications_enabled")
      && defaults.object(forKey: "flutter.ls.bg_debug_notifications_enabled") != nil
    {
      return false
    }

    guard let remoteFlags = defaults.string(forKey: "flutter.remote_flags"),
      let data = remoteFlags.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return false
    }

    return json["internalUser"] as? Bool ?? false
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let content = notification.request.content
    if content.userInfo["notificationVersion"] != nil {
      completionHandler([])
      return
    }
    // iOS suppresses foreground notification presentation unless the delegate
    // opts in. Workmanager debug notifications are silent (banner only); all
    // other notifications get the standard banner + sound + badge.
    if content.threadIdentifier == Self.workmanagerDebugThreadIdentifier {
      if #available(iOS 14.0, *) {
        completionHandler([.list, .banner])
      } else {
        completionHandler([.alert])
      }
      return
    }

    if #available(iOS 14.0, *) {
      completionHandler([.list, .banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}
