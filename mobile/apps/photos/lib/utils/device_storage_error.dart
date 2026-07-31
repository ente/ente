import "dart:io";

import "package:dio/dio.dart";
import "package:flutter/services.dart" show PlatformException;

class DeviceStorageFullException implements Exception {
  const DeviceStorageFullException();

  @override
  String toString() => "Device storage is full";
}

bool isDeviceStorageFullError(Object error) {
  if (error is DeviceStorageFullException) {
    return true;
  }
  if (error is FileSystemException) {
    // ENOSPC on POSIX, ERROR_DISK_FULL on Windows.
    return error.osError?.errorCode == (Platform.isWindows ? 112 : 28);
  }
  if (error is PlatformException) {
    return error.code == "NSCocoaErrorDomain (640)" ||
        error.code == "NSPOSIXErrorDomain (28)" ||
        error.code == "PHPhotosErrorDomain (3305)";
  }
  if (error is DioException && error.error != null) {
    return isDeviceStorageFullError(error.error!);
  }
  return false;
}
