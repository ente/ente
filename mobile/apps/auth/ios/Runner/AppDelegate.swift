import Flutter
import UIKit
import app_links

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let url = AppLinks.shared.getLink(launchOptions: launchOptions) {
      AppLinks.shared.handleLink(url: url)
    }

    return false

  }
}
