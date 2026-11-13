import Flutter
import UIKit

public final class EnteScreenBrightnessPlugin: NSObject, FlutterPlugin {
    private weak var registrar: FlutterPluginRegistrar?
    private var dimmingView: UIView?

    private init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackgroundNotification(_:)),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.ente.screen_brightness",
            binaryMessenger: registrar.messenger()
        )
        let instance = EnteScreenBrightnessPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setApplicationBrightness":
            guard let number = call.arguments as? NSNumber else {
                result(invalidBrightnessError())
                return
            }

            let brightness = CGFloat(number.doubleValue)
            guard brightness.isFinite, (0...1).contains(brightness) else {
                result(invalidBrightnessError())
                return
            }
            guard UIApplication.shared.applicationState == .active,
                  let view = registrar?.viewController?.viewIfLoaded else {
                result(false)
                return
            }

            setApplicationBrightness(brightness, in: view)
            result(true)

        case "resetApplicationBrightness":
            resetApplicationBrightness()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func setApplicationBrightness(_ brightness: CGFloat, in view: UIView) {
        if brightness == 1 {
            resetApplicationBrightness()
            return
        }

        let overlay: UIView
        if let dimmingView, dimmingView.superview === view {
            overlay = dimmingView
        } else {
            resetApplicationBrightness()
            overlay = UIView(frame: view.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.backgroundColor = .black
            overlay.isAccessibilityElement = false
            overlay.isUserInteractionEnabled = false
            overlay.alpha = 0
            view.addSubview(overlay)
            dimmingView = overlay
        }

        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            overlay.alpha = 1 - brightness
        }
    }

    private func resetApplicationBrightness() {
        dimmingView?.layer.removeAllAnimations()
        dimmingView?.removeFromSuperview()
        dimmingView = nil
    }

    private func invalidBrightnessError() -> FlutterError {
        FlutterError(
            code: "INVALID_BRIGHTNESS",
            message: "Application brightness must be a number from 0 to 1.",
            details: nil
        )
    }

    @objc private func handleDidEnterBackgroundNotification(_ notification: Notification) {
        resetApplicationBrightness()
    }

    deinit {
        resetApplicationBrightness()
        NotificationCenter.default.removeObserver(self)
    }
}
