import "package:flutter/services.dart" show PlatformException;

const phPhotosResourceUnavailableReason =
    "iCloud Photos download failed (PHPhotosErrorDomain 3169)";

const _phPhotosErrorDomain = "PHPhotosErrorDomain";
const _phPhotosNetworkErrorCode = "3169";
const _phPhotosUnsupportedResourceErrorCode = "3302";

bool isPHPhotosNetworkError(Object error) {
  return _isPHPhotosError(error, _phPhotosNetworkErrorCode);
}

bool isPHPhotosUnsupportedResourceError(Object error) {
  return _isPHPhotosError(error, _phPhotosUnsupportedResourceErrorCode);
}

bool _isPHPhotosError(Object error, String code) {
  if (error is! PlatformException) return false;
  return error.code == "$_phPhotosErrorDomain ($code)" ||
      (error.code.contains(_phPhotosErrorDomain) &&
          error.code.contains(code)) ||
      (error.message?.contains("$_phPhotosErrorDomain error $code") ?? false);
}
