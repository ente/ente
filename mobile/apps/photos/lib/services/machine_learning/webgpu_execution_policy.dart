import "dart:io" show Platform;

import "package:device_info_plus/device_info_plus.dart";
import "package:photos/service_locator.dart"
    show flagService, isLocalGalleryMode;
import "package:photos/utils/ram_check_util.dart";

final webGpuExecutionPolicy = WebGpuExecutionPolicy();

/// Computes the app-owned portion of Android WebGPU eligibility.
///
/// Durable quarantine and GPU adapter compatibility are owned by Rust.
class WebGpuExecutionPolicy {
  Future<int?>? _androidSdkFuture;

  Future<bool> isEligible() async {
    if (!Platform.isAndroid ||
        (!isLocalGalleryMode && !flagService.webGPUEnabled) ||
        !enoughRamForLocalIndexing) {
      return false;
    }
    final sdk = await (_androidSdkFuture ??= _readAndroidSdk());
    // Android 12+
    return sdk != null && sdk >= 31;
  }

  static Future<int?> _readAndroidSdk() async {
    try {
      return (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (_) {
      return null;
    }
  }
}
