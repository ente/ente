import "dart:io";

import "package:dio/dio.dart";
import "package:flutter/services.dart" show PlatformException;
import "package:photos/core/errors.dart" show DeviceStorageFullError;

class DeviceStorageFullException implements Exception {
  const DeviceStorageFullException();

  @override
  String toString() => "Device storage is full";
}

/// POSIX ENOSPC ("No space left on device"), surfaced by dart:io on
/// iOS/macOS/Android/Linux as [OSError.errorCode].
const _enospc = 28;

/// Windows ERROR_DISK_FULL.
const _windowsDiskFull = 112;

/// NSCocoaErrorDomain NSFileWriteOutOfSpaceError (Foundation write failure
/// when the volume is out of space).
const _nsFileWriteOutOfSpaceError = 640;

/// PHPhotosErrorDomain PHPhotosErrorNotEnoughSpace (PhotoKit could not
/// materialize/export an asset because the device is out of space).
const _phPhotosErrorNotEnoughSpace = 3305;

/// Native error domain/code pairs that indicate local storage exhaustion.
///
/// photo_manager (and our other iOS plugin surfaces) report an `NSError` as a
/// [PlatformException] whose `code` is `"<domain> (<code>)"`, e.g.
/// `"NSCocoaErrorDomain (640)"` — see `PMResultHandler.replyError`. The same
/// convention is already relied upon in `apple_photos_errors.dart`.
const _nativeOutOfSpaceCodes = <(String, int)>[
  ("NSCocoaErrorDomain", _nsFileWriteOutOfSpaceError),
  ("NSPOSIXErrorDomain", _enospc),
  ("PHPhotosErrorDomain", _phPhotosErrorNotEnoughSpace),
];

/// Canonical classifier for local device-storage exhaustion.
///
/// Recognizes, across every file boundary used during backup and download
/// (PhotoKit materialization, cache writes, temporary encrypted files, and
/// upload staging):
///  - already-classified [DeviceStorageFullException] / [DeviceStorageFullError],
///  - Dart [FileSystemException] / [OSError] with POSIX `ENOSPC` (28) or
///    Windows `ERROR_DISK_FULL` (112),
///  - [PlatformException]s carrying native `NSError`s for
///    `NSFileWriteOutOfSpaceError` (NSCocoaErrorDomain 640), `ENOSPC`
///    (NSPOSIXErrorDomain 28), or `PHPhotosErrorNotEnoughSpace`
///    (PHPhotosErrorDomain 3305),
///  - [DioException]s wrapping any of the above.
bool isDeviceStorageFullError(Object error) {
  if (error is DeviceStorageFullException || error is DeviceStorageFullError) {
    return true;
  }
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    return code == _enospc || code == _windowsDiskFull;
  }
  if (error is OSError) {
    return error.errorCode == _enospc || error.errorCode == _windowsDiskFull;
  }
  if (error is PlatformException) {
    for (final (domain, code) in _nativeOutOfSpaceCodes) {
      // Structured code emitted by the plugin's NSError bridge.
      if (error.code == "$domain ($code)") {
        return true;
      }
      // Fallback for NSError descriptions embedded in the message, following
      // the existing convention in apple_photos_errors.dart.
      if (error.message?.contains("$domain error $code") ?? false) {
        return true;
      }
    }
    return false;
  }
  if (error is DioException && error.error != null) {
    return isDeviceStorageFullError(error.error!);
  }
  return false;
}
