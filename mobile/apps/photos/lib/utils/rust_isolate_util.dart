import "package:photos/src/rust/frb_generated.dart";

Future<void> ensureRustInitialized() async {
  if (!EntePhotosRust.instance.initialized) {
    await EntePhotosRust.init();
  }
}
