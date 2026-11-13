@preconcurrency import Flutter

@MainActor
final class CountryNamesChannelAdapter {
    private let channel: FlutterMethodChannel
    private let service = CountryNamesService()

    init(registrar: FlutterPluginRegistrar) {
        channel = FlutterMethodChannel(
            name: "io.ente.photos.platform/country_names",
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { [service] call, result in
            guard call.method == "get" else {
                result(FlutterMethodNotImplemented)
                return
            }
            guard let arguments = call.arguments as? [String: Any] else {
                result(FlutterError(code: "invalid_arguments", message: "Expected country name arguments", details: nil))
                return
            }
            guard let locale = arguments["locale"] as? String else {
                result(FlutterError(code: "invalid_locale", message: "Expected a locale identifier", details: nil))
                return
            }
            guard let nativeLocales = arguments["nativeLocales"] as? [String: [String]] else {
                result(FlutterError(code: "invalid_native_locales", message: "Expected native country locales", details: nil))
                return
            }
            let names = service.names(localeIdentifier: locale, nativeLocales: nativeLocales)
            result(["region": names.region, "names": names.names, "nativeNames": names.nativeNames])
        }
    }

    func detach() {
        channel.setMethodCallHandler(nil)
    }
}
