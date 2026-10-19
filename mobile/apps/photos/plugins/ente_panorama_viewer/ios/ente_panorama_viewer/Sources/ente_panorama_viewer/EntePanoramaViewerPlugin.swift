import CoreMotion
import Flutter
import UIKit

public final class EntePanoramaViewerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let motionManager = CMMotionManager()
    private var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = EntePanoramaViewerPlugin()
        let methodChannel = FlutterMethodChannel(
            name: "io.ente.panorama_viewer/motion",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        let eventChannel = FlutterEventChannel(
            name: "io.ente.panorama_viewer/motion_events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(motionManager.isDeviceMotionAvailable)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        guard motionManager.isDeviceMotionAvailable else {
            return FlutterError(
                code: "motion_unavailable",
                message: "Device orientation is unavailable",
                details: nil
            )
        }
        motionManager.stopDeviceMotionUpdates()
        eventSink = events
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                self.motionManager.stopDeviceMotionUpdates()
                let sink = self.eventSink
                self.eventSink = nil
                sink?(
                    FlutterError(
                        code: "motion_error",
                        message: error.localizedDescription,
                        details: nil
                    )
                )
                return
            }
            guard let motion else { return }
            let quaternion = motion.attitude.quaternion
            self.eventSink?([
                quaternion.w,
                quaternion.x,
                quaternion.y,
                quaternion.z,
                self.interfaceQuarterTurns(),
            ])
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        motionManager.stopDeviceMotionUpdates()
        eventSink = nil
        return nil
    }

    private func interfaceQuarterTurns() -> Int {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .interfaceOrientation
        switch orientation {
        case .landscapeLeft:
            return 1
        case .portraitUpsideDown:
            return 2
        case .landscapeRight:
            return 3
        default:
            return 0
        }
    }
}
