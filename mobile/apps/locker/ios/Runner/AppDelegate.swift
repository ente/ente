import Flutter
import UIKit
import app_links

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // AppLinks 6.4.1 does not read cold-start scene connection options.
    for context in connectionOptions.urlContexts {
      AppLinks.shared.handleLink(url: context.url)
    }
    for activity in connectionOptions.userActivities {
      if let url = activity.webpageURL {
        AppLinks.shared.handleLink(url: url)
      }
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

}
