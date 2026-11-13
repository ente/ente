import Flutter
import UIKit

public class EnteQrScannerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let factory = EnteQrScannerViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: "io.ente.qr_scanner/view")
  }
}
