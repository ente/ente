import Flutter
import UIKit

public class EnteScreenCoverPlugin: NSObject, FlutterPlugin {
    private var overlay: UIView?
    private var observing = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "ente_screen_cover",
            binaryMessenger: registrar.messenger()
        )
        let instance = EnteScreenCoverPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enable":
            startObserving()
            result(nil)
        case "disable":
            stopObserving()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startObserving() {
        if observing { return }
        observing = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(showOverlay),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(hideOverlay),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    private func stopObserving() {
        if !observing { return }
        observing = false
        NotificationCenter.default.removeObserver(self)
        hideOverlay()
    }

    @objc private func showOverlay() {
        guard overlay == nil, let window = keyWindow() else { return }
        let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        cover.frame = window.bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(cover)
        overlay = cover
    }

    @objc private func hideOverlay() {
        overlay?.removeFromSuperview()
        overlay = nil
    }

    private func keyWindow() -> UIWindow? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
