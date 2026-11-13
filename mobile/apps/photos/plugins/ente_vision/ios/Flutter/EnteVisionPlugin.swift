@preconcurrency import Flutter
import Foundation

@MainActor
public final class EnteVisionPlugin: NSObject, @preconcurrency FlutterPlugin {
    private let textRecognitionAdapter: TextRecognitionChannelAdapter

    private init(registrar: FlutterPluginRegistrar) {
        textRecognitionAdapter = TextRecognitionChannelAdapter(registrar: registrar)
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        registrar.publish(EnteVisionPlugin(registrar: registrar))
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        textRecognitionAdapter.detach()
    }
}
