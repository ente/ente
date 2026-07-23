import "package:photos/core/exceptions.dart";

enum InvalidReason {
  assetDeleted,
  assetDeletedEvent,
  sourceFileMissing,
  livePhotoToImageTypeChanged,
  imageToLivePhotoTypeChanged,
  livePhotoVideoMissing,
  thumbnailMissing,
  tooLargeFile,
  photosResourceUnavailable,
  unknown,
}

extension InvalidReasonExn on InvalidReason {
  bool get isLivePhotoErr =>
      this == InvalidReason.livePhotoToImageTypeChanged ||
      this == InvalidReason.imageToLivePhotoTypeChanged ||
      this == InvalidReason.livePhotoVideoMissing;
}

class InvalidFileError extends ArgumentError implements LocallyHandledError {
  final InvalidReason reason;

  InvalidFileError(String super.message, this.reason);

  @override
  String toString() {
    return 'InvalidFileError: $message (reason: $reason)';
  }
}

class SubscriptionAlreadyClaimedError extends Error {}

class WiFiUnavailableError extends Error implements LocallyHandledError {
  final String? message;

  WiFiUnavailableError([this.message]);

  @override
  String toString() => message == null
      ? "WiFiUnavailableError"
      : "WiFiUnavailableError: $message";
}

class SyncStopRequestedError extends Error {}

class NoActiveSubscriptionError extends Error implements LocallyHandledError {}

class StorageLimitExceededError extends Error implements LocallyHandledError {}

// error when file size + current usage >= storage plan limit + buffer
class FileTooLargeForPlanError extends Error {}

class SilentlyCancelUploadsError extends Error {}

class UserCancelledUploadError extends Error {}

bool isHandledSyncError(Object errObj) {
  if (errObj is UnauthorizedError ||
      errObj is NoActiveSubscriptionError ||
      errObj is WiFiUnavailableError ||
      errObj is StorageLimitExceededError ||
      errObj is SyncStopRequestedError) {
    return true;
  }
  return false;
}

class LockAlreadyAcquiredError extends Error {}

class LockFreedError extends Error {}

class UnauthorizedError extends Error {}

class RequestCancelledError extends Error {}

class InvalidSyncStatusError extends AssertionError {
  InvalidSyncStatusError(String super.message);
}

class UnauthorizedEditError extends AssertionError {}

class InvalidStateError extends AssertionError {
  InvalidStateError(String super.message);
}

class SrpSetupNotCompleteError extends Error {}

class SharingNotPermittedForFreeAccountsError extends Error {}

class LinkEditNotAllowedError extends Error {}

class NoMediaLocationAccessError extends Error {}

class PassKeySessionNotVerifiedError extends Error {}

class PassKeySessionExpiredError extends Error {}

class MultiPartFileMissingError implements Exception {
  final String message;
  MultiPartFileMissingError(this.message);

  @override
  String toString() => "MultiPartFileMissingError: $message";
}

class MultiPartError implements Exception {
  final String message;
  MultiPartError(this.message);

  @override
  String toString() => "MultiPartError: $message";
}

class EncSizeMismatchError implements Exception {
  final String message;
  EncSizeMismatchError(this.message);

  @override
  String toString() => "EncSizeMismatchError: $message";
}

class InvalidDateTimeError implements Exception {
  final String assetId;
  final String? assetTitle;
  final String field;
  final String originalError;

  InvalidDateTimeError({
    required this.assetId,
    this.assetTitle,
    required this.field,
    required this.originalError,
  });

  @override
  String toString() {
    return 'InvalidDateTimeError: $field is invalid for asset '
        '(id: $assetId, title: ${assetTitle ?? "unknown"}) - $originalError';
  }
}

class BadMD5DigestError implements Exception {
  final String message;
  BadMD5DigestError(this.message);

  @override
  String toString() => message;
}
