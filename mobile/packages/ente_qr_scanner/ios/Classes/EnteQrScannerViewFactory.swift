import Flutter
import UIKit

final class EnteQrScannerViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier platformViewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    EnteQrScannerView(
      frame: frame,
      platformViewId: platformViewId,
      args: args,
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}
