import AVFoundation
import Flutter
import UIKit
import UserNotifications
import app_links
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let workmanagerDebugThreadIdentifier =
    "io.ente.frame.workmanager.debug"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureWorkmanagerDebugHandler()

    // Prevent interrupting background audio from other apps on launch
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .ambient,
        mode: .default,
        options: [.mixWithOthers]
      )
    } catch {
      print("Failed to configure initial audio session: \(error)")
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    GeneratedPluginRegistrant.register(with: self)
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    var freqInMinutes = 30 * 60
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "io.ente.frame.iOSBackgroundAppRefresh",
      frequency: NSNumber(value: freqInMinutes))
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "io.ente.frame.iOSBackgroundProcessing")

    if let url = AppLinks.shared.getLink(launchOptions: launchOptions) {
      // only accept non-homewidget urls for AppLinks
      if !url.absoluteString.contains("homeWidget") {
        AppLinks.shared.handleLink(url: url)
        return true
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureWorkmanagerDebugHandler() {
    guard shouldEnableWorkmanagerDebugNotifications() else {
      return
    }

    WorkmanagerDebug.setCurrent(
      NotificationDebugHandler(threadIdentifier: Self.workmanagerDebugThreadIdentifier)
    )
  }

  private func shouldEnableWorkmanagerDebugNotifications() -> Bool {
    let defaults = UserDefaults.standard
    if defaults.bool(forKey: "flutter.ls.internal_user_disabled") {
      return false
    }
    if !defaults.bool(forKey: "flutter.ls.bg_debug_notifications_enabled") &&
        defaults.object(forKey: "flutter.ls.bg_debug_notifications_enabled") != nil {
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

  override func applicationDidBecomeActive(_ application: UIApplication) {
    signal(SIGPIPE, SIG_IGN)
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    signal(SIGPIPE, SIG_IGN)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let content = notification.request.content
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
