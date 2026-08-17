@preconcurrency import Flutter
import Foundation

@MainActor
public final class PhotosPlatformPlugin: NSObject, @preconcurrency FlutterPlugin {
    private let deviceHealthAdapter: DeviceHealthChannelAdapter
    private let processLockAdapter: ProcessLockChannelAdapter

    private init(registrar: FlutterPluginRegistrar) {
        deviceHealthAdapter = DeviceHealthChannelAdapter(registrar: registrar)
        processLockAdapter = ProcessLockChannelAdapter(registrar: registrar)
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        registrar.publish(PhotosPlatformPlugin(registrar: registrar))
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        deviceHealthAdapter.detach()
        processLockAdapter.detach()
    }
}
