import "dart:io";

import "package:dio/dio.dart";

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
    final code = error.osError?.errorCode;
    return code == 28 || code == 112;
  }
  if (error is DioException && error.error != null) {
    return isDeviceStorageFullError(error.error!);
  }
  return false;
}
