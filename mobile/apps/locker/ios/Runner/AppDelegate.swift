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
    LockerFileOpenerPlugin.register(in: engineBridge.pluginRegistry)
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

final class LockerFileOpenerPlugin: NSObject, FlutterPlugin, UIDocumentInteractionControllerDelegate {
  private static var documentController: UIDocumentInteractionController?

  static func register(in registry: FlutterPluginRegistry) {
    if let registrar = registry.registrar(forPlugin: "LockerFileOpenerPlugin") {
      register(with: registrar)
    }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "io.ente.locker/file_opener",
      binaryMessenger: registrar.messenger()
    )
    let instance = LockerFileOpenerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "openFile" {
      guard let args = call.arguments as? [String: Any],
            let filePath = args["filePath"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "filePath is required", details: nil))
        return
      }

      let fileUrl = URL(fileURLWithPath: filePath)
      guard FileManager.default.fileExists(atPath: fileUrl.path) else {
        result(["resultType": "fileNotFound", "message": "File does not exist"])
        return
      }

      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        let controller = UIDocumentInteractionController(url: fileUrl)
        controller.delegate = self
        Self.documentController = controller

        guard let rootViewController = Self.findTopViewController() else {
          result(["resultType": "error", "message": "No active view controller found"])
          return
        }

        let didPresent = controller.presentOptionsMenu(
          from: rootViewController.view.bounds,
          in: rootViewController.view,
          animated: true
        )
        if didPresent {
          result(["resultType": "done", "message": "done"])
        } else {
          result(["resultType": "noAppToOpen", "message": "No application available to open this file"])
        }
      }
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
  ) -> UIViewController {
    Self.findTopViewController() ?? UIViewController()
  }

  private static func findTopViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }),
         let root = keyWindow.rootViewController {
        var top = root
        while let presented = top.presentedViewController {
          top = presented
        }
        return top
      }
    }
    return nil
  }
}
