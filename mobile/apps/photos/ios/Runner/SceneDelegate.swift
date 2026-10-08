import Flutter
import UIKit
import app_links
import ente_background_manager

class SceneDelegate: FlutterSceneDelegate {
  private let startupTrace: BackgroundStartupTrace = {
    let trace = BackgroundStartupTrace(scope: "scene")
    trace.event("scene.delegate.initializing")
    return trace
  }()
  private let foregroundHeartbeat = ForegroundHeartbeat()

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    startupTrace.event("scene.willConnect.begin")
    defer { startupTrace.event("scene.willConnect.end") }
    startupTrace.measure("scene.super.willConnect") {
      super.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    // app_links 6.x does not consume scene connection options. Flutter forwards
    // warm links and legacy share-intent callbacks through its scene delegate.
    startupTrace.measure("scene.links") {
      for context in connectionOptions.urlContexts {
        handleInitialLink(context.url)
      }
      for activity in connectionOptions.userActivities {
        if let url = activity.webpageURL {
          handleInitialLink(url)
        }
      }
    }
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    startupTrace.event("scene.didBecomeActive")
    super.sceneDidBecomeActive(scene)
    foregroundHeartbeat.start()
    signal(SIGPIPE, SIG_IGN)
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    startupTrace.event("scene.willEnterForeground")
    super.sceneWillEnterForeground(scene)
    foregroundHeartbeat.start()
    signal(SIGPIPE, SIG_IGN)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    startupTrace.event("scene.didEnterBackground")
    foregroundHeartbeat.stop()
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    startupTrace.event("scene.didDisconnect")
    foregroundHeartbeat.stop()
    super.sceneDidDisconnect(scene)
  }

  private func handleInitialLink(_ url: URL) {
    if !url.absoluteString.contains("homeWidget") {
      AppLinks.shared.handleLink(url: url)
    }
  }
}
